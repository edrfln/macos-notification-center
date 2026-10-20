import AppKit
import Foundation
import Observation

/// Central data store and queue manager for unread notifications and incoming alert banners.
@Observable
@MainActor
public final class NotificationManager {
    public static let alertDurationDefaultsKey = "DynamicNotch.alertDuration"
    public static let playAlertSoundDefaultsKey = "DynamicNotch.playAlertSound"
    public static let hoverExpandWhenEmptyDefaultsKey = "DynamicNotch.hoverExpandWhenEmpty"
    
    /// All received notifications, ordered latest first.
    public var notifications: [NotificationItem] = []
    
    /// Unread count for displaying badge dots and counters.
    public var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }
    
    /// Current notification item being actively displayed in the alert banner.
    public var activeAlert: NotificationItem?
    
    /// FIFO queue for incoming notifications while an alert is already on-screen.
    private var alertQueue: [NotificationItem] = []
    
    /// Auto-dismiss timer task for the active alert.
    @ObservationIgnored
    private var autoDismissTask: Task<Void, Never>?
    
    /// Multi-window presentation listeners
    private var alertListeners: [UUID: (NotificationItem) -> Void] = [:]
    private var dismissListeners: [UUID: () -> Void] = [:]
    private var storeChangeListeners: [UUID: () -> Void] = [:]
    
    public var configuredAlertDuration: TimeInterval {
        let val = UserDefaults.standard.double(forKey: Self.alertDurationDefaultsKey)
        return val >= 1.5 ? val : 4.2
    }
    
    public var shouldPlayAlertSound: Bool {
        if UserDefaults.standard.object(forKey: Self.playAlertSoundDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: Self.playAlertSoundDefaultsKey)
    }
    
    public init() {
        if UserDefaults.standard.object(forKey: Self.alertDurationDefaultsKey) == nil {
            UserDefaults.standard.set(4.2, forKey: Self.alertDurationDefaultsKey)
        }
        if UserDefaults.standard.object(forKey: Self.hoverExpandWhenEmptyDefaultsKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.hoverExpandWhenEmptyDefaultsKey)
        }
        
        // Seed with initial mock notifications so the tray is visually rich out of the box
        self.notifications = [
            NotificationItem(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                appName: "Slack",
                title: "Engineering Team",
                subtitle: "Alex: Window tracking and notch exclusion look awesome!",
                timestamp: Date().addingTimeInterval(-180),
                category: .message
            ),
            NotificationItem(
                bundleIdentifier: "com.github.GitHubClient",
                appName: "GitHub",
                title: "PR #42 Merged",
                subtitle: "Dynamic Notch: Phase 1 & 2 verified on M1 Pro",
                timestamp: Date().addingTimeInterval(-900),
                category: .codeReview
            )
        ]
    }
    
    // MARK: - Multi-Window Listener Registration
    
    public func registerListener(
        id: UUID,
        onAlert: @escaping (NotificationItem) -> Void,
        onDismiss: @escaping () -> Void,
        onStoreChange: (() -> Void)? = nil
    ) {
        alertListeners[id] = onAlert
        dismissListeners[id] = onDismiss
        if let onStoreChange = onStoreChange {
            storeChangeListeners[id] = onStoreChange
        }
    }
    
    public func unregisterListener(id: UUID) {
        alertListeners.removeValue(forKey: id)
        dismissListeners.removeValue(forKey: id)
        storeChangeListeners.removeValue(forKey: id)
    }
    
    private func notifyStoreChanged() {
        for listener in storeChangeListeners.values {
            listener()
        }
    }
    
    // MARK: - Ingestion & Queueing
    
    /// Ingests a new notification from any provider (Mock, Socket, System).
    public func ingest(_ item: NotificationItem) {
        // Insert at beginning of tray list
        notifications.insert(item, at: 0)
        notifyStoreChanged()
        
        if activeAlert == nil {
            presentAlert(item)
        } else {
            // Queue for sequential presentation once current alert finishes
            alertQueue.append(item)
        }
    }
    
    /// Presents an alert banner for the given item and schedules auto-dismissal.
    public func presentAlert(_ item: NotificationItem, duration: TimeInterval? = nil) {
        autoDismissTask?.cancel()
        self.activeAlert = item
        
        if shouldPlayAlertSound {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
        
        for listener in alertListeners.values {
            listener(item)
        }
        
        scheduleAutoDismiss(after: duration ?? configuredAlertDuration)
    }
    
    /// Pauses the active alert's auto-dismiss timer while the user hovers over the banner.
    public func pauseAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
    }
    
    /// Resumes the active alert's auto-dismiss timer after the cursor leaves the banner.
    public func resumeAutoDismiss(remainingDuration: TimeInterval = 2.0) {
        guard activeAlert != nil else { return }
        scheduleAutoDismiss(after: remainingDuration)
    }
    
    private func scheduleAutoDismiss(after duration: TimeInterval) {
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismissActiveAlert(userInitiated: false)
        }
    }
    
    /// Dismisses the active alert banner and drains the queue if pending items exist.
    public func dismissActiveAlert(userInitiated: Bool = true) {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        self.activeAlert = nil
        
        if let nextItem = alertQueue.first {
            alertQueue.removeFirst()
            // Brief gap for smooth spring transition between consecutive alerts
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.presentAlert(nextItem)
            }
        } else {
            for listener in dismissListeners.values {
                listener()
            }
        }
    }
    
    // MARK: - Tray & Activation Actions
    
    /// Activates the source application or action URL associated with a notification item and marks it as read.
    public func activate(item: NotificationItem) {
        markAsRead(id: item.id)
        
        if let actionURL = item.actionURL {
            NSWorkspace.shared.open(actionURL)
            return
        }
        
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleIdentifier) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            return
        }
        
        // Fallback: try matching running application by localized name
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.localizedCaseInsensitiveCompare(item.appName) == .orderedSame
        }) {
            runningApp.activate()
        }
    }
    
    /// Removes a specific notification from the store.
    public func dismiss(id: UUID) {
        notifications.removeAll { $0.id == id }
        notifyStoreChanged()
    }
    
    /// Marks a notification as read.
    public func markAsRead(id: UUID) {
        if let index = notifications.firstIndex(where: { $0.id == id }) {
            notifications[index].isRead = true
            notifyStoreChanged()
        }
    }
    
    /// Clears all notifications from the store.
    public func clearAll() {
        notifications.removeAll()
        alertQueue.removeAll()
        notifyStoreChanged()
        dismissActiveAlert(userInitiated: true)
    }
}
