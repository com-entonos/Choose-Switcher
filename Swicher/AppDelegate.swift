//
//  AppDelegate.swift
//  Swicher
//
//  Created by G.J. Parker on 4/11/26.
//

import SwiftUI
import OSLog

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.log("Choose Switcher has started")
        NSApp.servicesProvider = self
        checkPermissions()
        setupObserver()
    }

    // This shows the settings when you "open" the app again
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Logger.log("showing Settings from double start", category: .ui, level: .debug)
        showSettings()
        return true
    }
    
    @objc func serviceToSetting(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        Logger.log("showing Settings from Services", category: .ui, level: .debug)
        showSettings()
    }

    @objc func undoSwitch(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        Logger.log("trying to do Undo from Services", category: .ui, level: .debug)
        SpaceManager.shared.performUndo()
    }
    
    private func setupObserver() {
        Logger.log("setting up observer for apps")
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                SpaceManager.shared.handleActivation(app: app)
            }
        }
    }
    
    private func showSettings() {
        if window == nil {
            let contentView = ContentView()
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            window?.center()
            window?.title = "Choose Switcher Settings"
            window?.isReleasedWhenClosed = false // CRITICAL: Keeps the window object in memory
            window?.contentView = NSHostingView(rootView: contentView)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
        
    private func checkPermissions() {
        // 1. Trigger Accessibility Prompt
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !isTrusted {
            Logger.log("lacking Accessibility permision", level: .error)
            // The system prompt is now on screen.
            // We show our own alert to explain why we are closing.
            
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Please enable Choose Switcher in System Settings. The app will now quit; relaunch it once permission is granted."
            alert.addButton(withTitle: "Open Accessibility in System Preferences")
            alert.addButton(withTitle: "Just Quit")
            
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
            NSApp.terminate(nil)  // abort without permissions
        }
        Logger.log("have Accessibility permisions", level: .debug)
    }
}

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!
    static let scriptExecution = Logger(subsystem: subsystem, category: "ScriptExecution")
    static let ui = Logger(subsystem: subsystem, category: "UserInterface")
    static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
    
    static func log(_ message: String, category: Logger = .lifecycle, level: OSLogType = .info) {
        // 1. Send to System Console
        switch level {
        case .debug: category.debug("\(message, privacy: .public)")
        case .error: category.error("\(message, privacy: .public)")
        case .fault: category.fault("\(message, privacy: .public)")
        default: category.info("\(message, privacy: .public)")
        }
        
        // 2. Print to Xcode Console
        let emoji = level == .error || level == .fault ? "❌" : "ℹ️"
        print("\(emoji) [\(level)] \(message)")
    }
}
