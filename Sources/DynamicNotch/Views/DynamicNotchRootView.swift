import SwiftUI

/// Root SwiftUI view rendered inside the transparent NSPanel.
public struct DynamicNotchRootView: View {
    @Bindable var viewModel: NotchViewModel
    let controller: NotchWindowController
    
    @State private var showDiagnostics: Bool = false
    @State private var showUnreadOnly: Bool = false
    
    public init(viewModel: NotchViewModel, controller: NotchWindowController) {
        self.viewModel = viewModel
        self.controller = controller
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            islandShell
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - Dynamic Island Shell
    
    private var islandShell: some View {
        let currentSize = viewModel.geometry.visualSize(for: viewModel.state, unreadCount: viewModel.unreadCount)
        let topRadius = viewModel.geometry.topCornerRadius(for: viewModel.state)
        let bottomRadius = viewModel.geometry.cornerRadius(for: viewModel.state)
        let fillShape = NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius, closeTopEdge: true)
        let borderShape = NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius, closeTopEdge: false)
        
        return ZStack(alignment: .top) {
            // Jet-black background with flared concave top ears melting seamlessly into the screen border
            fillShape
                .fill(Color.black)
                .overlay(
                    // Rendered wider than the island by `topRadius` per side so the glow also fills
                    // the flared top ears, which the shape draws outside its own bounds.
                    ambientBackdrop(for: viewModel.state, size: currentSize, bleed: topRadius)
                        .frame(width: currentSize.width + topRadius * 2.0, height: currentSize.height)
                        .frame(width: currentSize.width, height: currentSize.height)
                        .clipShape(fillShape)
                )
                .overlay(
                    // Rim light: invisible where the island meets the bezel, warming into the
                    // content's accent color along the bottom edge as if lit from beneath.
                    borderShape
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.0), location: 0.0),
                                    .init(color: Color.white.opacity(0.10), location: 0.3),
                                    .init(color: rimColor.opacity(accent == nil ? 0.18 : 0.75), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 0.85, lineCap: .round, lineJoin: .round)
                        )
                )
                .shadow(
                    color: viewModel.state == .idle ? (viewModel.geometry.hasHardwareNotch ? .clear : Color.black.opacity(0.38)) : Color.black.opacity(0.5),
                    radius: viewModel.state == .idle ? (viewModel.geometry.hasHardwareNotch ? 0 : 6) : 16,
                    x: 0,
                    y: viewModel.state == .idle ? (viewModel.geometry.hasHardwareNotch ? 0 : 3) : 6
                )
                // Accent under-glow (kept within the panel's 28pt bottom shadow padding)
                // Tighter and stronger than the black drop shadow so the color survives on top of it
                .shadow(
                    color: (accent ?? .clear).opacity(isExpandedSurface ? 0.5 : 0.0),
                    radius: 10,
                    x: 0,
                    y: 4
                )
            
            // State-driven interactive content clipped cleanly to the island contour
            contentForState(viewModel.state)
                .frame(width: currentSize.width, height: currentSize.height, alignment: .top)
                .clipShape(fillShape)
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .animation(NotchMotion.smooth, value: accentKey)
    }

    // MARK: - Contextual Accent

    /// The color the island is "lit" by for the current content, if any.
    private var accent: Color? {
        switch viewModel.state {
        case .incomingAlert(let item):
            return item.category.themeColor
        case .mediaCompact(let media), .mediaExpanded(let media):
            return media.accentColor
        case .liveActivity:
            return NotchInk.activity
        case .idle, .hoverPreview, .trayExpanded:
            return nil
        }
    }

    private var rimColor: Color {
        accent ?? .white
    }

    /// Stable identity for animating accent changes without diffing every media update.
    private var accentKey: String {
        switch viewModel.state {
        case .incomingAlert(let item): return "alert-\(item.category.rawValue)"
        case .mediaCompact(let media), .mediaExpanded(let media):
            return "media-\(media.accentColorRed)-\(media.accentColorGreen)-\(media.accentColorBlue)"
        case .liveActivity: return "activity"
        default: return "none"
        }
    }

    private var isExpandedSurface: Bool {
        switch viewModel.state {
        case .incomingAlert, .mediaExpanded: return true
        default: return false
        }
    }

    /// Full-bleed, multi-stop feathered ambient glow (album art for media, category color for alerts) that blends
    /// into the jet-black notch frame without any padding seams or harsh cutoff edges.
    @ViewBuilder
    private func ambientBackdrop(for state: NotchState, size: CGSize, bleed: CGFloat) -> some View {
        // Maps a point in island coordinates into the bleed-widened backdrop's unit space.
        let unit: (CGFloat, CGFloat) -> UnitPoint = { x, y in
            UnitPoint(
                x: (x + bleed) / max(size.width + bleed * 2.0, 1),
                y: y / max(size.height, 1)
            )
        }
        switch state {
        case .mediaCompact(let media):
            // Ultra-soft, localized radial aura behind the compact cover art that dissolves
            // completely into pure black before reaching the center camera cutout or edges.
            RadialGradient(
                stops: [
                    .init(color: media.accentColor.opacity(0.10), location: 0.0),
                    .init(color: media.accentColor.opacity(0.055), location: 0.30),
                    .init(color: media.accentColor.opacity(0.02), location: 0.62),
                    .init(color: .clear, location: 1.0)
                ],
                center: unit(size.width * 0.08, size.height * 0.36),
                startRadius: 2,
                endRadius: 58
            )
            .allowsHitTesting(false)
            
        case .mediaExpanded(let media):
            // 6-stop eased radial diffusion centered on the 52x52 cover art, masked at the top
            // so the physical hardware notch region remains 100% pure black.
            RadialGradient(
                stops: [
                    .init(color: media.accentColor.opacity(0.13), location: 0.0),
                    .init(color: media.accentColor.opacity(0.085), location: 0.22),
                    .init(color: media.accentColor.opacity(0.045), location: 0.46),
                    .init(color: media.accentColor.opacity(0.018), location: 0.70),
                    .init(color: media.accentColor.opacity(0.004), location: 0.88),
                    .init(color: .clear, location: 1.0)
                ],
                center: unit(size.width * 0.14, size.height * 0.34),
                startRadius: 8,
                endRadius: max(size.width * 0.65, 250)
            )
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.35), location: 0.12),
                        .init(color: .black, location: 0.28),
                        .init(color: .black, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)

        case .incomingAlert(let item):
            // Category-colored wash radiating from the app glyph, fading out before the notch
            // Centered on the 38pt glyph (≈34pt in from the leading edge, mid-height below the safe inset)
            RadialGradient(
                stops: [
                    .init(color: item.category.themeColor.opacity(0.30), location: 0.0),
                    .init(color: item.category.themeColor.opacity(0.12), location: 0.4),
                    .init(color: item.category.themeColor.opacity(0.03), location: 0.75),
                    .init(color: .clear, location: 1.0)
                ],
                center: unit(34.0, size.height * (viewModel.geometry.hasHardwareNotch ? 0.68 : 0.5)),
                startRadius: 4,
                endRadius: max(size.width * 0.6, 220)
            )
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: viewModel.geometry.hasHardwareNotch ? .clear : .black, location: 0.0),
                        .init(color: .black, location: 0.35),
                        .init(color: .black, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)

        default:
            EmptyView()
        }
    }
    
    // MARK: - State Views with Safe Content Inset
    
    @ViewBuilder
    private func contentForState(_ state: NotchState) -> some View {
        switch state {
        case .idle:
            idleRestingView
            
        case .mediaCompact(let media):
            MediaCompactPillView(
                media: media,
                geometry: viewModel.geometry,
                onExpand: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    controller.transition(to: .mediaExpanded(media))
                },
                onTogglePlayPause: {
                    viewModel.mediaManager.togglePlayPause()
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            
        case .liveActivity(let item):
            LiveActivityPillView(item: item, geometry: viewModel.geometry)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            
        case .hoverPreview:
            VStack(spacing: 0) {
                Spacer().frame(height: viewModel.geometry.safeContentTopInset)
                hoverPreviewContent
                    .padding(.horizontal, 14)
                Spacer(minLength: 0)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            
        case .incomingAlert(let item):
            VStack(spacing: 0) {
                Spacer().frame(height: viewModel.geometry.safeContentTopInset)
                AlertBannerView(
                    item: item,
                    onDismiss: {
                        viewModel.notificationManager.dismissActiveAlert(userInitiated: true)
                    },
                    onOpen: {
                        controller.transition(to: .trayExpanded)
                    },
                    onActivate: {
                        viewModel.notificationManager.activate(item: item)
                        viewModel.notificationManager.dismissActiveAlert(userInitiated: true)
                    }
                )
                .padding(.horizontal, 14)
                Spacer(minLength: 0)
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .scale(scale: 0.95))
            ))
            
        case .mediaExpanded(let media):
            VStack(spacing: 0) {
                Spacer().frame(height: viewModel.geometry.safeContentTopInset)
                MediaExpandedPlayerView(
                    media: media,
                    unreadCount: viewModel.unreadCount,
                    onTogglePlayPause: {
                        viewModel.mediaManager.togglePlayPause()
                    },
                    onNext: {
                        viewModel.mediaManager.nextTrack()
                    },
                    onPrevious: {
                        viewModel.mediaManager.previousTrack()
                    },
                    onSeek: { targetTime in
                        viewModel.mediaManager.seek(to: targetTime)
                    },
                    onOpenSourceApp: {
                        viewModel.mediaManager.activateSourceApp()
                    },
                    onOpenTray: {
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        controller.transition(to: .trayExpanded)
                    },
                    onCollapse: {
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        controller.transition(to: controller.restingState)
                    },
                    onStopSimulated: {
                        viewModel.mediaManager.stopSimulatedPlayback()
                    }
                )
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            
        case .trayExpanded:
            VStack(spacing: 0) {
                Spacer().frame(height: viewModel.geometry.safeContentTopInset)
                trayExpandedContent
                    .padding(.horizontal, 14)
                Spacer(minLength: 0)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
    
    // MARK: - Unread Helpers

    private var unreadItems: [NotificationItem] {
        viewModel.notificationManager.notifications.filter { !$0.isRead }
    }

    /// Category colors of the most recent unread items, newest first.
    private var unreadColors: [Color] {
        Array(unreadItems.prefix(3).map { $0.category.themeColor })
    }

    /// Up to two distinct app names among unread items, newest first.
    private var unreadAppNames: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for item in unreadItems where seen.insert(item.appName).inserted {
            names.append(item.appName)
            if names.count == 2 { break }
        }
        return names
    }

    private var unreadBadgeText: String {
        viewModel.unreadCount > 9 ? "9+" : "\(viewModel.unreadCount)"
    }

    // 1. Idle Resting View (Flanking Ears for Hardware Notch)
    private var idleRestingView: some View {
        Group {
            if viewModel.geometry.hasHardwareNotch {
                if viewModel.unreadCount > 0 {
                    HStack(spacing: 0) {
                        // Left Ear: constellation of the latest unread sources
                        UnreadConstellation(colors: unreadColors, dotSize: 6.5)
                            .frame(width: viewModel.geometry.earWidth, height: viewModel.geometry.notchHeight)

                        // Center: Physical notch camera cutout (dead screen pixels)
                        Spacer()
                            .frame(width: viewModel.geometry.notchWidth, height: viewModel.geometry.notchHeight)

                        // Right Ear: rolling unread count
                        Text(unreadBadgeText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(NotchInk.unread)
                            .shadow(color: NotchInk.unread.opacity(0.7), radius: 3)
                            .contentTransition(.numericText())
                            .breathing(minOpacity: 0.7, period: 1.8)
                            .frame(width: viewModel.geometry.earWidth, height: viewModel.geometry.notchHeight)
                    }
                } else {
                    Color.clear
                        .frame(width: viewModel.geometry.notchWidth, height: viewModel.geometry.notchHeight)
                }
            } else {
                // External display: compact top-center pill
                HStack(spacing: 7) {
                    if viewModel.unreadCount > 0 {
                        UnreadConstellation(colors: unreadColors, dotSize: 7)
                            .padding(.leading, 12)

                        Text(unreadAppNames.first ?? "New")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(NotchInk.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 2)

                        Text(unreadBadgeText)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.black)
                            .contentTransition(.numericText())
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(Capsule().fill(NotchInk.unread))
                            .shadow(color: NotchInk.unread.opacity(0.6), radius: 4)
                            .padding(.trailing, 8)
                    } else {
                        Spacer()
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 18, height: 3)
                        Spacer()
                    }
                }
                .frame(height: viewModel.geometry.notchHeight)
            }
        }
        .animation(NotchMotion.snappy, value: viewModel.unreadCount)
    }

    // 2. Hover Preview Content
    private var hoverPreviewContent: some View {
        Group {
            if let activity = viewModel.currentActivity {
                LiveActivityHoverCardView(item: activity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Haptics.tap()
                        controller.transition(to: .trayExpanded)
                    }
            } else {
                HStack(spacing: 9) {
                    if viewModel.unreadCount > 0 {
                        // Overlapping stack of the latest unread app glyphs
                        HStack(spacing: -8) {
                            ForEach(Array(unreadItems.prefix(3).enumerated()), id: \.element.id) { index, item in
                                AppGlyph(symbol: item.systemIcon, color: item.category.themeColor, size: 20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.black, lineWidth: 1.5)
                                    )
                                    .zIndex(Double(3 - index))
                            }
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(viewModel.unreadCount) new")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(NotchInk.primary)
                                .contentTransition(.numericText())
                            Text(unreadAppNames.joined(separator: ", "))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(NotchInk.tertiary)
                                .lineLimit(1)
                        }
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.green.opacity(0.85))

                        Text("All caught up")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(NotchInk.secondary)
                    }

                    Spacer()

                    HStack(spacing: 3) {
                        Text("Open")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(NotchInk.primary)
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background(Capsule().fill(NotchInk.fillHover))
                    .overlay(Capsule().strokeBorder(NotchInk.hairline, lineWidth: 0.5))
                }
                .frame(height: 32)
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.tap()
                    controller.transition(to: .trayExpanded)
                }
            }
        }
    }

    // 3. Expanded Tray Content
    private var trayExpandedContent: some View {
        VStack(spacing: 9) {
            trayHeader
                .padding(.top, 4)

            if let activity = viewModel.currentActivity {
                VStack(alignment: .leading, spacing: 5) {
                    NotchSectionLabel("Running", tint: NotchInk.activity.opacity(0.9))
                    LiveActivityHoverCardView(item: activity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [NotchInk.activity.opacity(0.10), Color.white.opacity(0.04)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(NotchInk.activity.opacity(0.18), lineWidth: 0.5)
                        )
                }
            }

            NotchHairline()

            if showDiagnostics {
                GeometryDiagnosticsView(geometry: viewModel.geometry, viewModel: viewModel, controller: controller)
            } else {
                notificationListView
            }
        }
        .padding(.bottom, 10)
    }

    private var trayHeader: some View {
        HStack(spacing: 8) {
            Text("Notifications")
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundColor(NotchInk.primary)
                .lineLimit(1)
                .layoutPriority(1)

            if !viewModel.notificationManager.notifications.isEmpty && !showDiagnostics {
                NotchFilterSegment(showUnreadOnly: $showUnreadOnly, unreadCount: viewModel.unreadCount)
            }

            Spacer(minLength: 4)

            if let media = viewModel.currentMedia {
                Button {
                    Haptics.tap()
                    controller.transition(to: .mediaExpanded(media))
                } label: {
                    HStack(spacing: 5) {
                        MediaAlbumArtView(media: media, size: 16, cornerRadius: 4)
                        Text(media.title)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(NotchInk.primary)
                            .lineLimit(1)
                            .frame(maxWidth: 64)
                        AudioVisualizerView(
                            isPlaying: media.playbackState == .playing,
                            accentColor: media.accentColor,
                            barCount: 3,
                            maxHeight: 9,
                            barWidth: 2,
                            spacing: 1.5
                        )
                    }
                    .padding(.leading, 3)
                    .padding(.trailing, 7)
                    .frame(height: 22)
                    .background(Capsule().fill(media.accentColor.opacity(0.2)))
                    .overlay(Capsule().strokeBorder(media.accentColor.opacity(0.3), lineWidth: 0.5))
                    .contentShape(Capsule())
                }
                .buttonStyle(TransportScaleButtonStyle())
                .help("Open Now Playing Player")
            }

            GlassIconButton(
                showDiagnostics ? "info.circle.fill" : "info.circle",
                help: "Toggle diagnostics & test HUD",
                size: 22,
                tint: showDiagnostics ? .yellow : NotchInk.secondary
            ) {
                withAnimation(NotchMotion.snappy) { showDiagnostics.toggle() }
            }

            if !viewModel.notificationManager.notifications.isEmpty {
                GlassIconButton("trash", help: "Clear all notifications", size: 22) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.notificationManager.clearAll()
                    }
                }
            }

            GlassIconButton("chevron.up", help: "Collapse tray", size: 22) {
                controller.transition(to: controller.restingState)
            }
        }
    }

    private var displayedNotifications: [NotificationItem] {
        if showUnreadOnly {
            return unreadItems
        }
        return viewModel.notificationManager.notifications
    }

    private var notificationListView: some View {
        VStack(spacing: 8) {
            if displayedNotifications.isEmpty {
                emptyState
            } else {
                let newItems = displayedNotifications.filter { !$0.isRead }
                let earlierItems = displayedNotifications.filter { $0.isRead }
                let showSections = !newItems.isEmpty && !earlierItems.isEmpty

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        if showSections {
                            NotchSectionLabel("New", tint: NotchInk.unread.opacity(0.9))
                        }
                        ForEach(newItems) { item in
                            notificationRow(for: item)
                        }
                        if showSections {
                            NotchSectionLabel("Earlier")
                                .padding(.top, 4)
                        }
                        ForEach(earlierItems) { item in
                            notificationRow(for: item)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: 195)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.9),
                            .init(color: .black.opacity(0.0), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }

    private func notificationRow(for item: NotificationItem) -> some View {
        TrayNotificationRow(
            item: item,
            onDismiss: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.notificationManager.dismiss(id: item.id)
                }
            },
            onMarkRead: {
                withAnimation(NotchMotion.smooth) {
                    viewModel.notificationManager.markAsRead(id: item.id)
                }
            },
            onActivate: {
                viewModel.notificationManager.activate(item: item)
                controller.transition(to: controller.restingState)
            }
        )
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.92))
        ))
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Spacer(minLength: 18)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [(showUnreadOnly ? Color.green : Color.white).opacity(0.16), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 34
                        )
                    )
                    .frame(width: 68, height: 68)
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                    .frame(width: 42, height: 42)
                Image(systemName: showUnreadOnly ? "checkmark.seal.fill" : "bell.slash.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(showUnreadOnly ? Color.green.opacity(0.85) : NotchInk.tertiary)
                    .symbolEffect(.bounce, value: showUnreadOnly)
            }
            .frame(height: 52)

            Text(showUnreadOnly ? "All caught up" : "Nothing here yet")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundColor(NotchInk.secondary)
            Text(showUnreadOnly ? "Every notification has been read." : "Incoming alerts and CLI task completions land here.")
                .font(.system(size: 10.5))
                .foregroundColor(NotchInk.quaternary)
            Spacer(minLength: 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}

