# Dynamic Notch

A native macOS Dynamic Island utility built with Swift, AppKit, and SwiftUI. It sits over your MacBook display notch (and top-center on external displays) to present incoming alerts and unread notifications with fluid spring animations.

For the detailed 6-phase engineering roadmap and checklist, see [PLAN.md](PLAN.md).

---

## Features

- **Hardware Notch & External Display Support:** Detects the physical MacBook camera cutout and creates flanking ears for status indicators; automatically renders a top-center island on external monitors (e.g. 1080p, 1440p, 4K).
- **Multi-Monitor Mirroring:** Spawns synchronized islands across all connected displays simultaneously.
- **Fluid Spring Physics:** Continuous corner radius capsules (`RoundedRectangle(..., style: .continuous)`) with Apple-tuned springs (`response: 0.38, dampingFraction: 0.78`).
- **Interactive Notification Tray:** Hovering expands the pill into a scrollable tray with unread badges, timestamps, and hover action triggers ("Mark Read", "Dismiss", "Clear All").
- **FIFO Alert Queue:** Gracefully presents rapid bursts of incoming notifications one by one without dropping alerts.
- **CLI & Script Dispatcher:** Post alerts directly from Terminal, bash scripts, or CI build hooks via `DynamicNotch <title> [subtitle] [appName] [category]`.
- **Launch at Login:** Uses modern macOS Ventura+ `SMAppService.mainApp` API.
- **Spaces & Fullscreen Auxiliary:** Stays anchored across virtual desktops, floating seamlessly over full-screen apps and Mission Control.
- **Outside-Click Dismissal:** Clicking outside the expanded tray smoothly collapses it back to resting idle.
- **Now Playing:** Album art and a live visualizer flank the notch for Apple Music, Spotify, and other players. Click to open a full player with scrubbing, transport controls, and time-synced lyrics from [LRCLIB](https://lrclib.net) (track title and artist are sent to LRCLIB and the iTunes Search API for lyrics and artwork).
- **On-Device Lyric Translation:** Optional English translations of non-English lyrics using Apple's Translation framework (macOS 26+). Nothing leaves your Mac. Download the source language under *System Settings → General → Language & Region → Translation Languages*.
- **Agent & Shell Integrations:** Live activities for long-running zsh commands and Claude Code sessions (see [Integrations](#integrations-optional)).

---

## Installation

Requires macOS 14 Sonoma or later (Apple Silicon or Intel).

### Option A: Download (recommended)

1. Download the latest **DynamicNotch-x.y.z.zip** from [Releases](https://github.com/edrfln/macos-notification-center/releases/latest), unzip it, and move **DynamicNotch.app** to **Applications**.
2. Open it. macOS shows *"Apple could not verify DynamicNotch is free of malware"*. Click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to DynamicNotch, and confirm.

You only need to do this once per download. Or skip steps 2–3 from Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/DynamicNotch.app && open /Applications/DynamicNotch.app
```

> **Why the warning?** Dynamic Notch is free and open source, and isn't notarized through Apple's paid Developer Program. The build is produced by the [Release workflow](.github/workflows/release.yml) straight from this repository's source. Each zip has a `.sha256` checksum next to it on the Releases page if you want to verify your download.

### Option B: Build from source

Requires Xcode 26 or later, or the matching Command Line Tools (`xcode-select --install`).

```bash
gh repo clone edrfln/macos-notification-center
cd macos-notification-center

./build_app.sh                 # → ./DynamicNotch.app (UNIVERSAL=1 for an Apple Silicon + Intel build)
cp -R DynamicNotch.app /Applications/
open /Applications/DynamicNotch.app
```

### After installing

Dynamic Notch runs as a menu bar agent: there is no Dock icon. Look for the capsule icon in the menu bar.

> **Now Playing for every app:** Apple Music and Spotify work out of the box. Other players (browsers, Podcasts…) go through a small helper that needs the Xcode Command Line Tools: `xcode-select --install`.

### Grant permissions

| Permission | When it's asked | Why |
| :--- | :--- | :--- |
| **Accessibility** | First launch (System Settings opens automatically) | Captures real macOS notifications (Slack, Messages, Mail…) into the notch. Enable **DynamicNotch** under *Privacy & Security → Accessibility*, then relaunch the app. |
| **Automation** (Music / Spotify) | First time you use the media controls | Play/pause, skip, and artwork fallback when the Now Playing helper is unavailable. |

The app works without these permissions: mock alerts, CLI alerts and live activities still appear, but real system notifications don't.

> **If system notifications stop showing up after an update or rebuild**, macOS may be treating it as a new app. Remove **DynamicNotch** from the Accessibility list with the **–** button, add it again, and relaunch. Releases signed with the project's certificate keep the permission across updates. Local builds don't, unless you sign them too (see [Signing](#signing-optional)).

### Launch at login (optional)

Menu bar icon → **Launch at Login**.

### Add the `notch` command (optional)

Every CLI example below works with the full binary path. A short alias is easier:

```bash
mkdir -p ~/.local/bin
ln -sf /Applications/DynamicNotch.app/Contents/MacOS/DynamicNotch ~/.local/bin/notch
# Make sure ~/.local/bin is on your PATH (add to ~/.zshrc if needed):
# export PATH="$HOME/.local/bin:$PATH"

notch alert "Hello" "Dynamic Notch is installed" "Terminal" "system"
```

The shell and Claude Code integrations below look for `~/.local/bin/notch` by default. Set `DYNAMIC_NOTCH_BIN` to use a different path.

### Updating

**Downloaded:** quit Dynamic Notch, replace `/Applications/DynamicNotch.app` with the new release, and open it again (with *Open Anyway* the first time).

**From source:**

```bash
git pull
./build_app.sh
pkill -x DynamicNotch   # quit the running copy
cp -R DynamicNotch.app /Applications/ && open /Applications/DynamicNotch.app
```

Re-grant Accessibility if needed (see [Grant permissions](#grant-permissions)).

### Uninstalling

1. Quit from the menu bar, and turn off **Launch at Login** first if you enabled it.
2. Delete the app: `rm -rf /Applications/DynamicNotch.app`
3. Remove the alias: `rm ~/.local/bin/notch`
4. Remove **DynamicNotch** from *Privacy & Security → Accessibility*.
5. Remove any integration lines you added (see below) from `~/.zshrc` and `~/.claude/settings.json`.

### Developing

```bash
swift run DynamicNotch   # run directly from source without bundling
```

### Signing (optional)

Without an Apple Developer ID, builds are ad-hoc signed, so macOS asks for Accessibility again after every rebuild. A free self-signed certificate gives every build the same identity. It doesn't remove the *Open Anyway* step for downloads.

```bash
tools/create-signing-cert.sh --login    # create once, import into your login keychain
CODESIGN_IDENTITY="Dynamic Notch Self-Signed" ./build_app.sh

tools/create-signing-cert.sh --upload   # maintainers: store it as GitHub secrets so releases use it too
```

The certificate lives in `~/.dynamicnotch-signing`. Back it up: a new certificate means users re-grant permissions once.

### Publishing a release

```bash
git tag v1.0.0 && git push origin v1.0.0
```

The [Release workflow](.github/workflows/release.yml) builds a universal app, zips it with a SHA-256 checksum, and publishes it on the Releases page. Run it manually from the Actions tab to get a test build without publishing.

---

## Integrations (optional)

### Long-running terminal commands (zsh)

Any command that runs longer than 3 seconds shows a live activity with a timer, then a success or failure alert when it exits. Add to `~/.zshrc`:

```bash
source /Applications/DynamicNotch.app/Contents/Resources/scripts/dynamic-notch-zsh-hook.sh
# export NOTCH_THRESHOLD_SECONDS=5   # optional: change the 3s threshold
```

Editors, pagers, REPLs and `ssh` are skipped automatically.

### Claude Code agent activity

Shows Claude's progress in the notch in every Claude Code session on this Mac: terminal, VS Code/JetBrains extensions, and the desktop app. You'll see "Thinking…", the current step ("Editing Foo.swift", "Running: tests"), permission requests, and a finished alert. Requires `jq` (preinstalled on macOS 15+, or `brew install jq`).

Merge these entries into the `hooks` object of `~/.claude/settings.json`. The scripts ship inside the app, so the paths work for both downloaded and source installs. Keep any hooks you already have; add these alongside them in the same event arrays.

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "/Applications/DynamicNotch.app/Contents/Resources/scripts/claude-notch-hook.sh", "args": ["UserPromptSubmit"], "timeout": 5 }] }
    ],
    "PreToolUse": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "/Applications/DynamicNotch.app/Contents/Resources/scripts/claude-notch-hook.sh", "args": ["PreToolUse"], "timeout": 5 }] }
    ],
    "Notification": [
      { "hooks": [{ "type": "command", "command": "/Applications/DynamicNotch.app/Contents/Resources/scripts/claude-notch-hook.sh", "args": ["Notification"], "timeout": 5 }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "/Applications/DynamicNotch.app/Contents/Resources/scripts/claude-notch-hook.sh", "args": ["Stop"], "timeout": 5 }] }
    ],
    "SessionEnd": [
      { "hooks": [{ "type": "command", "command": "/Applications/DynamicNotch.app/Contents/Resources/scripts/claude-notch-hook.sh", "args": ["SessionEnd"], "timeout": 5 }] }
    ]
  }
}
```

The pill only appears if Claude is still working after 4 seconds. Change that with `NOTCH_CLAUDE_DELAY_SECONDS`. Use `/hooks` inside Claude Code to review or disable the hooks.

---

## CLI Task Runner & Live Activities

Dynamic Notch includes a live progress system ("Live Activities") for tracking terminal commands, background scripts, or AI agent executions right inside the notch and external islands:

### 1. Universal Command Runner (`DynamicNotch run`)
Wrap any command or script. Dynamic Notch displays a live animated spinner and elapsed timer in the notch ears, streams stdout/stderr to your terminal, and automatically raises a success (green checkmark) or failure (red) alert banner when finished:

```bash
# Wrap a build command
./DynamicNotch.app/Contents/MacOS/DynamicNotch run "Building Project" -- swift build -c release

# Wrap long tests or npm scripts
./DynamicNotch.app/Contents/MacOS/DynamicNotch run "Running Unit Tests" -- npm test

# Wrap downloads or background processes
./DynamicNotch.app/Contents/MacOS/DynamicNotch run "Downloading Assets" -- curl -O https://example.com/data.tar.gz
```

### 2. Granular Activity Controls (`DynamicNotch activity`)
For multi-step workflows, scripts, or AI agents that report progress step by step:

```bash
# Start a task (displays spinning icon and timer in notch)
./DynamicNotch.app/Contents/MacOS/DynamicNotch activity start "task1" "AI Working" "Analyzing AST..." "sparkles"

# Update status or progress percentage (0.0 - 1.0)
./DynamicNotch.app/Contents/MacOS/DynamicNotch activity update "task1" "Compiling modules..." 0.65

# Complete task (triggers green completion alert banner with elapsed time)
./DynamicNotch.app/Contents/MacOS/DynamicNotch activity complete "task1" "Task Completed" "All 18 modules verified"

# Or flag failure (triggers red error alert banner)
./DynamicNotch.app/Contents/MacOS/DynamicNotch activity fail "task1" "Compilation error in main.swift"
```

### 3. Instant Alert Banner Dispatch
```bash
# Post an alert directly to the notch
./DynamicNotch.app/Contents/MacOS/DynamicNotch alert "Build Succeeded" "All tests passed in 1.4s" "Xcode" "codeReview"

# Quick syntax (backward compatible)
./DynamicNotch.app/Contents/MacOS/DynamicNotch "Engineering Sync" "Can you check the pull request?" "Slack" "message"
```

Available categories: `message`, `codeReview`, `calendar`, `email`, `system`, `reminder`, `activitySuccess`, `activityFailure`.

---

## Menu Bar Controls & Keyboard Shortcuts

Click the capsule icon in your macOS menu bar to access controls:

| Action | Shortcut | Description |
| :--- | :--- | :--- |
| **Simulate Slack** | `Cmd + 1` | Triggers a simulated Slack message alert |
| **Simulate GitHub** | `Cmd + 2` | Triggers a simulated GitHub pull request alert |
| **Simulate Calendar** | `Cmd + 3` | Triggers a simulated calendar meeting alert |
| **Simulate Live Task** | `Cmd + 4` | Triggers a 5-second animated CLI progress activity |
| **Simulate Now Playing** | `Cmd + 5` | Starts a demo track in the media player |
| **Simulate Queue Burst** | `Cmd + B` | Enqueues 3 rapid notifications to demonstrate FIFO queueing |
| **Toggle Media Player** | `Cmd + P` | Opens or closes the expanded Now Playing player |
| **Lyric Translation** | `Cmd + E` | Shows English translations under non-English lyrics |
| **Toggle Tray** | `Cmd + T` | Expands or collapses the notification tray |
| **Collapse to Idle** | `Cmd + I` | Snaps all islands back to resting idle state |
| **Clear All** | `Cmd + K` | Clears all unread notifications from the store |
| **Preferences** | `Cmd + ,` | Opens the native Preferences window |
| **Quit** | `Cmd + Q` | Terminates Dynamic Notch |

---

## Project Architecture

```
DynamicNotch/
├── Package.swift                                      // SPM manifest (macOS 14+)
├── build_app.sh                                       // Release bundler script
├── PLAN.md                                            // Architecture plan & implementation checklist
├── README.md                                          // This documentation guide
├── LICENSE                                            // MIT
├── scripts/
│   ├── dynamic-notch-zsh-hook.sh                      // zsh preexec/precmd hook for long-running commands
│   └── claude-notch-hook.sh                           // Claude Code hook bridge (prompt → tools → finish)
└── Sources/
    └── DynamicNotch/
        ├── App/
        │   ├── AppDelegate.swift                      // Stealth agent lifecycle & status item
        │   └── DynamicNotchLauncher.swift             // @main entrypoint, CLI runner & dispatcher
        ├── Core/
        │   ├── NotchPanel.swift                       // Non-activating NSPanel with Spaces behaviors
        │   ├── ScreenGeometryManager.swift            // Display discovery & hardware notch cutout math
        │   ├── TrackingHostingView.swift              // NSTrackingArea & pass-through hit testing
        │   ├── NotchWindowController.swift            // Per-display frame coordination & outside-click monitor
        │   └── LaunchAtLoginManager.swift             // SMAppService.mainApp login registration
        ├── Models/
        │   ├── NotchState.swift                       // State machine (.idle, .hover, .alert, .tray, .liveActivity)
        │   ├── ScreenGeometry.swift                   // Geometry model & corner radii
        │   ├── NotchViewModel.swift                   // Observable presentation state coordinator
        │   ├── NotificationItem.swift                 // Strongly typed notification model
        │   ├── LiveActivityItem.swift                 // Live task progress, duration, and status model
        │   └── MediaItem.swift                        // Now Playing track, artwork, and time-synced LRC lyrics
        ├── Pipeline/
        │   ├── NotificationManager.swift              // Multi-window reactive store & FIFO alert queue
        │   ├── LiveActivityManager.swift              // Active task lifecycle coordinator & alert bridge
        │   ├── MockNotificationEmitter.swift          // Presets (Slack, GitHub, Calendar) & burst tester
        │   ├── LocalNotificationServer.swift          // DistributedNotificationCenter IPC for CLI triggers
        │   ├── SystemNotificationObserver.swift       // Real macOS Accessibility AXObserver notification intake
        │   └── MediaPlaybackManager.swift             // Now Playing intake, transport controls, artwork & lyrics lookup
        └── Views/
            ├── DynamicNotchRootView.swift             // Fluid visual capsule shell & interactive tray
            ├── GeometryDiagnosticsView.swift          // Live screen geometry HUD
            ├── PreferencesView.swift                  // Tabbed Settings interface
            ├── PreferencesWindowController.swift      // Standalone Settings window controller
            └── Components/
                ├── NotchDesignSystem.swift            // Shared tokens, motion, haptics & reusable controls
                ├── AlertBannerView.swift              // Incoming alert pill stretch layout
                ├── LiveActivityPillView.swift         // Progress ring, timer, and task HUD
                ├── MediaPlayerView.swift              // Compact Now Playing pill & expanded player with lyrics
                └── TrayNotificationRow.swift          // Swipeable notification card with actions
```

---

## License

MIT. See [LICENSE](LICENSE).
