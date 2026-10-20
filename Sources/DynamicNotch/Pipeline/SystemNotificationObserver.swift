import AppKit
import ApplicationServices
import Foundation
import Observation

/// Intercepts live macOS system notification banners (Slack, Messages, Mail, WhatsApp, Xcode, etc.)
/// using the macOS Accessibility API (AXObserver attached to com.apple.notificationcenterui).
@Observable
@MainActor
public final class SystemNotificationObserver {
    public static let shared = SystemNotificationObserver()
    
    public var isAccessibilityGranted: Bool = false
    public var isObserving: Bool = false
    public var lastInterceptedApp: String?
    public var lastInterceptedTitle: String?
    public var onPermissionChanged: ((Bool) -> Void)?
    
    private var notificationManager: NotificationManager?
    private var observer: AXObserver?
    private var targetPid: pid_t = 0
    private var permissionCheckTimer: Task<Void, Never>?
    
    /// Cache of recently ingested alert signatures to prevent duplicate triggers from AX hierarchy events
    @ObservationIgnored
    private var recentSignatures: [String: Date] = [:]
    
    private init() {
        self.isAccessibilityGranted = AXIsProcessTrusted()
    }
    
    /// Starts the bridge with the given notification manager.
    public func start(with manager: NotificationManager) {
        self.notificationManager = manager
        self.isAccessibilityGranted = AXIsProcessTrusted()
        
        if isAccessibilityGranted {
            attachToNotificationCenter()
        } else {
            // Automatically prompt the user on startup so macOS registers the app
            // in System Settings > Privacy & Security > Accessibility and displays the prompt.
            requestAccessibilityPermission()
        }
    }
    
