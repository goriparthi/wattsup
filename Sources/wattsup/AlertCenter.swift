import Foundation
import UserNotifications
import WattsupCore

/// Feeds each reading to the alert rules and posts what they return as notifications.
@MainActor
final class AlertCenter {
    private var engine: AlertEngine
    private let settings: AppSettings
    /// Notifications need a real app bundle; the bare debug binary has none.
    private let canNotify = Bundle.main.bundleIdentifier != nil

    init(settings: AppSettings) {
        self.settings = settings
        engine = AlertEngine(enabled: settings.alerts, chargedLevel: settings.chargedAlertLevel)
    }

    func start() {
        guard canNotify, !settings.alerts.isEmpty else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { log.error("Notification permission failed: \(error.localizedDescription)") }
            log.info("Notifications \(granted ? "allowed" : "not allowed")")
        }
    }

    private var lastReceipt: Date?

    /// Posts a finished charging session, if the user turned receipts on.
    func receipt(_ session: ChargingSession?, chargerName: String?) {
        guard let session, session.start != lastReceipt else { return }
        lastReceipt = session.start
        guard canNotify, settings.alerts.contains(.chargingReceipt) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Charged on \(chargerName ?? session.chargerTitle)"
        content.body = session.summary
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "receipt-\(session.start.timeIntervalSince1970)",
                                                                    content: content, trigger: nil)) { error in
            if let error { log.error("Could not post a receipt: \(error.localizedDescription)") }
        }
    }

    func evaluate(_ snapshot: PowerSnapshot?, _ assessment: ChargerAssessment?) {
        guard let snapshot else { return }
        engine.enabled = settings.alerts
        engine.chargedLevel = settings.chargedAlertLevel
        for event in engine.evaluate(snapshot, assessment: assessment) {
            log.info("Alert: \(event.title)")
            guard canNotify else { continue }
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            let request = UNNotificationRequest(identifier: "\(event.kind.rawValue)-\(Date().timeIntervalSince1970)",
                                                content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error { log.error("Could not post notification: \(error.localizedDescription)") }
            }
        }
    }
}
