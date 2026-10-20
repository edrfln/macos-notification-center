import AppKit

/// A specialized, non-activating floating NSPanel configured for notch anchoring.
public final class NotchPanel: NSPanel {
    
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .nonactivatingPanel,
                .borderless
            ],
            backing: .buffered,
            defer: false
        )
        
        configurePanelAttributes()
    }
    
    private func configurePanelAttributes() {
        // High window level: float above normal windows and align with menu bar / status bar
        self.level = .statusBar
        
        // Multi-desktop (Spaces) & Fullscreen configuration:
        // .canJoinAllSpaces: Panel persists across all virtual desktops without jumping
        // .fullScreenAuxiliary: Stays visible above full-screen spaces (crucial for notch masking)
        // .stationary: Prevents Mission Control from displacing the panel
        // .ignoresCycle: Excluded from Cmd+` window cycling
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        
        // Transparency and rendering
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        
        // Interaction behavior
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.acceptsMouseMovedEvents = true
    }
    
    // Prevent the panel from stealing main/key status from the foreground app
    public override var canBecomeKey: Bool {
        return false
    }
    
    public override var canBecomeMain: Bool {
        return false
    }
}
