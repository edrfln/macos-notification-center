import AppKit
import SwiftUI

/// Coordinates window frame dimensions, screen geometry changes, and AppKit-SwiftUI state synchronization
/// for a specific display (hardware notch or external monitor).
@MainActor
public final class NotchWindowController: Identifiable {
    public let id: UUID = UUID()
    public let screen: NSScreen
    public let panel: NotchPanel
    public let viewModel: NotchViewModel
    public let notificationManager: NotificationManager
    public let activityManager: LiveActivityManager
    public let mediaManager: MediaPlaybackManager
    
    private var hostingView: TrackingHostingView<AnyView>?
    private var collapseTask: Task<Void, Never>?
    private var mouseEnterDwellTask: Task<Void, Never>?
    private var mouseExitDebounceTask: Task<Void, Never>?
    
    @ObservationIgnored
    private var outsideClickMonitor: Any?
    
    @ObservationIgnored
    nonisolated(unsafe) private var spaceChangeObserver: (any NSObjectProtocol)?
    
    public var restingState: NotchState {
        if let activity = activityManager.currentActivity {
            return .liveActivity(activity)
        }
        if let media = mediaManager.currentMedia {
            return .mediaCompact(media)
        }
        return .idle
    }
    
    public init(
        screen: NSScreen,
        notificationManager: NotificationManager,
        activityManager: LiveActivityManager,
        mediaManager: MediaPlaybackManager? = nil
    ) {
        let mm = mediaManager ?? MediaPlaybackManager.shared
        self.screen = screen
        self.notificationManager = notificationManager
        self.activityManager = activityManager
        self.mediaManager = mm
        
        let geometry = ScreenGeometry(screen: screen)
        self.viewModel = NotchViewModel(
            geometry: geometry,
            notificationManager: notificationManager,
            activityManager: activityManager,
            mediaManager: mm
        )
        
        let initialRest: NotchState = {
            if let activity = activityManager.currentActivity {
                return .liveActivity(activity)
            }
            if let media = mm.currentMedia {
                return .mediaCompact(media)
            }
            return .idle
        }()
        self.viewModel.state = initialRest
        
        let initialFrame = geometry.windowFrame(for: initialRest, unreadCount: notificationManager.unreadCount)
        self.panel = NotchPanel(contentRect: initialFrame)
        
        setupHostingView()
        setupNotificationListeners()
        setupActivityListeners()
        setupMediaListeners()
        setupSpaceChangeObserver()
        
        // Show panel without activating the application
        panel.orderFrontRegardless()
    }
    
