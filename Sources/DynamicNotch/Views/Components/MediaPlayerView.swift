import AppKit
import SwiftUI

/// Animated 4-bar harmonic equalizer waveform that dances when audio is playing
/// and settles into a calm baseline when paused.
public struct AudioVisualizerView: View {
    public let isPlaying: Bool
    public let accentColor: Color
    public var barCount: Int = 4
    public var maxHeight: CGFloat = 13.0
    public var barWidth: CGFloat = 2.6
    public var spacing: CGFloat = 2.4
    
    public init(
        isPlaying: Bool,
        accentColor: Color,
        barCount: Int = 4,
        maxHeight: CGFloat = 13.0,
        barWidth: CGFloat = 2.6,
        spacing: CGFloat = 2.4
    ) {
        self.isPlaying = isPlaying
        self.accentColor = accentColor
        self.barCount = barCount
        self.maxHeight = maxHeight
        self.barWidth = barWidth
        self.spacing = spacing
    }
    
    public var body: some View {
        TimelineView(.animation(minimumInterval: 0.07, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let height = barHeight(for: index, time: t)
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.65)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barWidth, height: height)
                        .animation(.easeInOut(duration: 0.12), value: isPlaying)
                }
            }
            .frame(height: maxHeight)
        }
    }
    
    private func barHeight(for index: Int, time: TimeInterval) -> CGFloat {
        guard isPlaying else {
            return max(3.0, maxHeight * 0.22)
        }
        let speeds: [Double] = [6.4, 8.9, 5.3, 7.6, 6.9]
        let phases: [Double] = [0.0, 1.3, 2.5, 0.8, 1.9]
        let speed = speeds[index % speeds.count]
        let phase = phases[index % phases.count]
        
        let primary = sin(time * speed + phase)
        let secondary = cos(time * (speed * 0.63) - phase * 1.4)
        let normalized = (primary * 0.65 + secondary * 0.35 + 1.0) / 2.0
        let minH = max(3.0, maxHeight * 0.24)
        return minH + CGFloat(normalized) * (maxHeight - minH)
    }
}

/// Renders album artwork with a fallback stylized gradient and smooth play/pause scale physics.
public struct MediaAlbumArtView: View {
    public let media: MediaItem
    public let size: CGFloat
    public let cornerRadius: CGFloat
    
    public init(media: MediaItem, size: CGFloat = 20, cornerRadius: CGFloat = 5.5) {
        self.media = media
        self.size = size
        self.cornerRadius = cornerRadius
    }
    
    public var body: some View {
        ZStack {
            if let data = media.artworkData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                media.accentColor.opacity(0.78),
                                media.accentColor.opacity(0.32),
                                Color.black.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                
                Image(systemName: media.source.iconSystemName)
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundColor(.white.opacity(0.92))
            }
        }
        // Soft inner edge vignette + subtle rim so bright covers feather smoothly into the dark notch frame
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .clear, location: 0.62),
                            .init(color: Color.black.opacity(0.26), location: 1.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.72
                    )
                )
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.02),
                            Color.black.opacity(0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }
}

/// Smoothly rolls and fades between consecutive lyric lines (with optional English translation underneath,
/// or Title • Artist when hovered) with soft top/bottom edge gradient masking.
public struct ScrollingLyricSlot: View {
    public let text: String
    public let translation: String?
    public let subtitle: String?
    public let lineID: String
    public let alignment: Alignment
    
    public init(
        text: String,
        translation: String? = nil,
        subtitle: String? = nil,
        lineID: String,
        alignment: Alignment = .center
    ) {
        self.text = text
        self.translation = translation
        self.subtitle = subtitle
        self.lineID = lineID
        self.alignment = alignment
    }
    
    public var body: some View {
        let hAlignment: HorizontalAlignment = (alignment == .leading) ? .leading : .center
        ZStack(alignment: alignment) {
            VStack(alignment: hAlignment, spacing: 1.5) {
                HStack(spacing: 4) {
                    Text(text)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(1)
                    
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text("• \(subtitle)")
                            .font(.system(size: 10.5, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.58))
                            .lineLimit(1)
                    }
                }
                
                if let translation = translation, !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.64))
                        .lineLimit(1)
                }
            }
            .id(lineID)
            .transition(
                .asymmetric(
                    insertion: .offset(y: 12).combined(with: .opacity).combined(with: .scale(scale: 0.97)),
                    removal: .offset(y: -12).combined(with: .opacity).combined(with: .scale(scale: 0.97))
                )
            )
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: lineID)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .clipped()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

