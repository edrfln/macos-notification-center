import SwiftUI

/// An interactive notification card displayed inside the expanded Dynamic Notch tray.
public struct TrayNotificationRow: View {
    public let item: NotificationItem
    public let onDismiss: () -> Void
    public let onMarkRead: () -> Void
    public let onActivate: (() -> Void)?

    @State private var isHovered: Bool = false
    @State private var dragOffset: CGFloat = 0.0

    private static let dismissThreshold: CGFloat = 95
    private let cardShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    public init(
        item: NotificationItem,
        onDismiss: @escaping () -> Void,
        onMarkRead: @escaping () -> Void,
        onActivate: (() -> Void)? = nil
    ) {
        self.item = item
        self.onDismiss = onDismiss
        self.onMarkRead = onMarkRead
        self.onActivate = onActivate
    }

    public var body: some View {
        ZStack {
            swipeBackdrop
            card
                .offset(x: dragOffset)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            if let onActivate = onActivate {
                onActivate()
            } else {
                onMarkRead()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 18)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let crossed = abs(value.translation.width) > Self.dismissThreshold
                    let wasCrossed = abs(dragOffset) > Self.dismissThreshold
                    if crossed != wasCrossed {
                        Haptics.align()
                    }
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    if abs(value.translation.width) > Self.dismissThreshold {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            dragOffset = value.translation.width > 0 ? 420 : -420
                        }
                        Haptics.tap()
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onHover { hovering in
            withAnimation(NotchMotion.hover) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Card

    private var card: some View {
        HStack(alignment: .top, spacing: 10) {
            AppGlyph(symbol: item.systemIcon, color: item.category.themeColor, size: 30, dimmed: item.isRead)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.appName)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(item.isRead ? NotchInk.tertiary : item.category.themeColor.opacity(0.95))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if isHovered {
                        hoverActions
                            .transition(.opacity.combined(with: .offset(x: 6)))
                    } else {
                        Text(item.formattedTime)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(NotchInk.quaternary)
                            .transition(.opacity)
                    }
                }
                .frame(height: 18)

                Text(item.title)
                    .font(.system(size: 12, weight: item.isRead ? .medium : .semibold, design: .rounded))
                    .foregroundColor(item.isRead ? NotchInk.secondary : NotchInk.primary)
                    .lineLimit(1)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(item.isRead ? NotchInk.quaternary : NotchInk.tertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .background(
            ZStack(alignment: .leading) {
                cardShape.fill(isHovered ? Color.white.opacity(0.085) : Color.white.opacity(0.045))

                // Unread rows carry a soft wash of their category color from the leading edge
                if !item.isRead {
                    cardShape.fill(
                        LinearGradient(
                            colors: [item.category.themeColor.opacity(0.14), .clear],
                            startPoint: .leading,
                            endPoint: .init(x: 0.45, y: 0.5)
                        )
                    )
                    Capsule()
                        .fill(item.category.themeColor)
                        .frame(width: 2.5)
                        .padding(.vertical, 10)
                        .shadow(color: item.category.themeColor.opacity(0.8), radius: 3)
                }
            }
        )
        .overlay(
            cardShape.strokeBorder(Color.white.opacity(isHovered ? 0.14 : 0.05), lineWidth: 0.5)
        )
        .clipShape(cardShape)
        .scaleEffect(isHovered ? 1.008 : 1.0)
    }

    private var hoverActions: some View {
        HStack(spacing: 4) {
            if let onActivate = onActivate {
                GlassIconButton("arrow.up.right", help: "Open \(item.appName)", size: 18, tint: NotchInk.activity, action: onActivate)
            }
            if !item.isRead {
                GlassIconButton("checkmark", help: "Mark as read", size: 18, tint: Color.green.opacity(0.9), action: onMarkRead)
            }
            GlassIconButton("xmark", help: "Dismiss", size: 18, action: onDismiss)
        }
    }

    // MARK: - Swipe Backdrop

    /// Red "release to dismiss" layer revealed underneath the card as it slides away.
    private var swipeBackdrop: some View {
        let progress = min(1.0, abs(dragOffset) / Self.dismissThreshold)
        let armed = abs(dragOffset) > Self.dismissThreshold
        return cardShape
            .fill(NotchInk.danger.opacity(0.12 + 0.5 * progress))
            .overlay(alignment: dragOffset >= 0 ? .leading : .trailing) {
                Image(systemName: armed ? "trash.fill" : "trash")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.4 + 0.6 * progress))
                    .scaleEffect(armed ? 1.15 : 0.8 + 0.2 * progress)
                    .animation(NotchMotion.bouncy, value: armed)
                    .padding(.horizontal, 16)
            }
            .opacity(dragOffset == 0 ? 0 : 1)
    }
}
