# Dynamic Notch: Architecture Plan & Implementation Checklist

A native macOS agent utility (`LSUIElement = true`) floating over the MacBook display notch (and top-center on external displays) providing an iPhone-inspired Dynamic Island notification  center.

---

## 1. Project Vision & Core Mechanics

1. **Stealth Agent:** Runs without a Dock icon (`LSUIElement = true` / `NSApp.setActivationPolicy(.accessory)`). Provides an `NSStatusItem` in the system menu bar for controls, simulation, display targeting, and preferences.
2. **Anchor Geometry & Notch Exclusion:** Floats at `.statusBar` level (`NSWindow.Level.statusBar`). Uses `NSScreen.auxiliaryTopLeftArea` and `NSScreen.auxiliaryTopRightArea` to identify hardware notch cutouts on MacBook screens, creating flanking "ears" for resting indicators and adding safe top insets for below-notch readability.
3. **Multi-Display Mirroring:** Provisions an independent `NotchWindowController` for every connected display (MacBook hardware notch + external displays like LG FHD 1080p).
4. **Fluid Presentation Shell:** Built using continuous corner radii (`RoundedRectangle(cornerRadius:style:.continuous)`), specular glass highlights, and Apple-tuned spring curves (`response: 0.38, damping: 0.78`).
5. **Reactive Ingestion & FIFO Queue:** Strongly typed `NotificationItem` pipeline with FIFO queueing in `NotificationManager` to sequentially drain rapid bursts of notifications.
6. **IPC & CLI Dispatching:** Listens to `DistributedNotificationCenter` so external terminal commands, scripts, or build hooks can post alerts via `DynamicNotch <title> [subtitle] [appName] [category]`.

---

## 2. Six-Phase Implementation Roadmap & Checklist

### Phase 1: Window Architecture & Screen Geometry
- [x] Configure `NSPanel` subclass (`NotchPanel`) with style mask `[.nonactivatingPanel, .borderless]`.
- [x] Set window level to `.statusBar` (`CGWindowLevelForKey(.statusWindow)`).
- [x] Configure collection behavior: `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`.
- [x] Enable window transparency (`isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`).
- [x] Prevent stealing keyboard or main focus (`canBecomeKey = false`, `canBecomeMain = false`).
- [x] Detect physical MacBook notch via `screen.auxiliaryTopLeftArea`, `screen.auxiliaryTopRightArea`, and `safeAreaInsets.top > 0`.
- [x] Compute exact hardware notch cutout dimensions: `width = right.minX - left.maxX`, `height = safeAreaInsets.top`.
- [x] Implement fallback top-center geometry for external displays (`width = 160.0`, `height = 32.0`, `centerX = screen.frame.midX`).
- [x] Observe `NSApplication.didChangeScreenParametersNotification` for display plug/unplug and resolution changes.

### Phase 2: Dynamic Sizing & Smooth Tracking
- [x] Implement two-tier window sizing coordination to eliminate WindowServer IPC resizing jitter:
  - **Expanding:** Instantly enlarge `NSPanel.frame` without animation, then run SwiftUI spring animation inside the canvas.
  - **Collapsing:** Run SwiftUI spring back to resting size, wait ~320ms for spring settle, then shrink `NSPanel.frame`.
- [x] Implement custom `TrackingHostingView: NSHostingView` with active `NSTrackingArea`:
  - Options: `[.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]`.
- [x] Implement 220ms mouse exit debounce to prevent jitter along edges.
- [x] Implement granular `hitTest(_:)` predicate to pass clicks through to underlying apps when outside the visible island.
- [x] Add `ScreenGeometry` model computing state-based dimensions and corner radii.

### Phase 3: SwiftUI UI System & Fluid States
- [x] Build Dynamic Island visual shell using continuous corner radius capsules (`RoundedRectangle(cornerRadius:style:.continuous)`).
- [x] Implement multi-stop specular sheen border (`LinearGradient` with 0.8pt stroke) and ambient drop shadows.
- [x] Build explicit state machine in `NotchState`:
  - `.idle`: Resting state (flush notch mask with flanking ears on MacBook; compact pill on external displays).
  - `.hoverPreview`: Subtle downward expansion (`"2 unread • Open ▼"`).
  - `.incomingAlert(NotificationItem)`: Liquid pill stretch into alert banner.
  - `.trayExpanded`: Full interactive notification center tray.
- [x] Implement `AlertBannerView` with category gradients, title, subtitle, open action, and dismiss trigger.
- [x] Implement `TrayNotificationRow` card with hover-revealed action buttons ("Mark Read", "Dismiss").
- [x] Implement notch exclusion zone spacer (`safeContentTopInset = notchHeight`) so all content renders safely below the physical camera housing.
- [x] Implement flanking notch ears in `.idle` so unread bell icon and glowing dot render in visible display pixels beside the notch.