/// Compact ambient Now Playing pill flanking the hardware notch (or top-center on external monitors).
public struct MediaCompactPillView: View {
    public let media: MediaItem
    public let geometry: ScreenGeometry
    public let onExpand: () -> Void
    public let onTogglePlayPause: () -> Void
    
    @State private var isHovered: Bool = false
    
    public init(
        media: MediaItem,
        geometry: ScreenGeometry,
        onExpand: @escaping () -> Void,
        onTogglePlayPause: @escaping () -> Void
    ) {
        self.media = media
        self.geometry = geometry
        self.onExpand = onExpand
        self.onTogglePlayPause = onTogglePlayPause
    }
    
    public var body: some View {
        Group {
            if geometry.hasHardwareNotch {
                hardwareNotchLayout
            } else {
                externalDisplayLayout
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onExpand()
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isHovered = hovering
            }
        }
    }
    
    private var hardwareNotchLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left Ear: Song Cover Artwork squircle in visible screen pixels beside the notch
                ZStack {
                    MediaAlbumArtView(media: media, size: 21, cornerRadius: 5.5)
                        .shadow(color: Color.black.opacity(0.5), radius: 3.5, y: 1)
                        .scaleEffect(isHovered ? 1.06 : 1.0)
                }
                .frame(width: 56.0, height: geometry.notchHeight)
                
                // Center: Physical notch camera housing (dead screen pixels)
                Spacer(minLength: geometry.notchWidth)
                    .frame(height: geometry.notchHeight)
                
                // Right Ear: Harmonic Audio Visualizer in visible screen pixels
                ZStack {
                    AudioVisualizerView(
                        isPlaying: media.playbackState == .playing,
                        accentColor: media.accentColor,
                        barCount: 4,
                        maxHeight: 12.5,
                        barWidth: 2.5,
                        spacing: 2.2
                    )
                }
                .frame(width: 56.0, height: geometry.notchHeight)
            }
            .frame(height: geometry.notchHeight)
            
            // Ambient Live Lyric Ribbon directly beneath the notch cutout:
            // Shows pure scrolling lyrics (+ English translation underneath when enabled) when unfocused,
            // and smoothly rolls to Title • Artist on hover.
            if !media.lyrics.isEmpty {
                let showTranslation = MediaPlaybackManager.shared.isTranslationEnabled
                TimelineView(.animation(minimumInterval: 0.2, paused: media.playbackState != .playing)) { context in
                    let activeLine = media.activeLyricLine(at: context.date)
                    let showMetadata = isHovered || activeLine == nil
                    
                    ScrollingLyricSlot(
                        text: showMetadata ? media.title : (activeLine?.text ?? media.title),
                        translation: (!showMetadata && showTranslation) ? activeLine?.translation : nil,
                        subtitle: showMetadata ? media.artist : nil,
                        lineID: showMetadata ? "meta-\(media.id)" : "lyric-\(activeLine?.id ?? -1)-\(showTranslation)",
                        alignment: .center
                    )
                    .padding(.horizontal, 14)
                    .frame(height: (showTranslation && media.hasTranslations) ? 34.0 : 22.0)
                }
            }
        }
    }
    
    private var externalDisplayLayout: some View {
        let showTranslation = MediaPlaybackManager.shared.isTranslationEnabled
        return TimelineView(.animation(minimumInterval: 0.2, paused: media.playbackState != .playing)) { context in
            let progress = media.progress(at: context.date)
            let activeLine = media.activeLyricLine(at: context.date)
            let showMetadata = isHovered || media.lyrics.isEmpty || activeLine == nil
            let pillHeight: CGFloat = (showTranslation && media.hasTranslations && !media.lyrics.isEmpty) ? 40.0 : geometry.notchHeight
            
            ZStack(alignment: .bottom) {
                HStack(spacing: 8) {
                    MediaAlbumArtView(media: media, size: 21, cornerRadius: 5.5)
                        .shadow(color: Color.black.opacity(0.5), radius: 3.5, y: 1)
                        .padding(.leading, 9)
                    
                    ScrollingLyricSlot(
                        text: showMetadata ? media.title : (activeLine?.text ?? media.title),
                        translation: (!showMetadata && showTranslation) ? activeLine?.translation : nil,
                        subtitle: showMetadata ? media.artist : nil,
                        lineID: showMetadata ? "meta-\(media.id)" : "lyric-\(activeLine?.id ?? -1)-\(showTranslation)",
                        alignment: .leading
                    )
                    
                    AudioVisualizerView(
                        isPlaying: media.playbackState == .playing,
                        accentColor: media.accentColor,
                        barCount: 4,
                        maxHeight: 11.5,
                        barWidth: 2.3,
                        spacing: 2.0
                    )
                    .padding(.trailing, 12)
                }
                .frame(height: pillHeight)
                
                // Subtle bottom progress line
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [media.accentColor.opacity(0.18), media.accentColor.opacity(0.55)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(progress), height: 1.5)
                }
                .frame(height: 1.5)
            }
        }
    }
}

