import Foundation
import SwiftUI

/// Lifecycle status of an ongoing command-line or background task.
public enum ActivityStatus: Equatable, Sendable, Codable {
    case running
    case completed(message: String)
    case failed(error: String)
}

/// Represents an active ongoing command-line operation or background process displayed in the Dynamic Notch.
public struct LiveActivityItem: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public var title: String
    public var subtitle: String
    public var progress: Double? // 0.0 to 1.0, or nil for indeterminate spinner
    public var iconSystemName: String
    public var startedAt: Date
    public var status: ActivityStatus
    
    public init(
        id: String,
        title: String,
        subtitle: String = "",
        progress: Double? = nil,
        iconSystemName: String = "gearshape.arrow.triangle.2.circlepath",
        startedAt: Date = Date(),
        status: ActivityStatus = .running
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.iconSystemName = iconSystemName
        self.startedAt = startedAt
        self.status = status
    }
    
    /// Elapsed seconds since task start.
    public var elapsedSeconds: Int {
        Int(Date().timeIntervalSince(startedAt))
    }
    
    /// User-friendly formatted elapsed time (e.g. "0:42", "2:15").
    public var formattedElapsedTime: String {
        formattedElapsedTime(at: Date())
    }
    
    /// User-friendly formatted elapsed time relative to a given reference date.
    public func formattedElapsedTime(at date: Date) -> String {
        let elapsed = max(0, Int(date.timeIntervalSince(startedAt)))
        let mins = elapsed / 60
        let secs = elapsed % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
