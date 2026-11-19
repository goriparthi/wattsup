import Foundation
import IOKit
import WattsupCore

/// Read only client for the AppleSMC driver: fan speeds and chip temperatures, no privileges.
/// The parameter block mirrors the driver's 80 byte SMCParamStruct exactly.
final class SMC {
    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    /// C pads this to 12 bytes; Swift would not, so the padding is spelled out
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0; var attributes: UInt8 = 0; var pad: (UInt8, UInt8, UInt8) = (0, 0, 0) }
    private struct Param {
        var key: UInt32 = 0
        var vers = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
            = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Command: UInt8 { case readKey = 5, keyFromIndex = 8, keyInfo = 9 }
    private static let handleEvent: UInt32 = 2

    private var connection: io_connect_t = 0
    private var infoCache: [UInt32: KeyInfo] = [:]

    /// Nil when the driver is missing or refuses the connection, as on some virtual machines.
    init?() {
        guard MemoryLayout<Param>.stride == 80 else {
            log.error("SMC parameter block is \(MemoryLayout<Param>.stride) bytes, expected 80; thermals disabled")
            return nil
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
            log.error("Could not open AppleSMC; thermals disabled")
            return nil
        }
    }

    deinit { IOServiceClose(connection) }

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        let inSize = MemoryLayout<Param>.stride
        var outSize = MemoryLayout<Param>.stride
        let kr = IOConnectCallStructMethod(connection, Self.handleEvent, &input, inSize, &output, &outSize)
        return kr == KERN_SUCCESS && output.result == 0 ? output : nil
    }

    private func info(_ key: UInt32) -> KeyInfo? {
        if let cached = infoCache[key] { return cached }
        var p = Param()
        p.key = key
        p.data8 = Command.keyInfo.rawValue
        guard let out = call(&p) else { return nil }
        infoCache[key] = out.keyInfo
        return out.keyInfo
    }

    func read(_ name: String) -> Double? {
        let key = SMCValue.fourCC(name)
        guard let info = info(key) else { return nil }
        var p = Param()
        p.key = key
        p.keyInfo.dataSize = info.dataSize
        p.data8 = Command.readKey.rawValue
        guard let out = call(&p) else { return nil }
        let bytes = withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(min(info.dataSize, 32)))) }
        return SMCValue.decode(type: SMCValue.string(info.dataType), bytes: bytes)
    }

    /// Every key the controller exposes. Slow (one call per key), so done once and cached.
    func allKeys() -> [String] {
        guard let count = read("#KEY"), count > 0, count < 10000 else { return [] }
        return (0..<Int(count)).compactMap { i in
            var p = Param()
            p.data8 = Command.keyFromIndex.rawValue
            p.data32 = UInt32(i)
            return call(&p).map { SMCValue.string($0.key) }
        }
    }

    func fans() -> [Fan] {
        guard let count = read("FNum"), count > 0, count < 10 else { return [] }
        return (0..<Int(count)).compactMap { i in
            guard let rpm = read("F\(i)Ac") else { return nil }
            return Fan(index: i, rpm: max(0, rpm), minRPM: read("F\(i)Mn"), maxRPM: read("F\(i)Mx"))
        }
    }
}
