import Foundation

/// Per process energy impact as Activity Monitor reports it: a relative score, not watts.
public struct ProcessImpact: Equatable, Sendable {
    public var pid: Int32
    public var command: String
    public var impact: Double

    public init(pid: Int32, command: String, impact: Double) {
        self.pid = pid
        self.command = command
        self.impact = impact
    }
}

public struct AppImpact: Equatable, Sendable, Identifiable {
    public var name: String
    public var bundlePath: String?
    public var impact: Double
    public var processes: Int
    public var id: String { bundlePath ?? name }
}

public enum EnergyImpact {
    /// Parses `top -l 2 -stats pid,command,power` output, keeping only the last sample, since
    /// the first one is cumulative since boot. Commands may contain spaces.
    public static func parse(top output: String) -> [ProcessImpact] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        guard let header = lines.lastIndex(where: { $0.hasPrefix("PID") && $0.contains("POWER") }) else { return [] }
        return lines[(header + 1)...].compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = Int32(parts[0]), let power = Double(parts[parts.count - 1]) else { return nil }
            let command = parts[1..<(parts.count - 1)].joined(separator: " ")
            return ProcessImpact(pid: pid, command: command, impact: power)
        }
    }

    /// Groups processes by the app bundle they belong to (helpers count toward their app),
    /// falling back to the command name for processes outside any bundle.
    public static func group(_ processes: [ProcessImpact], bundleOf: (Int32) -> (name: String, path: String)?) -> [AppImpact] {
        var apps: [String: AppImpact] = [:]
        for p in processes where p.impact > 0 {
            let bundle = bundleOf(p.pid)
            let key = bundle?.path ?? p.command
            var app = apps[key] ?? AppImpact(name: bundle?.name ?? p.command, bundlePath: bundle?.path, impact: 0, processes: 0)
            app.impact += p.impact
            app.processes += 1
            apps[key] = app
        }
        return apps.values.sorted { $0.impact > $1.impact }
    }

    /// The outermost .app in a process path, so helpers inside an app's bundle map to the app.
    public static func appBundle(inPath path: String) -> (name: String, path: String)? {
        guard let range = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app") : nil) else { return nil }
        let bundlePath = String(path[..<range.upperBound]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let name = (bundlePath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        return (name, "/" + bundlePath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
