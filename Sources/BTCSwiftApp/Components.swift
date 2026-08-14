import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Address/PSBT QR via CoreImage's CIQRCodeGenerator.
struct QRCodeView: View {
    let content: String

    private var image: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        } else {
            ContentUnavailableView("QR unavailable", systemImage: "qrcode")
        }
    }
}

/// A scrollable monospaced blob (address, descriptor, PSBT) with copy/share.
struct CopyableTextBlock: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            HStack {
                Button("Copy") { UIPasteboard.general.string = text }
                ShareLink(item: text)
            }
            .buttonStyle(.bordered)
        }
    }
}

/// The bundled design paper (docs/read-side.md), rendered as plain text so
/// the esplora opt-in warning can link to it offline.
struct ReadSideDocumentView: View {
    private var text: String {
        guard let url = Bundle.main.url(forResource: "read-side", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "The bundled copy of docs/read-side.md could not be loaded." }
        return text
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("The Read Side")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Sats with thousands separators plus the unit.
func satsText(_ amount: Int64) -> String {
    "\(amount.formatted()) sats"
}

/// A double sat/vB rate, trimmed of trailing zeros.
func feeRateText(_ rate: Double) -> String {
    "\(rate.formatted(.number.precision(.fractionLength(0 ... 2)))) sat/vB"
}
