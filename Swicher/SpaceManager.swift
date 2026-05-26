//
//  SpaceManager.swift
//  Switcher
//

import Cocoa
import Combine
import OSLog

class SpaceManager: ObservableObject {
    static let shared = SpaceManager()

    @Published var forceSwitch: [String: Bool] {
        didSet { UserDefaults.standard.set(forceSwitch, forKey: "ForceSwitch") }
    }

    private var previousLastActiveApp: NSRunningApplication?
    private var lastActiveApp: NSRunningApplication? {
        didSet { previousLastActiveApp = oldValue }
    }
    private var justOnce  = false
    private var doingUndo = false

    init() {
        self.forceSwitch = UserDefaults.standard.dictionary(forKey: "ForceSwitch")
                           as? [String: Bool]
                           ?? ["com.apple.loginwindow": false,
                               "com.apple.UserNotificationCenter": false]
    }

    // MARK: - Main entry point

    func handleActivation(app: NSRunningApplication) {
        let bid      = app.bundleIdentifier ?? "<noID>"
        let name     = app.localizedName ?? "<none>"
        let lastBid  = lastActiveApp?.bundleIdentifier ?? "<noID>"
        let prevBid  = previousLastActiveApp?.bundleIdentifier ?? "<noID>"

        Logger.log("\((bid != Bundle.main.bundleIdentifier && bid != lastBid) ? "" : "REJECTED: ")app activation: \(name) (\(bid)) last=\(lastBid) plast=\(prevBid)", level: .debug)
        guard bid != Bundle.main.bundleIdentifier, bid != lastBid else { return }

        if hasWindowInCurrentSpace(pid: app.processIdentifier) {
            if forceSwitch[bid] != nil || doingUndo { lastActiveApp = app }
            doingUndo = false
            Logger.log("has on-screen windows, \(forceSwitch[bid] == nil ? "would ask to" : (forceSwitch[bid]! ? "would" : "would not")) switch", level: .debug)
            return
        }

        if forceSwitch[bid] == nil {
            Logger.log("need to call showPrompt", level: .debug)
            justOnce = showPrompt(app: app)
        }

        let toSwitch = justOnce || doingUndo || forceSwitch[bid] ?? false
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bid && toSwitch {
            Logger.log("first need to activate instead of \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "<none>")", level: .debug)
            app.activate()
        } else {
            if toSwitch {
                if justOnce { forceSwitch.removeValue(forKey: bid); justOnce = false }
                Logger.log("trying to switch Space...", level: .debug)
                switchToApp(app)
            } else {
                Logger.log("not switching", level: .debug)
            }
            lastActiveApp = app; doingUndo = false
        }
    }

    // MARK: - Space switching

    /// Finds which Space the app is on (via com.apple.spaces plist + CGWindowList),
    /// determines its 1-based ctrl+number position, and sends the keystroke.
    private func switchToApp(_ app: NSRunningApplication) {
        guard let spaceNumber = spaceNumber(for: app.processIdentifier) else {
            Logger.log("could not find space number, falling back to Dock click", level: .debug)
            clickDockIcon(appName: app.localizedName ?? "")
            return
        }
        Logger.log("switching to space \(spaceNumber) via ctrl+\(spaceNumber)", level: .debug)
        switchViaAppleScript(spaceNumber: spaceNumber)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { app.activate() }
    }

    /// Returns the 1-based Mission Control space number for ctrl+N shortcut.
    private func spaceNumber(for pid: Int32) -> Int? {
        guard let prefs  = UserDefaults(suiteName: "com.apple.spaces"),
              let config = prefs.dictionary(forKey: "SpacesDisplayConfiguration"),
              let mgmt   = config["Management Data"] as? [String: Any],
              let monitors = mgmt["Monitors"] as? [[String: Any]],
              let spaceProps = config["Space Properties"] as? [[String: Any]]
        else {
            Logger.log("could not read com.apple.spaces", level: .error)
            return nil
        }

        // Get all CGWindowIDs for this pid using public API
        let allWindows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID)
                         as? [[String: Any]] ?? []
        let pidWIDs = Set(allWindows.compactMap { w -> Int? in
            guard let winPid = w[kCGWindowOwnerPID as String] as? Int32,
                  winPid == pid,
                  let wid = w[kCGWindowNumber as String] as? Int
            else { return nil }
            return wid
        })
        guard !pidWIDs.isEmpty else {
            Logger.log("no windows found for pid \(pid)", level: .debug)
            return nil
        }
        Logger.log("pid \(pid) has \(pidWIDs.count) windows: \(pidWIDs)", level: .debug)

        // Find which space UUID contains one of our window IDs
        var targetUUID: String? = nil   // TODO if more than one Space has a window, perhaps take the one with the most windows?
        for prop in spaceProps {
            guard let uuid    = prop["name"] as? String,
                  let windows = prop["windows"] as? [Int]
            else { continue }
            if windows.contains(where: { pidWIDs.contains($0) }) {
                targetUUID = uuid
                Logger.log("found app in space uuid=\(uuid)", level: .debug)
                break
            }
        }
        guard let targetUUID else {
            Logger.log("app not found in any Space Properties entry", level: .debug)
            return nil
        }

        
        // below is assuming something about the order in the com.apple.spaces plist, it seems. it works currently, but surprised the order is correct or that the dictionary doesn't scramble it. perhaps the magic of enumerated...
        
