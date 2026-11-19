import Foundation
import IOKit
import Observation
import WattsupCore

/// Wireless accessory batteries. The Bluetooth profile takes about a second to query, so it
/// runs at most once a minute off the main thread; HID devices are read from the registry.
@MainActor @Observable
final class AccessoryBatteryReader {
    private(set) var devices: [AccessoryBattery] = []
    @ObservationIgnored private var lastRun = Date.distantPast
    @ObservationIgnored private var running = false

    func refreshIfDue() {
        guard !running, Date().timeIntervalSince(lastRun) > 60 else { return }
        running = true
        lastRun = Date()
        Task.detached(priority: .utility) {
            let bluetooth = Self.bluetooth()
            let hid = Self.hid()
            let names = Set(bluetooth.map(\.name))
            let merged = bluetooth + hid.filter { !names.contains($0.name) }
            await MainActor.run {
                if merged.map(\.name) != self.devices.map(\.name) {
                    log.info("Accessory batteries: \(merged.count) device\(merged.count == 1 ? "" : "s")")
                }
                self.devices = merged
                self.running = false
            }
        }
    }

    nonisolated private static func bluetooth() -> [AccessoryBattery] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return AccessoryBattery.parse(bluetoothJSON: data)
        } catch {
            log.error("Could not read the Bluetooth profile: \(error.localizedDescription)")
            return []
        }
    }

    nonisolated private static func hid() -> [AccessoryBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var out: [AccessoryBattery] = []
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let d = props?.takeRetainedValue() as? [String: Any], let device = AccessoryBattery(hid: d) {
                out.append(device)
            }
        }
        return out
    }
}
