import Foundation

/// Notification names used for cross-process IPC dispatching via DistributedNotificationCenter.
public extension NSNotification.Name {
    static let dynamicNotchDispatch = NSNotification.Name("com.dynamicnotch.dispatchNotification")
    static let dynamicNotchActivityStart = NSNotification.Name("com.dynamicnotch.activityStart")
    static let dynamicNotchActivityUpdate = NSNotification.Name("com.dynamicnotch.activityUpdate")
    static let dynamicNotchActivityComplete = NSNotification.Name("com.dynamicnotch.activityComplete")
    static let dynamicNotchActivityFail = NSNotification.Name("com.dynamicnotch.activityFail")
}

/// Listens for IPC notifications from CLI triggers or background scripts via DistributedNotificationCenter.
@MainActor
public final class LocalNotificationServer {
    private let notificationManager: NotificationManager
    private let activityManager: LiveActivityManager
    private var observers: [any NSObjectProtocol] = []
    
    public init(notificationManager: NotificationManager, activityManager: LiveActivityManager) {
        self.notificationManager = notificationManager
        self.activityManager = activityManager
        startListening()
    }
    
    deinit {
        for observer in observers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }
    
    private func startListening() {
        let center = DistributedNotificationCenter.default()
        
        // 1. Regular notification banner dispatch
        let notifObs = center.addObserver(
            forName: .dynamicNotchDispatch,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self, let userInfo = notification.userInfo else { return }
                
                let title = userInfo["title"] as? String ?? "Alert"
                let subtitle = userInfo["subtitle"] as? String ?? ""
                let appName = userInfo["appName"] as? String ?? "Terminal"
                let categoryRaw = userInfo["category"] as? String ?? "message"
                let category = NotificationCategory(rawValue: categoryRaw) ?? .message
                
                let item = NotificationItem(
                    bundleIdentifier: "com.terminal.client",
                    appName: appName,
                    title: title,
                    subtitle: subtitle,
                    category: category
                )
                
                self.notificationManager.ingest(item)
            }
        }
        observers.append(notifObs)
        
        // 2. Live Activity: Start
        let startObs = center.addObserver(
            forName: .dynamicNotchActivityStart,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self, let userInfo = notification.userInfo else { return }
                
                let id = userInfo["id"] as? String ?? UUID().uuidString
                let title = userInfo["title"] as? String ?? "Command Executing"
                let subtitle = userInfo["subtitle"] as? String ?? ""
                let icon = userInfo["icon"] as? String ?? "gearshape.arrow.triangle.2.circlepath"
                let progressStr = userInfo["progress"] as? String
                let progress = progressStr.flatMap { Double($0) }
                
                self.activityManager.startActivity(
                    id: id,
                    title: title,
                    subtitle: subtitle,
                    progress: progress,
                    iconSystemName: icon
                )
            }
        }
        observers.append(startObs)
        
        // 3. Live Activity: Update
        let updateObs = center.addObserver(
            forName: .dynamicNotchActivityUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self, let userInfo = notification.userInfo else { return }
                
                guard let id = userInfo["id"] as? String else { return }
                let subtitle = userInfo["subtitle"] as? String
                let progressStr = userInfo["progress"] as? String
                let progress = progressStr.flatMap { Double($0) }
                
                self.activityManager.updateActivity(
                    id: id,
                    subtitle: subtitle,
                    progress: progress
                )
            }
        }
        observers.append(updateObs)
        
        // 4. Live Activity: Complete
        let completeObs = center.addObserver(
            forName: .dynamicNotchActivityComplete,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let userInfo = notification.userInfo
                let id = userInfo?["id"] as? String
                let title = userInfo?["title"] as? String
                let subtitle = userInfo?["subtitle"] as? String
                
                self.activityManager.completeActivity(
                    id: id,
                    title: title,
                    subtitle: subtitle
                )
            }
        }
        observers.append(completeObs)
        
        // 5. Live Activity: Fail
        let failObs = center.addObserver(
            forName: .dynamicNotchActivityFail,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let userInfo = notification.userInfo
                let id = userInfo?["id"] as? String
                let error = userInfo?["error"] as? String ?? "Execution error"
                
                self.activityManager.failActivity(
                    id: id,
                    error: error
                )
            }
        }
        observers.append(failObs)
    }
    
    // MARK: - Static CLI Helper Senders
    
    /// Static helper for CLI processes to dispatch an alert banner to Dynamic Notch.
    public static func postFromCLI(title: String, subtitle: String, appName: String, category: String = "message") {
        let userInfo: [String: String] = [
            "title": title,
            "subtitle": subtitle,
            "appName": appName,
            "category": category
        ]
        
        DistributedNotificationCenter.default().postNotificationName(
            .dynamicNotchDispatch,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
    
    /// Static helper to start a live activity from the CLI or external script.
    public static func postActivityStart(
        id: String,
        title: String,
        subtitle: String = "",
        icon: String = "gearshape.arrow.triangle.2.circlepath",
        progress: Double? = nil
    ) {
        var userInfo: [String: String] = [
            "id": id,
            "title": title,
            "subtitle": subtitle,
            "icon": icon
        ]
        if let progress = progress {
            userInfo["progress"] = String(progress)
        }
        
        DistributedNotificationCenter.default().postNotificationName(
            .dynamicNotchActivityStart,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
    
    /// Static helper to update ongoing activity progress or subtitle.
    public static func postActivityUpdate(
        id: String,
        subtitle: String? = nil,
        progress: Double? = nil
    ) {
        var userInfo: [String: String] = ["id": id]
        if let subtitle = subtitle {
            userInfo["subtitle"] = subtitle
        }
        if let progress = progress {
            userInfo["progress"] = String(progress)
        }
        
        DistributedNotificationCenter.default().postNotificationName(
            .dynamicNotchActivityUpdate,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
    
    /// Static helper to complete a live activity and trigger a success alert.
    public static func postActivityComplete(
        id: String,
        title: String? = nil,
        subtitle: String? = nil
    ) {
        var userInfo: [String: String] = ["id": id]
        if let title = title {
            userInfo["title"] = title
        }
        if let subtitle = subtitle {
            userInfo["subtitle"] = subtitle
        }
        
        DistributedNotificationCenter.default().postNotificationName(
            .dynamicNotchActivityComplete,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
    
    /// Static helper to flag failure and trigger an error alert.
    public static func postActivityFail(
        id: String,
        error: String
    ) {
        let userInfo: [String: String] = [
            "id": id,
            "error": error
        ]
        
        DistributedNotificationCenter.default().postNotificationName(
            .dynamicNotchActivityFail,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
}