public struct NotchActionButtonStyle: ButtonStyle {
    public let color: Color
    public init(color: Color) { self.color = color }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(color.opacity(configuration.isPressed ? 0.45 : 0.25))
            .cornerRadius(6)
    }
}

/// Custom animatable notch silhouette featuring outward concave top shoulders that flare seamlessly
/// into the top screen border and continuous squircle-like rounded bottom corners.
public struct NotchShape: Shape {
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat
    public var closeTopEdge: Bool
    
    public init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat, closeTopEdge: Bool = true) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.closeTopEdge = closeTopEdge
    }
    
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }
    
    public func path(in rect: CGRect) -> Path {
        let tr = min(topCornerRadius, rect.height * 0.48)
        let br = min(bottomCornerRadius, min(rect.width * 0.48, rect.height - tr))
        
        var path = Path()
        
        // Start at top-left flared tip on the top screen border (y = 0)
        path.move(to: CGPoint(x: rect.minX - tr, y: rect.minY))
        
        // Top-left concave fillet sweeping inward from top screen border into left vertical wall
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + tr),
            control1: CGPoint(x: rect.minX - tr * 0.32, y: rect.minY),
            control2: CGPoint(x: rect.minX, y: rect.minY + tr * 0.32)
        )
        
        // Left vertical wall
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - br))
        
        // Bottom-left continuous rounded corner
        path.addCurve(
            to: CGPoint(x: rect.minX + br, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: rect.maxY - br * 0.42),
            control2: CGPoint(x: rect.minX + br * 0.42, y: rect.maxY)
        )
        
        // Bottom horizontal edge
        path.addLine(to: CGPoint(x: rect.maxX - br, y: rect.maxY))
        
        // Bottom-right continuous rounded corner
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - br),
            control1: CGPoint(x: rect.maxX - br * 0.42, y: rect.maxY),
            control2: CGPoint(x: rect.maxX, y: rect.maxY - br * 0.42)
        )
        
        // Right vertical wall
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + tr))
        
        // Top-right concave fillet flaring outward from right vertical wall into top screen border
        path.addCurve(
            to: CGPoint(x: rect.maxX + tr, y: rect.minY),
            control1: CGPoint(x: rect.maxX, y: rect.minY + tr * 0.32),
            control2: CGPoint(x: rect.maxX + tr * 0.32, y: rect.minY)
        )
        
        if closeTopEdge {
            path.closeSubpath()
        }
        
        return path
    }
}
