import SwiftUI

/// High-polish alert banner displaying an incoming notification inside the expanded island pill.
public struct AlertBannerView: View {
    public let item: NotificationItem
    public let onDismiss: () -> Void
    public let onOpen: (() -> Void)?
    public let onActivate: (() -> Void)?

    @State private var hasArrived: Bool = false
    @State private var isHovered: Bool = false

    public init(
        item: NotificationItem,
        onDismiss: @escaping () -> Void,
        onOpen: (() -> Void)? = nil,
        onActivate: (() -> Void)? = nil
    ) {
        self.item = item
        self.onDismiss = onDismiss
        self.onOpen = onOpen
        self.onActivate = onActivate
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Clickable notification area (icon + text)
            HStack(spacing: 12) {
                glyph

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(item.appName.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.7)
                            .foregroundColor(item.category.themeColor)
                            .lineLimit(1)

                        Circle()
                            .fill(NotchInk.quaternary)
                            .frame(width: 2.5, height: 2.5)

                        Text(item.formattedTime)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundColor(NotchInk.tertiary)
                    }

                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(NotchInk.primary)
                        .lineLimit(1)

                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(NotchInk.secondary)
                            .lineLimit(1)
                    }
                }
                .offset(y: hasArrived ? 0 : 6)
                .opacity(hasArrived ? 1 : 0)

                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.tap()
                if let onActivate = onActivate {
                    onActivate()
                } else {
                    onOpen?()
                }
            }

            // Trailing Quick Actions
            HStack(spacing: 6) {
                if let onOpen = onOpen {
                    GlassIconButton("chevron.down", help: "Expand Notification Tray", size: 24, action: onOpen)
                }
                GlassIconButton("xmark", help: "Dismiss Alert", size: 24, action: onDismiss)
            }
            .opacity(hasArrived ? 1 : 0)
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            withAnimation(NotchMotion.hover) { isHovered = hovering }
        }
        .onAppear {
            withAnimation(NotchMotion.bouncy.delay(0.05)) {
                hasArrived = true
            }
        }
    }

    /// Category tile that springs in on arrival with a soft colored halo behind it.
    private var glyph: some View {
        ZStack {
            // Halo must clear the 38pt tile to read at all, so it's sized well past it
            Circle()
                .fill(item.category.themeColor)
                .frame(width: 46, height: 46)
                .blur(radius: 13)
                .scaleEffect(hasArrived ? 1.2 : 0.4)
                .opacity(isHovered ? 0.75 : 0.5)

            AppGlyph(symbol: item.systemIcon, color: item.category.themeColor, size: 38)
                .symbolEffect(.bounce, value: hasArrived)
                .scaleEffect(hasArrived ? 1.0 : 0.55)
                .rotationEffect(.degrees(hasArrived ? 0 : -14))
        }
        .frame(width: 40, height: 40)
    }
}
