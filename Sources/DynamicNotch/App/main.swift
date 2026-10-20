import AppKit
import Foundation

nonisolated(unsafe) private var activeActivityIdForSignal: String?

@main
enum DynamicNotchLauncher {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        
        if args.count > 1 {
            let firstArg = args[1]
            
            if firstArg == "run" {
                handleRunCommand(args: args)
                return
            } else if firstArg == "activity" {
                handleActivityCommand(args: args)
                return
            } else if firstArg == "alert" {
                handleAlertCommand(args: Array(args.dropFirst()))
                return
            } else if firstArg == "--help" || firstArg == "-h" {
                printHelp()
                return
            } else {
                // Backward-compatible default: DynamicNotch <title> [subtitle] [appName] [category]
                handleAlertCommand(args: args)
                return
            }
        }
        
        // Default agent mode: launch AppKit NSApplication with delegate
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
    
    // MARK: - CLI Task Runner (`DynamicNotch run <title> -- <command...>`)
    
    @MainActor
    private static func handleRunCommand(args: [String]) {
        guard args.count > 2 else {
            print("Usage: DynamicNotch run <task-title> [--] <command...>")
            print("Example: DynamicNotch run \"Compiling Project\" -- swift build")
            exit(1)
        }
        
        var title = args[2]
        var commandTokens: [String] = []
        
        if let dashDashIndex = args.firstIndex(of: "--") {
            commandTokens = Array(args[(dashDashIndex + 1)...])
            if dashDashIndex > 2 {
                title = args[2..<dashDashIndex].joined(separator: " ")
            }
        } else if args.count > 3 {
            title = args[2]
            commandTokens = Array(args[3...])
        } else {
            title = args[2]
            commandTokens = [args[2]]
        }
        
        guard !commandTokens.isEmpty else {
            print("Error: No command specified to execute.")
            exit(1)
        }
        
        let activityId = UUID().uuidString
        let commandString = commandTokens.joined(separator: " ")
        let startTime = Date()
        
        print("▶ Dynamic Notch Activity Started: [\(title)]")
        print("  Executing: \(commandString)")
        
        LocalNotificationServer.postActivityStart(
            id: activityId,
            title: title,
            subtitle: commandString,
            icon: "terminal.fill"
        )
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = commandTokens
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.environment = ProcessInfo.processInfo.environment
        
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        
        activeActivityIdForSignal = activityId
        signal(SIGINT) { _ in
            if let id = activeActivityIdForSignal {
                LocalNotificationServer.postActivityFail(id: id, error: "Cancelled (SIGINT)")
            }
            exit(130)
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let status = process.terminationStatus
            let elapsedSecs = Int(Date().timeIntervalSince(startTime))
            let mins = elapsedSecs / 60
            let secs = elapsedSecs % 60
            let elapsedStr = String(format: "%d:%02d", mins, secs)
            
            if status == 0 {
                print("✔ Dynamic Notch Task Succeeded: [\(title)] (finished in \(elapsedStr))")
                LocalNotificationServer.postActivityComplete(
                    id: activityId,
                    title: "Completed: \(title)",
                    subtitle: "Finished in \(elapsedStr)"
                )
            } else {
                print("✖ Dynamic Notch Task Failed: [\(title)] (exit code \(status))")
                LocalNotificationServer.postActivityFail(
                    id: activityId,
                    error: "Failed with exit code \(status)"
                )
            }
            exit(status)
        } catch {
            print("✖ Failed to launch command: \(error.localizedDescription)")
            LocalNotificationServer.postActivityFail(
                id: activityId,
                error: error.localizedDescription
            )
            exit(1)
        }
    }
    
    // MARK: - Granular Live Activity Controls (`DynamicNotch activity <start|update|complete|fail>`)
    
