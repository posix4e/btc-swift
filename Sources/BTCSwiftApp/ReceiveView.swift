import SwiftUI
import UIKit

/// Fresh BIP86 receive address with a QR. The address is peeked (not marked
/// used) until a payment to it confirms or the user asks for a new one.
struct ReceiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var address: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let address {
                    QRCodeView(content: address)
                        .frame(width: 240, height: 240)
                        .padding(.top)
                    Text(address)
                        .font(.system(.footnote, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.horizontal)
                        .accessibilityIdentifier("receiveAddress")
                        .accessibilityValue(address)
                    HStack(spacing: 16) {
                        Button("Copy") { UIPasteboard.general.string = address }
                        ShareLink(item: address)
                        Button("New address") { newAddress() }
                    }
                    .buttonStyle(.bordered)
                    Text("Incoming payments appear once they confirm in a block — compact filters see blocks, not the mempool.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else if let error {
                    ContentUnavailableView("No address", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else {
                    ProgressView()
                }
                Spacer()
            }
            .navigationTitle("Receive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                address = try? await model.currentReceiveAddress()
                if address == nil { error = "The wallet is not available." }
            }
        }
    }

    private func newAddress() {
        Task {
            do {
                address = try await model.freshReceiveAddress()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
