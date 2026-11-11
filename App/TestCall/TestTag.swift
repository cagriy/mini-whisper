import SwiftUI

/// The TEST chip that marks a test call, and the TEST tag colours (design §5.4).
struct TestTag: View {
    static let color = rgb(0x7A4FD0)
    static let fill = rgb(0xF1ECFB)
    static let border = rgb(0xDDD0F5)

    var body: some View {
        Text("TEST")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Self.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Self.fill))
            .overlay(Capsule().stroke(Self.border))
            .fixedSize()
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double(hex >> 16 & 0xFF) / 255,
            green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
