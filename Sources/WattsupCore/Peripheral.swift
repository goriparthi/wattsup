import Foundation

/// A USB device the Mac is powering. macOS reports the power it allocated, not a live draw,
/// so every figure here is a ceiling and is labeled that way.
public struct Peripheral: Identifiable, Equatable, Sendable {
    public var name: String
    public var vendor: String?
    public var allocatedMilliamps: Int
    public var capabilityMilliamps: Int?
    public var locationID: Int
    public var id: Int { locationID }

    /// USB power allocations are made at the 5 V bus voltage.
    public var allocatedWatts: Double { Double(allocatedMilliamps) * 5 / 1000 }

    public init(name: String, vendor: String?, allocatedMilliamps: Int, capabilityMilliamps: Int?, locationID: Int) {
        self.name = name
        self.vendor = vendor
        self.allocatedMilliamps = allocatedMilliamps
        self.capabilityMilliamps = capabilityMilliamps
        self.locationID = locationID
    }

    /// Parses one IOUSBHostDevice entry; nil when the Mac allocated it no power.
    public init?(registry d: [String: Any]) {
        guard let allocated = d.int("UsbPowerSinkAllocation"), allocated > 0 else { return nil }
        self.init(
            name: d.string("USB Product Name") ?? d.string("kUSBProductString") ?? "USB device",
            vendor: d.string("USB Vendor Name") ?? d.string("kUSBVendorString"),
            allocatedMilliamps: allocated,
            capabilityMilliamps: d.int("UsbPowerSinkCapability"),
            locationID: d.int("locationID") ?? allocated)
    }

    public var symbolName: String {
        let n = name.lowercased()
        if n.contains("iphone") { return "iphone" }
        if n.contains("ipad") { return "ipad" }
        if n.contains("watch") { return "applewatch" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("keyboard") { return "keyboard" }
        if n.contains("mouse") || n.contains("trackpad") { return "computermouse" }
        if n.contains("hub") || n.contains("dock") { return "cable.connector.horizontal" }
        return "cable.connector"
    }
}

public extension Array where Element == Peripheral {
    var allocatedWatts: Double { reduce(0) { $0 + $1.allocatedWatts } }
}
