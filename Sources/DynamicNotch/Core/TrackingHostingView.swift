import AppKit
import SwiftUI

/// Custom NSHostingView that injects robust NSTrackingArea tracking
/// and granular hit-testing pass-through for transparent canvas areas.
public final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    
    private var trackingArea: NSTrackingArea?
    private var isInsideActiveRegion: Bool = false
    
    /// Closure invoked when the cursor enters the active island area.
    public var onMouseEntered: (() -> Void)?
    
    /// Closure invoked when the cursor exits the active island area.
    public var onMouseExited: (() -> Void)?
    
    /// Closure invoked on mouse movement within the active view area.
    public var onMouseMoved: ((NSPoint) -> Void)?
    
    /// Predicate determining whether a given point (in local view coordinates)
    /// is inside the active visual island. Returning false lets clicks and hover pass through.
    public var hitTestPredicate: ((NSPoint) -> Bool)?
    
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        // .activeAlways: Guarantees mouse enter/exit events fire even when app is accessory / unactivated
        // .mouseEnteredAndExited: High-efficiency edge crossing notifications
        // .inVisibleRect: Automatically updates as view geometry changes
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect
        ]
        
        let newArea = NSTrackingArea(
            rect: self.bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
        self.trackingArea = newArea
    }
    
    private func evaluateHoverRegion(at localPoint: NSPoint) {
        let inside = hitTestPredicate?(localPoint) ?? true
        if inside && !isInsideActiveRegion {
            isInsideActiveRegion = true
            onMouseEntered?()
        } else if !inside && isInsideActiveRegion {
            isInsideActiveRegion = false
            onMouseExited?()
        }
    }
    
    public override func mouseEntered(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        evaluateHoverRegion(at: location)
    }
    
    public override func mouseExited(with event: NSEvent) {
        if isInsideActiveRegion {
            isInsideActiveRegion = false
            onMouseExited?()
        }
    }
    
    public override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        evaluateHoverRegion(at: location)
        if isInsideActiveRegion {
            onMouseMoved?(location)
        }
    }
    
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = superview != nil ? convert(point, from: superview) : point
        if let predicate = hitTestPredicate {
            guard predicate(localPoint) else {
                // Point rejected: pass mouse events straight through to underlying macOS apps
                return nil
            }
        }
        return super.hitTest(point)
    }
}
