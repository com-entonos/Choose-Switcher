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
    enum LastAction : Int, CaseIterable { case  onScreen = 0, override, switched }
    private var previousLastActiveApp: NSRunningApplication?
    private var lastActiveApp: NSRunningApplication? {
        didSet { previousLastActiveApp = oldValue }
    }
    private var lastAction = LastAction.onScreen
    private var justOnce = false
    
    init() {
        self.forceSwitch = UserDefaults.standard.dictionary(forKey: "ForceSwitch") as? [String: Bool] ??
                            [ "com.apple.loginwindow":false, "com.apple.UserNotificationCenter":false]
    }
    
    func handleActivation(app: NSRunningApplication) {
        let m0 = "\(app.localizedName ?? "<none>") (\(app.bundleIdentifier ?? "<noID>"))"
        // do nothing if new app Bundle is our Bundle or lastActiveApp bundle
        Logger.log("app activation: \(m0) \((app.bundleIdentifier != Bundle.main.bundleIdentifier && app.bundleIdentifier != lastActiveApp?.bundleIdentifier ?? "nil") ? "" : "REJECTED: ")last=\(lastActiveApp?.bundleIdentifier ?? "<noID>") plast=\(previousLastActiveApp?.bundleIdentifier ?? "<noID>")", level: .debug)
        guard let bid = app.bundleIdentifier, bid != Bundle.main.bundleIdentifier, bid != lastActiveApp?.bundleIdentifier ?? "" else { return }
        
        
        if hasWindowInCurrentSpace(pid: app.processIdentifier) {  // if in current Space, do nothing
            lastAction = .onScreen
            if forceSwitch[bid] ?? false { lastActiveApp = app }
            Logger.log("has on screen windows\(forceSwitch[bid] ?? false ? ", updated lastActiveApp" : "")", level: .debug)
            return
        }
        
        if forceSwitch[bid] == nil && !justOnce {    // go ask
            Logger.log("need to call showPrompt", level: .debug)
            justOnce = showPrompt(app: app)
        }
        
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bid && ( forceSwitch[bid] ?? false) {
            Logger.log("first need to activate instead of \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "<none>") (\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "<noID>"))", level: .debug)
            app.activate()
        } else {
            if justOnce || forceSwitch[bid] ?? false {
                Logger.log("trying to switch (.switched) Space... (justOnce? \(justOnce), forceSwitch? \(forceSwitch[bid] != nil ? (forceSwitch[bid]! ? "true" : "false") : "nil"))",level: .debug)
                lastAction = .switched
                justOnce = false
                clickDockIcon(appName: app.localizedName ?? "")
            } else {
                lastAction = .override
                Logger.log("does not switch (.override) Space (forceSwitch? \(forceSwitch[bid] != nil ? (forceSwitch[bid]! ? "true" : "false") : "nil"))",level: .debug)
            }
            lastActiveApp = app
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
        if response == .alertSecondButtonReturn {
            forceSwitch[app.bundleIdentifier!] = false
        } else if response == .alertFirstButtonReturn {
            forceSwitch[app.bundleIdentifier!] = true
        }
        return response == .alertThirdButtonReturn
    }
    
    // Logic for the new Undo/Force shortcut
    func performUndo() {
        guard let currentApp = NSWorkspace.shared.frontmostApplication else { return }
        
        Logger.log("try undo of \(lastAction), curr: \(currentApp.localizedName ?? ""), last: \(lastActiveApp?.localizedName ?? ""), prev: \(previousLastActiveApp?.localizedName ?? "") \(lastAction == .switched && previousLastActiveApp != nil && previousLastActiveApp?.bundleIdentifier != currentApp.bundleIdentifier)",level: .debug)
        switch lastAction {
        case .switched:
            if let prevApp = previousLastActiveApp, prevApp.bundleIdentifier != currentApp.bundleIdentifier {  // want to try to switch back to the previous app
                Logger.log("trying to activate prev", level: .debug)
                lastActiveApp = currentApp
                prevApp.activate()
            }
        case .override:
            Logger.log("trying to switch Space (was .override) back to curr", level: .debug)
            lastAction = .switched
            lastActiveApp = currentApp
            clickDockIcon(appName: currentApp.localizedName ?? "")
        case .onScreen:
            Logger.log("do nothing (.onScreen)",level: .debug)
            // do nothing
            break
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
                Logger.log("Forced osascript ran successfully.", category: .scriptExecution, level: .debug)
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
