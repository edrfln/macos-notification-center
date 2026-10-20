import SwiftUI

/// High-polish animated live activity pill rendered when a command-line or background task is in progress.
public struct LiveActivityPillView: View {
    public let item: LiveActivityItem
    public let geometry: ScreenGeometry

    public init(item: LiveActivityItem, geometry: ScreenGeometry) {
        self.item = item
        self.geometry = geometry
    }

    public var body: some View {
        TimelineView(.periodic(from: item.startedAt, by: 1.0)) { context in
            let currentElapsed = item.formattedElapsedTime(at: context.date)
            Group {
                if geometry.hasHardwareNotch {
                    hardwareNotchLayout(currentElapsed: currentElapsed)
                } else {
                    externalDisplayLayout(currentElapsed: currentElapsed)
                }
            }
        }
    }

    /// Progress ring with the task's glyph nested inside.
    private func ringedIcon(size: CGFloat) -> some View {
        ZStack {
            ActivityRing(progress: item.progress, size: size, lineWidth: 2.0)
            Image(systemName: item.iconSystemName)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(NotchInk.activity)
        }
    }

    private func statusText(currentElapsed: String, size: CGFloat) -> some View {
        Group {
            if let progress = item.progress {
                Text("\(Int(progress * 100))%")
                    .foregroundColor(NotchInk.activity)
            } else {
                Text(currentElapsed)
                    .foregroundColor(NotchInk.primary)
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .contentTransition(.numericText())
    }

    // MARK: - Hardware Notch (Flanking Ears)

    private func hardwareNotchLayout(currentElapsed: String) -> some View {
        HStack(spacing: 0) {
            // Left Ear: progress ring around the task glyph
            ringedIcon(size: 17)
                .frame(width: 55.0, height: geometry.notchHeight)

            // Center: Physical notch camera housing (dead screen pixels)
            Spacer()
                .frame(width: geometry.notchWidth, height: geometry.notchHeight)

            // Right Ear: Elapsed timer or progress %
            statusText(currentElapsed: currentElapsed, size: 10.5)
                .frame(width: 55.0, height: geometry.notchHeight)
        }
    }

    // MARK: - External Monitor Layout (LG FHD Top Center Pill)

    private func externalDisplayLayout(currentElapsed: String) -> some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 8) {
                ringedIcon(size: 17)
                    .padding(.leading, 10)

                Text(item.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(NotchInk.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                statusText(currentElapsed: currentElapsed, size: 10)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(NotchInk.activity.opacity(0.14)))
                    .padding(.trailing, 8)
            }
            .frame(height: geometry.notchHeight)

            if let progress = item.progress {
                GeometryReader { geo in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [NotchInk.activity.opacity(0.35), NotchInk.activity],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(progress), height: 1.5)
                        .shadow(color: NotchInk.activity.opacity(0.8), radius: 2)
                        .animation(NotchMotion.smooth, value: progress)
                }
                .frame(height: 1.5)
                .padding(.horizontal, 12)
            }
        }
    }
}

/// Detailed HUD view displayed when hovering over an active Live Activity.
public struct LiveActivityHoverCardView: View {
    public let item: LiveActivityItem
    @State private var sweep: Bool = false

    public init(item: LiveActivityItem) {
        self.item = item
    }

    public var body: some View {
        TimelineView(.periodic(from: item.startedAt, by: 1.0)) { context in
            let currentElapsed = item.formattedElapsedTime(at: context.date)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    ZStack {
                        ActivityRing(progress: item.progress, size: 22, lineWidth: 2.2)
                        Image(systemName: item.iconSystemName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(NotchInk.activity)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(NotchInk.primary)
                            .lineLimit(1)
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle)
                                .font(.system(size: 10.5))
                                .foregroundColor(NotchInk.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "stopwatch.fill")
                            .font(.system(size: 9))
                        Text(currentElapsed)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .foregroundColor(NotchInk.activity)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(NotchInk.activity.opacity(0.15)))
                }

                progressTrack
            }
            .padding(.vertical, 4)
        }
        .onAppear { sweep = true }
    }

    @ViewBuilder
    private var progressTrack: some View {
        if let progress = item.progress {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [NotchInk.activity.opacity(0.6), .mint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * CGFloat(progress)))
                        .shadow(color: NotchInk.activity.opacity(0.7), radius: 3)
                        .animation(NotchMotion.smooth, value: progress)
                }
            }
            .frame(height: 4)
        } else {
            // Indeterminate comet sweeping across the track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [.clear, NotchInk.activity, .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 80)
                        .offset(x: sweep ? geo.size.width - 40 : -40)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: sweep)
                }
            }
            .frame(height: 3)
            .clipShape(Capsule())
        }
    }
}
