import SwiftUI

// MARK: - macOS Platform Compatibility
// Provides no-op shims for iOS-only APIs so shared code compiles on both platforms.

#if os(macOS)
import AppKit

// MARK: UIImage → NSImage

typealias UIImage = NSImage

extension NSImage {
    convenience init?(systemName: String) {
        self.init(systemSymbolName: systemName, accessibilityDescription: nil)
    }

    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

// MARK: UIDevice

enum UIDevice {
    static let current = MacDevice()
}

struct MacDevice {
    var name: String { Host.current().localizedName ?? "Mac" }
    var model: String { "Mac" }
    var identifierForVendor: UUID? { nil }
}

// MARK: TextInputAutocapitalization (no-op on macOS)

enum TextInputAutocapitalization {
    case never, words, sentences, characters
}

extension View {
    func textInputAutocapitalization(_ style: TextInputAutocapitalization?) -> some View {
        self
    }
}

// MARK: navigationBarTitleDisplayMode (no-op on macOS)

enum NavigationBarTitleDisplayMode {
    case automatic, inline, large
}

extension View {
    func navigationBarTitleDisplayMode(_ displayMode: NavigationBarTitleDisplayMode) -> some View {
        self
    }
}

// MARK: UIApplication shim

enum UIApplication {
    static let shared = MacApplication()
}

struct MacWindowScene {
    var screen: MacScreen { MacScreen() }
}

struct MacScreen {
    var bounds: CGRect { NSScreen.main?.frame ?? .zero }
}

struct MacApplication {
    var connectedScenes: [MacWindowScene] { [MacWindowScene()] }
}

// Allow `as? UIWindowScene` pattern matching
typealias UIWindowScene = MacWindowScene

// MARK: Image(uiImage:) → Image(nsImage:)

extension Image {
    init(uiImage: NSImage) {
        self.init(nsImage: uiImage)
    }
}

// MARK: keyboardType (no-op on macOS)

enum UIKeyboardType {
    case `default`, decimalPad, numberPad, emailAddress, URL, asciiCapable
}

extension View {
    func keyboardType(_ type: UIKeyboardType) -> some View {
        self
    }
}

// MARK: Haptic Feedback (no-op on macOS)

enum UIImpactFeedbackStyle {
    case light, medium, heavy, soft, rigid
}

class UIImpactFeedbackGenerator {
    init(style: UIImpactFeedbackStyle) {}
    func impactOccurred() {}
}

enum UINotificationFeedbackType {
    case success, warning, error
}

class UINotificationFeedbackGenerator {
    init() {}
    func notificationOccurred(_ type: UINotificationFeedbackType) {}
}

#endif
