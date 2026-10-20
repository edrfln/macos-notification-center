import AppKit
import Foundation
import NaturalLanguage
import Observation
import Translation

/// Central manager for intercepting live macOS media playback (Apple Music, Spotify, and system-wide Now Playing)
/// via a best-effort MediaRemote helper subprocess + DistributedNotificationCenter, automatically fetching high-res
/// song covers, and executing bi-directional playback controls (with an AppleScript fallback when the helper is unavailable).
@Observable
@MainActor
public final class MediaPlaybackManager {
    public static let shared = MediaPlaybackManager()

    /// UserDefaults key backing `isTranslationEnabled`.
    public nonisolated static let translationDefaultsKey = "DynamicNotch.isTranslationEnabled"

    /// Currently active media item (playing or recently paused). Nil when stopped/closed.
    public private(set) var currentMedia: MediaItem?

    /// Whether active media is currently playing.
    public var isPlaying: Bool {
        currentMedia?.playbackState == .playing
    }

    /// Whether English lyric translation is fetched and shown beneath the original lyrics (Off by default).
    /// Translation runs on-device (macOS 26+) using installed language packs; no lyric text leaves the Mac.
    public var isTranslationEnabled: Bool = (UserDefaults.standard.object(forKey: MediaPlaybackManager.translationDefaultsKey) as? Bool) ?? false {
        didSet {
            UserDefaults.standard.set(isTranslationEnabled, forKey: Self.translationDefaultsKey)
            if isTranslationEnabled, let media = currentMedia, !media.lyrics.isEmpty, !media.hasTranslations {
                translateAndApply(media.lyrics, cacheKey: "\(media.title)|\(media.artist)", forTitle: media.title)
            }
            broadcast()
        }
    }
    
    /// Toggles the English lyric translation display on or off.
    public func toggleTranslation() {
        performHaptic()
        isTranslationEnabled.toggle()
    }
    
    /// Multi-window listeners notified whenever media metadata, artwork, or playback state changes.
    private var listeners: [UUID: (MediaItem?) -> Void] = [:]
    
    /// Cache of downloaded song cover artwork keyed by "title|artist"
    private var artworkCache: [String: Data] = [:]
    
    /// Cache of parsed time-synced LRC lyrics keyed by "title|artist"
    private var lyricsCache: [String: [LyricLine]] = [:]
    
    @ObservationIgnored
    nonisolated(unsafe) private var musicObserver: (any NSObjectProtocol)?
    
    @ObservationIgnored
    nonisolated(unsafe) private var spotifyObserver: (any NSObjectProtocol)?
    
    @ObservationIgnored
    private var helperProcess: Process?
    
    @ObservationIgnored
    private var helperStdinPipe: Pipe?
    
    @ObservationIgnored
    private var helperStdoutPipe: Pipe?
    
    @ObservationIgnored
    private var stdoutBuffer: Data = Data()

    @ObservationIgnored
    private var helperRestartCount: Int = 0

    private static let maxHelperRestarts = 3

    /// Debounced clear for when MediaRemote reports nothing playing (avoids flicker between tracks).
    @ObservationIgnored
    private var pendingClearTask: Task<Void, Never>?

    /// Network lookup bookkeeping so repeated playback events don't re-issue the same requests.
    @ObservationIgnored
    private var inFlightArtworkKeys: Set<String> = []
    @ObservationIgnored
    private var missingArtworkKeys: Set<String> = []
    @ObservationIgnored
    private var inFlightLyricsKeys: Set<String> = []
    @ObservationIgnored
    private var missingLyricsKeys: Set<String> = []
    @ObservationIgnored
    private var inFlightTranslationKeys: Set<String> = []

    /// Simulated demo playlist index
    private var simulatedIndex: Int = 0
    
    private struct SimulatedTrack {
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let colors: (NSColor, NSColor)
        let accent: (Double, Double, Double)
        let symbol: String
    }
    
    private let simulatedPlaylist: [SimulatedTrack] = [
        SimulatedTrack(
            title: "夜に駆ける",
            artist: "YOASOBI",
            album: "THE BOOK",
            duration: 261.0,
            colors: (NSColor(calibratedRed: 0.96, green: 0.28, blue: 0.58, alpha: 1.0),
                     NSColor(calibratedRed: 0.35, green: 0.22, blue: 0.92, alpha: 1.0)),
            accent: (0.96, 0.36, 0.64),
            symbol: "sparkles"
        ),
        SimulatedTrack(
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            duration: 243.0,
            colors: (NSColor(calibratedRed: 0.55, green: 0.18, blue: 0.88, alpha: 1.0),
                     NSColor(calibratedRed: 0.96, green: 0.28, blue: 0.58, alpha: 1.0)),
            accent: (0.85, 0.35, 0.95),
            symbol: "waveform.path.ecg"
        ),
        SimulatedTrack(
            title: "Starboy",
            artist: "The Weeknd",
            album: "Starboy (Deluxe)",
            duration: 230.0,
            colors: (NSColor(calibratedRed: 0.92, green: 0.15, blue: 0.28, alpha: 1.0),
                     NSColor(calibratedRed: 0.98, green: 0.58, blue: 0.14, alpha: 1.0)),
            accent: (0.98, 0.34, 0.38),
            symbol: "bolt.fill"
        )
    ]
    
