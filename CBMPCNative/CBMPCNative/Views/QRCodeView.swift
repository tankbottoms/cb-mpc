import SwiftUI
import CoreImage

struct QRCodeView: View {
    let data: String
    var size: CGFloat = 160
    var showBorder: Bool = true

    var body: some View {
        if let image = generateQR(data) {
            let qrImage = Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)

            if showBorder {
                qrImage
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.black, lineWidth: 3)
                    )
            } else {
                qrImage
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "qrcode")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("QR Generation Failed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: size, height: size)
        }
    }

    private func generateQR(_ string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }

        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")

        guard let output = filter?.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    VStack(spacing: 16) {
        QRCodeView(data: "02a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6")
        Text("Public Key")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
}
