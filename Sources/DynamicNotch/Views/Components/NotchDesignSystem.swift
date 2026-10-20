import AppKit
import SwiftUI

// MARK: - Tokens

/// Ink levels for content drawn on the jet-black island. Keeping every surface on the same few steps
/// is what makes the tray, banner, and player read as one object.
public enum NotchInk {
    public static let primary = Color.white.opacity(0.96)
    public static let secondary = Color.white.opacity(0.66)
    public static let tertiary = Color.white.opacity(0.42)
    public static let quaternary = Color.white.opacity(0.24)

    public static let fill = Color.white.opacity(0.075)
    public static let fillHover = Color.white.opacity(0.14)
    public static let hairline = Color.white.opacity(0.10)

    /// Warm amber used for anything "unread".
    public static let unread = Color(red: 1.0, green: 0.64, blue: 0.24)
    /// Electric cyan used for running background tasks.
    public static let activity = Color(red: 0.32, green: 0.86, blue: 0.98)
    public static let danger = Color(red: 1.0, green: 0.34, blue: 0.37)
}

/// Shared spring presets so every surface moves with the same physics.
public enum NotchMotion {
    public static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)
    public static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.86)
    public static let bouncy = Animation.spring(response: 0.44, dampingFraction: 0.6)
    public static let hover = Animation.easeOut(duration: 0.16)
}

@MainActor
public enum Haptics {
    public static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    public static func align() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

// MARK: - App Glyph

/// Squircle app/category tile with a glassy top highlight and hairline rim.
public struct AppGlyph: View {
    public let symbol: String
    public let color: Color
    public var size: CGFloat
    public var dimmed: Bool

    public init(symbol: String, color: Color, size: CGFloat = 30, dimmed: Bool = false) {
        self.symbol = symbol
        self.color = color
        self.size = size
        self.dimmed = dimmed
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        ZStack {
            shape.fill(
                LinearGradient(
                    colors: [color, color.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.30), location: 0.0),
                        .init(color: Color.white.opacity(0.0), location: 0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        .saturation(dimmed ? 0.2 : 1.0)
        .opacity(dimmed ? 0.62 : 1.0)
    }
}

// MARK: - Glass Icon Button

/// Circular glass control used for every secondary action on the island.
public struct GlassIconButton: View {
    public let systemName: String
    public let help: String
    public var size: CGFloat
    public var tint: Color
    public var isActive: Bool
    public var activeFill: Color
    public let action: () -> Void

    @State private var isHovered: Bool = false

    public init(
        _ systemName: String,
        help: String,
        size: CGFloat = 24,
        tint: Color = NotchInk.secondary,
        isActive: Bool = false,
        activeFill: Color = .white,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.help = help
        self.size = size
        self.tint = tint
        self.isActive = isActive
        self.activeFill = activeFill
        self.action = action
    }

    public var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(isActive ? .black : (isHovered ? NotchInk.primary : tint))
                .frame(width: size, height: size)
                .background(
                    Circle().fill(isActive ? activeFill : (isHovered ? NotchInk.fillHover : NotchInk.fill))
                )
                .overlay(Circle().strokeBorder(NotchInk.hairline, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(TransportScaleButtonStyle())
        .help(help)
        .onHover { hovering in
            withAnimation(NotchMotion.hover) { isHovered = hovering }
        }
    }
}

// MARK: - Activity Ring

/// Determinate progress ring, or a spinning comet arc when progress is unknown.
public struct ActivityRing: View {
    public let progress: Double?
    public var size: CGFloat
    public var lineWidth: CGFloat
    public var tint: Color

    @State private var spin: Bool = false

    public init(progress: Double?, size: CGFloat = 16, lineWidth: CGFloat = 2.2, tint: Color = NotchInk.activity) {
        self.progress = progress
        self.size = size
        self.lineWidth = lineWidth
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)

            if let progress = progress {
                let clamped = max(0.02, min(1.0, progress))
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        AngularGradient(
                            colors: [tint.opacity(0.55), tint],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360 * clamped)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.7), radius: 2.5)
                    .animation(NotchMotion.smooth, value: clamped)
            } else {
                Circle()
                    .trim(from: 0, to: 0.32)
                    .stroke(
                        AngularGradient(
                            colors: [tint.opacity(0.0), tint],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(115)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .shadow(color: tint.opacity(0.7), radius: 2.5)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
            }
        }
        .frame(width: size, height: size)
        .onAppear { spin = true }
    }
}

// MARK: - Unread Constellation

/// Overlapping category-colored dots representing the most recent unread sources.
public struct UnreadConstellation: View {
    public let colors: [Color]
    public var dotSize: CGFloat

    public init(colors: [Color], dotSize: CGFloat = 7) {
        self.colors = colors
        self.dotSize = dotSize
    }

    public var body: some View {
        HStack(spacing: -dotSize * 0.32) {
            ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { index, color in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1.4))
                    .shadow(color: color.opacity(0.8), radius: 2.5)
                    .zIndex(Double(3 - index))
            }
        }
    }
}

// MARK: - Breathing Glow

extension View {
    /// Slow opacity "breath" for ambient indicators that should feel alive without demanding attention.
    public func breathing(minOpacity: Double = 0.55, period: Double = 1.6) -> some View {
        phaseAnimator([1.0, minOpacity]) { content, phase in
            content.opacity(phase)
        } animation: { _ in
            .easeInOut(duration: period)
        }
    }
}

// MARK: - Segmented Filter

/// Two-segment All / Unread switch with a sliding white puck.
public struct NotchFilterSegment: View {
    @Binding public var showUnreadOnly: Bool
    public let unreadCount: Int

    @Namespace private var puck

    public init(showUnreadOnly: Binding<Bool>, unreadCount: Int) {
        self._showUnreadOnly = showUnreadOnly
        self.unreadCount = unreadCount
    }

    public var body: some View {
        HStack(spacing: 0) {
            segment(title: "All", value: false)
            segment(title: "Unread", value: true)
        }
        .padding(2)
        .background(Capsule().fill(NotchInk.fill))
        .overlay(Capsule().strokeBorder(NotchInk.hairline, lineWidth: 0.5))
    }

    private func segment(title: String, value: Bool) -> some View {
        let isSelected = showUnreadOnly == value
        return Button {
            guard !isSelected else { return }
            Haptics.tap()
            withAnimation(NotchMotion.snappy) { showUnreadOnly = value }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if value && unreadCount > 0 {
                    Text("\(unreadCount)")
                        .monospacedDigit()
                        .foregroundColor(isSelected ? NotchInk.unread.opacity(0.95) : NotchInk.unread)
                        .contentTransition(.numericText())
                }
            }
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundColor(isSelected ? .black : NotchInk.secondary)
            .padding(.horizontal, 8)
            .frame(height: 18)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.white)
                        .matchedGeometryEffect(id: "puck", in: puck)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Label

public struct NotchSectionLabel: View {
    public let title: String
    public var tint: Color

    public init(_ title: String, tint: Color = NotchInk.tertiary) {
        self.title = title
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundColor(tint)
            Rectangle()
                .fill(LinearGradient(colors: [NotchInk.hairline, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Hairline Divider

public struct NotchHairline: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.14), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.5)
    }
}