/// Full interactive Now Playing media player card inside the expanded Dynamic Island.
public struct MediaExpandedPlayerView: View {
    public let media: MediaItem
    public let unreadCount: Int
    public let onTogglePlayPause: () -> Void
    public let onNext: () -> Void
    public let onPrevious: () -> Void
    public let onSeek: (TimeInterval) -> Void
    public let onOpenSourceApp: () -> Void
    public let onOpenTray: () -> Void
    public let onCollapse: () -> Void
    public let onStopSimulated: (() -> Void)?
    
    @State private var isScrubbing: Bool = false
    @State private var scrubProgress: Double = 0.0
    @State private var isHoveringScrubber: Bool = false
    @State private var showFullLyrics: Bool = false
    @State private var previousTapCount: Int = 0
    @State private var nextTapCount: Int = 0

    public init(
        media: MediaItem,
        unreadCount: Int,
        onTogglePlayPause: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onSeek: @escaping (TimeInterval) -> Void,
        onOpenSourceApp: @escaping () -> Void,
        onOpenTray: @escaping () -> Void,
        onCollapse: @escaping () -> Void,
        onStopSimulated: (() -> Void)? = nil
    ) {
        self.media = media
        self.unreadCount = unreadCount
        self.onTogglePlayPause = onTogglePlayPause
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onSeek = onSeek
        self.onOpenSourceApp = onOpenSourceApp
        self.onOpenTray = onOpenTray
        self.onCollapse = onCollapse
        self.onStopSimulated = onStopSimulated
    }
    
