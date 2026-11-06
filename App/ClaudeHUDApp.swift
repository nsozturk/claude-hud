//
//  ClaudeHUDApp.swift
//  ClaudeHUD
//
//  Standalone macOS Native App Entry Point
//  Boots Live Floating Notch Overlay, UDS Socket Interceptor, and Debug Logger.
//

import AppKit
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        hudLog("🚀 Claude HUD Application Launched", category: "APP")
        HUDSettingsStore.shared.applyDockPolicy()
        
        // 1. Setup macOS Menu Bar (Navbar / Status Bar) Item
        DispatchQueue.main.async {
            HUDMenuBarController.shared.setupStatusBarItem()
        }
        
        // 2. Start the Live Screen Floating Notch Overlay Panel
        DispatchQueue.main.async {
            LiveNotchPanelController.shared.startOverlay()
        }
        
        // 3. Start Live Transcript & Socket Interceptor
        ClaudeSessionWatcher.shared.start()
        HUDHotkeys.shared.start()

        // 4. First launch: walkthrough (position, hook, Accessibility).
        DispatchQueue.main.async { HUDOnboardingController.shared.showIfNeeded() }

        hudLog("✨ All background daemons, menu bar item, and notch overlay initialized successfully", category: "APP")
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        hudLog("👋 Claude HUD Application Terminating...", category: "APP")
        ClaudeSessionWatcher.shared.stop()
        LiveNotchPanelController.shared.stopOverlay()
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep Claude HUD alive permanently in the macOS Menu Bar and Dynamic Notch Overlay
        return false
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            HUDMenuBarController.shared.openDesignLabWindow()
        }
        return true
    }
}

@main
struct ClaudeHUDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No WindowGroup: nothing opens at launch. The window comes from the menu bar icon
        // (HUDMenuBarController.openDesignLabWindow); first launch shows the welcome instead.
        Settings {
            ClaudeHUDSettingsView()
                .frame(width: 340, height: 620)
        }
    }
}
