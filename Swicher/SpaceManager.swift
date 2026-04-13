//
//  SpaceManager.swift
//  Swicher
//
//  Created by G.J. Parker on 4/11/26.
//

import Cocoa
import Combine

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
        // do nothing if new app Bundle is our Bundle or lastActiveApp bundle
        print("\( (app.bundleIdentifier != Bundle.main.bundleIdentifier && app.bundleIdentifier != lastActiveApp?.bundleIdentifier ?? "") ? "" : "REJECTED: " )bid=\(app.bundleIdentifier)(\(app.processIdentifier)) last=\(lastActiveApp?.bundleIdentifier) plast-\(previousLastActiveApp?.bundleIdentifier)")
        guard let bid = app.bundleIdentifier, bid != Bundle.main.bundleIdentifier, bid != lastActiveApp?.bundleIdentifier ?? "" else { return }
        
        if hasWindowInCurrentSpace(pid: app.processIdentifier) {  // if in current Space, do nothing
            lastAction = .onScreen
            if forceSwitch[bid] ?? false { lastActiveApp = app }
            return
        }
        
        print("forceSwitch[\(bid)]: \(forceSwitch[bid] == nil ? "nil" : forceSwitch[bid]! ? "true" : "false")")
        if forceSwitch[bid] == nil && !justOnce {    // go ask
            print("need to call showPrompt")
            justOnce = showPrompt(app: app)
        }
        
        print("justOnce: \(justOnce), forceSwitch[\(bid)]: \(forceSwitch[bid] == nil ? "nil" : forceSwitch[bid]! ? "true" : "false")\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bid ? ", app not in front!" : "")")
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bid && ( forceSwitch[bid] ?? false) {
            print("need to activate \(app.localizedName ?? "") (\(app.processIdentifier))")
            app.activate()
        } else {
            if justOnce || forceSwitch[bid] ?? false {
                lastAction = .switched
                justOnce = false
                clickDockIcon(appName: app.localizedName ?? "")
            } else {
                lastAction = .override
            }
            lastActiveApp = app
        }
    }
    
    private func hasWindowInCurrentSpace(pid: Int32) -> Bool {
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        // return if windowList contains any windows with our new PID
        print("number of windows for \(pid): \(windowList.count(where: { win in (win[kCGWindowOwnerPID as String] as? Int32) == pid}))")
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
    
        print("showPrompt: \(response)")
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
        
        switch lastAction {
        case .switched:
            if let prevApp = previousLastActiveApp, prevApp.bundleIdentifier != currentApp.bundleIdentifier {  // want to try to switch back to the previous app
                lastActiveApp = currentApp
                prevApp.activate()
            }
        case .override:
            lastAction = .switched
            lastActiveApp = currentApp
            clickDockIcon(appName: currentApp.localizedName ?? "")
        case .onScreen:
            // do nothing
            break
        }
    }
    
    func clickDockIcon(appName: String) {
        let scriptSource = appleScript(appName: appName)
        
        print("script: \(scriptSource)")
        /* for debugging */
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            
            if let err = error {
                print("AS error: \(err)")
                let errorCode = err["NSAppleScriptErrorNumber"] as? Int
                
                if errorCode == -1743 {
                    ForcePermissionClickDockIcon(appName: appName)
                } else {
                    handleUnrecoverableError(message: "Allow Choose Switcher to automate System Events. In System Preferences...>Privacy & Security>Automation>Choose Switcher check System Events")
                }
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
        print("force script: \(script)")
        
        // Using a shell process forces macOS to recognize the external interaction
        /*let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]*/
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        // This will trigger the "Choose Switcher wants to control System Events" prompt
        /*process.launch()*/
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let err = String(data: data, encoding: .utf8)
                handleUnrecoverableError(message: "osascript error: \(err ?? "<none>") Perhaps in System Preferences...>Privacy & Security>Automation>Choose Switcher check System Events")
            }
        } catch {
            handleUnrecoverableError(message: "osascript failled to launch error: \(error) Perhaps in System Preferences...>Privacy & Security>Automation>Choose Switcher check System Events")
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
