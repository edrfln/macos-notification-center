import AppKit
import SwiftUI

/// Preference for displaying Dynamic Notch on all connected monitors or a specific one.
public enum DisplayPreference: Equatable, Sendable {
    case allDisplays
    case screenName(String)
}

/// Main application delegate managing the stealth lifecycle, multi-screen window controllers,
/// menu bar status item, and notification ingestion.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusItem: NSStatusItem?
    public let notificationManager: NotificationManager
    public let activityManager: LiveActivityManager
    private var windowControllers: [NotchWindowController] = []
    private var localServer: LocalNotificationServer?
    private var displayPreference: DisplayPreference = .allDisplays
    
    public override init() {
        let nm = NotificationManager()
        self.notificationManager = nm
        self.activityManager = LiveActivityManager(notificationManager: nm)
        super.init()
    }
    
    @ObservationIgnored
    nonisolated(unsafe) private var screenChangeObserver: (any NSObjectProtocol)?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce stealth agent mode: no Dock icon, accessory activation policy
        NSApp.setActivationPolicy(.accessory)
        
        // Build islands for all connected screens (MacBook notch + external monitors)
        rebuildWindowControllers()
        
        // Listen for screen reconnects, resolution changes, or unplug events
        setupScreenChangeObserver()
        
        // Start local IPC notification listener (DistributedNotificationCenter)
        self.localServer = LocalNotificationServer(
            notificationManager: notificationManager,
            activityManager: activityManager
        )
        
        // Start live system notification observer (AXObserver on com.apple.notificationcenterui)
        SystemNotificationObserver.shared.onPermissionChanged = { [weak self] _ in
            self?.setupStatusItem()
        }
        SystemNotificationObserver.shared.start(with: notificationManager)
        
        // Build fallback menu bar status item
        setupStatusItem()
        
        print("Dynamic Notch initialized on \(windowControllers.count) display(s):")
        for controller in windowControllers {
            print("  - \(controller.screen.localizedName): \(controller.viewModel.geometry.hasHardwareNotch ? "Hardware Notch" : "External Top-Center")")
        }
    }
    
    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setupScreenChangeObserver() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildWindowControllers()
                self?.setupStatusItem()
            }
        }
    }
    
    /// Re-evaluates connected screens and spawns or cleans up window controllers.
    private func rebuildWindowControllers() {
        // Close and clean up existing window controllers
        for controller in windowControllers {
            controller.close()
        }
        windowControllers.removeAll()
        
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        switch displayPreference {
        case .allDisplays:
            // Spawn an island for EVERY connected display (MacBook notch AND external monitor)
            for screen in screens {
                let controller = NotchWindowController(
                    screen: screen,
                    notificationManager: notificationManager,
                    activityManager: activityManager
                )
                windowControllers.append(controller)
            }
            
        case .screenName(let targetName):
            if let matched = screens.first(where: { $0.localizedName == targetName }) {
                let controller = NotchWindowController(
                    screen: matched,
                    notificationManager: notificationManager,
                    activityManager: activityManager
                )
                windowControllers.append(controller)
            } else {
                // Fallback to all if selected screen was disconnected
                for screen in screens {
                    let controller = NotchWindowController(
                        screen: screen,
                        notificationManager: notificationManager,
                        activityManager: activityManager
                    )
                    windowControllers.append(controller)
                }
            }
        }
    }
    
    // MARK: - Menu Bar Status Item
    
    private func setupStatusItem() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "capsule.portrait.fill",
                accessibilityDescription: "Dynamic Notch"
            )
            button.imagePosition = .imageOnly
        }
        
        let menu = NSMenu(title: "Dynamic Notch")
        
        // Header info item
        let activeCount = windowControllers.count
        let infoTitle = "Dynamic Notch (\(activeCount) Display\(activeCount == 1 ? "" : "s") Active)"
        let infoItem = NSMenuItem(title: infoTitle, action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        
        if !SystemNotificationObserver.shared.isAccessibilityGranted {
            let permItem = NSMenuItem(
                title: "⚠️ Grant Live Notification Access...",
                action: #selector(requestAccessibilityPermission),
                keyEquivalent: ""
            )
            menu.addItem(permItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Simulation actions
        let simulateMenu = NSMenu(title: "Simulate Incoming Alerts")
        
        simulateMenu.addItem(NSMenuItem(title: "Slack Message", action: #selector(triggerSlackAlert), keyEquivalent: "1"))
        simulateMenu.addItem(NSMenuItem(title: "GitHub Pull Request", action: #selector(triggerGitHubAlert), keyEquivalent: "2"))
        simulateMenu.addItem(NSMenuItem(title: "Calendar Meeting", action: #selector(triggerCalendarAlert), keyEquivalent: "3"))
        simulateMenu.addItem(NSMenuItem(title: "Queue Burst (3 Alerts)", action: #selector(triggerBurstAlert), keyEquivalent: "b"))
        simulateMenu.addItem(NSMenuItem.separator())
        simulateMenu.addItem(NSMenuItem(title: "CLI Live Activity (5s Progress)", action: #selector(triggerMockLiveActivity), keyEquivalent: "4"))
        simulateMenu.addItem(NSMenuItem(title: "Now Playing Media (Music/Spotify)", action: #selector(triggerMockMediaPlayback), keyEquivalent: "5"))
        
        let simulateSubmenuItem = NSMenuItem(title: "Simulate Alert", action: nil, keyEquivalent: "")
        simulateSubmenuItem.submenu = simulateMenu
        menu.addItem(simulateSubmenuItem)
        
        menu.addItem(
            NSMenuItem(
                title: "Toggle Media Player",
                action: #selector(toggleMediaPlayer),
                keyEquivalent: "p"
            )
        )
        
        let translationItem = NSMenuItem(
            title: "Show English Lyric Translation",
            action: #selector(toggleLyricTranslation),
            keyEquivalent: "e"
        )
        translationItem.state = MediaPlaybackManager.shared.isTranslationEnabled ? .on : .off
        menu.addItem(translationItem)
        
        menu.addItem(
            NSMenuItem(
                title: "Toggle Expanded Tray",
                action: #selector(toggleExpandedTray),
                keyEquivalent: "t"
            )
        )
        
        menu.addItem(
            NSMenuItem(
                title: "Collapse to Idle",
                action: #selector(collapseToIdle),
                keyEquivalent: "i"
            )
        )
        
        menu.addItem(
            NSMenuItem(
                title: "Clear All Notifications",
                action: #selector(clearAllNotifications),
                keyEquivalent: "k"
            )
        )
        
        menu.addItem(NSMenuItem.separator())
        
        // Target Displays Submenu
        let displayMenu = NSMenu(title: "Target Displays")
        
        let allItem = NSMenuItem(
            title: "All Displays (Mirroring)",
            action: #selector(selectAllDisplays),
            keyEquivalent: ""
        )
        allItem.state = (displayPreference == .allDisplays) ? .on : .off
        displayMenu.addItem(allItem)
        
        displayMenu.addItem(NSMenuItem.separator())
        
        for screen in NSScreen.screens {
            let name = screen.localizedName
            let hasNotch = screen.auxiliaryTopLeftArea != nil && screen.safeAreaInsets.top > 0
            let title = hasNotch ? "\(name) (Hardware Notch)" : "\(name) (External)"
            
            let item = NSMenuItem(
                title: title,
                action: #selector(selectSpecificScreen(_:)),
                keyEquivalent: ""
            )
            item.representedObject = name
            
            if case .screenName(let selectedName) = displayPreference, selectedName == name {
                item.state = .on
            } else {
                item.state = .off
            }
            displayMenu.addItem(item)
        }
        
        let displaySubmenuItem = NSMenuItem(title: "Target Displays", action: nil, keyEquivalent: "")
        displaySubmenuItem.submenu = displayMenu
        menu.addItem(displaySubmenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Launch at Login
        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        menu.addItem(launchItem)
        
        // Preferences
        menu.addItem(
            NSMenuItem(
                title: "Preferences...",
                action: #selector(openPreferences),
                keyEquivalent: ","
            )
        )
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        menu.addItem(
            NSMenuItem(
                title: "Quit Dynamic Notch",
                action: #selector(quitApp),
                keyEquivalent: "q"
            )
        )
        
        item.menu = menu
        self.statusItem = item
    }
    
    // MARK: - Menu Actions
    
    @objc private func toggleLaunchAtLogin() {
        LaunchAtLoginManager.shared.toggle()
        setupStatusItem()
    }
    
    @objc private func openPreferences() {
        PreferencesWindowController.shared.show()
    }
    
    @objc private func requestAccessibilityPermission() {
        SystemNotificationObserver.shared.requestAccessibilityPermission()
        SystemNotificationObserver.shared.openSystemSettings()
    }
    
    @objc private func triggerSlackAlert() {
        MockNotificationEmitter.emitSlack(to: notificationManager)
    }
    
    @objc private func triggerGitHubAlert() {
        MockNotificationEmitter.emitGitHub(to: notificationManager)
    }
    
    @objc private func triggerCalendarAlert() {
        MockNotificationEmitter.emitCalendar(to: notificationManager)
    }
    
    @objc private func triggerBurstAlert() {
        MockNotificationEmitter.emitBurst(count: 3, to: notificationManager)
    }
    
    @objc private func triggerMockLiveActivity() {
        let id = UUID().uuidString
        activityManager.startActivity(
            id: id,
            title: "AI Agent Working",
            subtitle: "Executing codebase analysis...",
            progress: 0.2,
            iconSystemName: "sparkles"
        )
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            self?.activityManager.updateActivity(id: id, subtitle: "Generating code changes...", progress: 0.65)
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            self?.activityManager.updateActivity(id: id, subtitle: "Running build & verification...", progress: 0.95)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self?.activityManager.completeActivity(id: id, title: "Task Completed", subtitle: "All checks passed")
        }
    }
    
    @objc private func triggerMockMediaPlayback() {
        MediaPlaybackManager.shared.startSimulatedPlayback()
    }
    
    @objc private func toggleLyricTranslation() {
        MediaPlaybackManager.shared.toggleTranslation()
        setupStatusItem()
    }
    
    @objc private func toggleMediaPlayer() {
        if MediaPlaybackManager.shared.currentMedia == nil {
            MediaPlaybackManager.shared.startSimulatedPlayback()
        }
        guard let media = MediaPlaybackManager.shared.currentMedia else { return }
        for controller in windowControllers {
            let targetState: NotchState = controller.viewModel.isMediaExpanded
                ? controller.restingState
                : .mediaExpanded(media)
            controller.transition(to: targetState)
        }
    }
    
    @objc private func toggleExpandedTray() {
        for controller in windowControllers {
            let targetState: NotchState = controller.viewModel.state == .trayExpanded
                ? controller.restingState
                : .trayExpanded
            controller.transition(to: targetState)
        }
    }
    
    @objc private func collapseToIdle() {
        for controller in windowControllers {
            controller.transition(to: controller.restingState)
        }
    }
    
    @objc private func clearAllNotifications() {
        notificationManager.clearAll()
    }
    
    @objc private func selectAllDisplays() {
        displayPreference = .allDisplays
        rebuildWindowControllers()
        setupStatusItem()
    }
    
    @objc private func selectSpecificScreen(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        displayPreference = .screenName(name)
        rebuildWindowControllers()
        setupStatusItem()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
