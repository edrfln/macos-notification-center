import AppKit
import Foundation
import SwiftUI

/// A single time-synchronized lyric line parsed from LRC format `[mm:ss.xx]`,
/// optionally paired with an English translation line.
public struct LyricLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let timestamp: TimeInterval
    public let text: String
    public var translation: String?
    
    public init(id: Int, timestamp: TimeInterval, text: String, translation: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.translation = translation
    }
    
    /// Parses a standard LRC string (`[00:14.62] Lyric text`) into sorted `LyricLine` items.
    /// Automatically pairs bilingual duplicate-timestamp lines or inline ` / ` translations.
    public static func parseLRC(_ lrcString: String) -> [LyricLine] {
        var rawEntries: [(TimeInterval, String)] = []
        let lines = lrcString.components(separatedBy: .newlines)
        
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["),
                  let closeBracket = trimmed.firstIndex(of: "]") else {
                continue
            }
            let timeToken = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracket])
            let lyricText = String(trimmed[trimmed.index(after: closeBracket)...])
                .trimmingCharacters(in: .whitespaces)
            
            let parts = timeToken.components(separatedBy: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1].replacingOccurrences(of: ",", with: ".")) else {
                continue
            }
            
            let timestamp = minutes * 60.0 + seconds
            if !lyricText.isEmpty {
                rawEntries.append((timestamp, lyricText))
            } else {
                rawEntries.append((timestamp, "♪ • • •"))
            }
        }
        
        rawEntries.sort { $0.0 < $1.0 }
        
        // Merge duplicate timestamps (bilingual LRC files) or inline " / " translations
        var merged: [(timestamp: TimeInterval, text: String, translation: String?)] = []
        for (ts, text) in rawEntries {
            if let lastIdx = merged.indices.last,
               abs(merged[lastIdx].timestamp - ts) < 0.08,
               merged[lastIdx].text != "♪ • • •",
               text != "♪ • • •",
               merged[lastIdx].translation == nil {
                if merged[lastIdx].text.caseInsensitiveCompare(text) != .orderedSame {
                    merged[lastIdx].translation = text
                }
                continue
            }
            
            // Check for inline "Original / Translation" separator
            let slashParts = text.components(separatedBy: " / ")
            if slashParts.count == 2,
               !slashParts[0].trimmingCharacters(in: .whitespaces).isEmpty,
               !slashParts[1].trimmingCharacters(in: .whitespaces).isEmpty {
                let orig = slashParts[0].trimmingCharacters(in: .whitespaces)
                let trans = slashParts[1].trimmingCharacters(in: .whitespaces)
                merged.append((ts, orig, orig.caseInsensitiveCompare(trans) == .orderedSame ? nil : trans))
            } else {
                merged.append((ts, text, nil))
            }
        }
        
        return merged.enumerated().map { index, item in
            LyricLine(id: index, timestamp: item.timestamp, text: item.text, translation: item.translation)
        }
    }
}

/// Represents the current Now Playing track, artwork, and time-synced lyrics.
public struct MediaItem: Identifiable, Equatable, Sendable {
    public enum PlaybackState: String, Equatable, Sendable, Codable {
        case playing
        case paused
        case stopped
    }
    
    public enum SourceApp: String, Equatable, Sendable, Codable {
        case appleMusic = "Music"
        case spotify = "Spotify"
        case simulated = "Now Playing"
        
        public var bundleIdentifier: String {
            switch self {
            case .appleMusic: return "com.apple.Music"
            case .spotify: return "com.spotify.client"
            case .simulated: return "com.apple.Music"
            }
        }
        
        public var iconSystemName: String {
            switch self {
            case .appleMusic: return "music.note"
            case .spotify: return "waveform.circle.fill"
            case .simulated: return "music.quarternote.3"
            }
        }
        
        public var brandColor: Color {
            switch self {
            case .appleMusic: return Color(red: 0.98, green: 0.23, blue: 0.36)
            case .spotify: return Color(red: 0.12, green: 0.84, blue: 0.38)
            case .simulated: return Color(red: 0.62, green: 0.42, blue: 1.0)
            }
        }
    }
    
