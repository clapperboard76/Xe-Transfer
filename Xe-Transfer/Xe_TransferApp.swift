import SwiftUI

@main
struct Xe_TransferApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var transferManager = FileTransferManager()
    @StateObject private var settings = Settings()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(transferManager)
                .environmentObject(settings)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .help) { }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Get the main menu
        if let mainMenu = NSApp.mainMenu {
            // Find or create the Help menu
            var helpMenuItem: NSMenuItem?
            for item in mainMenu.items {
                if item.title == "Help" {
                    helpMenuItem = item
                    break
                }
            }
            
            if helpMenuItem == nil {
                helpMenuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
                mainMenu.addItem(helpMenuItem!)
            }
            
            // Create the help submenu
            let helpMenu = NSMenu(title: "Help")
            
            // Add the help item
            let helpItem = NSMenuItem(title: "Xe-Transfer Help", action: #selector(showHelp), keyEquivalent: "?")
            helpItem.keyEquivalentModifierMask = [.command, .shift]
            helpMenu.addItem(helpItem)
            
            // Set the submenu
            helpMenuItem?.submenu = helpMenu
        }
    }
    
    @objc private func showHelp() {
        if let helpPath = Bundle.main.path(forResource: "Xe-Transfer Help", ofType: "html", inDirectory: "Help") {
            let helpURL = URL(fileURLWithPath: helpPath)
            NSWorkspace.shared.open(helpURL)
        } else {
            // Show error alert
            let alert = NSAlert()
            alert.messageText = "Help File Not Found"
            alert.informativeText = "The help file could not be found. Please contact support."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
} 