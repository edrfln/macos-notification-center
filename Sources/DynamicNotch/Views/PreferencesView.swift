import SwiftUI

/// Settings window content view providing user configurations for Dynamic Notch.
public struct PreferencesView: View {
    @Bindable var launchManager = LaunchAtLoginManager.shared
    @Bindable var systemObserver = SystemNotificationObserver.shared
    @State private var selectedTab: Int = 0
    @AppStorage(NotificationManager.alertDurationDefaultsKey) private var alertDuration: Double = 4.2
    @AppStorage(NotificationManager.playAlertSoundDefaultsKey) private var playAlertSound: Bool = false
    @AppStorage(NotificationManager.hoverExpandWhenEmptyDefaultsKey) private var hoverExpandWhenEmpty: Bool = true
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)
            
            displaysTab
                .tabItem {
                    Label("Displays", systemImage: "display.2")
                }
                .tag(1)
            
            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(2)
        }
        .frame(width: 500, height: 380)
        .padding(16)
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchManager.isEnabled },
                    set: { _ in launchManager.toggle() }
                ))
                
                Text("Status: \(launchManager.statusDescription)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("System Integration")
            }
            
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Live Notification Interception")
                            .font(.system(size: 13, weight: .medium))
                        Text(systemObserver.isAccessibilityGranted
                             ? "Connected to Notification Center • All apps active"
                             : "Requires Accessibility permission to capture third-party notifications")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if systemObserver.isAccessibilityGranted {
                        Text("Active")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                    } else {
                        Button("Grant Access") {
                            systemObserver.requestAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                
                if !systemObserver.isAccessibilityGranted {
                    Button("Open System Settings...") {
                        systemObserver.openSystemSettings()
                    }
                    .font(.caption)
                }
            } header: {
                Text("System Notification Inbox")
            } footer: {
                Text("Enables Dynamic Notch to passively capture incoming banners from Slack, Messages, Mail, WhatsApp, Xcode, and Calendar.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Alert Display Duration:")
                        Spacer()
                        Text("\(String(format: "%.1f", alertDuration))s")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $alertDuration, in: 2.5...8.0, step: 0.5)
                }
                
                Toggle("Play Sound on Incoming Alert", isOn: $playAlertSound)
                Toggle("Expand Preview on Hover When Empty", isOn: $hoverExpandWhenEmpty)
            } header: {
                Text("Banner & Hover Behavior")
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Displays Tab
    
    private var displaysTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connected Displays:")
                        .font(.headline)
                    
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        HStack {
                            Image(systemName: screen.auxiliaryTopLeftArea != nil ? "laptopcomputer" : "display")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(screen.localizedName)
                                    .font(.system(size: 12, weight: .semibold))
                                Text("\(Int(screen.frame.width)) × \(Int(screen.frame.height)) pt • \(screen.auxiliaryTopLeftArea != nil ? "Hardware Notch" : "External Top-Center")")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("Active")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 4)
                        if index < NSScreen.screens.count - 1 {
                            Divider()
                        }
                    }
                }
            } header: {
                Text("Multi-Monitor Mirroring")
            } footer: {
                Text("Dynamic Notch automatically creates an independent floating island on every connected display.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - About Tab
    
    private var aboutTab: some View {
        VStack(spacing: 12) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.black, Color(white: 0.15)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                
                Image(systemName: "capsule.portrait.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 4) {
                Text("Dynamic Notch")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Native macOS Dynamic Island Notification Center")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("Version 1.0 (Build 2026)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            Spacer()
        }
    }
}