    public let id: String
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var playbackPosition: TimeInterval
    public var playbackState: PlaybackState
    public var source: SourceApp
    public var artworkData: Data?
    public var lyrics: [LyricLine]
    public var accentColorRed: Double
    public var accentColorGreen: Double
    public var accentColorBlue: Double
    public var updatedAt: Date
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        artist: String,
        album: String = "",
        duration: TimeInterval = 180.0,
        playbackPosition: TimeInterval = 0.0,
        playbackState: PlaybackState = .playing,
        source: SourceApp = .appleMusic,
        artworkData: Data? = nil,
        lyrics: [LyricLine] = [],
        accentColor: (Double, Double, Double)? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = max(1.0, duration)
        self.playbackPosition = max(0.0, min(playbackPosition, max(1.0, duration)))
        self.playbackState = playbackState
        self.source = source
        self.artworkData = artworkData
        self.lyrics = lyrics
        if let accent = accentColor {
            self.accentColorRed = accent.0
            self.accentColorGreen = accent.1
            self.accentColorBlue = accent.2
        } else {
            switch source {
            case .appleMusic:
                self.accentColorRed = 0.98
                self.accentColorGreen = 0.23
                self.accentColorBlue = 0.36
            case .spotify:
                self.accentColorRed = 0.12
                self.accentColorGreen = 0.84
                self.accentColorBlue = 0.38
            case .simulated:
                self.accentColorRed = 0.58
                self.accentColorGreen = 0.38
                self.accentColorBlue = 0.98
            }
        }
        self.updatedAt = updatedAt
    }
    
    public var accentColor: Color {
        Color(red: accentColorRed, green: accentColorGreen, blue: accentColorBlue)
    }
    
    /// Computes the live interpolated playback position at a given reference date.
    public func currentPosition(at date: Date = Date()) -> TimeInterval {
        guard playbackState == .playing else {
            return min(playbackPosition, duration)
        }
        let elapsed = max(0.0, date.timeIntervalSince(updatedAt))
        return min(duration, playbackPosition + elapsed)
    }
    
    /// Normalized playback progress (0.0 ... 1.0) at a given reference date.
    public func progress(at date: Date = Date()) -> Double {
        guard duration > 0 else { return 0.0 }
        return min(1.0, max(0.0, currentPosition(at: date) / duration))
    }
    
    /// Returns the index of the active time-synced lyric line at a given reference date.
    public func activeLyricIndex(at date: Date = Date()) -> Int? {
        guard !lyrics.isEmpty else { return nil }
        let pos = currentPosition(at: date)
        var matchedIndex: Int? = nil
        for (idx, line) in lyrics.enumerated() {
            if line.timestamp <= pos + 0.15 {
                matchedIndex = idx
            } else {
                break
            }
        }
        return matchedIndex ?? 0
    }
    
    /// Returns the currently active lyric line at a given reference date.
    public func activeLyricLine(at date: Date = Date()) -> LyricLine? {
        guard let idx = activeLyricIndex(at: date), lyrics.indices.contains(idx) else {
            return nil
        }
        return lyrics[idx]
    }
    
    /// Whether any lyric line in this track carries an English translation.
    public var hasTranslations: Bool {
        lyrics.contains { ($0.translation?.isEmpty == false) }
    }
    
    /// Formatted elapsed timestamp (e.g., "1:24") at a given reference date.
    public func formattedElapsed(at date: Date = Date()) -> String {
        Self.formatSeconds(currentPosition(at: date))
    }
    
    /// Formatted remaining timestamp (e.g., "-2:11") at a given reference date.
    public func formattedRemaining(at date: Date = Date()) -> String {
        let remaining = max(0.0, duration - currentPosition(at: date))
        return "-" + Self.formatSeconds(remaining)
    }
    
    public static func formatSeconds(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
