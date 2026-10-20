import Foundation
import Observation

/// Central manager for live ongoing command-line operations and background tasks.
/// Coordinates live activity state across multi-display NotchWindowControllers
/// and triggers alert banners upon task completion or failure.
@Observable
@MainActor
public final class LiveActivityManager {
    /// Stack of active live activities (latest last).
    public private(set) var activeActivities: [LiveActivityItem] = []
    
    /// Primary active live activity displayed in the notch, if any.
    public var currentActivity: LiveActivityItem? {
        activeActivities.last
    }
    
    /// Reference to the notification manager for delivering completion alert banners.
    private weak var notificationManager: NotificationManager?
    
    /// Window-specific change listeners
    private var listeners: [UUID: (LiveActivityItem?) -> Void] = [:]
    
    public init(notificationManager: NotificationManager? = nil) {
        self.notificationManager = notificationManager
    }
    
    public func setNotificationManager(_ manager: NotificationManager) {
        self.notificationManager = manager
    }
    
    // MARK: - Listener Registration
    
    public func registerListener(id: UUID, onActivityChange: @escaping (LiveActivityItem?) -> Void) {
        listeners[id] = onActivityChange
    }
    
    public func unregisterListener(id: UUID) {
        listeners.removeValue(forKey: id)
    }
    
    // MARK: - Task Lifecycle Controls
    
    /// Begins tracking a live command-line task or agent request.
    public func startActivity(
        id: String,
        title: String,
        subtitle: String = "",
        progress: Double? = nil,
        iconSystemName: String = "gearshape.arrow.triangle.2.circlepath"
    ) {
        let item = LiveActivityItem(
            id: id,
            title: title,
            subtitle: subtitle,
            progress: progress,
            iconSystemName: iconSystemName,
            startedAt: Date(),
            status: .running
        )
        activeActivities.removeAll { $0.id == id }
        activeActivities.append(item)
        broadcast()
    }
    
    /// Updates progress, current step, or status message of the active task.
    public func updateActivity(id: String, subtitle: String? = nil, progress: Double? = nil) {
        guard let index = activeActivities.firstIndex(where: { $0.id == id }) else { return }
        
        if let subtitle = subtitle {
            activeActivities[index].subtitle = subtitle
        }
        if let progress = progress {
            activeActivities[index].progress = max(0.0, min(1.0, progress))
        }
        
        broadcast()
    }
    
    /// Completes the task, removes the live activity, and raises a success alert banner.
    public func completeActivity(id: String? = nil, title: String? = nil, subtitle: String? = nil) {
        let activity: LiveActivityItem
        if let id = id, !id.isEmpty {
            guard let index = activeActivities.firstIndex(where: { $0.id == id }) else { return }
            activity = activeActivities.remove(at: index)
        } else {
            guard let last = activeActivities.popLast() else { return }
            activity = last
        }
        
        let elapsed = activity.formattedElapsedTime
        let alertTitle = title ?? "Done: \(activity.title)"
        let alertSubtitle: String
        if let customSubtitle = subtitle, !customSubtitle.isEmpty {
            if customSubtitle.lowercased().contains("finished in") || customSubtitle.contains("(in ") {
                alertSubtitle = customSubtitle
            } else {
                alertSubtitle = "\(customSubtitle) (in \(elapsed))"
            }
        } else if !activity.subtitle.isEmpty {
            alertSubtitle = "\(activity.subtitle) (in \(elapsed))"
        } else {
            alertSubtitle = "Finished in \(elapsed)"
        }
        
        broadcast()
        
        let alert = NotificationItem(
            bundleIdentifier: "com.apple.Terminal",
            appName: "Live Activity",
            title: alertTitle,
            subtitle: alertSubtitle,
            category: .activitySuccess,
            systemIcon: "checkmark.circle.fill"
        )
        notificationManager?.ingest(alert)
    }
    
    /// Flags task failure, removes live activity, and raises an error alert banner.
    public func failActivity(id: String? = nil, error: String = "Command failed") {
        let activity: LiveActivityItem
        if let id = id, !id.isEmpty {
            guard let index = activeActivities.firstIndex(where: { $0.id == id }) else { return }
            activity = activeActivities.remove(at: index)
        } else {
            guard let last = activeActivities.popLast() else { return }
            activity = last
        }
        
        let elapsed = activity.formattedElapsedTime
        let alertTitle = "Failed: \(activity.title)"
        let alertSubtitle = error.isEmpty ? "Exited with failure after \(elapsed)" : "\(error) (after \(elapsed))"
        
        broadcast()
        
        let alert = NotificationItem(
            bundleIdentifier: "com.apple.Terminal",
            appName: "Live Activity",
            title: alertTitle,
            subtitle: alertSubtitle,
            category: .activityFailure,
            systemIcon: "xmark.circle.fill"
        )
        notificationManager?.ingest(alert)
    }
    
    /// Silently cancels tracking without raising an alert.
    public func cancelActivity(id: String? = nil) {
        if let id = id, !id.isEmpty {
            guard let index = activeActivities.firstIndex(where: { $0.id == id }) else { return }
            activeActivities.remove(at: index)
        } else {
            guard !activeActivities.isEmpty else { return }
            activeActivities.removeLast()
        }
        broadcast()
    }
    
    private func broadcast() {
        for listener in listeners.values {
            listener(currentActivity)
        }
    }
}
