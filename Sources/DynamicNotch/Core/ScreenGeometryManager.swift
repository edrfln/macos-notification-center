import AppKit
import Combine
import Foundation
import Observation

/// Preference for which screen should host the Dynamic Notch window.
public enum ScreenTargetMode: Equatable, Sendable {
    /// Anchors to the screen with a physical notch if connected.
    case preferHardwareNotch
    /// Dynamically shifts to whichever screen currently holds the mouse cursor.
    case followMouse
    /// Anchors to a specifically chosen screen name (e.g. "LG FHD").
    case screenName(String)
}

/// Discovers, monitors, and recalculates screen dimensions and notch cutout geometries.
@Observable
@MainActor
public final class ScreenGeometryManager {
    public var currentGeometry: ScreenGeometry
    public var currentScreen: NSScreen?
    public var targetMode: ScreenTargetMode = .preferHardwareNotch {
        didSet {
            updateMouseTrackingState()
            recalculateGeometry()
        }
    }
    
    /// Optional closure called when geometry changes due to display reconfiguration or mouse crossing.
    public var onGeometryChanged: ((ScreenGeometry) -> Void)?
    
    @ObservationIgnored
    nonisolated(unsafe) private var screenChangeObserver: (any NSObjectProtocol)?
    
    @ObservationIgnored
    private var mouseMonitorTask: Task<Void, Never>?
    
    public init() {
        let detected = Self.selectScreen(for: .preferHardwareNotch)
        self.currentScreen = detected
        self.currentGeometry = detected != nil ? ScreenGeometry(screen: detected!) : .fallback
        
        setupScreenChangeObserver()
        updateMouseTrackingState()
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
                self?.recalculateGeometry()
            }
        }
    }
    
    private func updateMouseTrackingState() {
        mouseMonitorTask?.cancel()
        mouseMonitorTask = nil
        
        guard targetMode == .followMouse else { return }
        
        // Lightweight polling to detect when mouse moves to a different monitor
        mouseMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard let self = self, self.targetMode == .followMouse else { return }
                
                let mouseLoc = NSEvent.mouseLocation
                if let activeScreen = NSScreen.screens.first(where: { NSPointInRect(mouseLoc, $0.frame) }) {
                    if activeScreen != self.currentScreen {
                        self.currentScreen = activeScreen
                        let newGeometry = ScreenGeometry(screen: activeScreen)
                        if self.currentGeometry != newGeometry {
                            self.currentGeometry = newGeometry
                            self.onGeometryChanged?(newGeometry)
                        }
                    }
                }
            }
        }
    }
    
    /// Re-evaluates connected monitors and updates geometry.
    public func recalculateGeometry() {
        let newScreen = Self.selectScreen(for: targetMode)
        self.currentScreen = newScreen
        
        let newGeometry = newScreen != nil ? ScreenGeometry(screen: newScreen!) : .fallback
        if self.currentGeometry != newGeometry {
            self.currentGeometry = newGeometry
            self.onGeometryChanged?(newGeometry)
        }
    }
    
    /// Selects the target display based on the chosen mode.
    private static func selectScreen(for mode: ScreenTargetMode) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return NSScreen.main }
        
        switch mode {
        case .preferHardwareNotch:
            if let notchScreen = screens.first(where: {
                $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil && $0.safeAreaInsets.top > 0
            }) {
                return notchScreen
            }
            return NSScreen.main ?? screens.first
            
        case .followMouse:
            let mouseLoc = NSEvent.mouseLocation
            return screens.first(where: { NSPointInRect(mouseLoc, $0.frame) }) ?? NSScreen.main ?? screens.first
            
        case .screenName(let name):
            return screens.first(where: { $0.localizedName == name }) ?? NSScreen.main ?? screens.first
        }
    }
}