    @MainActor
    private static func handleActivityCommand(args: [String]) {
        guard args.count > 2 else {
            print("Usage: DynamicNotch activity <start|update|complete|fail> [options...]")
            exit(1)
        }
        
        let subcommand = args[2]
        switch subcommand {
        case "delay-start":
            // DynamicNotch activity delay-start <id> <delaySeconds> <pendingFile> <activeFile> <title> [subtitle] [icon]
            guard args.count > 7 else {
                print("Usage: DynamicNotch activity delay-start <id> <delaySeconds> <pendingFile> <activeFile> <title> [subtitle] [icon]")
                exit(1)
            }
            let id = args[3]
            let delaySeconds = Double(args[4]) ?? 3.0
            let pendingFile = args[5]
            let activeFile = args[6]
            let title = args[7]
            let subtitle = args.count > 8 ? args[8] : "Running in terminal..."
            let icon = args.count > 9 ? args[9] : "terminal.fill"
            
            Thread.sleep(forTimeInterval: delaySeconds)
            
            if FileManager.default.fileExists(atPath: pendingFile) {
                FileManager.default.createFile(atPath: activeFile, contents: nil)
                LocalNotificationServer.postActivityStart(
                    id: id,
                    title: title,
                    subtitle: subtitle,
                    icon: icon
                )
            }
            return
            
        case "start":
            guard args.count > 4 else {
                print("Usage: DynamicNotch activity start <id> <title> [subtitle] [icon] [progress]")
                exit(1)
            }
            let id = args[3]
            let title = args[4]
            let subtitle = args.count > 5 ? args[5] : ""
            let icon = args.count > 6 ? args[6] : "gearshape.arrow.triangle.2.circlepath"
            let progress = args.count > 7 ? Double(args[7]) : nil
            
            LocalNotificationServer.postActivityStart(
                id: id,
                title: title,
                subtitle: subtitle,
                icon: icon,
                progress: progress
            )
            print("🚀 Started live activity [\(id)]: \(title)")
            
        case "update":
            guard args.count > 3 else {
                print("Usage: DynamicNotch activity update <id> [subtitle] [progress]")
                exit(1)
            }
            let id = args[3]
            let subtitle = args.count > 4 ? args[4] : nil
            let progress = args.count > 5 ? Double(args[5]) : nil
            
            LocalNotificationServer.postActivityUpdate(
                id: id,
                subtitle: subtitle,
                progress: progress
            )
            print("🔄 Updated live activity [\(id)]")
            
        case "complete", "stop":
            let id = args.count > 3 ? args[3] : ""
            let title = args.count > 4 ? args[4] : nil
            let subtitle = args.count > 5 ? args[5] : nil
            
            LocalNotificationServer.postActivityComplete(
                id: id,
                title: title,
                subtitle: subtitle
            )
            print("✅ Completed live activity")
            
        case "fail":
            let id = args.count > 3 ? args[3] : ""
            let error = args.count > 4 ? args[4] : "Command failed"
            
            LocalNotificationServer.postActivityFail(
                id: id,
                error: error
            )
            print("❌ Failed live activity")
            
        default:
            print("Unknown activity subcommand: \(subcommand)")
            print("Available: start, update, complete, fail")
            exit(1)
        }
    }
    
    // MARK: - Alert Banner Dispatch
    
    @MainActor
    private static func handleAlertCommand(args: [String]) {
        let title = args.count > 1 ? args[1] : "Alert"
        let subtitle = args.count > 2 ? args[2] : ""
        let appName = args.count > 3 ? args[3] : "Terminal"
        let category = args.count > 4 ? args[4] : "message"
        
        LocalNotificationServer.postFromCLI(
            title: title,
            subtitle: subtitle,
            appName: appName,
            category: category
        )
        print("🚀 Dispatched alert to Dynamic Notch:")
        print("   App:      \(appName)")
        print("   Title:    \(title)")
        if !subtitle.isEmpty {
            print("   Subtitle: \(subtitle)")
        }
    }
    
    private static func printHelp() {
        print("""
        Dynamic Notch CLI - Dynamic Island & Notification Center for macOS

        USAGE:
          DynamicNotch                               Launch Dynamic Notch daemon
          DynamicNotch run <title> -- <command...>   Execute command with live notch activity & completion alert
          DynamicNotch activity <command> [args...]  Granular activity controls (start, update, complete, fail)
          DynamicNotch alert <title> [subtitle] ...  Dispatch an instant notification alert banner

        EXAMPLES:
          # Run a build with live progress & completion banner:
          DynamicNotch run "Building Project" -- swift build -c release

          # Wrap any script or test command:
          DynamicNotch run "Running Tests" -- npm test

          # Granular script integration:
          DynamicNotch activity start task1 "Analyzing Codebase" "Scanning AST..."
          DynamicNotch activity update task1 "Generating artifacts..." 0.65
          DynamicNotch activity complete task1 "Analysis Done" "0 errors found"
        """)
    }
}
