import Foundation
import IOKit
import os
import WattsupCore


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
            log.error("\(message)")
            return .failed(message)
        }
        return .properties(dict)
    }
}

/// Lists USB devices the Mac is powering, from IOUSBHostDevice entries.
enum USBPeripherals {
    static func read() -> [Peripheral] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else {
            log.error("Could not enumerate USB devices")
            return []
        }
        defer { IOObjectRelease(iterator) }
        var found: [Peripheral] = []
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let peripheral = Peripheral(registry: dict) else { continue }
            found.append(peripheral)
        }
        return found.sorted { $0.allocatedMilliamps > $1.allocatedMilliamps }
    }
}
