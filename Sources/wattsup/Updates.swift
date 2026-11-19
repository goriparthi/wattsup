// Update check against GitHub releases, plus a verified in-place install. Ported from RedLine.
// The update check is the only network request Wattsup makes, and it can be turned off.
import AppKit
import Foundation
import Observation
import WattsupCore

enum Updates {
    static let repoURL = URL(string: "https://github.com/goriparthi/wattsup")!
    static let latestURL = URL(string: "https://api.github.com/repos/goriparthi/wattsup/releases/latest")!
    /// Updates are swapped in only when signed by this Developer ID team as this bundle id.
    static let expectedTeamID = "QX3NQYWX6F"
    static let expectedBundleID = "com.goriparthi.wattsup"
    static let downloadHosts: Set<String> = ["github.com", "objects.githubusercontent.com",
                                             "release-assets.githubusercontent.com"]

    enum Result {
        case upToDate
        case available(version: String, page: URL, dmg: URL?)
        case failed(String)
    }

    static let noReleases = "No releases published yet"

    static var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func check(currentVersion: String) async -> Result {
        var req = URLRequest(url: latestURL)
        req.timeoutInterval = 12
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                return .failed(status == 404 ? noReleases : "Update check failed (HTTP \(status))")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
                log.error("Release payload was not the expected JSON (\(data.count) bytes)")
                return .failed("Update check failed: unexpected response")
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let dmg = (json["assets"] as? [[String: Any]])?
                .compactMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
                .first { $0.pathExtension == "dmg" && isTrustedDownload($0) }
            return VersionCompare.isNewer(latest, than: currentVersion)
                ? .available(version: latest, page: page, dmg: dmg) : .upToDate
        } catch {
            return .failed("Update check failed: \(error.localizedDescription)")
        }
    }

    static func isTrustedDownload(_ url: URL) -> Bool {
        url.scheme == "https" && downloadHosts.contains(url.host?.lowercased() ?? "")
    }

    // MARK: In-place install

    enum StageResult {
        case ready(swap: () -> Void)
        case failed(String)
    }

    /// Downloads, mounts and verifies the DMG, then stages the new bundle beside a swap helper.
    /// Nothing touches the installed app until the caller runs `swap` and quits.
    static func stage(dmg: URL, version: String, replacing target: URL) async -> StageResult {
        guard isTrustedDownload(dmg) else { return .failed("Update rejected: unexpected download location") }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("wattsup-update-\(UUID().uuidString)")
        let image = work.appendingPathComponent("update.dmg")
        do {
            let (tmp, _) = try await URLSession.shared.download(from: dmg)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            try fm.moveItem(at: tmp, to: image)
        } catch {
            return .failed("Download failed: \(error.localizedDescription)")
        }
        return await Task.detached(priority: .userInitiated) {
            verifyAndStage(image: image, work: work, target: target, version: version)
        }.value
    }

    private static func verifyAndStage(image: URL, work: URL, target: URL, version: String) -> StageResult {
        let fm = FileManager.default
        func fail(_ message: String) -> StageResult {
            try? fm.removeItem(at: work)
            log.error("Update rejected: \(message)")
            return .failed(message)
        }

        let attach = run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly",
                                              "-mountrandom", fm.temporaryDirectory.path])
        guard attach.status == 0,
              let mount = attach.output.split(separator: "\n").last?
                  .split(separator: "\t").last.map({ $0.trimmingCharacters(in: .whitespaces) })
        else { return fail("Could not open the downloaded image") }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount, "-quiet"]) }

        // A real directory only; a symlink could point anywhere on disk
        guard let app = (try? fm.contentsOfDirectory(atPath: mount))?
            .filter({ $0.hasSuffix(".app") })
            .map({ (mount as NSString).appendingPathComponent($0) })
            .first(where: { (try? fm.attributesOfItem(atPath: $0)[.type] as? FileAttributeType) == .typeDirectory })
        else { return fail("No app inside the downloaded image") }

        // Copy first, then verify the copy, so what is checked is exactly what gets installed
        let staged = work.appendingPathComponent("staged.app")
        guard run("/bin/cp", ["-R", app, staged.path]).status == 0 else {
            return fail("Could not copy the new version")
        }
        guard run("/usr/sbin/spctl", ["-a", "-t", "exec", staged.path]).status == 0 else {
            return fail("Update rejected: not accepted by Gatekeeper")
        }
        // Team and bundle id enforced as a code signing requirement, so the match is cryptographic
        let requirement = "identifier \"\(expectedBundleID)\" and anchor apple generic "
            + "and certificate leaf[subject.OU] = \"\(expectedTeamID)\""
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=\(requirement)", staged.path]).status == 0 else {
            return fail("Update rejected: unexpected signing identity")
        }
        let info = Bundle(url: staged)?.infoDictionary ?? [:]
        guard info["CFBundleIdentifier"] as? String == expectedBundleID else {
            return fail("Update rejected: not Wattsup")
        }
        let stagedVersion = info["CFBundleShortVersionString"] as? String ?? "0"
        guard stagedVersion == version, VersionCompare.isNewer(stagedVersion, than: bundleVersion) else {
            return fail("Update rejected: version \(stagedVersion) is not the advertised \(version)")
        }

        let script = work.appendingPathComponent("swap.sh")
        let body = """
        #!/bin/bash
        PID=$1; TARGET=$2; STAGED=$3; WORK=$4
        for _ in $(seq 1 150); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
        rm -rf "$TARGET"
        if mv "$STAGED" "$TARGET"; then
            open "$TARGET"
        else
            osascript -e 'display notification "Update failed; reinstall from the release page." with title "Wattsup"'
        fi
        rm -rf "$WORK"
        """
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch { return fail("Could not write the update helper") }

        return .ready(swap: {
            // nohup and & detach the helper so it outlives this process
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = ["-c", "nohup /bin/bash \(shq(script.path)) \(getpid()) \(shq(target.path)) "
                + "\(shq(staged.path)) \(shq(work.path)) >/dev/null 2>&1 &"]
            try? p.run()
            p.waitUntilExit()
        })
    }

    private static func shq(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (127, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

/// Runs the daily background check and the user's Check for Updates, and owns the dialogs.
@MainActor @Observable
final class UpdateController {
    private(set) var status = "Version \(Updates.bundleVersion)"
    private(set) var busy = false
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var timer: Timer?
    private static let lastCheckKey = "lastUpdateCheck"
    private static let interval: TimeInterval = 24 * 3600

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Looks hourly whether a day has passed, so sleep or a late launch never skips a check.
    func start() {
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.checkIfDue() }
    }

    private func checkIfDue() {
        guard settings.checksForUpdates else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= Self.interval else { return }
        Task { await check(interactive: false) }
    }

    /// Interactive checks answer every outcome; background checks only speak up for an update.
    func check(interactive: Bool) async {
        guard !busy else { return }
        busy = true
        status = "Checking…"
        log.info("Update check (\(interactive ? "asked" : "daily"))")
        let result = await Updates.check(currentVersion: Updates.bundleVersion)
        busy = false
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

        switch result {
        case .upToDate:
            status = "Up to date (\(Updates.bundleVersion))"
            if interactive { inform("You're up to date", "Wattsup \(Updates.bundleVersion) is the latest release.") }
        case .failed(let message):
            status = message
            // An empty releases page is a normal state, not a failure worth flagging in diagnostics
            if message == Updates.noReleases { log.info(message) } else { log.error(message) }
            if interactive { inform("Update check failed", message) }
        case .available(let version, let page, let dmg):
            status = "Update available: \(version)"
            log.info("Update available: \(version)")
            offer(version: version, page: page, dmg: dmg)
        }
    }

    private func offer(version: String, page: URL, dmg: URL?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Wattsup \(version) is available"
        alert.informativeText = "You have \(Updates.bundleVersion)."
        let canInstall = dmg != nil && Bundle.main.bundleURL.pathExtension == "app"
        if canInstall { alert.addButton(withTitle: "Install and Relaunch") }
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        if canInstall, response == .alertFirstButtonReturn, let dmg {
            Task { await install(dmg: dmg, version: version) }
        } else if response == (canInstall ? .alertSecondButtonReturn : .alertFirstButtonReturn) {
            NSWorkspace.shared.open(page)
        }
    }

    private func install(dmg: URL, version: String) async {
        busy = true
        status = "Downloading \(version)…"
        let result = await Updates.stage(dmg: dmg, version: version, replacing: Bundle.main.bundleURL)
        busy = false
        switch result {
        case .failed(let message):
            status = message
            inform("Update not installed", message)
        case .ready(let swap):
            status = "Relaunching…"
            log.info("Update \(version) verified; relaunching into it")
            swap()
            NSApp.terminate(nil)
        }
    }

    private func inform(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
