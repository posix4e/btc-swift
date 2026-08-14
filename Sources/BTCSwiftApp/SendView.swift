import BitcoinP2P
import SwiftUI
import UIKit
import WalletCore

/// Send to any standard address or an sp1…/tsp1… silent payment code: fee
/// selection (FeePolicy presets + the peers' feefilter floor + override), a
/// review step, then sign + broadcast via TxBroadcaster. Relay status comes
/// from the broadcaster's events; confirmation arrives as a filter match
/// ("seen in block N").
struct SendView: View {
    @Environment(AppModel.self) private var model

    @State private var destination = ""
    @State private var amountText = ""
    @State private var priority: FeePolicy.Priority = .medium
    @State private var overrideText = ""
    @State private var resolvedRate: Double?
    @State private var preview: AppModel.SendPreview?
    @State private var error: String?
    @State private var sending = false
    @State private var sentTxid: Data?
    @State private var relayLog: [String] = []
    @State private var confirmedHeight: UInt32?
    @FocusState private var amountFocused: Bool

    private var override: Double? {
        Double(overrideText.trimmingCharacters(in: .whitespaces))
    }

    private var destinationIsSilentPayment: Bool {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("sp1") || trimmed.hasPrefix("tsp1")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Destination") {
                    TextField("Address or sp1… silent payment code", text: $destination)
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("destinationField")
                    Button("Paste") {
                        destination = UIPasteboard.general.string ?? ""
                    }
                    .accessibilityIdentifier("pasteDestinationButton")
                    TextField("Amount (sats)", text: $amountText)
                        .keyboardType(.numberPad)
                        .focused($amountFocused)
                        .accessibilityIdentifier("amountField")
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { amountFocused = false }
                            }
                        }
                }

                Section {
                    Picker("Priority", selection: $priority) {
                        Text("Low").tag(FeePolicy.Priority.low)
                        Text("Medium").tag(FeePolicy.Priority.medium)
                        Text("High").tag(FeePolicy.Priority.high)
                    }
                    LabeledContent("Resolved rate", value: resolvedRate.map(feeRateText) ?? "—")
                    LabeledContent("Network floor", value: model.status.feeFloorSatPerVByte.map(feeRateText) ?? "unknown")
                    TextField("Override (sat/vB, optional)", text: $overrideText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Fee")
                } footer: {
                    Text("A filter-only wallet cannot see the fee market: the rate is the override, then your own confirmed transactions' median, then a conservative preset — never below the peers' relay floor.")
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .accessibilityIdentifier("sendError")
                    }
                }

                if sentTxid == nil {
                    Section {
                        Button("Review payment") { review() }
                            .accessibilityIdentifier("reviewButton")
                            .disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      || Int64(amountText) == nil)
                    }
                }

                if let preview, sentTxid == nil {
                    Section("Review") {
                        LabeledContent("Pays", value: destinationIsSilentPayment
                                       ? "silent payment (derived P2TR output)"
                                       : String(destination.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)) + "…")
                        LabeledContent("Amount", value: satsText(preview.payments.map(\.amount).reduce(0, +)
                                                                   + preview.silentPayments.map(\.amount).reduce(0, +)))
                        LabeledContent("Fee", value: satsText(preview.fee))
                        LabeledContent("Rate", value: feeRateText(preview.feeRateSatPerVByte))
                        LabeledContent("Inputs", value: "\(preview.inputCount)")
                        if let change = preview.changeAmount {
                            LabeledContent("Change back", value: satsText(change))
                        }
                        Button(sending ? "Signing & broadcasting…" : "Sign & broadcast") { send() }
                            .accessibilityIdentifier("sendButton")
                            .disabled(sending)
                    }
                    .accessibilityIdentifier("reviewSection")
                }

                if let sentTxid {
                    Section("Broadcast") {
                        Text(sentTxid.displayHex)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                        ForEach(Array(relayLog.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.footnote)
                        }
                        if let confirmedHeight {
                            Label("Seen in block \(confirmedHeight)", systemImage: "checkmark.seal")
                                .foregroundStyle(.green)
                                .accessibilityIdentifier("broadcastConfirmed")
                        } else {
                            Text("Awaiting confirmation — a filter match will report the block here.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("broadcastPending")
                        }
                        Button("New payment") { reset() }
                    }
                    .accessibilityIdentifier("broadcastSection")
                }
            }
            .navigationTitle("Send")
            .task(id: feeInputs) {
                resolvedRate = await model.resolvedFeeRate(priority: priority, override: override)
            }
            .task(id: sentTxid) {
                await watchBroadcastEvents()
            }
            .onChange(of: model.status.history) { _, history in
                guard let sentTxid, confirmedHeight == nil,
                      let entry = history.first(where: { $0.txid == sentTxid }), entry.height > 0
                else { return }
                confirmedHeight = entry.height
            }
        }
    }

    /// Recomputes the resolved rate when priority/override/floor change.
    private var feeInputs: String {
        "\(priority.rawValue)|\(overrideText)|\(model.status.feeFloorSatPerVByte ?? -1)"
    }

    private func review() {
        error = nil
        preview = nil
        guard let amount = Int64(amountText), amount > 0 else {
            error = "Enter an amount in sats."
            return
        }
        Task {
            do {
                preview = try await model.previewSend(destination: destination, amount: amount,
                                                      priority: priority, override: override)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func send() {
        guard let preview else { return }
        sending = true
        error = nil
        Task {
            do {
                sentTxid = try await model.send(preview: preview)
            } catch {
                self.error = error.localizedDescription
            }
            sending = false
        }
    }

    private func reset() {
        destination = ""
        amountText = ""
        preview = nil
        sentTxid = nil
        relayLog = []
        confirmedHeight = nil
        error = nil
    }

    /// Follows the broadcaster's events for the sent transaction: announced →
    /// relayed (a peer asked for the tx) → confirmed (filter match).
    private func watchBroadcastEvents() async {
        guard let sentTxid, let broadcaster = model.stack?.broadcaster else { return }
        for await event in await broadcaster.events() {
            switch event {
            case let .announced(txid, peerCount) where txid == sentTxid:
                relayLog.append("Announced to \(peerCount) peer(s)")
            case let .requested(txid, peer) where txid == sentTxid:
                relayLog.append("Relayed to \(peer)")
            case let .confirmed(txid) where txid == sentTxid:
                confirmedHeight = model.status.history.first { $0.txid == txid }?.height
            default:
                break
            }
        }
    }
}