### Phase 4: Notification Data Store & Ingestion Pipeline
- [x] Define strongly typed `NotificationItem` model:
  - `id: UUID`, `bundleIdentifier`, `appName`, `title`, `subtitle`, `message`, `timestamp`, `category`, `systemIcon`, `actionURL`, `isRead`.
- [x] Implement `NotificationCategory` enum (`message`, `codeReview`, `calendar`, `email`, `system`, `reminder`) with theme colors and default SF Symbols.
- [x] Implement centralized `@Observable @MainActor NotificationManager`:
  - Stores notifications (latest first).
  - Dynamic `unreadCount` calculation.
  - FIFO `alertQueue` for handling bursts of incoming notifications sequentially.
  - Auto-dismiss timer (4.2 seconds) with smooth transitions between queued alerts.
  - Methods: `ingest(_:)`, `dismiss(id:)`, `markAsRead(id:)`, `clearAll()`.
- [x] Implement `MockNotificationEmitter` with realistic presets (Slack, GitHub, Calendar, Mail) and a 3-alert burst stress tester.
- [x] Implement `LocalNotificationServer` using `DistributedNotificationCenter` for cross-process IPC.
- [x] Support CLI alert dispatching from `main.swift`: `DynamicNotch <title> [subtitle] [appName] [category]`.
- [x] Implement `SystemNotificationObserver` using macOS Accessibility API (`AXObserver` on `com.apple.notificationcenterui`) to passively capture live third-party notifications (Slack, Messages, Mail, WhatsApp, Xcode, Calendar, etc.) in real time.

### Phase 5: App Lifecycle, Menu Bar Controls & Preferences
- [x] Enforce stealth agent mode: `NSApp.setActivationPolicy(.accessory)` and `LSUIElement = true` in `Info.plist`.
- [x] Implement comprehensive `NSStatusItem` in the system menu bar:
  - Active display count badge.
  - Quick simulation submenu with keyboard shortcuts (`Cmd+1` Slack, `Cmd+2` GitHub, `Cmd+3` Calendar, `Cmd+B` Burst).
  - Tray triggers: Toggle Tray (`Cmd+T`), Collapse to Idle (`Cmd+I`), Clear All (`Cmd+K`).
  - Target Displays submenu (All Displays Mirroring, LG FHD, Built-in Retina Display).
  - Launch at Login toggle.
  - Preferences window trigger (`Cmd+,`).
  - Quit (`Cmd+Q`).
- [x] Implement modern macOS Ventura+ Launch at Login via `SMAppService.mainApp` in `LaunchAtLoginManager`.
- [x] Build native tabbed `PreferencesView` (General, Displays, About) in SwiftUI.
- [x] Build `PreferencesWindowController` for standalone settings window management.

### Phase 6: Edge Cases & Multi-Display Polish
- [x] Ensure mouse events pass through to underlying windows when idle and collapsed (`hitTest` predicate returning `nil`).
- [x] Implement outside-click dismissal: clicking on another app or desktop while the tray is expanded automatically collapses back to `.idle` via `NSEvent.addGlobalMonitorForEvents`.
- [x] Prevent Mission Control displacement: `.stationary` collection behavior keeps the island pinned during window exposés.
- [x] Prevent virtual desktop (Spaces) switching glitches: `.canJoinAllSpaces` and `.fullScreenAuxiliary` keep the island floating seamlessly above full-screen spaces.
- [x] Observe `NSWorkspace.activeSpaceDidChangeNotification` to preserve `.orderFrontRegardless()` z-ordering across Spaces.
- [x] Implement simultaneous multi-display mirroring:
  - Spawns a dedicated `NotchWindowController` for every connected display.
  - Broadcasts incoming alert banners across all screens simultaneously.
  - Supports display hotplugging and dynamic reconfiguration.

### Phase 7: Live Activities & CLI Progress Tracking
- [x] Implement `LiveActivityItem` model (`id`, `title`, `subtitle`, `progress`, `iconSystemName`, `startedAt`, `status`).
- [x] Expand `NotchState` with `.liveActivity(LiveActivityItem)` state.
- [x] Implement `LiveActivityManager` coordinating active tasks across multi-display window controllers and triggering completion/failure alert banners via `NotificationManager`.
- [x] Extend `LocalNotificationServer` with IPC endpoints for:
  - `.dynamicNotchActivityStart`
  - `.dynamicNotchActivityUpdate`
  - `.dynamicNotchActivityComplete`
  - `.dynamicNotchActivityFail`
- [x] Build SwiftUI `LiveActivityPillView` and `LiveActivityHoverCardView`:
  - On MacBook hardware notch: Rotating animated icon in left ear, elapsed timer or progress `%` in right ear (safe from camera occlusion).
  - On external displays: Glowing animated spinner, task title, and timer capsule pill with bottom progress line.
  - On hover: Expands to rich Live Activity HUD card with animated progress track.
