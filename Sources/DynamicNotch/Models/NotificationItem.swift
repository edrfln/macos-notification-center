import Foundation
import SwiftUI

/// Functional category of the notification to configure branding and styling.
public enum NotificationCategory: String, Codable, Sendable, CaseIterable {
    case message = "message"
    case codeReview = "codeReview"
    case calendar = "calendar"
    case email = "email"
    case system = "system"
    case reminder = "reminder"
    case activitySuccess = "activitySuccess"
    case activityFailure = "activityFailure"
    
    public var defaultSymbol: String {
        switch self {
        case .message: return "message.fill"
        case .codeReview: return "arrow.triangle.branch"
        case .calendar: return "calendar"
        case .email: return "envelope.fill"
        case .system: return "gearshape.fill"
        case .reminder: return "checklist"
        case .activitySuccess: return "checkmark.circle.fill"
        case .activityFailure: return "xmark.circle.fill"
        }
    }
    
    public var themeColor: Color {
        switch self {
        case .message: return Color.blue
        case .codeReview: return Color.purple
        case .calendar: return Color.red
        case .email: return Color.cyan
        case .system: return Color.gray
        case .reminder: return Color.orange
        case .activitySuccess: return Color.green
        case .activityFailure: return Color.red
        }
    }
}

/// Strongly typed notification model supporting intake from mocks, local sockets, or macOS APIs.
public struct NotificationItem: Identifiable, Equatable, Hashable, Sendable, Codable {
    public let id: UUID
    public let bundleIdentifier: String
    public let appName: String
    public let title: String
    public let subtitle: String
    public let message: String
    public let timestamp: Date
    public let category: NotificationCategory
    public let systemIcon: String
    public let actionURL: URL?
    public var isRead: Bool
    
    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        appName: String,
        title: String,
        subtitle: String = "",
        message: String = "",
        timestamp: Date = Date(),
        category: NotificationCategory = .message,
        systemIcon: String? = nil,
        actionURL: URL? = nil,
        isRead: Bool = false
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.message = message
        self.timestamp = timestamp
        self.category = category
        self.systemIcon = systemIcon ?? category.defaultSymbol
        self.actionURL = actionURL
        self.isRead = isRead
    }
    
    /// User-friendly relative time string (e.g. "Just now", "2m ago", "1h ago").
    public var formattedTime: String {
        let seconds = -timestamp.timeIntervalSinceNow
        if seconds < 60 {
            return "Now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        }
    }
}