    /// Stops the observer and tears down runloop sources.
    public func stop() {
        permissionCheckTimer?.cancel()
        permissionCheckTimer = nil
        
        if let observer = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            self.observer = nil
        }
        self.isObserving = false
    }
    
    /// Prompts the user with macOS's native Accessibility Permission request dialog.
    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        self.isAccessibilityGranted = trusted
        if trusted {
            attachToNotificationCenter()
        } else {
            startPermissionPolling()
        }
    }
    
    /// Opens macOS System Settings directly to the Accessibility pane.
    public func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        startPermissionPolling()
    }
    
    private func startPermissionPolling() {
        permissionCheckTimer?.cancel()
        permissionCheckTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // check every 1s
                guard let self = self else { return }
                
                let trusted = AXIsProcessTrusted()
                if trusted != self.isAccessibilityGranted {
                    self.isAccessibilityGranted = trusted
                    self.onPermissionChanged?(trusted)
                    if trusted {
                        print("Accessibility permission granted! Attaching observer...")
                        self.attachToNotificationCenter()
                        break
                    }
                }
            }
        }
    }
    
    // MARK: - Accessibility Observer Attachment
    
    private func attachToNotificationCenter() {
        guard isAccessibilityGranted else { return }
        guard observer == nil else { return }
        
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui")
        guard let ncApp = apps.first else {
            print("com.apple.notificationcenterui is not running.")
            return
        }
        
        self.targetPid = ncApp.processIdentifier
        let appElement = AXUIElementCreateApplication(targetPid)
        
        var newObserver: AXObserver?
        let callback: AXObserverCallback = { observer, element, notification, refcon in
            guard let refcon = refcon else { return }
            let bridge = Unmanaged<SystemNotificationObserver>.fromOpaque(refcon).takeUnretainedValue()
            bridge.handleAXNotification(element: element, notification: notification as String)
        }
        
        let err = AXObserverCreate(targetPid, callback, &newObserver)
        guard err == .success, let obs = newObserver else {
            print("Failed to create AXObserver for NotificationCenter: \(err.rawValue)")
            return
        }
        
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        // Listen for window creation and SwiftUI banner layout events
        AXObserverAddNotification(obs, appElement, kAXWindowCreatedNotification as CFString, selfPtr)
        AXObserverAddNotification(obs, appElement, kAXCreatedNotification as CFString, selfPtr)
        AXObserverAddNotification(obs, appElement, kAXLayoutChangedNotification as CFString, selfPtr)
        AXObserverAddNotification(obs, appElement, kAXValueChangedNotification as CFString, selfPtr)
        AXObserverAddNotification(obs, appElement, kAXTitleChangedNotification as CFString, selfPtr)
        
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        self.observer = obs
        self.isObserving = true
        print("SystemNotificationObserver successfully attached to Notification Center (PID \(targetPid))")
    }
    
    // MARK: - Banner Parsing & Ingestion
    
    private func handleAXNotification(element: AXUIElement, notification: String) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.inspectForBanners(from: element)
            // Also re-check after a short delay in case AXWindowCreated fired before SwiftUI finished layout
            try? await Task.sleep(nanoseconds: 180_000_000)
            self.inspectForBanners(from: element)
        }
    }
    
    private func inspectForBanners(from rootElement: AXUIElement) {
        var bannerElements: [AXUIElement] = []
        findBannerElements(in: rootElement, results: &bannerElements, depth: 0)
        
        // If notification fired on the application or window root and no banner was directly in subtree,
        // also check the application's top-level AXWindows
        if bannerElements.isEmpty, targetPid > 0 {
            let appEl = AXUIElementCreateApplication(targetPid)
            findBannerElements(in: appEl, results: &bannerElements, depth: 0)
        }
        
        for banner in bannerElements {
            parseBannerGroup(banner)
        }
    }
    
    /// Recursively locates AXGroup elements whose subrole is AXNotificationCenterBanner or AXNotificationCenterAlert.
    private func findBannerElements(in element: AXUIElement, results: inout [AXUIElement], depth: Int) {
        guard depth < 8 else { return }
        
        var roleRef: CFTypeRef?
        let role = (AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success)
            ? (roleRef as? String)
            : nil
        
        if role == "AXMenuBar" {
            return
        }
        
        var subroleRef: CFTypeRef?
        let subrole = (AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success)
            ? (subroleRef as? String)
            : nil
        
        if subrole == "AXNotificationCenterBanner" || subrole == "AXNotificationCenterAlert" {
            results.append(element)
            return
        }
        
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                findBannerElements(in: child, results: &results, depth: depth + 1)
            }
        }
    }
    
    /// Extracts App Name, Title, and Subtitle/Body from a verified AXNotificationCenterBanner / Alert element.
    private func parseBannerGroup(_ bannerElement: AXUIElement) {
        var staticTexts: [String] = []
        extractStaticTexts(from: bannerElement, into: &staticTexts, depth: 0)
        
        staticTexts = staticTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !staticTexts.isEmpty else { return }
        
        // Extract app name from the banner group's AXDescription (format: "AppName, Title, Subtitle, Body")
        var appName = "Notification"
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(bannerElement, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let desc = descRef as? String, !desc.isEmpty {
            let parts = desc.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let firstPart = parts.first, firstPart != staticTexts.first {
                appName = firstPart
            }
        }
        
        let title: String
        let subtitle: String
        
        if staticTexts.count == 1 {
            title = staticTexts[0]
            subtitle = ""
        } else if staticTexts.count == 2 {
            title = staticTexts[0]
            subtitle = staticTexts[1]
        } else {
            // When 3+ static texts exist (e.g. Title, Subtitle, Body), combine Subtitle + Body cleanly
            title = staticTexts[0]
            subtitle = staticTexts.dropFirst().joined(separator: " • ")
        }
        
        // Deduplication: prevent processing multiple AX events for the same banner within 4s
        let signature = "\(appName)|\(title)|\(subtitle)"
        let now = Date()
        if let lastSeen = recentSignatures[signature], now.timeIntervalSince(lastSeen) < 4.0 {
            return
        }
        recentSignatures[signature] = now
        recentSignatures = recentSignatures.filter { now.timeIntervalSince($0.value) < 12.0 }
        
        self.lastInterceptedApp = appName
        self.lastInterceptedTitle = title
        
        let category = Self.categorizeApp(appName + " " + title)
        
        let item = NotificationItem(
            bundleIdentifier: Self.inferBundleIdentifier(for: appName),
            appName: appName,
            title: title,
            subtitle: subtitle,
            timestamp: now,
            category: category
        )
        
        print("🔔 Intercepted live system notification: [\(appName)] \(title) - \(subtitle)")
        self.notificationManager?.ingest(item)
    }
    
    private func extractStaticTexts(from element: AXUIElement, into values: inout [String], depth: Int) {
        guard depth < 6 else { return }
        
        var roleRef: CFTypeRef?
        let role = (AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success)
            ? (roleRef as? String)
            : nil
        
        if role == (kAXButtonRole as String) || role == (kAXScrollBarRole as String) || role == (kAXImageRole as String) {
            return
        }
        
        if role == (kAXStaticTextRole as String) {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let text = valueRef as? String {
                values.append(text)
            } else if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &valueRef) == .success,
                      let text = valueRef as? String {
                values.append(text)
            }
            return
        }
        
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                extractStaticTexts(from: child, into: &values, depth: depth + 1)
            }
        }
    }
    
    private static func inferBundleIdentifier(for appName: String) -> String {
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.localizedCaseInsensitiveCompare(appName) == .orderedSame
        }), let bundleId = running.bundleIdentifier {
            return bundleId
        }
        return "com.apple.notificationcenterui.\(appName.lowercased())"
    }
    
    private static func categorizeApp(_ app: String) -> NotificationCategory {
        let lower = app.lowercased()
        if lower.contains("slack") || lower.contains("message") || lower.contains("whatsapp") || lower.contains("telegram") || lower.contains("discord") || lower.contains("signal") {
            return .message
        } else if lower.contains("github") || lower.contains("xcode") || lower.contains("gitlab") || lower.contains("git") {
            return .codeReview
        } else if lower.contains("calendar") || lower.contains("fantastical") || lower.contains("meeting") || lower.contains("zoom") {
            return .calendar
        } else if lower.contains("mail") || lower.contains("outlook") || lower.contains("spark") {
            return .email
        } else if lower.contains("reminder") || lower.contains("todo") || lower.contains("things") {
            return .reminder
        } else {
            return .system
        }
    }
}