- [x] Implement universal CLI wrapper `DynamicNotch run <title> -- <command...>`:
  - Spawns subprocess while streaming stdout/stderr in real time to terminal.
  - Posts live activity start, captures elapsed execution time, and automatically raises green success or red error alert banner on completion.
- [x] Implement granular CLI commands:
  - `DynamicNotch activity start <id> <title> [subtitle] [icon] [progress]`
  - `DynamicNotch activity update <id> [subtitle] [progress]`
  - `DynamicNotch activity complete <id> [title] [subtitle]`
  - `DynamicNotch activity fail <id> [error]`
- [x] Add simulation trigger for Live Activities in the system menu bar (`Cmd + 4`).

---

## 3. Project File Structure

```
DynamicNotch/
├── Package.swift                                      // SPM package manifest (macOS 14+)
├── build_app.sh                                       // Release bundler generating DynamicNotch.app
├── PLAN.md                                            // Architecture plan & implementation checklist
├── README.md                                          // Project documentation & usage guide
└── Sources/
    └── DynamicNotch/
        ├── App/
        │   ├── AppDelegate.swift                      // Lifecycle, menu bar status item, multi-window coordinator
        │   └── main.swift                             // Concurrency entrypoint & CLI dispatcher
        ├── Core/
        │   ├── NotchPanel.swift                       // Non-activating NSPanel, Spaces & FullScreen aux
        │   ├── ScreenGeometryManager.swift            // Display discovery & hardware notch math
        │   ├── TrackingHostingView.swift              // NSTrackingArea & pass-through hit testing
        │   ├── NotchWindowController.swift            // Per-display frame coordination & outside-click monitor
        │   └── LaunchAtLoginManager.swift             // SMAppService.mainApp login registration
        ├── Models/
        │   ├── NotchState.swift                       // State machine (.idle, .hover, .alert, .tray, .liveActivity)
        │   ├── ScreenGeometry.swift                   // Safe area, cutout math & corner radii
        │   ├── NotchViewModel.swift                   // Observable presentation state coordinator
        │   ├── NotificationItem.swift                 // Strongly typed notification model
        │   └── LiveActivityItem.swift                 // Live task progress, duration, and status model
        ├── Pipeline/
        │   ├── NotificationManager.swift              // Multi-window reactive store & FIFO alert queue
        │   ├── LiveActivityManager.swift              // Active task lifecycle coordinator & alert bridge
        │   ├── MockNotificationEmitter.swift          // Presets (Slack, GitHub, Calendar) & burst tester
        │   ├── LocalNotificationServer.swift          // DistributedNotificationCenter IPC for CLI triggers
        │   └── SystemNotificationObserver.swift       // Real macOS Accessibility AXObserver notification intake
        └── Views/
            ├── DynamicNotchRootView.swift             // Fluid visual capsule shell & interactive tray
            ├── GeometryDiagnosticsView.swift          // Live screen geometry HUD
            ├── PreferencesView.swift                  // Tabbed Settings interface
            ├── PreferencesWindowController.swift      // Standalone Settings window controller
            └── Components/
                ├── AlertBannerView.swift              // Incoming alert pill stretch layout
                ├── LiveActivityPillView.swift         // Animated task spinner, timer, and progress HUD
                └── TrayNotificationRow.swift          // Interactive notification card with actions
```

---

## 4. Verification History

| Date | Phase | Verified Hardware | Result |
| :--- | :--- | :--- | :--- |
| **Oct 19, 2026** | Phases 1 & 2 | MacBook Pro M1 Pro (Built-in Notch) | Verified. Notch geometry (`165 × 28.5 pt`) detected and anchored. |
| **Oct 19, 2026** | Hardware Notch Fix | MacBook Pro M1 Pro | Resolved camera occlusion via flanking ears and safe content top inset (`28.5 pt`). |
| **Oct 19, 2026** | Phases 3 & 4 | MacBook Pro M1 Pro | Verified. Spring physics, alert banner stretch, interactive tray, and FIFO queue tested. |
| **Oct 19, 2026** | Multi-Display Engine | LG FHD 1080p + MacBook Pro M1 Pro | Verified live. Dual synchronized islands rendering on both screens simultaneously. |
| **Oct 19, 2026** | Phases 5 & 6 | Dual Display Setup | Verified. `SMAppService` launch at login, Preferences window, outside-click dismissal, and Spaces stability. |
| **Oct 19, 2026** | Phase 7 (Live Activities) | Dual Display Setup + CLI Runner | Verified live. `DynamicNotch run` wrapper, animated spinner/timer in notch ears, progress bar, and completion/failure banners verified. |
