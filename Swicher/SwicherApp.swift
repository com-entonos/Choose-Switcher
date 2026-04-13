//
//  SwicherApp.swift
//  Swicher
//
//  Created by G.J. Parker on 4/11/26.
//

import SwiftUI

@main
struct ChooseSwitcher: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() } // Required by SwiftUI but unused
    }
}
