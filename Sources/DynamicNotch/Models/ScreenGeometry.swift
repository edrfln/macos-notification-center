import AppKit
import Foundation

/// Models the geometry of a display and its physical or simulated notch cutout.
public struct ScreenGeometry: Equatable, Sendable {
    public let screenFrame: NSRect
    public let visibleFrame: NSRect
    public let safeAreaInsetsTop: CGFloat
    public let hasHardwareNotch: Bool
    public let notchWidth: CGFloat
    public let notchHeight: CGFloat
    public let notchCenterX: CGFloat
    
    public init(screen: NSScreen) {
        self.screenFrame = screen.frame
        self.visibleFrame = screen.visibleFrame
        self.safeAreaInsetsTop = screen.safeAreaInsets.top
        
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            self.hasHardwareNotch = true
            let calculatedWidth = right.minX - left.maxX
            self.notchWidth = max(calculatedWidth, 140.0)
            self.notchHeight = screen.safeAreaInsets.top
            self.notchCenterX = left.maxX + (self.notchWidth / 2.0)
        } else {
            self.hasHardwareNotch = false
            // External monitor (e.g. LG FHD): simulated top-center pill protruding gently below menu bar
            self.notchWidth = 160.0
            self.notchHeight = 32.0
            self.notchCenterX = screen.frame.midX
        }
    }
    
    public static var fallback: ScreenGeometry {
        let dummyScreen = NSScreen.main ?? NSScreen()
        return ScreenGeometry(screen: dummyScreen)
    }
    
    /// The resting frame of the notch in Cocoa global screen coordinates.
    public var restingNotchFrame: NSRect {
        let x = notchCenterX - (notchWidth / 2.0)
        let y = screenFrame.maxY - notchHeight
        return NSRect(x: x, y: y, width: notchWidth, height: notchHeight)
    }
    
    /// Ear width extending on both sides of the hardware notch when unread alerts exist.
    public var earWidth: CGFloat {
        return hasHardwareNotch ? 34.0 : 0.0
    }
    
    /// Safe top inset required so that text and icons are never rendered behind the physical camera housing.
    public var safeContentTopInset: CGFloat {
        return hasHardwareNotch ? notchHeight : 8.0
    }
    
    /// Computes the visual size of the Dynamic Island for a specific state.
    public func visualSize(for state: NotchState, unreadCount: Int = 0) -> CGSize {
        switch state {
        case .idle:
            if hasHardwareNotch {
                if unreadCount > 0 {
                    // Expand flanking "ears" around the notch so indicators are visible in screen pixels
                    return CGSize(width: notchWidth + (earWidth * 2.0), height: notchHeight)
                } else {
                    // Flush mask over the notch
                    return CGSize(width: notchWidth, height: notchHeight)
                }
            } else {
                // External display: clearly visible top-center pill protruding slightly below menu bar
                let width: CGFloat = unreadCount > 0 ? 170.0 : 140.0
                return CGSize(width: width, height: notchHeight)
            }
            
        case .mediaCompact(let media):
            let hasLyrics = !media.lyrics.isEmpty
            let showTranslation = (UserDefaults.standard.object(forKey: MediaPlaybackManager.translationDefaultsKey) as? Bool ?? false) && media.hasTranslations
            if hasHardwareNotch {
                if hasLyrics {
                    // Flank camera with cover & visualizer on top + lyric ribbon beneath the notch
                    let ribbonHeight: CGFloat = showTranslation ? 34.0 : 22.0
                    let width = max(notchWidth + 154.0, 326.0)
                    return CGSize(width: width, height: notchHeight + ribbonHeight)
                } else {
                    // Flank both sides of notch camera with album art on left (56pt) and audio visualizer on right (56pt)
                    let earTotalWidth: CGFloat = 112.0
                    return CGSize(width: notchWidth + earTotalWidth, height: notchHeight)
                }
            } else {
                // External display: sleek pill (expands height slightly when displaying stacked translation beneath lyrics)
                let width: CGFloat = hasLyrics ? 336.0 : 264.0
                let height: CGFloat = (hasLyrics && showTranslation) ? 40.0 : notchHeight
                return CGSize(width: width, height: height)
            }
            
        case .hoverPreview:
            let width = max(notchWidth + 90.0, 260.0)
            let height = hasHardwareNotch ? (notchHeight + 38.0) : 48.0
            return CGSize(width: width, height: height)
            
        case .incomingAlert:
            let width = max(notchWidth + 210.0, 390.0)
            let height = hasHardwareNotch ? (notchHeight + 62.0) : 70.0
            return CGSize(width: width, height: height)
            
        case .liveActivity:
            if hasHardwareNotch {
                // Flank both sides of notch camera with generous ears for animated spinner & timer
                let earTotalWidth: CGFloat = 110.0 // 55pt on each side
                return CGSize(width: notchWidth + earTotalWidth, height: notchHeight)
            } else {
                // External display: sleek top-center pill displaying animated spinner, title, and timer
                return CGSize(width: 260.0, height: notchHeight)
            }
            
        case .mediaExpanded:
            let width = max(notchWidth + 240.0, 420.0)
            let height = hasHardwareNotch ? (notchHeight + 204.0) : 218.0
            return CGSize(width: width, height: height)
            
        case .trayExpanded:
            let width = max(notchWidth + 260.0, 450.0)
            let height = hasHardwareNotch ? (notchHeight + 250.0) : 270.0
            return CGSize(width: width, height: height)
        }
    }
    
    /// Horizontal padding around the visual island inside the NSPanel to prevent clipping flared top ears, shadows, and spring overshoot.
    public var shadowPaddingX: CGFloat {
        return 38.0
    }
    
    /// Bottom padding below the visual island inside the NSPanel to prevent clipping drop shadows and spring overshoot.
    public var shadowPaddingBottom: CGFloat {
        return 28.0
    }
    
    /// Computes the AppKit window frame in global screen coordinates for a given state.
    /// Includes transparent padding on the left, right, and bottom so shadows and spring physics never clip.
    public func windowFrame(for state: NotchState, unreadCount: Int = 0) -> NSRect {
        let size = visualSize(for: state, unreadCount: unreadCount)
        let paddedWidth = size.width + (shadowPaddingX * 2.0)
        let paddedHeight = size.height + shadowPaddingBottom
        let x = notchCenterX - (paddedWidth / 2.0)
        let y = screenFrame.maxY - paddedHeight
        return NSRect(x: x, y: y, width: paddedWidth, height: paddedHeight)
    }
    
    /// Outward concave fillet radius where the left and right edges meet the top screen border.
    public func topCornerRadius(for state: NotchState) -> CGFloat {
        switch state {
        case .idle:
            return hasHardwareNotch ? 10.0 : 12.0
        case .mediaCompact, .liveActivity:
            return 12.0
        case .hoverPreview:
            return 15.0
        case .incomingAlert:
            return 18.0
        case .mediaExpanded:
            return 20.0
        case .trayExpanded:
            return 22.0
        }
    }
    
    /// Visual bottom corner radius appropriate for the notch or expanded container.
    public func cornerRadius(for state: NotchState) -> CGFloat {
        switch state {
        case .idle:
            return hasHardwareNotch ? 14.0 : 15.0
        case .mediaCompact, .liveActivity:
            return 15.0
        case .hoverPreview:
            return 20.0
        case .incomingAlert:
            return 24.0
        case .mediaExpanded:
            return 26.0
        case .trayExpanded:
            return 28.0
        }
    }
}
