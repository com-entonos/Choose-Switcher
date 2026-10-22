//
//  ContentView.swift
//  Swicher
//
//  Created by G.J. Parker on 4/11/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject var manager = SpaceManager.shared

    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Button("Quit Entirely") {
                    NSApp.terminate(nil)
                }
                Spacer()
                // This closes the window but the background observer stays alive
                Button("Continue") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            
            Divider()

            List {
                if manager.forceSwitch.isEmpty {
                    Text("No app rules saved yet.").foregroundColor(.secondary)
                }
                ForEach(manager.forceSwitch.keys.sorted(), id: \.self) { bid in
                    HStack {
                        let ID = Text(" (\(bid))").font(.system(size: 7, design: .monospaced))
                        Text("\(getAppName(from: bid)) \(ID)").font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { manager.forceSwitch[bid]! ? 1 : 0 },
                            set: { manager.forceSwitch[bid] = ($0 == 1) }
                        )) {
                            Text("Stay").tag(0)
                            Text("Switch").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                        
                        Button(action: { manager.forceSwitch.removeValue(forKey: bid) }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Divider()
            HStack {
                Button("Set Keyboard Shortcut...") {
                    // This URL jumps directly to the Services shortcuts page
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")!
                    NSWorkspace.shared.open(url)
                }
                .controlSize(.small)
                .help("To set shortcut: System Settings...>Keyboard>Keyboard Shortcuts...>Services>General. Recommended: ⌥`")
                
                //Spacer()
                Text("then select Services on left, open General on right then double-click to set").font(Font.system(size: 11, design: .default))
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

/*
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Version 1: With mock data
            ContentView()
                .onAppear {
                    SpaceManager.shared.forceSwitch = [
                        "com.apple.Safari": true,
                        "com.apple.Terminal": false,
                        "com.spotify.client": true
                    ]
                }
                .previewDisplayName("Settings with Apps")

            // Version 2: Empty state
            ContentView()
                .onAppear {
                    SpaceManager.shared.forceSwitch = [:]
                }
                .previewDisplayName("Empty Settings")
        }
        .frame(width: 500, height: 400)
    }
}
*/

func getAppName(from bundleIdentifier: String) -> String {
    // 1. Get the local file URL of the application bundle
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
        return bundleIdentifier
    }
    
    // 2. Initialize the bundle for that application
    guard let bundle = Bundle(url: appURL) else {
        return bundleIdentifier
    }
    
    // 3. Extract the localized or regular display name
    if let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !appName.isEmpty {
        return appName
    } else {
        return bundleIdentifier
    }
    
    //return appName == nil ? bundleIdentifier : appName! //(appName! + " (" + bundleIdentifier + ")")
}
