import Foundation
import ServiceManagement
import Observation

/// Manages macOS Ventura+ Launch at Login registration using modern SMAppService.
@Observable
@MainActor
public final class LaunchAtLoginManager {
    public static let shared = LaunchAtLoginManager()
    
    public var isEnabled: Bool = false
    public var statusDescription: String = "Disabled"
    
    private init() {
        refreshStatus()
    }
    
    public func refreshStatus() {
        // SMAppService.mainApp is available in macOS 13.0+
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            self.isEnabled = true
            self.statusDescription = "Enabled"
        case .notRegistered:
            self.isEnabled = false
            self.statusDescription = "Disabled"
        case .requiresApproval:
            self.isEnabled = false
            self.statusDescription = "Requires Approval in System Settings"
        case .notFound:
            self.isEnabled = false
            self.statusDescription = "Bundle Not Registered"
        @unknown default:
            self.isEnabled = false
            self.statusDescription = "Unknown"
        }
    }
    
    public func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }
    
    public func enable() {
        do {
            try SMAppService.mainApp.register()
            refreshStatus()
        } catch {
            print("Failed to register Launch at Login: \(error.localizedDescription)")
            refreshStatus()
        }
    }
    
    public func disable() {
        do {
            try SMAppService.mainApp.unregister()
            refreshStatus()
        } catch {
            print("Failed to unregister Launch at Login: \(error.localizedDescription)")
            refreshStatus()
        }
    }
}
