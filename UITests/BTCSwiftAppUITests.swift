import BitcoinCore
import Foundation
import WalletCore
import XCTest

/// Smoke probe: the whole suite hinges on the iOS-simulator test runner
/// being able to spawn host processes (bitcoin-cli mining, pasteboard
/// copies). Runs first (alphabetical) and fails fast.
@MainActor
final class HostProcessProbeTests: XCTestCase {
    func test00CanSpawnHostProcesses() throws {
        let echo = try HostProcess.run("/bin/echo", ["host-spawn-ok"])
        XCTAssertEqual(echo.status, 0)
        XCTAssertEqual(echo.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "host-spawn-ok")
        let node = try BitcoinCLI.run(["getblockcount"])
        XCTAssertGreaterThan(Int(node) ?? 0, 0, "local signet node unreachable")
    }
}

/// End-to-end UI tests against the local custom-signet node (datadir
/// ~/.bitcoin-mysignet, P2P 127.0.0.1:38401). The app is launched with
/// BTCSWIFT_E2E=1 (see Sources/BTCSwiftApp/E2EMode.swift): throwaway storage
/// and Keychain namespace, custom-signet params, the node as manual peer, and
/// a fixed wallet entropy for reproducible screenshots.
///
/// The suite is deliberately ordered (test01…test06 — XCTest runs a class's
/// methods alphabetically): 01 creates the wallet, 02 funds it, 03 spends,
/// 06 imports a bundle built from the funding data.
@MainActor
final class BTCSwiftAppUITests: XCTestCase {
    /// Fixed 16-byte entropy → the same mnemonic/addresses every run.
    static let entropyHex = "000102030405060708090a0b0c0d0e0f"
    static let mnemonic = try! BIP39.mnemonic(entropy: Data(hex: entropyHex)!)

    /// Facts about the funding coinbase, captured in test02, reused in 06.
    /// Persisted to the runner's temp dir because a crashed/restarted runner
    /// process loses statics.
    struct FundingInfo: Codable {
        var txid: String // display hex
        var amount: Int64
        var scriptPubKey: String // hex
        var height: Int
    }
    nonisolated(unsafe) static var funding: FundingInfo?

    static var fundingFile: URL {
        FileManager.default.temporaryDirectory.appending(path: "btcswift-e2e-funding.json")
    }

    static func saveFunding(_ info: FundingInfo) {
        funding = info
        try? JSONEncoder().encode(info).write(to: fundingFile)
    }

