//
//  SpaceManager.swift
//  Swicher
//
//  Created by G.J. Parker on 4/11/26.
//

import Cocoa
import Combine
import OSLog

class SpaceManager: ObservableObject {
    static let shared = SpaceManager()
    
    @Published var forceSwitch : [String: Bool] {
        didSet { UserDefaults.standard.set(forceSwitch, forKey: "ForceSwitch") }
    }

    // for 'undo'
    private var previousLastActiveApp: NSRunningApplication?
    private var lastActiveApp: NSRunningApplication? {
        didSet { previousLastActiveApp = oldValue }
    }
    private var justOnce = false
    private var doingUndo = false
    
    init() {
        self.forceSwitch = UserDefaults.standard.dictionary(forKey: "ForceSwitch") as? [String: Bool] ??
                            [ "com.apple.loginwindow":false, "com.apple.UserNotificationCenter":false]
    }
    
    func handleActivation(app: NSRunningApplication) {
        let bid = app.bundleIdentifier ?? "<noID>"
        let name = app.localizedName ?? "<none>"
        let lastBid = lastActiveApp?.bundleIdentifier ?? "<noID>"
        let prevBid = previousLastActiveApp?.bundleIdentifier ?? "<noID>"
        // do nothing if new app Bundle is our Bundle or lastActiveApp bundle
        Logger.log("\((bid != Bundle.main.bundleIdentifier && bid != lastBid) ? "" : "REJECTED: ")app activation: \(name) (\(bid)) last=\(lastBid) plast=\(prevBid)", level: .debug)
        guard let bid = app.bundleIdentifier, bid != Bundle.main.bundleIdentifier, bid != lastBid else { return }
        
        
        if hasWindowInCurrentSpace(pid: app.processIdentifier) {  // if in current Space, do nothing
            if forceSwitch[bid] != nil || doingUndo { lastActiveApp = app }
            doingUndo = false
            Logger.log("has on screen windows, \(forceSwitch[bid] == nil ? "would ask to" : (forceSwitch[bid]! ? "would" : "would not")) switch", level: .debug)
            return
        }
        
        if forceSwitch[bid] == nil {    // go ask
            Logger.log("need to call showPrompt", level: .debug)
            justOnce = showPrompt(app: app)
        }
        
        let toSwitch = justOnce || doingUndo || forceSwitch[bid] ?? false
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bid && toSwitch {
            Logger.log("first need to activate instead of \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "<none>") (\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "<noID>"))", level: .debug)
            app.activate()
        } else {
            if toSwitch {
                if justOnce { forceSwitch.removeValue(forKey: bid); justOnce = false }
                Logger.log("trying to switch (.switched) Space... (forceSwitch? \(forceSwitch[bid] != nil ? (forceSwitch[bid]! ? "true" : "false") : "nil"))",level: .debug)
                clickDockIcon(appName: app.localizedName ?? "")
            } else {
                Logger.log("does not switch (.override) Space (forceSwitch? \(forceSwitch[bid] != nil ? (forceSwitch[bid]! ? "true" : "false") : "nil"))",level: .debug)
            }
            lastActiveApp = app; doingUndo = false
        }
    }
    
    private func hasWindowInCurrentSpace(pid: Int32) -> Bool {
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        Logger.log("  number of windows for \(pid): \(windowList.count(where: { win in (win[kCGWindowOwnerPID as String] as? Int32) == pid}))", level: .debug)
        // return if windowList contains any windows with our new PID
        return windowList.contains { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
        // return if windList contains any windows with our new PID AND size of the windows are > 100 (avoids small non-user windows)
        /*
        return windowList.contains { window in
            let bounds = window[kCGWindowBounds as String] as? [String: Any]
            return (window[kCGWindowOwnerPID as String] as? Int32) == pid &&
                   (bounds?["CGRectWidth"] as? CGFloat ?? 0) > 100 &&
                   (bounds?["CGRectHeight"] as? CGFloat ?? 0) > 100
        }
         */
    }

    private func showPrompt(app: NSRunningApplication) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Switch Spaces?"
        alert.informativeText = "\(app.localizedName ?? "App") has no windows here. Switch to its Space?"
        alert.addButton(withTitle: "Always Switch")
        alert.addButton(withTitle: "Stay Here")
        alert.addButton(withTitle: "Just Once")
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
    
        Logger.log("showPrompt: \(response == .alertFirstButtonReturn ? "switch" : "")\(response == .alertSecondButtonReturn ? "stay" : "")\(response == .alertThirdButtonReturn ? "just once" : "") button choosen", category: .ui, level: .debug)
        forceSwitch[app.bundleIdentifier!] = !(response == .alertSecondButtonReturn)
        return response == .alertThirdButtonReturn
    }
    