        // With "Displays have separate spaces" ON, ctrl+N numbers spaces globally
        // across all displays in Mission Control order — laptop first, then external.
        // We walk monitors in order, accumulating an offset, so the external display's
        // spaces get ctrl+(laptopCount+1) through ctrl+(laptopCount+externalCount).
        var globalOffset = 0
        for monitor in monitors {
            guard let spaces = monitor["Spaces"] as? [[String: Any]] else { continue }
            for (i, space) in spaces.enumerated() {
                let uuid = space["uuid"] as? String ?? ""
                if uuid == targetUUID {
                    let spaceNum = globalOffset + i + 1
                    Logger.log("target space global #\(spaceNum) (display offset \(globalOffset), local index \(i))", level: .debug)
                    return spaceNum
                }
            }
            globalOffset += spaces.count
        }

        Logger.log("target uuid \(targetUUID) not found in any monitor", level: .debug)
        return nil
    }

    /// Sends ctrl+N via AppleScript to switch to space N on the active display.
    private func switchViaAppleScript(spaceNumber: Int) {
        // Key codes for ctrl+1 through ctrl+12
        let keyCodes = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24] // this is 1-9,0,-,= which is the top row of US keyboard
        let keys = ["control down", "{control down, option down}", "{control down, option down, shift down}", "{control down, option down, shift down, command down}"]
        guard spaceNumber >= 1, spaceNumber <= keyCodes.count * keys.count else {
            Logger.log("space number \(spaceNumber) out of range", level: .error)
            return
        }
        let keyCode = keyCodes[(spaceNumber - 1) % 12]
        let key = keys[min(keys.count - 1, (spaceNumber - 1) / 12)]
        let script  = """
        tell application "System Events" to key code \(keyCode) using \(key) down
        """
        Logger.log("AppleScript: ctrl+\(spaceNumber) (key code \(keyCode))", category: .scriptExecution, level: .debug)
        if let as_ = NSAppleScript(source: script) {
            var err: NSDictionary?
            as_.executeAndReturnError(&err)
            if let err { Logger.log("AppleScript error: \(err)", category: .scriptExecution, level: .error) }
        }
    }

    // MARK: - Window detection

    private func hasWindowInCurrentSpace(pid: Int32) -> Bool {
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        Logger.log("  on-screen windows for pid \(pid): \(windowList.count(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }))", level: .debug)
        return windowList.contains { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
    }

    // MARK: - Prompt

    private func showPrompt(app: NSRunningApplication) -> Bool {
        let alert = NSAlert()
        alert.messageText    = "Switch Spaces?"
        alert.informativeText = "\(app.localizedName ?? "App") has no windows here. Switch to its Space?"
        alert.addButton(withTitle: "Always Switch")
        alert.addButton(withTitle: "Stay Here")
        alert.addButton(withTitle: "Just Once")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        Logger.log("showPrompt: \(response == .alertFirstButtonReturn ? "switch" : "")\(response == .alertSecondButtonReturn ? "stay" : "")\(response == .alertThirdButtonReturn ? "just once" : "")", category: .ui, level: .debug)
        forceSwitch[app.bundleIdentifier!] = !(response == .alertSecondButtonReturn)
        return response == .alertThirdButtonReturn
    }

    // MARK: - Undo

    func performUndo() {
        guard let curr = lastActiveApp,
              let prev = previousLastActiveApp,
              curr != prev,
              let _ = prev.bundleIdentifier else { return }
        Logger.log("try undo: \(curr.localizedName ?? "") back to \(prev.localizedName ?? "")", level: .debug)
        doingUndo = forceSwitch[prev.bundleIdentifier!] != nil
        if doingUndo {
            previousLastActiveApp = lastActiveApp
            prev.activate()
        }
    }

    // MARK: - Dock click (fallback)
    private func AScript(appName: String) -> String {
        return """
        tell application "System Events"
            tell process "Dock"
                repeat with aList in every list
                    repeat with anItem in every UI element of aList
                        if name of anItem is "\(appName)" then
                            click anItem
                            return
                        end if
                    end repeat
                end repeat
            end tell
        end tell
        """
    }
    func clickDockIcon(appName: String) {
        let script = AScript(appName: appName)
        Logger.log("Dock click script for: \(appName)", category: .scriptExecution, level: .debug)
        if let as_ = NSAppleScript(source: script) {
            var err: NSDictionary?
            as_.executeAndReturnError(&err)
            if let err {
                Logger.log("Dock click error: \(err)", category: .scriptExecution, level: .error)
                let code = err["NSAppleScriptErrorNumber"] as? Int
                if code == -1743 {
                    ForcePermissionClickDockIcon(appName: appName)
                } else {
                    handleUnrecoverableError(message: "Allow Choose Switcher to automate System Events.")
                }
            }
        }
    }

    func ForcePermissionClickDockIcon(appName: String) {
        let script = AScript(appName: appName)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments     = ["-e", script]
        let errPipe = Pipe()
        process.standardError = errPipe
        Logger.log("Force osascript for: \(appName)", category: .scriptExecution, level: .debug)
        do {
            try process.run(); process.waitUntilExit()
            if process.terminationStatus == 0 {
                Logger.log("Force osascript succeeded", category: .scriptExecution, level: .debug)
            } else {
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                let msg  = String(data: data, encoding: .utf8) ?? "unknown"
                Logger.log("Force osascript failed: \(msg)", category: .scriptExecution, level: .fault)
                handleUnrecoverableError(message: "Fatal osascript error: \(msg)")
            }
        } catch {
            Logger.log("Force process error: \(error)", category: .scriptExecution, level: .fault)
            handleUnrecoverableError(message: "Failed to launch: \(error.localizedDescription)")
        }
    }

    private func handleUnrecoverableError(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText     = "Fatal Automation Permission"
            alert.informativeText = message
            alert.addButton(withTitle: "Open Automation in System Preferences")
            alert.addButton(withTitle: "Just Quit")
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            }
            NSApp.terminate(nil)
        }
    }
}