    public init() {
        setupDistributedObservers()
        startMediaRemoteHelper()
    }
    
    deinit {
        let dnc = DistributedNotificationCenter.default()
        if let musicObserver = musicObserver {
            dnc.removeObserver(musicObserver)
        }
        if let spotifyObserver = spotifyObserver {
            dnc.removeObserver(spotifyObserver)
        }
        helperStdoutPipe?.fileHandleForReading.readabilityHandler = nil
        helperProcess?.terminate()
    }
    
    // MARK: - Multi-Window Listener Registration
    
    public func registerListener(id: UUID, onMediaChange: @escaping (MediaItem?) -> Void) {
        listeners[id] = onMediaChange
        if let currentMedia = currentMedia {
            onMediaChange(currentMedia)
        }
    }
    
    public func unregisterListener(id: UUID) {
        listeners.removeValue(forKey: id)
    }
    
    private func broadcast() {
        for listener in listeners.values {
            listener(currentMedia)
        }
    }
    
    // MARK: - Platform-Entitled MediaRemote Subprocess Bridge
    
    private func startMediaRemoteHelper() {
        // `/usr/bin/swift` is a shim: without the Command Line Tools it pops an install dialog instead of running.
        guard Self.isSwiftToolchainAvailable() else {
            print("MediaRemote helper disabled: Swift toolchain not installed; using AppleScript transport fallback.")
            return
        }

        let script = """
        import Foundation
        
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            exit(0)
        }
        typealias RegFn = @convention(c) (DispatchQueue) -> Void
        typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
        typealias SendCmdFn = @convention(c) (UInt32, AnyObject?) -> Bool
        typealias SetTimeFn = @convention(c) (Double) -> Void
        
        let regSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")
        let infoSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")
        let cmdSym = dlsym(handle, "MRMediaRemoteSendCommand")
        let timeSym = dlsym(handle, "MRMediaRemoteSetElapsedTime")
        
        guard let infoSym = infoSym else { exit(0) }
        let getInfo = unsafeBitCast(infoSym, to: GetInfoFn.self)
        let sendCmd = cmdSym.map { unsafeBitCast($0, to: SendCmdFn.self) }
        let setTime = timeSym.map { unsafeBitCast($0, to: SetTimeFn.self) }
        
        if let regSym = regSym {
            let reg = unsafeBitCast(regSym, to: RegFn.self)
            reg(DispatchQueue.main)
        }
        
        func emitNowPlaying() {
            getInfo(DispatchQueue.main) { info in
                let title = (info["kMRMediaRemoteNowPlayingInfoTitle"] as? String) ?? ""
                let artist = (info["kMRMediaRemoteNowPlayingInfoArtist"] as? String) ?? ""
                let album = (info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String) ?? ""
                let duration = (info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double) ?? 0.0
                var elapsed = (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double) ?? 0.0
                let rate = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double)
                    ?? Double((info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Int) ?? 0)
                if rate > 0, let ts = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
                    elapsed += max(0.0, Date().timeIntervalSince(ts)) * rate
                }
                let isMusic = (info["kMRMediaRemoteNowPlayingInfoIsMusicApp"] as? Bool) ?? false
                var payload: [String: Any] = [
                    "title": title,
                    "artist": artist,
                    "album": album,
                    "duration": duration,
                    "elapsed": elapsed,
                    "rate": rate,
                    "isMusicApp": isMusic
                ]
                if let art = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data, !art.isEmpty {
                    payload["artworkBase64"] = art.base64EncodedString()
                }
                if let data = try? JSONSerialization.data(withJSONObject: payload),
                   let line = String(data: data, encoding: .utf8) {
                    print(line)
                    fflush(stdout)
                }
            }
        }
        
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"), object: nil, queue: .main) { _ in
            emitNowPlaying()
        }
        nc.addObserver(forName: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"), object: nil, queue: .main) { _ in
            emitNowPlaying()
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            while let line = readLine() {
                let cmd = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if cmd == "toggle" {
                    _ = sendCmd?(2, nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { emitNowPlaying() }
                } else if cmd == "next" {
                    _ = sendCmd?(4, nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { emitNowPlaying() }
                } else if cmd == "prev" {
                    _ = sendCmd?(5, nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { emitNowPlaying() }
                } else if cmd.hasPrefix("seek:") {
                    if let val = Double(cmd.dropFirst(5)) {
                        setTime?(val)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { emitNowPlaying() }
                    }
                } else if cmd == "refresh" {
                    DispatchQueue.main.async { emitNowPlaying() }
                }
            }
            exit(0)
        }
        
        emitNowPlaying()
        RunLoop.main.run()
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["-e", script]
        
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        
        // Writing to the pipe after the helper dies must fail with EPIPE rather than raise SIGPIPE and kill the app.
        _ = fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consumeHelperOutput(data)
            }
        }

        process.terminationHandler = { [weak self] proc in
            let reason = proc.terminationReason
            let status = proc.terminationStatus
            Task { @MainActor [weak self] in
                self?.handleHelperTermination(reason: reason, status: status)
            }
        }

        do {
            try process.run()
            self.helperProcess = process
            self.helperStdinPipe = stdinPipe
            self.helperStdoutPipe = stdoutPipe
        } catch {
            print("Failed to start MediaRemote helper: \(error)")
        }
    }

    private func handleHelperTermination(reason: Process.TerminationReason, status: Int32) {
        helperStdoutPipe?.fileHandleForReading.readabilityHandler = nil
        helperProcess = nil
        helperStdinPipe = nil
        helperStdoutPipe = nil
        stdoutBuffer.removeAll()

        // A clean or compile-failure exit (e.g. MediaRemote unavailable) won't improve on retry; only restart crashes.
        guard reason == .uncaughtSignal, helperRestartCount < Self.maxHelperRestarts else {
            print("MediaRemote helper exited (status \(status)); using AppleScript transport fallback.")
            return
        }
        helperRestartCount += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.startMediaRemoteHelper()
        }
    }

    /// Sends a command to the helper. Returns false when the helper isn't running or the write failed.
    @discardableResult
    private func sendHelperCommand(_ command: String) -> Bool {
        guard let process = helperProcess, process.isRunning,
              let pipe = helperStdinPipe,
              let data = (command + "\n").data(using: .utf8) else {
            return false
        }
        do {
            try pipe.fileHandleForWriting.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    /// Routes a transport command through the MediaRemote helper, falling back to AppleScript for Music/Spotify.
    private func performTransport(helperCommand: String, appleScriptCommand: String, for media: MediaItem) {
        if sendHelperCommand(helperCommand) { return }
        let appName: String
        switch media.source {
        case .appleMusic: appName = "Music"
        case .spotify: appName = "Spotify"
        case .simulated: return
        }
        let source = "if application \"\(appName)\" is running then tell application \"\(appName)\" to \(appleScriptCommand)"
        Task.detached {
            _ = Self.runAppleScript(source)
        }
    }

    private nonisolated static func isSwiftToolchainAvailable() -> Bool {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        probe.arguments = ["-p"]
        let output = Pipe()
        probe.standardOutput = output
        probe.standardError = FileHandle.nullDevice
        do {
            try probe.run()
        } catch {
            return false
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        probe.waitUntilExit()
        guard probe.terminationStatus == 0,
              let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return false
        }
        return FileManager.default.fileExists(atPath: path)
    }
    
    private func consumeHelperOutput(_ data: Data) {
        stdoutBuffer.append(data)
        let newline = UInt8(ascii: "\n")
        while let range = stdoutBuffer.firstRange(of: Data([newline])) {
            let lineData = stdoutBuffer.subdata(in: 0..<range.lowerBound)
            stdoutBuffer.removeSubrange(0..<range.upperBound)
            if !lineData.isEmpty,
               let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                handleMediaRemotePayload(json)
            }
        }
    }
    
    private func handleMediaRemotePayload(_ payload: [String: Any]) {
        // Do not overwrite active simulated demo playback unless a real player is actively playing
        let rate = (payload["rate"] as? Double) ?? 0.0
        if currentMedia?.source == .simulated && rate <= 0.01 {
            return
        }
        
        let rawTitle = (payload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawTitle.isEmpty else {
            // Empty Now Playing info means no player is active system-wide (covers sources without their own Stopped notification).
            scheduleNowPlayingClear()
            return
        }
        cancelPendingClear()

        let rawArtist = (payload["artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = rawArtist.isEmpty ? "Now Playing" : rawArtist
        let album = (payload["album"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let duration = max(1.0, (payload["duration"] as? Double) ?? 180.0)
        let elapsed = max(0.0, (payload["elapsed"] as? Double) ?? 0.0)
        let isMusicApp = (payload["isMusicApp"] as? Bool) ?? false
        
        let source: MediaItem.SourceApp
        if isMusicApp {
            source = .appleMusic
        } else if currentMedia?.source == .spotify && currentMedia?.title == rawTitle {
            source = .spotify
        } else {
            let runningIds = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
            if runningIds.contains("com.spotify.client") && !runningIds.contains("com.apple.Music") {
                source = .spotify
            } else {
                source = .appleMusic
            }
        }
        
        let cacheKey = "\(rawTitle)|\(artist)"
        var artworkData: Data? = artworkCache[cacheKey]
        if let base64 = payload["artworkBase64"] as? String,
           let decoded = Data(base64Encoded: base64), !decoded.isEmpty {
            artworkData = decoded
            artworkCache[cacheKey] = decoded
        }
        let cachedLyrics = lyricsCache[cacheKey] ?? []
        
        let playbackState: MediaItem.PlaybackState = (rate > 0.01) ? .playing : .paused
        var item = MediaItem(
            id: "mr-\(rawTitle)-\(artist)",
            title: rawTitle,
            artist: artist,
            album: album,
            duration: duration,
            playbackPosition: min(duration, elapsed),
            playbackState: playbackState,
            source: source,
            artworkData: artworkData,
            lyrics: cachedLyrics,
            updatedAt: Date()
        )
        if let art = artworkData, let accent = Self.extractDominantColor(from: art) {
            item.accentColorRed = accent.0
            item.accentColorGreen = accent.1
            item.accentColorBlue = accent.2
        }
        
        self.currentMedia = item
        broadcast()
        
        if artworkData == nil {
            fetchAndApplySongCover(title: rawTitle, artist: rawArtist, album: album, source: source)
        }
        if cachedLyrics.isEmpty {
            fetchAndApplyLyrics(title: rawTitle, artist: rawArtist, album: album)
        }
    }
    
    private func scheduleNowPlayingClear() {
        guard let media = currentMedia, media.source != .simulated, pendingClearTask == nil else { return }
        pendingClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self = self else { return }
            self.pendingClearTask = nil
            guard let current = self.currentMedia, current.source != .simulated else { return }
            self.currentMedia = nil
            self.broadcast()
        }
    }

    private func cancelPendingClear() {
        pendingClearTask?.cancel()
        pendingClearTask = nil
    }

    // MARK: - Zero-Poll Distributed Notification Interception
    
    private func setupDistributedObservers() {
        let dnc = DistributedNotificationCenter.default()
        
        musicObserver = dnc.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let info = notification.userInfo
            Task { @MainActor [weak self] in
                self?.handleAppleMusicNotification(userInfo: info)
            }
        }
        
        spotifyObserver = dnc.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let info = notification.userInfo
            Task { @MainActor [weak self] in
                self?.handleSpotifyNotification(userInfo: info)
            }
        }
    }
    
    private func handleAppleMusicNotification(userInfo: [AnyHashable: Any]?) {
        guard let userInfo = userInfo else { return }
        let stateStr = (userInfo["Player State"] as? String) ?? "Stopped"
        
        if stateStr == "Stopped" {
            if currentMedia?.source == .appleMusic {
                currentMedia = nil
                broadcast()
            }
            return
        }
        
        cancelPendingClear()
        let title = (userInfo["Name"] as? String) ?? (currentMedia?.title ?? "Unknown Track")
        let artist = (userInfo["Artist"] as? String) ?? (currentMedia?.artist ?? "Apple Music")
        let album = (userInfo["Album"] as? String) ?? (currentMedia?.album ?? "")
        
        let totalTimeMs = (userInfo["Total Time"] as? Double) ?? Double((userInfo["Total Time"] as? Int) ?? 180_000)
        let duration = max(1.0, totalTimeMs > 1000 ? (totalTimeMs / 1000.0) : totalTimeMs)
        let playbackState: MediaItem.PlaybackState = (stateStr == "Playing") ? .playing : .paused
        
        let cacheKey = "\(title)|\(artist)"
        let cachedArtwork = artworkCache[cacheKey]
        let cachedLyrics = lyricsCache[cacheKey] ?? []
        let previousPos = (currentMedia?.title == title) ? (currentMedia?.currentPosition() ?? 0.0) : 0.0
        
        var item = MediaItem(
            id: "applemusic-\(title)-\(artist)",
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            playbackPosition: previousPos,
            playbackState: playbackState,
            source: .appleMusic,
            artworkData: cachedArtwork,
            lyrics: cachedLyrics,
            updatedAt: Date()
        )
        if let data = cachedArtwork, let accent = Self.extractDominantColor(from: data) {
            item.accentColorRed = accent.0
            item.accentColorGreen = accent.1
            item.accentColorBlue = accent.2
        }
        
        self.currentMedia = item
        broadcast()
        
        sendHelperCommand("refresh")
        if cachedArtwork == nil {
            fetchAndApplySongCover(title: title, artist: artist, album: album, source: .appleMusic)
        }
        if cachedLyrics.isEmpty {
            fetchAndApplyLyrics(title: title, artist: artist, album: album)
        }
    }
    
    private func handleSpotifyNotification(userInfo: [AnyHashable: Any]?) {
        guard let userInfo = userInfo else { return }
        let stateStr = (userInfo["Player State"] as? String) ?? "Stopped"
        
        if stateStr == "Stopped" {
            if currentMedia?.source == .spotify {
                currentMedia = nil
                broadcast()
            }
            return
        }
        
        cancelPendingClear()
        let title = (userInfo["Name"] as? String) ?? (currentMedia?.title ?? "Unknown Track")
        let artist = (userInfo["Artist"] as? String) ?? (currentMedia?.artist ?? "Spotify")
        let album = (userInfo["Album"] as? String) ?? (currentMedia?.album ?? "")
        
        let rawDuration = (userInfo["Duration"] as? Double) ?? Double((userInfo["Duration"] as? Int) ?? 180)
        let duration = max(1.0, rawDuration > 2000 ? (rawDuration / 1000.0) : rawDuration)
        let position = (userInfo["Playback Position"] as? Double) ?? 0.0
        let playbackState: MediaItem.PlaybackState = (stateStr == "Playing") ? .playing : .paused
        
        let cacheKey = "\(title)|\(artist)"
        let cachedArtwork = artworkCache[cacheKey]
        let cachedLyrics = lyricsCache[cacheKey] ?? []
        
        var item = MediaItem(
            id: "spotify-\(title)-\(artist)",
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            playbackPosition: position,
            playbackState: playbackState,
            source: .spotify,
            artworkData: cachedArtwork,
            lyrics: cachedLyrics,
            updatedAt: Date()
        )
        if let data = cachedArtwork, let accent = Self.extractDominantColor(from: data) {
            item.accentColorRed = accent.0
            item.accentColorGreen = accent.1
            item.accentColorBlue = accent.2
        }
        
        self.currentMedia = item
        broadcast()
        
        if cachedArtwork == nil {
            fetchAndApplySongCover(title: title, artist: artist, album: album, source: .spotify)
        }
        if cachedLyrics.isEmpty {
            fetchAndApplyLyrics(title: title, artist: artist, album: album)
        }
    }
    
    // MARK: - Automatic High-Res Song Cover Lookup
    
    private func fetchAndApplySongCover(title: String, artist: String, album: String, source: MediaItem.SourceApp) {
        let displayArtist = artist.isEmpty ? "Now Playing" : artist
        let cacheKey = "\(title)|\(displayArtist)"
        if let cached = artworkCache[cacheKey] {
            applyArtworkData(cached, forTitle: title)
            return
        }
        guard !inFlightArtworkKeys.contains(cacheKey), !missingArtworkKeys.contains(cacheKey) else { return }
        inFlightArtworkKeys.insert(cacheKey)

        Task { @MainActor [weak self] in
            // 1. Try Spotify artwork URL if Spotify is the source
            var fetched: Data? = nil
            if source == .spotify {
                fetched = await Self.fetchSpotifyArtwork()
            }
            // 2. Fetch official 300x300 album cover from iTunes Search API
            if fetched == nil {
                fetched = await Self.fetchiTunesSongCover(title: title, artist: artist, album: album)
            }

            guard let self = self else { return }
            self.inFlightArtworkKeys.remove(cacheKey)
            guard let data = fetched else {
                self.missingArtworkKeys.insert(cacheKey)
                return
            }
            self.artworkCache[cacheKey] = data
            self.applyArtworkData(data, forTitle: title)
        }
    }
    
    private func applyArtworkData(_ data: Data, forTitle title: String) {
        guard var current = currentMedia, current.title == title else { return }
        current.artworkData = data
        if let accent = Self.extractDominantColor(from: data) {
            current.accentColorRed = accent.0
            current.accentColorGreen = accent.1
            current.accentColorBlue = accent.2
        }
        self.currentMedia = current
        broadcast()
    }
    
    private nonisolated static func fetchiTunesSongCover(title: String, artist: String, album: String) async -> Data? {
        let cleanTitle = title
            .components(separatedBy: " - ").first?
            .components(separatedBy: " (").first ?? title
        let queries = [
            "\(cleanTitle) \(artist) \(album)".trimmingCharacters(in: .whitespacesAndNewlines),
            "\(cleanTitle) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines),
            cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        
        var seen = Set<String>()
        for query in queries where !query.isEmpty {
            guard seen.insert(query).inserted else { continue }
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let searchURL = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1") else {
                continue
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: searchURL)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   let first = results.first,
                   let artUrl100 = first["artworkUrl100"] as? String {
                    let hiResUrlStr = artUrl100.replacingOccurrences(of: "100x100bb", with: "300x300bb")
                    if let artURL = URL(string: hiResUrlStr) {
                        let (imgData, _) = try await URLSession.shared.data(from: artURL)
                        if !imgData.isEmpty {
                            return imgData
                        }
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }
    
    // MARK: - Automatic Time-Synced LRC Lyrics Lookup (LRCLIB)
    
    private func fetchAndApplyLyrics(title: String, artist: String, album: String) {
        let displayArtist = artist.isEmpty ? "Now Playing" : artist
        let cacheKey = "\(title)|\(displayArtist)"
        if let cached = lyricsCache[cacheKey], !cached.isEmpty {
            applyLyrics(cached, forTitle: title)
            return
        }
        guard !inFlightLyricsKeys.contains(cacheKey), !missingLyricsKeys.contains(cacheKey) else { return }
        inFlightLyricsKeys.insert(cacheKey)

        Task { @MainActor [weak self] in
            let fetched = await Self.fetchLRCLIBLyrics(title: title, artist: artist, album: album)
            guard let self = self else { return }
            self.inFlightLyricsKeys.remove(cacheKey)
            guard let lines = fetched, !lines.isEmpty else {
                self.missingLyricsKeys.insert(cacheKey)
                return
            }

            // Apply original lyrics immediately for zero latency
            self.lyricsCache[cacheKey] = lines
            self.applyLyrics(lines, forTitle: title)

            // Only send lyric text to the translation service when the user has opted in
            if self.isTranslationEnabled {
                self.translateAndApply(lines, cacheKey: cacheKey, forTitle: title)
            }
        }
    }

    private func translateAndApply(_ lines: [LyricLine], cacheKey: String, forTitle title: String) {
        guard !inFlightTranslationKeys.contains(cacheKey) else { return }
        inFlightTranslationKeys.insert(cacheKey)

        Task { @MainActor [weak self] in
            let translated = await Self.translateLyricsToEnglish(lines)
            guard let self = self else { return }
            self.inFlightTranslationKeys.remove(cacheKey)
            self.lyricsCache[cacheKey] = translated
            self.applyLyrics(translated, forTitle: title)
        }
    }
    
    private func applyLyrics(_ lines: [LyricLine], forTitle title: String) {
        guard var current = currentMedia, current.title == title else { return }
        current.lyrics = lines
        self.currentMedia = current
        broadcast()
    }
    
    /// Translates non-English lyric lines into English on-device and attaches them as `translation`.
    private nonisolated static func translateLyricsToEnglish(_ lines: [LyricLine]) async -> [LyricLine] {
        guard !lines.isEmpty else { return lines }
        // If most lines already carry an embedded LRC translation, keep them as-is
        let existingCount = lines.filter { ($0.translation?.isEmpty == false) }.count
        if existingCount > lines.count / 3 {
            return lines
        }
        
        var updated = lines
        // Collect indices of substantive lines to translate
        let translatableIndices = updated.indices.filter { idx in
            let text = updated[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !text.isEmpty && text != "♪ • • •" && updated[idx].translation == nil
        }
        guard !translatableIndices.isEmpty else { return updated }
        
        // On-device Apple Translation (macOS 26+): nothing leaves the Mac. Only uses language packs the
        // user has already installed (System Settings → General → Language & Region → Translation Languages);
        // otherwise lines stay untranslated.
        guard #available(macOS 26.0, *) else { return updated }
        
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(translatableIndices.map { updated[$0].text }.joined(separator: "\n"))
        guard let dominant = recognizer.dominantLanguage,
              dominant != .english,
              dominant != .undetermined else {
            return updated
        }
        let source = Locale.Language(identifier: dominant.rawValue)
        let target = Locale.Language(identifier: "en")
        
        guard await LanguageAvailability().status(from: source, to: target) == .installed else {
            return updated
        }
        
        let session = TranslationSession(installedSource: source, target: target)
        let requests = translatableIndices.map { idx in
            TranslationSession.Request(sourceText: updated[idx].text, clientIdentifier: String(idx))
        }
        
        do {
            for response in try await session.translations(from: requests) {
                guard let id = response.clientIdentifier, let lineIdx = Int(id), updated.indices.contains(lineIdx) else {
                    continue
                }
                let candidate = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                let original = updated[lineIdx].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty && candidate.caseInsensitiveCompare(original) != .orderedSame {
                    updated[lineIdx].translation = candidate
                }
            }
        } catch {
            return lines
        }
        
        return updated
    }
    
    private nonisolated static func fetchLRCLIBLyrics(title: String, artist: String, album: String) async -> [LyricLine]? {
        let cleanTitle = title
            .components(separatedBy: " - ").first?
            .components(separatedBy: " (").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? title
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Try exact match on /api/get if artist is known
        if !cleanTitle.isEmpty && !cleanArtist.isEmpty {
            var components = URLComponents(string: "https://lrclib.net/api/get")
            components?.queryItems = [
                URLQueryItem(name: "track_name", value: cleanTitle),
                URLQueryItem(name: "artist_name", value: cleanArtist)
            ]
            if let url = components?.url,
               let lines = await requestLRCLIBObject(url: url), !lines.isEmpty {
                return lines
            }
        }
        
        // 2. Fallback to /api/search
        let searchQuery = "\(cleanTitle) \(cleanArtist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchQuery.isEmpty,
              let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://lrclib.net/api/search?q=\(encoded)") else {
            return nil
        }
        
        var request = URLRequest(url: searchURL)
        request.setValue("DynamicNotch/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 6.0
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for item in results {
                    if let synced = item["syncedLyrics"] as? String, !synced.isEmpty {
                        let parsed = LyricLine.parseLRC(synced)
                        if !parsed.isEmpty {
                            return parsed
                        }
                    }
                }
                // Plain lyrics fallback spaced across the track
                if let first = results.first,
                   let plain = first["plainLyrics"] as? String, !plain.isEmpty {
                    return parsePlainLyricsFallback(plain)
                }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    private nonisolated static func requestLRCLIBObject(url: URL) async -> [LyricLine]? {
        var request = URLRequest(url: url)
        request.setValue("DynamicNotch/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 5.0
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let synced = json["syncedLyrics"] as? String, !synced.isEmpty {
                    let parsed = LyricLine.parseLRC(synced)
                    if !parsed.isEmpty {
                        return parsed
                    }
                }
                if let plain = json["plainLyrics"] as? String, !plain.isEmpty {
                    return parsePlainLyricsFallback(plain)
                }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    private nonisolated static func parsePlainLyricsFallback(_ plain: String) -> [LyricLine] {
        let rawLines = plain
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return rawLines.enumerated().map { idx, text in
            LyricLine(id: idx, timestamp: Double(idx) * 4.5, text: text)
        }
    }
    
    // MARK: - Bi-Directional Transport Controls
    
    public func togglePlayPause() {
        performHaptic()
        guard var media = currentMedia else {
            startSimulatedPlayback()
            return
        }
        
        let now = Date()
        let currentPos = media.currentPosition(at: now)
        media.playbackPosition = currentPos
        media.updatedAt = now
        media.playbackState = (media.playbackState == .playing) ? .paused : .playing
        self.currentMedia = media
        broadcast()
        
        guard media.source != .simulated else { return }
        performTransport(helperCommand: "toggle", appleScriptCommand: "playpause", for: media)
    }
    
    public func nextTrack() {
        performHaptic()
        guard let media = currentMedia else { return }
        
        if media.source == .simulated {
            simulatedIndex = (simulatedIndex + 1) % simulatedPlaylist.count
            applySimulatedTrack(index: simulatedIndex, state: .playing)
            return
        }
        
        performTransport(helperCommand: "next", appleScriptCommand: "next track", for: media)
    }
    
    public func previousTrack() {
        performHaptic()
        guard let media = currentMedia else { return }
        
        if media.source == .simulated {
            if media.currentPosition() > 4.0 {
                seek(to: 0.0)
            } else {
                simulatedIndex = (simulatedIndex - 1 + simulatedPlaylist.count) % simulatedPlaylist.count
                applySimulatedTrack(index: simulatedIndex, state: .playing)
            }
            return
        }
        
        performTransport(helperCommand: "prev", appleScriptCommand: "previous track", for: media)
    }
    
    public func seek(to position: TimeInterval) {
        guard var media = currentMedia else { return }
        let clamped = max(0.0, min(position, media.duration))
        media.playbackPosition = clamped
        media.updatedAt = Date()
        self.currentMedia = media
        broadcast()
        
        guard media.source != .simulated else { return }
        performTransport(helperCommand: "seek:\(clamped)", appleScriptCommand: "set player position to \(String(format: "%.2f", clamped))", for: media)
    }
    
    public func activateSourceApp() {
        performHaptic()
        guard let media = currentMedia else { return }
        let bundleId = media.source.bundleIdentifier
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        }
    }
    
    // MARK: - Simulated Playback for Instant Testing & Demo
    
    public func startSimulatedPlayback() {
        performHaptic()
        applySimulatedTrack(index: simulatedIndex, state: .playing)
    }
    
    public func stopSimulatedPlayback() {
        performHaptic()
        self.currentMedia = nil
        broadcast()
        sendHelperCommand("refresh")
    }
    
    private func applySimulatedTrack(index: Int, state: MediaItem.PlaybackState) {
        let track = simulatedPlaylist[index % simulatedPlaylist.count]
        let cacheKey = "\(track.title)|\(track.artist)"
        let artworkData = artworkCache[cacheKey] ?? Self.generateGradientArtwork(
            colors: track.colors,
            symbolName: track.symbol
        )
        // Original placeholder lines written for this demo (not real song lyrics), bilingual so the
        // translation ribbon can be previewed without network access.
        let defaultLyrics: [LyricLine] = [
            LyricLine(id: 0, timestamp: 0.0, text: "ノッチの向こうで光がゆれる", translation: "Beyond the notch, a light is swaying"),
            LyricLine(id: 1, timestamp: 4.5, text: "通知の波が静かに届く", translation: "A wave of notifications quietly arrives"),
            LyricLine(id: 2, timestamp: 12.0, text: "ビルドはまだ終わらない", translation: "The build still isn't finished"),
            LyricLine(id: 3, timestamp: 15.0, text: "それでも画面は輝いている", translation: "Even so, the screen keeps shining"),
            LyricLine(id: 4, timestamp: 19.5, text: "小さな島が夜に浮かぶ", translation: "A tiny island floats in the night"),
            LyricLine(id: 5, timestamp: 24.0, text: "メニューバーの上で待っている", translation: "Waiting just above the menu bar"),
            LyricLine(id: 6, timestamp: 29.0, text: "テストが緑に変わる瞬間", translation: "The moment the tests turn green"),
            LyricLine(id: 7, timestamp: 32.5, text: "スプリングのように跳ねる心", translation: "A heart that bounces like a spring"),
            LyricLine(id: 8, timestamp: 36.5, text: "黒い曲線に色がにじむ", translation: "Color bleeds into the black curve"),
            LyricLine(id: 9, timestamp: 41.0, text: "未読の数を数えながら", translation: "While counting the unread ones"),
            LyricLine(id: 10, timestamp: 45.5, text: "コミットひとつ、またひとつ", translation: "One commit, then another"),
            LyricLine(id: 11, timestamp: 48.5, text: "ターミナルが静かに歌う", translation: "The terminal quietly sings"),
            LyricLine(id: 12, timestamp: 53.0, text: "すべてのタスクが終わったら", translation: "Once every task is done"),
            LyricLine(id: 13, timestamp: 57.5, text: "明日のためにノッチを閉じよう", translation: "Let's close the notch for tomorrow")
        ]
        let item = MediaItem(
            id: "simulated-\(index)",
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            playbackPosition: 0.5,
            playbackState: state,
            source: .simulated,
            artworkData: artworkData,
            lyrics: lyricsCache[cacheKey] ?? defaultLyrics,
            accentColor: track.accent,
            updatedAt: Date()
        )
        self.currentMedia = item
        broadcast()
        fetchAndApplySongCover(title: track.title, artist: track.artist, album: track.album, source: .simulated)
        fetchAndApplyLyrics(title: track.title, artist: track.artist, album: track.album)
    }
    
    private func performHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    
    // MARK: - Background AppleScript & Artwork Helpers
    
    private nonisolated static func fetchSpotifyArtwork() async -> Data? {
        let urlString = await Task.detached {
            runAppleScript("tell application \"Spotify\" to get artwork url of current track")
        }.value
        
        guard let urlStr = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlStr) else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        } catch {
            return nil
        }
    }
    
    private nonisolated static func runAppleScript(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error) else {
            return nil
        }
        return result.stringValue
    }
    
    /// Samples the average vibrant color from artwork image data for ambient glow lighting.
    public nonisolated static func extractDominantColor(from data: Data) -> (Double, Double, Double)? {
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let width = 8
        let height = 8
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var totalR: Double = 0
        var totalG: Double = 0
        var totalB: Double = 0
        var count: Double = 0
        
        for i in stride(from: 0, to: pixelData.count, by: 4) {
            let r = Double(pixelData[i]) / 255.0
            let g = Double(pixelData[i + 1]) / 255.0
            let b = Double(pixelData[i + 2]) / 255.0
            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            let weight = 0.4 + (maxC - minC) * 1.6
            totalR += r * weight
            totalG += g * weight
            totalB += b * weight
            count += weight
        }
        
        guard count > 0 else { return nil }
        let r = min(1.0, max(0.28, totalR / count * 1.25))
        let g = min(1.0, max(0.28, totalG / count * 1.25))
        let b = min(1.0, max(0.28, totalB / count * 1.25))
        return (r, g, b)
    }
    
    /// Generates a rich procedural album cover image for simulated tracks.
    private static func generateGradientArtwork(colors: (NSColor, NSColor), symbolName: String) -> Data? {
        let size = NSSize(width: 120, height: 120)
        let image = NSImage(size: size)
        image.lockFocus()
        
        let rect = NSRect(origin: .zero, size: size)
        if let gradient = NSGradient(starting: colors.0, ending: colors.1) {
            gradient.draw(in: rect, angle: -45.0)
        }
        
        let config = NSImage.SymbolConfiguration(pointSize: 44, weight: .bold)
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let symSize = symbol.size
            let symRect = NSRect(
                x: (size.width - symSize.width) / 2.0,
                y: (size.height - symSize.height) / 2.0,
                width: symSize.width,
                height: symSize.height
            )
            NSColor.white.withAlphaComponent(0.92).set()
            symbol.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 0.92)
        }
        
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
