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
        print("Bundle path: \(Bundle.main.bundlePath)")
        print("Resource path: \(Bundle.main.resourcePath ?? "nil")")
        
        // Try different possible paths for the help file
        let possiblePaths = [
            Bundle.main.path(forResource: "Xe-Transfer Help", ofType: "html", inDirectory: "Help"),
            Bundle.main.path(forResource: "Xe-Transfer Help", ofType: "html"),
            Bundle.main.bundlePath + "/Contents/Resources/Help/Xe-Transfer Help.html",
            Bundle.main.bundlePath + "/Contents/Resources/Xe-Transfer Help.html"
        ]
        
        for path in possiblePaths {
            if let helpPath = path {
                print("Found help file at: \(helpPath)")
                let helpURL = URL(fileURLWithPath: helpPath)
                NSWorkspace.shared.open(helpURL)
                return
            }
        }
        
        // If we get here, the help file wasn't found
        print("Help file not found in any location")
        let alert = NSAlert()
        alert.messageText = "Help File Not Found"
        alert.informativeText = "The help file could not be found. Please contact support."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
} 