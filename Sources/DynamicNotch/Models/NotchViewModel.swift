import AppKit
import Foundation
import Observation

/// Central observable state coordinator for Dynamic Island sizing, modes, and animation triggers.
@Observable
@MainActor
public final class NotchViewModel {
    public var state: NotchState = .idle
    public var geometry: ScreenGeometry = .fallback
    public var isMouseInside: Bool = false
    public var lastEventTimestamp: Date = Date()
    
    /// The notification data manager driving unread counts and alerts
    public let notificationManager: NotificationManager
    
    /// Live ongoing command-line or background tasks manager
    public let activityManager: LiveActivityManager
    
    /// Live Now Playing media playback manager
    public let mediaManager: MediaPlaybackManager
    
    public var unreadCount: Int {
        notificationManager.unreadCount
    }
    
    public var currentActivity: LiveActivityItem? {
        activityManager.currentActivity
    }
    
    public var currentMedia: MediaItem? {
        mediaManager.currentMedia
    }
    
    public var isLiveActivity: Bool {
        if case .liveActivity = state { return true }
        return false
    }
    
    public var isMediaCompact: Bool {
        if case .mediaCompact = state { return true }
        return false
    }
    
    public var isMediaExpanded: Bool {
        if case .mediaExpanded = state { return true }
        return false
    }
    
    public init(
        geometry: ScreenGeometry = .fallback,
        notificationManager: NotificationManager? = nil,
        activityManager: LiveActivityManager? = nil,
        mediaManager: MediaPlaybackManager? = nil
    ) {
        let nm = notificationManager ?? NotificationManager()
        self.geometry = geometry
        self.notificationManager = nm
        self.activityManager = activityManager ?? LiveActivityManager(notificationManager: nm)
        self.mediaManager = mediaManager ?? MediaPlaybackManager.shared
    }
    
    /// Updates screen geometry model and recalculates current layouts.
    public func updateGeometry(_ newGeometry: ScreenGeometry) {
        self.geometry = newGeometry
    }
    
    /// Programmatically trigger an alert using the notification manager pipeline.
    public func triggerAlert(title: String, subtitle: String, appName: String, category: NotificationCategory = .message) {
        let item = NotificationItem(
            bundleIdentifier: "com.dynamicnotch.test",
            appName: appName,
            title: title,
            subtitle: subtitle,
            category: category
        )
        notificationManager.ingest(item)
    }
}
