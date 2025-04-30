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
        print("\n=== Help File Debug Information ===")
        
        // Get the app bundle
        guard let bundle = Bundle.main.resourcePath else {
            print("Could not get resource path")
            return
        }
        
        // Try to find the help file using Bundle's built-in method first
        if let helpPath = Bundle.main.path(forResource: "Xe-Transfer Help", ofType: "html") {
            print("Found help file using Bundle method: \(helpPath)")
            if NSWorkspace.shared.openFile(helpPath) {
                print("✓ Successfully opened help file")
                return
            } else {
                print("✗ Failed to open help file")
            }
        } else {
            print("Could not find help file using Bundle method")
        }
        
        // Fallback: Try direct path
        let directPath = (bundle as NSString).appendingPathComponent("Xe-Transfer Help.html")
        print("\nTrying direct path: \(directPath)")
        
        if FileManager.default.fileExists(atPath: directPath) {
            print("✓ Found help file at direct path")
            if NSWorkspace.shared.openFile(directPath) {
                print("✓ Successfully opened help file")
                return
            } else {
                print("✗ Failed to open help file")
            }
        } else {
            print("✗ Help file not found at direct path")
        }
        
        // If we get here, we couldn't find or open the help file
        print("\nCould not find or open help file")
        let alert = NSAlert()
        alert.messageText = "Help File Not Found"
        alert.informativeText = "The help file could not be found or opened. Please check if the file exists in the app bundle."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
} 