import Foundation

/// Emitter for creating realistic mock notifications and stress-testing alert queues.
@MainActor
public enum MockNotificationEmitter {
    
    public static func emitSlack(to manager: NotificationManager) {
        let item = NotificationItem(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            appName: "Slack",
            title: "#mobile-infra",
            subtitle: "Sarah: The new Dynamic Island matched geometry looks incredible!",
            timestamp: Date(),
            category: .message,
            systemIcon: "bubble.left.and.bubble.right.fill"
        )
        manager.ingest(item)
    }
    
    public static func emitGitHub(to manager: NotificationManager) {
        let item = NotificationItem(
            bundleIdentifier: "com.github.GitHubClient",
            appName: "GitHub",
            title: "PR #108 Approved",
            subtitle: "lgtm: Phase 3 fluid animations and Phase 4 queue passed review",
            timestamp: Date(),
            category: .codeReview,
            systemIcon: "arrow.triangle.branch"
        )
        manager.ingest(item)
    }
    
    public static func emitCalendar(to manager: NotificationManager) {
        let item = NotificationItem(
            bundleIdentifier: "com.apple.iCal",
            appName: "Calendar",
            title: "Architecture Review",
            subtitle: "Starting in 5 minutes • Room 4B / Zoom",
            timestamp: Date(),
            category: .calendar,
            systemIcon: "calendar.badge.clock"
        )
        manager.ingest(item)
    }
    
    public static func emitMail(to manager: NotificationManager) {
        let item = NotificationItem(
            bundleIdentifier: "com.apple.mail",
            appName: "Mail",
            title: "Apple Developer Relations",
            subtitle: "Your app submission has been approved for release.",
            timestamp: Date(),
            category: .email,
            systemIcon: "envelope.badge.fill"
        )
        manager.ingest(item)
    }
    
    /// Emits a burst of multiple notifications in rapid succession to test FIFO queue draining.
    public static func emitBurst(count: Int = 3, to manager: NotificationManager) {
        let presets = [
            ("Slack", "Design Sync", "Can we check the corner radius on the pill?", NotificationCategory.message),
            ("GitHub", "CI Pipeline", "Build #841 completed successfully in 42s", NotificationCategory.codeReview),
            ("Calendar", "1:1 with Tech Lead", "In 10 minutes", NotificationCategory.calendar),
            ("Reminders", "Ship Phase 4", "Due today at 5:00 PM", NotificationCategory.reminder)
        ]
        
        for i in 0..<min(count, presets.count) {
            let p = presets[i]
            let item = NotificationItem(
                bundleIdentifier: "com.test.\(p.0.lowercased())",
                appName: p.0,
                title: p.1,
                subtitle: p.2,
                timestamp: Date(),
                category: p.3
            )
            manager.ingest(item)
        }
    }
    
    public static func emitRandom(to manager: NotificationManager) {
        let choices: [(NotificationManager) -> Void] = [
            emitSlack,
            emitGitHub,
            emitCalendar,
            emitMail
        ]
        choices.randomElement()?(manager)
    }
}
