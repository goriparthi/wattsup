import Foundation
import IOKit
import os

let log = Logger(subsystem: "com.goriparthi.wattsup", category: "app")

/// Reads the AppleSmartBattery registry entry, which needs no privileges.
enum SmartBattery {
    enum Reading {
        case properties([String: Any])
        case noBattery
        case failed(String)
    }

    static func read() -> Reading {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return .noBattery }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let dict = props?.takeRetainedValue() as? [String: Any] else {
            let message = "IORegistryEntryCreateCFProperties failed with \(result)"
            log.error("\(message, privacy: .public)")
            return .failed(message)
        }
        return .properties(dict)
    }
}