    // Logic for the new Undo/Force shortcut
    func performUndo() { // active app is us because of Services, so don't bother.
        guard let currentApp = lastActiveApp, let prevApp = previousLastActiveApp, currentApp != prevApp, let _ = prevApp.bundleIdentifier else { return }
        
        Logger.log("try undo: \"curr\": \(currentApp.localizedName ?? "") back to \"last\": \(prevApp.localizedName ?? "") !=? \(prevApp.bundleIdentifier != currentApp.bundleIdentifier)",level: .debug)
        
        
        doingUndo = forceSwitch[prevApp.bundleIdentifier!] != nil
        if doingUndo {
   //         if forceSwitch[currentApp.bundleIdentifier!] == false {
   //             lastActiveApp = prevApp
   //             currentApp.activate()
   //         } else {
                previousLastActiveApp = lastActiveApp
                prevApp.activate()
   //         }
        }
    }
    
    func clickDockIcon(appName: String) {
        let scriptSource = appleScript(appName: appName)
        
        Logger.log("script for Dock icon: \(scriptSource)", category: .scriptExecution, level: .debug)
        /* for debugging */
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            
            if let err = error {
                Logger.log("AS error: \(err)", category: .scriptExecution, level: .error)
                let errorCode = err["NSAppleScriptErrorNumber"] as? Int
                
                if errorCode == -1743 {
                    Logger.log("  errorCode of -1743, trying to force...", category: .scriptExecution, level: .error)
                    ForcePermissionClickDockIcon(appName: appName)
                } else {
                    Logger.log("  unknown error, abort!", category: .scriptExecution, level: .fault)
                    handleUnrecoverableError(message: "Allow Choose Switcher to automate System Events. In System Preferences...>Privacy & Security>Automation>Choose Switcher check System Events")
                }
            } else {
                Logger.log("script for Dock icon worked!", category: .scriptExecution, level: .debug)
            }
        } /* end debug */
    }

    private func appleScript(appName: String) -> String {
        // delay and tell app to activate to force app to be ready to accept keyboard
        return """
        tell application "System Events" to tell process "Dock" to click list 1's UI element "\(appName)"
        """
        /*
        return """
        tell application "System Events" to tell process "Dock" to click list 1's UI element "\(appName)"
        delay 0.1
        tell application "\(appName)" to activate
        """
        */
    }
    
    func ForcePermissionClickDockIcon(appName: String) {
        let script = appleScript(appName: appName)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        Logger.log("Attempting to force process delivering osascript: \(script)", category: .scriptExecution, level: .debug)
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                Logger.log("Forced osascript ran successfully", category: .scriptExecution, level: .debug)
            } else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let err = String(data: data, encoding: .utf8) ?? "Unknown error"
                Logger.log("Fatal osascript failed (Status=\(process.terminationStatus)): \(err)", category: .scriptExecution, level: .fault)
                handleUnrecoverableError(message: "Fatal osascript error: \(err) Perhaps in System Preferences...>Privacy & Security>Automation>Choose Switcher check System Events")
            }
        } catch {
            Logger.log("Fatal force process error: \(error.localizedDescription)", category: .scriptExecution, level: .fault)
            handleUnrecoverableError(message: "Fatal failed to launch error: \(error.localizedDescription) Perhaps in System Preferences...>Privacy & Security>Automation>Choose Switcher check System Events")
        }
    }
    
    private func handleUnrecoverableError(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Fatal Automation Permission"
            alert.informativeText = message
            alert.addButton(withTitle: "Open Automation in System Preferences")
            alert.addButton(withTitle: "Just Quit")
            
            // Ensure alert is visible even if app is an agent
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
                NSWorkspace.shared.open(url)
            }
            NSApp.terminate(nil)
        }
    }
    
}