    public var body: some View {
        ZStack {
            VStack(spacing: 10) {
                // Top Row: Artwork + Metadata + Quick Tray/Collapse buttons
                HStack(alignment: .center, spacing: 12) {
                    Button(action: onOpenSourceApp) {
                        ZStack {
                            // Blurred copy of the cover bleeding light onto the island, like a glowing sleeve
                            MediaAlbumArtView(media: media, size: 52, cornerRadius: 12)
                                .blur(radius: 14)
                                .opacity(media.playbackState == .playing ? 0.75 : 0.3)
                                .scaleEffect(media.playbackState == .playing ? 1.12 : 0.9)
                                .offset(y: 4)
                                .allowsHitTesting(false)

                            MediaAlbumArtView(media: media, size: 52, cornerRadius: 12)
                                .scaleEffect(media.playbackState == .playing ? 1.0 : 0.92)
                                .saturation(media.playbackState == .playing ? 1.0 : 0.55)
                                .shadow(
                                    color: Color.black.opacity(0.55),
                                    radius: media.playbackState == .playing ? 8 : 4,
                                    x: 0,
                                    y: 3
                                )
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: media.playbackState)
                    }
                    .buttonStyle(.plain)
                    .help("Open \(media.source.rawValue)")
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: media.source.iconSystemName)
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(media.accentColor)
                            
                            Text(media.source.rawValue.uppercased())
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundColor(media.accentColor)
                            
                            if !media.album.isEmpty {
                                Text("• \(media.album)")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundColor(.white.opacity(0.45))
                                    .lineLimit(1)
                            }
                        }
                        
                        Text(media.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(media.artist)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 4)
                    
                    // Right Utility Controls: Visualizer + Notification Tray Switch + Collapse
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 6) {
                            Button(action: onOpenTray) {
                                HStack(spacing: 3) {
                                    Image(systemName: unreadCount > 0 ? "bell.badge.fill" : "bell.fill")
                                        .symbolRenderingMode(.multicolor)
                                        .font(.system(size: 10.5, weight: .semibold))
                                    if unreadCount > 0 {
                                        Text("\(unreadCount)")
                                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    }
                                }
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Switch to Notification Tray")
                            
                            Button(action: onCollapse) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.75))
                                    .padding(6)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Circle())
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Minimize to Compact Pill")
                        }
                        
                        AudioVisualizerView(
                            isPlaying: media.playbackState == .playing,
                            accentColor: media.accentColor,
                            barCount: 5,
                            maxHeight: 14,
                            barWidth: 2.6,
                            spacing: 2.4
                        )
                        .padding(.trailing, 4)
                    }
                }
                
                // Time-Synced Lyrics Section (Live Ticker or Interactive Karaoke Scroll)
                let showTranslation = MediaPlaybackManager.shared.isTranslationEnabled
                TimelineView(.animation(minimumInterval: 0.2, paused: media.playbackState != .playing)) { context in
                    let activeIndex = media.activeLyricIndex(at: context.date)
                    
                    if showFullLyrics && !media.lyrics.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(alignment: .leading, spacing: 5) {
                                    ForEach(Array(media.lyrics.enumerated()), id: \.element.id) { idx, line in
                                        let isCurrent = (idx == activeIndex)
                                        Button {
                                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                                            onSeek(line.timestamp)
                                        } label: {
                                            HStack(alignment: .top, spacing: 6) {
                                                if isCurrent {
                                                    Circle()
                                                        .fill(media.accentColor)
                                                        .frame(width: 5, height: 5)
                                                        .shadow(color: media.accentColor, radius: 3)
                                                        .padding(.top, 5)
                                                }
                                                VStack(alignment: .leading, spacing: 1.5) {
                                                    Text(line.text)
                                                        .font(.system(size: isCurrent ? 12.5 : 11, weight: isCurrent ? .bold : .medium, design: .rounded))
                                                        .foregroundColor(isCurrent ? .white : .white.opacity(0.38))
                                                        .lineLimit(1)
                                                    
                                                    if showTranslation, let trans = line.translation, !trans.isEmpty {
                                                        Text(trans)
                                                            .font(.system(size: isCurrent ? 10.5 : 9.5, weight: .medium, design: .rounded))
                                                            .foregroundColor(isCurrent ? .white.opacity(0.68) : .white.opacity(0.26))
                                                            .lineLimit(1)
                                                    }
                                                }
                                                Spacer(minLength: 0)
                                            }
                                            .padding(.vertical, 1.5)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .id(idx)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                            .frame(height: 46)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .black, location: 0.16),
                                        .init(color: .black, location: 0.84),
                                        .init(color: .clear, location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .onChange(of: activeIndex) { _, newIdx in
                                if let newIdx = newIdx {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                        proxy.scrollTo(newIdx, anchor: .center)
                                    }
                                }
                            }
                            .onAppear {
                                if let activeIndex = activeIndex {
                                    proxy.scrollTo(activeIndex, anchor: .center)
                                }
                            }
                        }
                    } else {
                        Button {
                            guard !media.lyrics.isEmpty else { return }
                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showFullLyrics.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if let idx = activeIndex, media.lyrics.indices.contains(idx) {
                                    ZStack(alignment: .leading) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(media.lyrics[idx].text)
                                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                                .foregroundColor(.white.opacity(0.95))
                                                .lineLimit(1)
                                            
                                            if showTranslation, let trans = media.lyrics[idx].translation, !trans.isEmpty {
                                                Text(trans)
                                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                                    .foregroundColor(.white.opacity(0.65))
                                                    .lineLimit(1)
                                            } else if media.lyrics.indices.contains(idx + 1) {
                                                Text(media.lyrics[idx + 1].text)
                                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                                    .foregroundColor(.white.opacity(0.38))
                                                    .lineLimit(1)
                                            }
                                        }
                                        .id("exp-lyric-\(idx)-\(showTranslation)")
                                        .transition(
                                            .asymmetric(
                                                insertion: .offset(y: 12).combined(with: .opacity),
                                                removal: .offset(y: -12).combined(with: .opacity)
                                            )
                                        )
                                    }
                                    .animation(.spring(response: 0.42, dampingFraction: 0.84), value: idx)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                                    .clipped()
                                    .mask(
                                        LinearGradient(
                                            stops: [
                                                .init(color: .clear, location: 0.0),
                                                .init(color: .black, location: 0.14),
                                                .init(color: .black, location: 0.86),
                                                .init(color: .clear, location: 1.0)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                } else {
                                    Text("Synced lyrics • Live with playback")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.45))
                                        .lineLimit(1)
                                }
                                
                                Spacer(minLength: 4)
                                
                                if !media.lyrics.isEmpty {
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(media.lyrics.isEmpty ? "Searching for time-synced lyrics..." : "Click to expand interactive karaoke lyrics")
                    }
                }
                
                // Interactive Progress Scrubber Row
                TimelineView(.animation(minimumInterval: 0.25, paused: media.playbackState != .playing || isScrubbing)) { context in
                    let activeProgress = isScrubbing ? scrubProgress : media.progress(at: context.date)
                    let displaySeconds = activeProgress * media.duration
                    let remainingSeconds = max(0.0, media.duration - displaySeconds)
                    
                    HStack(spacing: 8) {
                        Text(MediaItem.formatSeconds(displaySeconds))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 34, alignment: .leading)
                        
                        GeometryReader { geo in
                            let trackHeight: CGFloat = isHoveringScrubber || isScrubbing ? 6.5 : 4.5
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.16))
                                    .frame(height: trackHeight)
                                
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [media.accentColor, .white],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(trackHeight, geo.size.width * CGFloat(activeProgress)), height: trackHeight)
                                
                                // Playhead: a glowing ember at rest, growing into a grabbable knob on hover
                                let knobSize: CGFloat = (isHoveringScrubber || isScrubbing) ? 11 : 5
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: knobSize, height: knobSize)
                                    .shadow(color: media.accentColor, radius: (isHoveringScrubber || isScrubbing) ? 5 : 3)
                                    .shadow(color: Color.white.opacity(0.6), radius: 1.5)
                                    .offset(x: max(0, min(geo.size.width - knobSize, geo.size.width * CGFloat(activeProgress) - knobSize / 2)))
                                    .animation(NotchMotion.snappy, value: knobSize)
                            }
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let ratio = max(0.0, min(1.0, Double(value.location.x / max(1.0, geo.size.width))))
                                        if !isScrubbing {
                                            isScrubbing = true
                                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                                        }
                                        scrubProgress = ratio
                                    }
                                    .onEnded { value in
                                        let ratio = max(0.0, min(1.0, Double(value.location.x / max(1.0, geo.size.width))))
                                        let targetTime = ratio * media.duration
                                        isScrubbing = false
                                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                                        onSeek(targetTime)
                                    }
                            )
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isHoveringScrubber = hovering
                                }
                            }
                        }
                        .frame(height: 14)
                        
                        Text("-" + MediaItem.formatSeconds(remainingSeconds))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                
                // Transport Controls Row
                HStack(spacing: 24) {
                    Button(action: onOpenSourceApp) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(TransportScaleButtonStyle())
                    .help("Launch \(media.source.rawValue)")
                    
                    Spacer()
                    
                    Button {
                        previousTapCount += 1
                        onPrevious()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 15, weight: .bold))
                            .symbolEffect(.bounce.down, value: previousTapCount)
                            .foregroundColor(.white.opacity(0.9))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(TransportScaleButtonStyle())
                    .help("Previous Track")
                    
                    Button(action: onTogglePlayPause) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 38, height: 38)
                                .shadow(color: media.accentColor.opacity(0.55), radius: 8, y: 2)
                            
                            Image(systemName: media.playbackState == .playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .black))
                                .foregroundColor(.black)
                                .contentTransition(.symbolEffect(.replace.downUp))
                                .offset(x: media.playbackState == .playing ? 0 : 1)
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(TransportScaleButtonStyle())
                    .help(media.playbackState == .playing ? "Pause" : "Play")
                    
                    Button {
                        nextTapCount += 1
                        onNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 15, weight: .bold))
                            .symbolEffect(.bounce.down, value: nextTapCount)
                            .foregroundColor(.white.opacity(0.9))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(TransportScaleButtonStyle())
                    .help("Next Track")
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                MediaPlaybackManager.shared.toggleTranslation()
                            }
                        } label: {
                            HStack(spacing: 2.5) {
                                Image(systemName: "character.bubble.fill")
                                    .font(.system(size: 9.5, weight: .bold))
                                Text("EN")
                                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                            }
                            .foregroundColor(showTranslation ? .black : .white.opacity(0.5))
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(showTranslation ? media.accentColor : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(TransportScaleButtonStyle())
                        .help(showTranslation ? "Hide English Lyric Translation (On)" : "Show English Lyric Translation (Off)")
                        
                        Button {
                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showFullLyrics.toggle()
                            }
                        } label: {
                            Image(systemName: showFullLyrics ? "quote.bubble.fill" : "quote.bubble")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(showFullLyrics ? .black : (media.lyrics.isEmpty ? .white.opacity(0.4) : media.accentColor))
                                .frame(width: 28, height: 28)
                                .background(showFullLyrics ? media.accentColor : Color.white.opacity(0.08))
                                .clipShape(Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(TransportScaleButtonStyle())
                        .help("Toggle Interactive Lyrics")
                    }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
    }
}

/// Interactive spring scale button style for media transport controls.
public struct TransportScaleButtonStyle: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
