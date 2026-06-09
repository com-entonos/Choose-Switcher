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
    private var previousLastActiveSpace: Int?
    private var lastActiveSpace: Int? {
        didSet { previousLastActiveSpace = oldValue }
    }
    var goingToApp : NSRunningApplication?
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
        let goingToBid = goingToApp?.bundleIdentifier ?? bid

        Logger.log("\((bid != Bundle.main.bundleIdentifier && bid != lastBid && bid != "com.apple.loginwindow" && bid == goingToBid) ? "" : "REJECTED: ")app activation: \(name) (\(bid)) goingToBid=\(goingToBid) last=\(lastBid) plast=\(prevBid)", level: .debug)
        guard bid != Bundle.main.bundleIdentifier, bid != lastBid, bid != "com.apple.loginwindow", bid == goingToBid else { return }

        if hasWindowInCurrentSpace(pid: app.processIdentifier) {
            if doingUndo, let spaceNumber = previousLastActiveSpace {
                lastActiveApp = app
                switchToSpace(app, spaceNumber)
            } else if forceSwitch[bid] != nil || doingUndo {
                lastActiveApp = app
                previousLastActiveSpace = lastActiveSpace
            }
            doingUndo = false
            Logger.log("  has on-screen windows, \(forceSwitch[bid] == nil ? "would ask to" : (forceSwitch[bid]! ? "would" : "would not")) switch", level: .debug)
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
                Logger.log("  trying to switch Space...", level: .debug)
                if doingUndo, let space = previousLastActiveSpace {
                    switchToSpace(app, space)
                } else {
                    switchToApp(app)
                }
            } else {
                Logger.log("  not switching", level: .debug)
            }
            lastActiveApp = app; doingUndo = false
        }
    }

    // MARK: - Space switching

    /// Finds which Space the app is on (via com.apple.spaces plist + CGWindowList),
    /// determines its 1-based ctrl+number position, and sends the keystroke.
    private func switchToApp(_ app: NSRunningApplication) {
        guard let spaceNumber = spaceNumber(for: app.processIdentifier) else {
            Logger.log("!! could not find space number- abort", level: .debug)
            return
        }
        switchToSpace(app, spaceNumber)
    }
    private func switchToSpace(_ app: NSRunningApplication, _ spaceNumber: Int) {
        lastActiveSpace = spaceNumber
        Logger.log("  switching to space \(spaceNumber) for \(app.localizedName ?? "<none>")", level: .debug)
        goingToApp = app
        switchViaCoreGraphics(spaceNumber: spaceNumber)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { app.activate(); self.goingToApp = nil }
    }

    /// Returns the 1-based Mission Control space number for ctrl+N shortcut.
    private func spaceNumber(for pid: Int32) -> Int? {
        let prefs  = UserDefaults(suiteName: "com.apple.spaces")
        prefs?.synchronize()  // hopefully force current info...
        guard let config = prefs?.dictionary(forKey: "SpacesDisplayConfiguration"),
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
            Logger.log("!!  no windows found for pid \(pid)", level: .debug)
            return nil
        }
        Logger.log("    pid \(pid) has \(pidWIDs.count) windows", level: .debug)

        // Find which space UUID contains the most windows belonging to this pid.
        var bestUUID:  String? = nil
        var bestCount = 0
        for prop in spaceProps {
            guard let uuid    = prop["name"] as? String,
                  let windows = prop["windows"] as? [Int]
            else { continue }
            let count = windows.filter { pidWIDs.contains($0) }.count
            if count > bestCount {
                bestCount = count
                bestUUID  = uuid
                Logger.log("     candidate space uuid=\(uuid) match count=\(count)", level: .debug)
            }
        }
        guard let targetUUID = bestUUID else {
            Logger.log("  app not found in any Space Properties entry", level: .debug)
            return nil
        }
        Logger.log("    selected space uuid=\(targetUUID) with \(bestCount) matching windows", level: .debug)

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
                    Logger.log("    target space global #\(spaceNum) (display offset \(globalOffset), local index \(i))", level: .debug)
                    return spaceNum
                }
            }
            globalOffset += spaces.count
        }

        Logger.log("!!  target uuid \(targetUUID) not found in any monitor", level: .debug)
        return nil
    }

    /// Sends native keyboard events to switch to space N on the active display.
    private func switchViaCoreGraphics(spaceNumber: Int) {
        // Key codes for ctrl+1 through ctrl+12 (corresponds to 1-9, 0, -, = on US Keyboards)
        let keyCodes = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24]
        guard spaceNumber >= 1, spaceNumber <= keyCodes.count * 4 else {
            Logger.log("space number \(spaceNumber) out of range", level: .error)
            return
        }
        // Create the system event source
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            Logger.log("Failed to create CGEventSource", level: .error)
            return
        }
        
        // Determine target index and tier
        let keyCode = CGKeyCode(keyCodes[(spaceNumber - 1) % 12])
        
        // Initialize key down and key up events
        guard let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            Logger.log("Failed to create CGEvent objects", level: .error)
            return
        }
        
        // Map your custom tier matrix back to pure CGEventFlags
        var flags: CGEventFlags = [.maskControl]
        switch (spaceNumber - 1) / 12 {
        case 0:
            // Tier 0: Control only
            break
        case 1:
            // Tier 1: Control + Option
            flags.insert(.maskAlternate)
        case 2:
            // Tier 2: Control + Option + Shift
            flags.insert([.maskAlternate, .maskShift])
        case 3:
            // Tier 3: Control + Option + Shift + Command
            flags.insert([.maskAlternate, .maskShift, .maskCommand])
        default:
            break
        }
        
        // Assign the built flags to both events
        keyDownEvent.flags = flags
        keyUpEvent.flags = flags
        
        Logger.log("CoreGraphics Event: spaceNumber = \(spaceNumber) -> keycode = \(keyCode), flags = \(flags.rawValue)", category: .lifecycle, level: .debug)
        
        // Post events directly to the HID system tap (simulating hardware input)
        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
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
}