    static func loadFunding() -> FundingInfo? {
        if let funding { return funding }
        guard let data = try? Data(contentsOf: fundingFile) else { return nil }
        funding = try? JSONDecoder().decode(FundingInfo.self, from: data)
        return funding
    }

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 600
    }

    // MARK: - Launch

    /// Launches the app in E2E mode against the local node and waits for the
    /// wallet shell (balance visible) unless onboarding is expected.
    @discardableResult
    func launchApp(run: String = "main", reset: Bool = false, clipboard: String? = nil,
                   expectOnboarding: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "BTCSWIFT_E2E": "1",
            "BTCSWIFT_E2E_RUN": run,
            "BTCSWIFT_E2E_PEER": "127.0.0.1:\(BitcoinCLI.p2pPort)",
            "BTCSWIFT_E2E_CHALLENGE": BitcoinCLI.challengeHex,
            "BTCSWIFT_E2E_ENTROPY": Self.entropyHex,
        ]
        if reset { app.launchEnvironment["BTCSWIFT_E2E_RESET"] = "1" }
        if let clipboard { app.launchEnvironment["BTCSWIFT_E2E_CLIPBOARD"] = clipboard }
        app.launch()
        if expectOnboarding {
            XCTAssertTrue(app.buttons["createWalletButton"].waitForExistence(timeout: 120),
                          "onboarding did not appear")
        } else {
            XCTAssertTrue(app.staticTexts["balanceText"].waitForExistence(timeout: 120),
                          "wallet home did not appear")
        }
        return app
    }

    /// Text of the balance label ("12,345 sats").
    func balanceText(_ app: XCUIApplication) -> String {
        (app.staticTexts["balanceText"].value as? String) ?? ""
    }

    /// Taps "Sync now" when idle to nudge a scan pass.
    func nudgeSync(_ app: XCUIApplication) {
        let button = app.buttons["syncNowButton"]
        if button.exists, button.isEnabled { button.tap() }
    }

    /// Scrolls the first collection view until `element` exists (SwiftUI
    /// Forms materialize rows lazily — `exists` is false below the fold).
    @discardableResult
    func scrollUntilExists(_ app: XCUIApplication, _ element: XCUIElement,
                           maxSwipes: Int = 10, up: Bool = false) -> Bool {
        for _ in 0 ... maxSwipes {
            if element.waitForExistence(timeout: 2) { return true }
            let list = app.collectionViews.firstMatch
            guard list.exists else { return element.exists }
            up ? list.swipeDown() : list.swipeUp()
        }
        return element.exists
    }

    // MARK: - 01 Onboarding

    func test01OnboardingCreateWallet() throws {
        let app = launchApp(reset: true, expectOnboarding: true)
        Screenshots.capture(app, "01-onboarding", testCase: self)

        app.buttons["createWalletButton"].tap()
        // Creation syncs headers from the local node first.
        let toggle = app.switches["writtenDownToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 180), "backup sheet did not appear")
        Screenshots.capture(app, "02-backup-mnemonic", testCase: self)

        // iOS 26: the toggle is a container switch element wrapping the real
        // UISwitch as a child — tapping the container/label does nothing.
        // Tap the child switch (right side of the row).
        let toggleThumb = toggle.children(matching: .switch).firstMatch
        let done = app.buttons["backupDoneButton"]
        let enabled = poll(timeout: 20, interval: 1, "backup Done button enabled") {
            if done.isEnabled { return true }
            if toggleThumb.exists {
                toggleThumb.tap()
            } else {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            }
            return done.isEnabled
        }
        if !enabled {
            Screenshots.capture(app, "debug-01-backup", testCase: self)
            print("E2E debug: writtenDownToggle value = \(toggle.value ?? "nil")")
            print(app.debugDescription)
        }
        done.tap()
        XCTAssertTrue(app.staticTexts["balanceText"].waitForExistence(timeout: 60),
                      "wallet home did not appear after backup")
    }

    // MARK: - 02 Receive + funding

    func test02ReceiveAndFunding() async throws {
        let app = launchApp()

        app.buttons["receiveButton"].tap()
        let addressElement = app.staticTexts["receiveAddress"]
        XCTAssertTrue(addressElement.waitForExistence(timeout: 30), "no receive address")
        Screenshots.capture(app, "03-receive", testCase: self)
        guard let address = addressElement.value as? String, address.hasPrefix("tb1") else {
            XCTFail("could not read the receive address from the UI")
            return
        }
        app.buttons["Done"].tap()

        // Fund it from the host: 101 blocks paying the receive address, so the
        // first coinbase is spendable by the time the send test runs.
        let script = try AddressDecoder.scriptPubKey(for: address, network: .signet)
        let startHeight = try BitcoinCLI.blockCount()
        let firstHash = try await SignetMiner.mineBlock(payingTo: script)
        let fundingTxid = try BitcoinCLI.coinbaseTxid(blockHash: firstHash)
        let output = try BitcoinCLI.outputZero(txid: fundingTxid)
        Self.saveFunding(FundingInfo(txid: fundingTxid, amount: output.amount,
                                     scriptPubKey: output.scriptPubKey, height: startHeight + 1))
        for _ in 0 ..< 100 {
            try await SignetMiner.mineBlock(payingTo: script)
        }

        // Filters see blocks, not the mempool: poll (nudging "Sync now")
        // until the confirmed balance shows.
        poll(timeout: 300, interval: 5, "confirmed balance after funding") {
            self.nudgeSync(app)
            return self.balanceText(app) != "0 sats" && self.balanceText(app) != ""
        }
        // A history entry must be there too.
        XCTAssertTrue(app.staticTexts["Received"].waitForExistence(timeout: 60),
                      "no history entry after funding")
        Screenshots.capture(app, "04-home-funded", testCase: self)
    }

    // MARK: - 03 Send

    func test03Send() async throws {
        // Send 0.01 BTC back out to a fixture address derived in-process
        // (the node's "miner" wallet is a signing-only wallet with no
        // keypool — it can't hand out receive addresses). The app gets the
        // destination on its own pasteboard via BTCSWIFT_E2E_CLIPBOARD.
        let destination = try Self.fixtureAddress(0xC3)
        let app = launchApp(clipboard: destination)
        XCTAssertTrue(poll(timeout: 120, "persisted funded balance") {
            self.balanceText(app) != "0 sats" && self.balanceText(app) != ""
        })

        app.tabBars.buttons["Send"].tap()
        XCTAssertTrue(app.buttons["pasteDestinationButton"].waitForExistence(timeout: 20))
        app.buttons["pasteDestinationButton"].tap()
        XCTAssertTrue(poll(timeout: 15, interval: 1, "destination pasted") {
            (app.textFields["destinationField"].value as? String) == destination
        })
        app.typeInto("amountField", "1000000")
        // The number pad has no return key and swallows the first outside
        // tap; switching tabs resigns the field (TabView keeps form state).
        if app.keyboards.firstMatch.exists {
            app.tabBars.buttons["Wallet"].tap()
            app.tabBars.buttons["Send"].tap()
        }
        Screenshots.capture(app, "05-send-form", testCase: self)

        app.buttons["reviewButton"].tap()
        // The Review section is appended below the fold; SwiftUI Forms
        // materialize rows lazily, so scroll it into existence.
        let sendButton = app.buttons["sendButton"]
        if !scrollUntilExists(app, sendButton, maxSwipes: 5) {
            app.buttons["reviewButton"].tap() // in case the tap was eaten by the keyboard
            _ = scrollUntilExists(app, sendButton, maxSwipes: 5)
        }
        if !sendButton.exists {
            _ = scrollUntilExists(app, app.staticTexts["sendError"], up: true)
            if app.staticTexts["sendError"].exists {
                print("E2E send error: \(app.staticTexts["sendError"].label)")
            }
            Screenshots.capture(app, "debug-03-send", testCase: self)
        }
        XCTAssertTrue(sendButton.exists, "no review section")
        Screenshots.capture(app, "06-send-review", testCase: self)

        app.buttons["sendButton"].tap()
        XCTAssertTrue(poll(timeout: 60, "broadcast status") {
            app.staticTexts["broadcastPending"].exists || app.staticTexts["broadcastConfirmed"].exists
        })
        Screenshots.capture(app, "07-send-broadcast", testCase: self)

        // Confirm it: mine one block (paying a fixture address), then poll the
        // send view's "Seen in block N" — nudging syncs from the Wallet tab.
        let payout = try AddressDecoder.scriptPubKey(for: Self.fixtureAddress(0xD4), network: .signet)
        try await SignetMiner.mineBlock(payingTo: payout)
        poll(timeout: 240, interval: 5, "send confirmation") {
            if app.staticTexts["broadcastConfirmed"].exists { return true }
            app.tabBars.buttons["Wallet"].tap()
            self.nudgeSync(app)
            app.tabBars.buttons["Send"].tap()
            return app.staticTexts["broadcastConfirmed"].exists
        }
        Screenshots.capture(app, "08-send-confirmed", testCase: self)

        app.tabBars.buttons["Wallet"].tap()
        self.nudgeSync(app)
        XCTAssertTrue(app.staticTexts["Sent"].waitForExistence(timeout: 60),
                      "no sent entry in history")
        Screenshots.capture(app, "09-home-after-send", testCase: self)
    }

    // MARK: - 04 Vaults

    /// A deterministic cosigner key expression ([fp/86'/1'/0']tpub…/<0;1>/*)
    /// from a one-byte repeated seed — a fixture, not a real cosigner.
    static func fixtureCosigner(_ byte: UInt8) throws -> String {
        let master = try HDKey(seed: Data(repeating: byte, count: 64))
        let account = try BIP86.accountKey(from: master, coinType: 1, account: 0)
        let fingerprint = String(format: "%08x", master.fingerprint)
        return "[\(fingerprint)/86'/1'/0']\(account.neutered.serialized(network: .testnet))/<0;1>/*"
    }

    /// A deterministic signet P2TR address from a one-byte repeated seed
    /// (fixture send destination / block payout).
    static func fixtureAddress(_ byte: UInt8) throws -> String {
        let master = try HDKey(seed: Data(repeating: byte, count: 64))
        let account = try BIP86.accountKey(from: master, coinType: 1, account: 0)
        return try BIP86.address(internalKey: account.publicKey.dropFirst(), hrp: "tb")
    }

    func test04VaultCreate() throws {
        let app = launchApp()
        app.tabBars.buttons["Vaults"].tap()
        app.buttons["newVaultButton"].tap()

        app.typeInto("vaultNameField", "E2E Vault")
        // Default policy: 2-of-n script path; three cosigners → 2-of-3.
        app.buttons["addDeviceKeyButton"].tap()
        for byte: UInt8 in [0xA1, 0xB2] {
            app.typeInto("cosignerField", try Self.fixtureCosigner(byte))
            app.buttons["addPastedKeyButton"].tap()
        }
        app.buttons["buildDescriptorButton"].tap()
        // The descriptor preview is a CopyableTextBlock whose Text starts
        // with "tr(" — below the fold, and SwiftUI Forms materialize rows
        // lazily, so scroll it into existence.
        let descriptor = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'tr('")).firstMatch
        XCTAssertTrue(scrollUntilExists(app, descriptor), "descriptor preview did not appear")
        app.dismissKeyboard()
        Screenshots.capture(app, "10-vault-create", testCase: self)

        XCTAssertTrue(scrollUntilExists(app, app.buttons["saveVaultButton"]),
                      "save button did not appear")
        app.buttons["saveVaultButton"].tap()
        XCTAssertTrue(app.staticTexts["E2E Vault"].waitForExistence(timeout: 30),
                      "vault was not saved")
        XCTAssertTrue(app.staticTexts["2-of-3 · script path"].waitForExistence(timeout: 10))
        Screenshots.capture(app, "11-vault-list", testCase: self)
    }

    // MARK: - 05 Settings

    func test05SettingsPeersAndEsploraWarning() throws {
        let app = launchApp()
        app.tabBars.buttons["Settings"].tap()

        // SwiftUI Forms materialize rows lazily: scroll the Connected peers
        // section into existence first.
        let refresh = app.buttons["refreshPeersButton"]
        if !scrollUntilExists(app, refresh) {
            Screenshots.capture(app, "debug-05-settings", testCase: self)
            print(app.debugDescription)
            XCTFail("settings form did not load")
            return
        }
        refresh.tap()
        let localPeer = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH '127.0.0.1:38401'")).firstMatch
        poll(timeout: 60, interval: 3, "connected local peer in settings") {
            if localPeer.exists { return true }
            if refresh.exists, refresh.isHittable { refresh.tap() }
            return localPeer.exists
        }
        // Bring the Connected peers section into view for the screenshot.
        if !localPeer.isHittable { app.collectionViews.firstMatch.swipeUp() }
        Screenshots.capture(app, "12-settings-peers", testCase: self)

        // The esplora opt-in warning is a design artifact: capture it, then
        // cancel — esplora stays OFF.
        let toggle = app.switches["esploraToggle"]
        XCTAssertTrue(scrollUntilExists(app, toggle, up: true), "no esplora toggle")
        app.flipSwitch(toggle)
        let alert = app.alerts["Enable the esplora fast path?"]
        if !alert.waitForExistence(timeout: 10) {
            // First flip may have been consumed by scroll settling — retry once.
            app.flipSwitch(toggle)
        }
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "esplora warning did not appear")
        Screenshots.capture(app, "13-esplora-warning", testCase: self)
        alert.buttons["Cancel"].tap()
        poll(timeout: 10, interval: 1, "esplora toggle off") {
            (toggle.value as? String) == "0"
        }
    }

    // MARK: - 06 Import

    func test06ImportBundleVerification() async throws {
        guard let funding = Self.loadFunding() else {
            XCTFail("no funding info from test02 — run the full suite")
            return
        }
        // Minimal bundle: the fixed mnemonic plus the funding coinbase as the
        // claimed UTXO/history, as of the funding block. Verification scans
        // forward from there and sees test03's spend — the report shows the
        // claimed UTXO as spent-since and the change as discovered.
        let bundle: [String: Any] = [
            "version": 1,
            "network": "signet",
            "mnemonic": Self.mnemonic,
            "lastKnownHeight": funding.height,
            "utxos": [[
                "txid": funding.txid, "vout": 0, "amount": funding.amount,
                "scriptPubKey": funding.scriptPubKey, "chain": 0, "index": 0,
                "height": funding.height,
            ]],
            "transactions": [[
                "txid": funding.txid, "height": funding.height,
                "received": funding.amount, "spent": 0,
            ]],
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: bundle), as: UTF8.self)

        // The app puts the bundle on its own pasteboard at boot.
        let app = launchApp(run: "import", reset: true, clipboard: json, expectOnboarding: true)
        app.buttons["importWalletButton"].tap()
        XCTAssertTrue(app.buttons["importPasteButton"].waitForExistence(timeout: 20))
        app.buttons["importPasteButton"].tap()
        app.buttons["importVerifyButton"].tap()
        XCTAssertTrue(app.staticTexts["Verification report"].waitForExistence(timeout: 300)
                        || app.otherElements["importReportSection"].waitForExistence(timeout: 5),
                      "no verification report")
        Screenshots.capture(app, "14-import-report", testCase: self)
        app.buttons["importContinueButton"].tap()
        XCTAssertTrue(app.staticTexts["balanceText"].waitForExistence(timeout: 60),
                      "wallet home did not appear after import")
    }
}
