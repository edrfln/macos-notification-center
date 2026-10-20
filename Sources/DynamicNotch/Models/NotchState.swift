import Foundation

/// Represents the visual and operational state of the Dynamic Notch island.
public enum NotchState: Equatable, Sendable {
    /// Resting state: flush with the MacBook notch or minimal bezel pill on external monitors.
    case idle
    
    /// Ambient compact Now Playing state: flanking album art & animated audio visualizer around the notch.
    case mediaCompact(MediaItem)
    
    /// Subtle downward expansion when cursor hovers near or over the notch resting zone.
    case hoverPreview
    
    /// Notification alert banner: stretches horizontally and downwards for an incoming notification.
    case incomingAlert(NotificationItem)
    
    /// Active command-line or background process indicator (spinner, timer, progress).
    case liveActivity(LiveActivityItem)
    
    /// Full interactive Now Playing media player card with artwork, scrubber, and transport controls.
    case mediaExpanded(MediaItem)
    
    /// Full interactive notification tray expanded downwards.
    case trayExpanded
    
    /// Whether this state accepts direct user clicks/interactions.
    public var isInteractive: Bool {
        switch self {
        case .idle:
            return false
        case .mediaCompact, .hoverPreview, .incomingAlert, .trayExpanded, .liveActivity, .mediaExpanded:
            return true
        }
    }
    
    public var displayName: String {
        switch self {
        case .idle: return "Idle (Resting)"
        case .mediaCompact(let media): return "Media Pill: \(media.title)"
        case .hoverPreview: return "Hover Preview"
        case .liveActivity(let activity): return "Live Activity: \(activity.title)"
        case .incomingAlert(let item): return "Alert: \(item.title)"
        case .mediaExpanded(let media): return "Now Playing: \(media.title)"
        case .trayExpanded: return "Tray Expanded"
        }
    }
}