    public func close() {
        mouseEnterDwellTask?.cancel()
        mouseExitDebounceTask?.cancel()
        collapseTask?.cancel()
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        if let obs = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            spaceChangeObserver = nil
        }
        notificationManager.unregisterListener(id: id)
        activityManager.unregisterListener(id: id)
        mediaManager.unregisterListener(id: id)
        panel.close()
    }
    
    private func setupHostingView() {
        let rootView = AnyView(DynamicNotchRootView(viewModel: viewModel, controller: self))
        let hosting = TrackingHostingView(rootView: rootView)
        self.hostingView = hosting
        
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = panel.contentView?.bounds ?? .zero
        panel.contentView = hosting
        
        hosting.hitTestPredicate = { [weak self] localPoint in
            guard let self = self else { return true }
            return self.isPointInsideIsland(localPoint)
        }
        
        hosting.onMouseEntered = { [weak self] in
            self?.handleMouseEntered()
        }
        
        hosting.onMouseExited = { [weak self] in
            self?.handleMouseExited()
        }
    }
    
    private func setupNotificationListeners() {
        notificationManager.registerListener(
            id: id,
            onAlert: { [weak self] item in
                guard let self = self else { return }
                // Don't yank the user out of the open player; the item still lands in the tray and unread badge.
                guard !self.viewModel.isMediaExpanded else { return }
                self.transition(to: .incomingAlert(item))
            },
            onDismiss: { [weak self] in
                guard let self = self else { return }
                if self.viewModel.state != .trayExpanded && !self.viewModel.isMediaExpanded {
                    let nextState: NotchState = self.viewModel.isMouseInside && !self.viewModel.isMediaCompact
                        ? .hoverPreview
                        : self.restingState
                    self.transition(to: nextState)
                }
            },
            onStoreChange: { [weak self] in
                guard let self = self else { return }
                if self.viewModel.state == .idle {
                    self.updateWindowFrame(for: .idle, immediate: true)
                }
            }
        )
    }
    
    private func setupActivityListeners() {
        activityManager.registerListener(id: id) { [weak self] activity in
            guard let self = self else { return }
            if let activity = activity {
                if self.viewModel.state == .idle || self.viewModel.isLiveActivity || self.viewModel.isMediaCompact {
                    self.transition(to: .liveActivity(activity))
                }
            } else {
                if case .liveActivity = self.viewModel.state {
                    self.transition(to: self.restingState)
                }
            }
        }
    }
    
    private func setupMediaListeners() {
        mediaManager.registerListener(id: id) { [weak self] media in
            guard let self = self else { return }
            if let media = media {
                if self.viewModel.isMediaExpanded {
                    self.transition(to: .mediaExpanded(media))
                } else if self.viewModel.state == .idle || self.viewModel.isMediaCompact {
                    self.transition(to: .mediaCompact(media))
                }
            } else {
                if self.viewModel.isMediaCompact || self.viewModel.isMediaExpanded {
                    self.transition(to: self.restingState)
                }
            }
        }
    }
    
    private func setupSpaceChangeObserver() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Re-assert front regardless to prevent glitching across Spaces
                self.panel.orderFrontRegardless()
            }
        }
    }
    
    public func updateGeometry(for newScreen: NSScreen) {
        let newGeometry = ScreenGeometry(screen: newScreen)
        viewModel.updateGeometry(newGeometry)
        updateWindowFrame(for: viewModel.state, immediate: true)
    }
    
    // MARK: - State & Window Frame Synchronization
    
    private func requiresOutsideClickMonitor(for state: NotchState) -> Bool {
        switch state {
        case .trayExpanded, .mediaExpanded:
            return true
        default:
            return false
        }
    }
    
    public func transition(to targetState: NotchState) {
        mouseEnterDwellTask?.cancel()
        mouseEnterDwellTask = nil
        collapseTask?.cancel()
        collapseTask = nil
        
        let currentVisualSize = viewModel.geometry.visualSize(for: viewModel.state, unreadCount: viewModel.unreadCount)
        let targetVisualSize = viewModel.geometry.visualSize(for: targetState, unreadCount: viewModel.unreadCount)
        let isCollapsing = targetVisualSize.width < currentVisualSize.width || targetVisualSize.height < currentVisualSize.height
        let isExpandingAnyDimension = targetVisualSize.width > currentVisualSize.width || targetVisualSize.height > currentVisualSize.height
        
        if !requiresOutsideClickMonitor(for: targetState), let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        
        if requiresOutsideClickMonitor(for: targetState) && outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.requiresOutsideClickMonitor(for: self.viewModel.state) else { return }
                    let mouseLoc = NSEvent.mouseLocation
                    if !NSPointInRect(mouseLoc, self.islandScreenRect()) {
                        self.transition(to: self.restingState)
                    }
                }
            }
        }
        
        if isCollapsing {
            // If transitioning between two states where one dimension grows while another shrinks (e.g. tray <-> mediaExpanded),
            // expand to the union bounding box first so neither axis clips during the spring animation.
            if isExpandingAnyDimension {
                let unionSize = CGSize(
                    width: max(currentVisualSize.width, targetVisualSize.width),
                    height: max(currentVisualSize.height, targetVisualSize.height)
                )
                setPanelFrame(forVisualSize: unionSize)
            }
            
            withAnimation(.spring(response: 0.34, dampingFraction: 0.80, blendDuration: 0)) {
                viewModel.state = targetState
            }
            collapseTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 340_000_000)
                guard !Task.isCancelled, let self = self, self.viewModel.state == targetState else { return }
                self.updateWindowFrame(for: targetState, immediate: true)
            }
        } else {
            updateWindowFrame(for: targetState, immediate: true)
            withAnimation(.spring(response: 0.36, dampingFraction: 0.76, blendDuration: 0)) {
                viewModel.state = targetState
            }
        }
    }
    
    private func setPanelFrame(forVisualSize size: CGSize) {
        let paddedWidth = size.width + (viewModel.geometry.shadowPaddingX * 2.0)
        let paddedHeight = size.height + viewModel.geometry.shadowPaddingBottom
        let x = viewModel.geometry.notchCenterX - (paddedWidth / 2.0)
        let y = viewModel.geometry.screenFrame.maxY - paddedHeight
        let frame = NSRect(x: x, y: y, width: paddedWidth, height: paddedHeight)
        if panel.frame != frame {
            panel.setFrame(frame, display: true, animate: false)
        }
    }
    
    private func updateWindowFrame(for state: NotchState, immediate: Bool) {
        let targetFrame = viewModel.geometry.windowFrame(for: state, unreadCount: viewModel.unreadCount)
        if panel.frame != targetFrame {
            panel.setFrame(targetFrame, display: true, animate: false)
        }
    }
    
    // MARK: - Mouse Hover & Pass-Through Logic
    
    private func handleMouseEntered() {
        mouseExitDebounceTask?.cancel()
        mouseExitDebounceTask = nil
        viewModel.isMouseInside = true
        
        if case .incomingAlert = viewModel.state {
            notificationManager.pauseAutoDismiss()
            return
        }
        
        // Note: .mediaCompact deliberately expands on click rather than hover to prevent
        // accidental full-player popups when moving the cursor across the menu bar.
        if viewModel.state == .idle || viewModel.isLiveActivity {
            let expandWhenEmpty = UserDefaults.standard.object(forKey: NotificationManager.hoverExpandWhenEmptyDefaultsKey) as? Bool ?? true
            if !expandWhenEmpty && viewModel.unreadCount == 0 && viewModel.currentActivity == nil {
                return
            }
            
            mouseEnterDwellTask?.cancel()
            mouseEnterDwellTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, let self = self, self.viewModel.isMouseInside else { return }
                if self.viewModel.state == .idle || self.viewModel.isLiveActivity {
                    self.transition(to: .hoverPreview)
                }
            }
        }
    }
    
    private func handleMouseExited() {
        mouseEnterDwellTask?.cancel()
        mouseEnterDwellTask = nil
        viewModel.isMouseInside = false
        
        if case .incomingAlert = viewModel.state {
            notificationManager.resumeAutoDismiss(remainingDuration: 2.0)
            return
        }
        
        // Keep expanded tray or expanded media player open until user clicks outside or presses Collapse
        if viewModel.state == .trayExpanded || viewModel.isMediaExpanded {
            return
        }
        
        mouseExitDebounceTask?.cancel()
        mouseExitDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled, let self = self else { return }
            
            if !self.viewModel.isMouseInside && self.viewModel.state == .hoverPreview {
                self.transition(to: self.restingState)
            }
        }
    }
    
    private func islandScreenRect() -> NSRect {
        let visualSize = viewModel.geometry.visualSize(for: viewModel.state, unreadCount: viewModel.unreadCount)
        let x = viewModel.geometry.notchCenterX - (visualSize.width / 2.0)
        let y = viewModel.geometry.screenFrame.maxY - visualSize.height
        return NSRect(x: x, y: y, width: visualSize.width, height: visualSize.height)
    }
    
    private func isPointInsideIsland(_ localPoint: NSPoint) -> Bool {
        guard let hosting = hostingView else { return true }
        let viewBounds = hosting.bounds
        let visualSize = viewModel.geometry.visualSize(for: viewModel.state, unreadCount: viewModel.unreadCount)
        
        let islandX = (viewBounds.width - visualSize.width) / 2.0
        let islandY = hosting.isFlipped ? 0.0 : (viewBounds.height - visualSize.height)
        
        let islandRect = NSRect(
            x: islandX - 4.0,
            y: islandY - 4.0,
            width: visualSize.width + 8.0,
            height: visualSize.height + 8.0
        )
        
        return islandRect.contains(localPoint)
    }
}
