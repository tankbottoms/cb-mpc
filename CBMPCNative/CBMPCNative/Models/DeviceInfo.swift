import Foundation
#if os(iOS)
import UIKit
#endif

/// Provides actual device model names (e.g., "iPhone 17 Pro Max") instead of generic "iPhone".
enum DeviceInfo {

    /// The user's custom device name (e.g., "Mark's iPhone")
    static var deviceName: String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }

    /// Human-readable model name (e.g., "iPhone 17 Pro Max", "iPad Pro 13-inch")
    static var modelName: String {
        #if os(iOS)
        let id = machineIdentifier
        return modelNameMap[id] ?? UIDevice.current.model
        #else
        return "Mac"
        #endif
    }

    /// Compact display string: "Mark's iPhone (iPhone 17 Pro Max)"
    static var displayString: String {
        "\(deviceName) (\(modelName))"
    }

    /// Unique per-app vendor identifier (stable across reinstalls if same vendor)
    static var vendorIdentifier: String {
        #if os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        #else
        return "unknown"
        #endif
    }

    /// Short vendor ID for display (first 8 chars)
    static var shortIdentifier: String {
        String(vendorIdentifier.prefix(8))
    }

    /// Hardware identifier string (e.g., "iPhone18,2")
    static var hardwareIdentifier: String {
        machineIdentifier
    }

    /// Whether iCloud is available (user signed in)
    static var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// WiFi IP address (en0 interface)
    static var wifiIPAddress: String? {
        #if os(iOS)
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            let interface = ptr!.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
        #else
        return nil
        #endif
    }

    // MARK: - Private

    private static var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }

    /// Maps hardware identifiers to human-readable names.
    /// Covers iPhone 12 through iPhone 17 and recent iPads.
    private static let modelNameMap: [String: String] = [
        // iPhone 12
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        // iPhone 13
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        // iPhone SE 3
        "iPhone14,6": "iPhone SE (3rd gen)",
        // iPhone 14
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        // iPhone 15
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        // iPhone 16
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        // iPhone 17
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone 17 Plus",
        "iPhone18,5": "iPhone 17 Air",
        // iPad Pro (M4)
        "iPad16,3": "iPad Pro 11-inch (M4)",
        "iPad16,4": "iPad Pro 11-inch (M4)",
        "iPad16,5": "iPad Pro 13-inch (M4)",
        "iPad16,6": "iPad Pro 13-inch (M4)",
        // iPad Air (M3)
        "iPad16,1": "iPad Air 11-inch (M3)",
        "iPad16,2": "iPad Air 13-inch (M3)",
        // iPad mini
        "iPad16,7": "iPad mini (A17 Pro)",
        // Simulator
        "x86_64": "Simulator",
        "arm64": "Simulator",
    ]
}
