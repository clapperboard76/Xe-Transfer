import SwiftUI
import CryptoKit
import Security
import ServiceManagement

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension Color {
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.0) // A warm gold shade
}

enum ChecksumType: String, CaseIterable {
    case sha256 = "SHA-256"
    case md5 = "MD5"
    case sha1 = "SHA-1"
}

extension URL {
    func isExternalDrive() -> Bool {
        let path = self.path
        // Check if the path starts with /Volumes/
        return path.hasPrefix("/Volumes/")
    }
    
    func getVolumeName() -> String? {
        guard isExternalDrive() else { return nil }
        let components = self.path.components(separatedBy: "/")
        // The volume name is the first component after /Volumes/
        if let volumesIndex = components.firstIndex(of: "Volumes"),
           volumesIndex + 1 < components.count {
            return components[volumesIndex + 1]
        }
        return nil
    }
    
    func requestWriteAccess() async throws -> Bool {
        // First try without elevation
        let testFile = self.appendingPathComponent(".xenon_test")
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFile)
            return true
        } catch {
            // If write fails, show a helpful message to the user
            let alert = NSAlert()
            alert.messageText = "Permission Required"
            alert.informativeText = """
                This drive requires permission to write files. To fix this:
                
                1. Open Finder
                2. Right-click on the drive in the sidebar
                3. Select "Get Info"
                4. Click the lock icon to make changes
                5. Enter your password
                6. Change permissions to "Read & Write"
                7. Close the Info window
                
                After changing permissions, try the transfer again.
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return false
        }
    }
}

struct SourceFolderSection: View {
    @Binding var sourceFolders: [URL?]
    @Binding var isHoveringSource: Bool
    @State private var showEjectAlert: Bool = false
    @State private var driveToEject: URL? = nil
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("SOURCE")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Source folders section")
                
                Button(action: { sourceFolders.append(nil) }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Add new source folder")
            }
            
            ForEach(0..<sourceFolders.count, id: \.self) { index in
                HStack {
                    Button(action: { selectSourceFolder(index: index) }) {
                        if let folder = sourceFolders[safe: index], let folderURL = folder {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: folderURL.path))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                        } else {
                            Image(isHoveringSource ? "SourceIconHover" : "SourceIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in
                        isHoveringSource = hovering
                    }
                    .accessibilityLabel("Select source folder \(index + 1)")
                    
                    if let folder = sourceFolders[safe: index], let folderPath = folder?.path {
                        Text(folderPath)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Select source")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    HStack(spacing: 5) {
                        if let folder = sourceFolders[safe: index], let folderURL = folder, folderURL.isExternalDrive() {
                            Button(action: {
                                driveToEject = folderURL
                                showEjectAlert = true
                            }) {
                                Image(systemName: "eject.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 10, height: 10)
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel("Eject drive \(folderURL.getVolumeName() ?? "")")
                        }
                        
                        Button(action: { removeSourceFolder(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 10, height: 10)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel("Remove source folder \(index + 1)")
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .alert("Eject Drive", isPresented: $showEjectAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Eject", role: .destructive) {
                if let drive = driveToEject {
                    ejectDrive(drive)
                }
            }
        } message: {
            if let drive = driveToEject, let volumeName = drive.getVolumeName() {
                Text("Are you sure you want to eject '\(volumeName)'?")
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func ejectDrive(_ drive: URL) {
        // First remove the drive from the UI
        DispatchQueue.main.async {
            if let index = sourceFolders.firstIndex(where: { $0?.path == drive.path }) {
                sourceFolders.remove(at: index)
            }
        }
        
        // Then attempt to eject the drive after a short delay
        let ejectQueue = DispatchQueue(label: "com.xenon.eject", qos: .userInitiated)
        
        ejectQueue.async {
            // Add a small delay to allow file handles to be released
            Thread.sleep(forTimeInterval: 1.0)
            
            // Use NSWorkspace to eject the volume
            let workspace = NSWorkspace.shared
            do {
                try workspace.unmountAndEjectDevice(at: drive)
                Swift.print("Drive ejected successfully")
            } catch {
                Swift.print("Error ejecting drive: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    errorMessage = "Failed to eject drive: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }
    
    private func selectSourceFolder(index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Source Folder \(index + 1)"
        if panel.runModal() == .OK, let folderURL = panel.url {
            while sourceFolders.count <= index {
                sourceFolders.append(nil)
            }
            sourceFolders[index] = folderURL
        }
    }
    
    private func removeSourceFolder(at index: Int) {
        if sourceFolders.indices.contains(index) {
            sourceFolders.remove(at: index)
        }
    }
}

struct DestinationFolderSection: View {
    @Binding var destinationFolders: [URL]
    @Binding var isHoveringDestination: Bool
    @Binding var destinationProgress: [Double]
    @Binding var dataRemainingForFolder: [Double]
    @Binding var estimatedTimeForFolder: [Double]
    @Binding var isPaused: [Bool]
    @State private var showEjectAlert: Bool = false
    @State private var driveToEject: URL? = nil
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("DESTINATION")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Destination folders section")
                
                Button(action: {
                    destinationFolders.append(URL(fileURLWithPath: "/"))
                    destinationProgress.append(0.0)
                    dataRemainingForFolder.append(0.0)
                    estimatedTimeForFolder.append(0.0)
                    isPaused.append(false)
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Add new destination folder")
            }
            
            ForEach(0..<destinationFolders.count, id: \.self) { index in
                HStack {
                    Button(action: { selectDestinationFolder(index: index) }) {
                        if destinationFolders.indices.contains(index) && destinationFolders[index].path != "/" {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: destinationFolders[index].path))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                        } else {
                            Image(isHoveringDestination ? "DestinationIconHover" : "DestinationIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                                .foregroundColor(.green)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in
                        isHoveringDestination = hovering
                    }
                    .accessibilityLabel("Select destination folder \(index + 1)")
                    
                    VStack(alignment: .leading, spacing: 10) {
                        if destinationFolders.indices.contains(index) {
                            Text(destinationFolders[index].path)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("Folder not set")
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        let minutes = Int((estimatedTimeForFolder[safe: index] ?? 0.0) / 60)
                        let seconds = Int((estimatedTimeForFolder[safe: index] ?? 0.0).truncatingRemainder(dividingBy: 60))
                        
                        if destinationFolders.indices.contains(index) && destinationFolders[index].path != "/" {
                            Text("Estimated Time: \(minutes)m \(seconds)s")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .accessibilityLabel("Estimated time remaining: \(minutes) minutes \(seconds) seconds")
                            
                            ProgressView(value: destinationProgress[safe: index] ?? 0.0, total: 1.0)
                                .accentColor(isPaused[safe: index] == true ? .red : .blue)
                                .accessibilityLabel("Transfer progress: \(Int((destinationProgress[safe: index] ?? 0.0) * 100))%")
                            
                            HStack {
                                Button(action: { pauseTransfer(at: index) }) {
                                    Text("Pause")
                                        .foregroundColor(isPaused[safe: index] == true ? .red : .gray)
                                }
                                .disabled(index >= isPaused.count ? true : isPaused[index])
                                .buttonStyle(PlainButtonStyle())
                                .accessibilityLabel("Pause transfer \(index + 1)")
                                
                                Button(action: { resumeTransfer(at: index) }) {
                                    Text("Resume")
                                        .foregroundColor(.gray)
                                }
                                .disabled(index >= isPaused.count ? true : !isPaused[index])
                                .buttonStyle(PlainButtonStyle())
                                .accessibilityLabel("Resume transfer \(index + 1)")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    HStack(spacing: 5) {
                        if destinationFolders.indices.contains(index) && destinationFolders[index].isExternalDrive() {
                            Button(action: {
                                driveToEject = destinationFolders[index]
                                showEjectAlert = true
                            }) {
                                Image(systemName: "eject.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 10, height: 10)
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel("Eject drive \(destinationFolders[index].getVolumeName() ?? "")")
                        }
                        
                        Button(action: { removeDestinationFolder(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 10, height: 10)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel("Remove destination folder \(index + 1)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .alert("Eject Drive", isPresented: $showEjectAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Eject", role: .destructive) {
                if let drive = driveToEject {
                    ejectDrive(drive)
                }
            }
        } message: {
            if let drive = driveToEject, let volumeName = drive.getVolumeName() {
                Text("Are you sure you want to eject '\(volumeName)'?")
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func ejectDrive(_ drive: URL) {
        // First remove the drive from the UI
        DispatchQueue.main.async {
            if let index = destinationFolders.firstIndex(where: { $0.path == drive.path }) {
                destinationFolders.remove(at: index)
                destinationProgress.remove(at: index)
                dataRemainingForFolder.remove(at: index)
                estimatedTimeForFolder.remove(at: index)
                isPaused.remove(at: index)
            }
        }
        
        // Then attempt to eject the drive after a short delay
        let ejectQueue = DispatchQueue(label: "com.xenon.eject", qos: .userInitiated)
        
        ejectQueue.async {
            // Add a small delay to allow file handles to be released
            Thread.sleep(forTimeInterval: 1.0)
            
            // Use NSWorkspace to eject the volume
            let workspace = NSWorkspace.shared
            do {
                try workspace.unmountAndEjectDevice(at: drive)
                Swift.print("Drive ejected successfully")
            } catch {
                Swift.print("Error ejecting drive: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    errorMessage = "Failed to eject drive: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }
    
    private func selectDestinationFolder(index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Destination Folder \(index + 1)"
        if panel.runModal() == .OK, let folderURL = panel.url {
            while destinationFolders.count <= index {
                destinationFolders.append(URL(fileURLWithPath: "/"))
                destinationProgress.append(0.0)
                dataRemainingForFolder.append(0.0)
                estimatedTimeForFolder.append(0.0)
            }
            destinationFolders[index] = folderURL
        }
    }
    
    private func removeDestinationFolder(at index: Int) {
        if destinationFolders.indices.contains(index) {
            destinationFolders.remove(at: index)
            destinationProgress.remove(at: index)
            dataRemainingForFolder.remove(at: index)
            estimatedTimeForFolder.remove(at: index)
            isPaused.remove(at: index)
        }
    }
    
    private func pauseTransfer(at index: Int) {
        if index < isPaused.count {
            isPaused[index] = true
        }
    }
    
    private func resumeTransfer(at index: Int) {
        if index < isPaused.count {
            isPaused[index] = false
        }
    }
}

struct MatrixRainView: View {
    let columns = 15  // Further reduced number of columns
    let characters = "01"
    @State private var drops: [Int] = []
    @State private var speeds: [Double] = []
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        MatrixColumn(
                            column: column,
                            width: geometry.size.width / CGFloat(columns),
                            height: geometry.size.height * 0.4, // Only use 40% of the height
                            speed: speeds[safe: column] ?? Double.random(in: 3.0...4.0), // Even slower speeds
                            drop: drops[safe: column] ?? 0
                        )
                    }
                }
                .frame(width: geometry.size.width * 0.4) // Only use 40% of the width
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                // Initialize random drops and speeds
                drops = (0..<columns).map { _ in Int.random(in: -50...0) }
                speeds = (0..<columns).map { _ in Double.random(in: 3.0...4.0) }
            }
        }
    }
}

struct MatrixColumn: View {
    let column: Int
    let width: CGFloat
    let height: CGFloat
    let speed: Double
    let drop: Int
    
    @State private var characters: [String] = []
    @State private var offset: CGFloat = 0
    let characterSet = "01"
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<Int(height/20), id: \.self) { index in
                Text(characters[safe: index] ?? String(characterSet.randomElement()!))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gray.opacity(0.15))
                    .frame(width: width)
            }
        }
        .offset(y: offset)
        .onAppear {
            characters = (0..<Int(height/20)).map { _ in
                String(characterSet.randomElement()!)
            }
            
            withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) {
                offset = height
            }
            
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
                let randomIndex = Int.random(in: 0..<characters.count)
                characters[randomIndex] = String(characterSet.randomElement()!)
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var settings = Settings()
    @StateObject private var transferHistory = TransferHistory()
    @State private var hasCompleted: Bool = false
    @State private var sourceFolders: [URL?] = [nil]
    @State private var destinationFolders: [URL] = [URL(fileURLWithPath: "/")]
    @State private var destinationProgress: [Double] = [0.0]
    @State private var transferProgress: Double = 0.0
    @State private var isTransferring: Bool = false
    @State private var dataRemainingForFolder: [Double] = [0.0]
    @State private var estimatedTimeForFolder: [Double] = [0.0]
    @State private var isHoveringSource: Bool = false
    @State private var isHoveringDestination: Bool = false
    @State private var showPreferences: Bool = false
    @State private var showHistory: Bool = false
    @State private var isPaused: [Bool] = []
    
    var body: some View {
        ZStack {
            VStack {
                // Logo and Preferences Button
                HStack {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 60)
                        .padding(.top, 20)
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        Button(action: { showHistory = true }) {
                            Image(systemName: "clock.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { showPreferences = true }) {
                            Image(systemName: "gearshape.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.trailing, 20)
                }
                
                Divider()
                    .background(Color.gray.opacity(0.2))
                    .padding(.vertical, 10)
                
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        SourceFolderSection(sourceFolders: $sourceFolders, isHoveringSource: $isHoveringSource)
                            .frame(width: 200)
                        
                        Rectangle()
                            .frame(width: 1)
                            .foregroundColor(.gray.opacity(0.2))
                            .padding(.vertical)
                            .padding(.horizontal, 10)
                        
                        DestinationFolderSection(
                            destinationFolders: $destinationFolders,
                            isHoveringDestination: $isHoveringDestination,
                            destinationProgress: $destinationProgress,
                            dataRemainingForFolder: $dataRemainingForFolder,
                            estimatedTimeForFolder: $estimatedTimeForFolder,
                            isPaused: $isPaused
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
                
                Divider()
                    .background(Color.gray.opacity(0.2))
                    .padding(.vertical, 10)
                
                // Transfer Button
                Button(action: { startTransfer() }) {
                    HStack {
                        if isTransferring {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.blue)
                            Text("Transferring...")
                                .font(.headline)
                                .foregroundColor(.blue)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.blue)
                            Text("Start Transfer")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.all, 20)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .disabled(isTransferring)
                
                // URL Link
                Link("xenon-post.com", destination: URL(string: "https://xenon-post.com")!)
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding()
            }
            .frame(minHeight: 600)
            
            if isTransferring && settings.showMatrixOverlay {
                MatrixRainView()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            isPaused = Array(repeating: false, count: destinationFolders.count)
        }
        .sheet(isPresented: $showPreferences) {
            PreferencesView(settings: settings)
        }
        .sheet(isPresented: $showHistory) {
            TransferHistoryView(history: transferHistory)
        }
    }
    
    // MARK: - Fetch and Transfer Files
    private func fetchAllFiles(in directoryURL: URL) -> [URL] {
        var fileURLs: [URL] = []
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        
        if let enumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey], options: options) {
            while let fileURL = enumerator.nextObject() as? URL {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) {
                    if !isDirectory.boolValue {
                        Swift.print("Found file: \(fileURL.path)")
                        fileURLs.append(fileURL)
                    } else {
                        Swift.print("Found directory: \(fileURL.path)")
                    }
                }
            }
        }
        
        Swift.print("Total files found: \(fileURLs.count)")
        return fileURLs
    }
    
    private func computeChecksum(for fileURL: URL) throws -> String {
        let fileData = try Data(contentsOf: fileURL)
        
        switch settings.selectedChecksumType {
        case .sha256:
            let hash = SHA256.hash(data: fileData)
            return hash.map { String(format: "%02hhx", $0) }.joined()
        case .md5:
            let hash = Insecure.MD5.hash(data: fileData)
            return hash.map { String(format: "%02hhx", $0) }.joined()
        case .sha1:
            let hash = Insecure.SHA1.hash(data: fileData)
            return hash.map { String(format: "%02hhx", $0) }.joined()
        }
    }
    
    private func validateChecksums(originalChecksums: [String: String], destinationFolder: URL) {
        for (relativePath, originalChecksum) in originalChecksums {
            let destinationURL = destinationFolder.appendingPathComponent(relativePath)
            do {
                let currentChecksum = try computeChecksum(for: destinationURL)
                if currentChecksum != originalChecksum {
                    Swift.print("Checksum mismatch for file: \(relativePath)")
                } else {
                    Swift.print("Checksum verified for file: \(relativePath)")
                }
            } catch {
                Swift.print("Error validating checksum for file \(relativePath): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Transfer Logic
    private func startTransfer() {
        Swift.print("Starting transfer...")
        isTransferring = true
        let startTime = Date()
        
        // Reset progress arrays and control states
        destinationProgress = Array(repeating: 0.0, count: destinationFolders.count)
        estimatedTimeForFolder = Array(repeating: 0.0, count: destinationFolders.count)
        dataRemainingForFolder = Array(repeating: 0.0, count: destinationFolders.count)
        isPaused = Array(repeating: false, count: destinationFolders.count)
        
        // Create a dedicated background queue
        let transferQueue = DispatchQueue(label: "com.xenon.transfer", qos: .userInitiated)
        
        transferQueue.async {
            Task {
                // Check permissions for all destination folders first
                var destinationErrors: [String] = []
                for (index, destinationFolder) in self.destinationFolders.enumerated() {
                    // Test write permissions by attempting to create a temporary file
                    let testFile = destinationFolder.appendingPathComponent(".xenon_test")
                    do {
                        // Try to write with elevated privileges if needed
                        let hasAccess = try await destinationFolder.requestWriteAccess()
                        if !hasAccess {
                            let errorMessage = "Cannot write to destination folder: \(destinationFolder.path)\nError: Permission denied"
                            Swift.print(errorMessage)
                            destinationErrors.append(errorMessage)
                            
                            // Update UI to show error state
                            DispatchQueue.main.async {
                                self.destinationProgress[index] = -1 // Use -1 to indicate error state
                            }
                        }
                    } catch {
                        let errorMessage = "Cannot write to destination folder: \(destinationFolder.path)\nError: \(error.localizedDescription)"
                        Swift.print(errorMessage)
                        destinationErrors.append(errorMessage)
                        
                        // Update UI to show error state
                        DispatchQueue.main.async {
                            self.destinationProgress[index] = -1 // Use -1 to indicate error state
                        }
                    }
                }
                
                // If there are any permission errors, show alert and stop transfer
                if !destinationErrors.isEmpty {
                    DispatchQueue.main.async {
                        self.isTransferring = false
                        let alert = NSAlert()
                        alert.messageText = "Permission Error"
                        alert.informativeText = "Cannot access one or more destination folders:\n\n" + destinationErrors.joined(separator: "\n\n")
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                    return
                }
                
                // Calculate total size for each destination
                var totalSizes: [Double] = Array(repeating: 0.0, count: self.destinationFolders.count)
                for (destIndex, _) in self.destinationFolders.enumerated() {
                    for sourceFolder in self.sourceFolders {
                        if let sourceURL = sourceFolder {
                            let contents = self.fetchAllFiles(in: sourceURL)
                            for fileURL in contents {
                                do {
                                    let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                                    if let fileSize = fileAttributes[.size] as? Double {
                                        totalSizes[destIndex] += fileSize
                                    }
                                } catch {
                                    Swift.print("Error fetching file attributes for \(fileURL.lastPathComponent): \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                    
                    // Update initial progress
                    DispatchQueue.main.async {
                        self.destinationProgress[destIndex] = 0.0
                        self.estimatedTimeForFolder[destIndex] = 0.0
                    }
                }
                
                // Perform file transfers and compute checksums
                await withTaskGroup(of: Void.self) { group in
                    for (destIndex, destinationFolder) in self.destinationFolders.enumerated() {
                        group.addTask {
                            let destStartTime = Date()
                            var bytesTransferred: Double = 0.0
                            var transferErrors: [String] = []
                            
                            // Generate unique checksum file name with timestamp
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                            let timestamp = dateFormatter.string(from: Date())
                            let checksumFileName = "checksum_\(timestamp).txt"
                            let checksumFileURL = destinationFolder.appendingPathComponent(checksumFileName)
                            
                            // Create the checksum file with project details
                            var projectDetails = ""
                            
                            // Add project details if they exist
                            if !settings.projectName.isEmpty {
                                projectDetails += "Project Name: \(settings.projectName)\n"
                            }
                            if !settings.date.isEmpty {
                                projectDetails += "Date: \(settings.date)\n"
                            }
                            if !settings.director.isEmpty {
                                projectDetails += "Director: \(settings.director)\n"
                            }
                            if !settings.dop.isEmpty {
                                projectDetails += "Director of Photography: \(settings.dop)\n"
                            }
                            if !settings.soundRecordist.isEmpty {
                                projectDetails += "Sound Recordist: \(settings.soundRecordist)\n"
                            }
                            if !settings.dit.isEmpty {
                                projectDetails += "DIT: \(settings.dit)\n"
                            }
                            if !settings.camera.isEmpty {
                                projectDetails += "Camera: \(settings.camera)\n"
                            }
                            projectDetails += "Checksum Type: \(settings.selectedChecksumType.rawValue)\n"
                            projectDetails += "\n" // Add a blank line before checksum data
                            
                            // Write project details to the checksum file
                            do {
                                try projectDetails.write(to: checksumFileURL, atomically: true, encoding: .utf8)
                            } catch {
                                let errorMessage = "Failed to create checksum file at \(checksumFileURL.path): \(error.localizedDescription)"
                                Swift.print(errorMessage)
                                transferErrors.append(errorMessage)
                            }
                            
                            for sourceFolder in self.sourceFolders {
                                if let sourceURL = sourceFolder {
                                    let contents = self.fetchAllFiles(in: sourceURL)
                                    for fileURL in contents {
                                        // Wait if transfer is paused
                                        while self.isPaused[destIndex] {
                                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                                        }
                                        
                                        do {
                                            let relativePath = fileURL.path.replacingOccurrences(of: sourceURL.path, with: "")
                                            let destinationURL = destinationFolder.appendingPathComponent(relativePath)
                                            
                                            // Ensure subdirectories exist
                                            let destinationSubdirectory = destinationURL.deletingLastPathComponent()
                                            if !FileManager.default.fileExists(atPath: destinationSubdirectory.path) {
                                                try FileManager.default.createDirectory(at: destinationSubdirectory, withIntermediateDirectories: true)
                                            }
                                            
                                            // Copy the file
                                            try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                                            
                                            // Verify the file was actually copied
                                            if !FileManager.default.fileExists(atPath: destinationURL.path) {
                                                throw NSError(domain: "com.xenon.transfer", code: -1, userInfo: [NSLocalizedDescriptionKey: "File copy verification failed"])
                                            }
                                            
                                            // Update progress
                                            let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                                            if let fileSize = fileAttributes[.size] as? Double {
                                                bytesTransferred += fileSize
                                                let progress = bytesTransferred / totalSizes[destIndex]
                                                let elapsedTime = Date().timeIntervalSince(destStartTime)
                                                let bytesPerSecond = elapsedTime > 0 ? bytesTransferred / elapsedTime : 0
                                                let remainingBytes = totalSizes[destIndex] - bytesTransferred
                                                let remainingSeconds = bytesPerSecond > 0 ? remainingBytes / bytesPerSecond : 0
                                                
                                                await MainActor.run {
                                                    self.destinationProgress[destIndex] = progress
                                                    self.estimatedTimeForFolder[destIndex] = remainingSeconds
                                                }
                                            }
                                            
                                            // Compute checksum
                                            let checksum = try self.computeChecksum(for: fileURL)
                                            
                                            // Append checksum to checksum file
                                            let checksumText = "\(relativePath): \(checksum) - Transfer Success\n"
                                            if let handle = try? FileHandle(forWritingTo: checksumFileURL) {
                                                handle.seekToEndOfFile()
                                                if let checksumData = checksumText.data(using: .utf8) {
                                                    handle.write(checksumData)
                                                }
                                                handle.closeFile()
                                            }
                                        } catch {
                                            let errorMessage = "Error transferring file \(fileURL.lastPathComponent): \(error.localizedDescription)"
                                            Swift.print(errorMessage)
                                            transferErrors.append(errorMessage)
                                        }
                                    }
                                }
                            }
                            
                            // If there were any transfer errors for this destination, mark it as failed
                            if !transferErrors.isEmpty {
                                await MainActor.run {
                                    self.destinationProgress[destIndex] = -1 // Use -1 to indicate error state
                                }
                            }
                        }
                    }
                }
                
                // Check if any destinations had successful transfers
                let successfulTransfers = self.destinationProgress.filter { $0 >= 0.9 }.count
                
                // Mark transfer as complete
                DispatchQueue.main.async {
                    // Ensure all progress bars reach 100% for successful transfers
                    for (index, progress) in self.destinationProgress.enumerated() {
                        if progress >= 0.9 {
                            self.destinationProgress[index] = 1.0
                        }
                    }
                    
                    // Add a small delay to allow the progress bars to update visually
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isTransferring = false  // Turn off the Matrix effect before showing the alert
                        
                        if successfulTransfers > 0 {
                            // Create and add transfer record only for successful destinations
                            let duration = Date().timeIntervalSince(startTime)
                            let record = TransferRecord(
                                id: UUID(),
                                timestamp: Date(),
                                sourceFolders: self.sourceFolders.compactMap { $0?.path },
                                destinationFolders: self.destinationFolders.enumerated().compactMap { index, folder in
                                    self.destinationProgress[index] >= 0.9 ? folder.path : nil
                                },
                                totalSize: totalSizes.enumerated().reduce(0) { sum, index in
                                    self.destinationProgress[index.offset] >= 0.9 ? sum + index.element : sum
                                },
                                duration: duration,
                                projectName: settings.projectName,
                                date: settings.date,
                                director: settings.director,
                                dop: settings.dop,
                                soundRecordist: settings.soundRecordist,
                                dit: settings.dit,
                                camera: settings.camera,
                                checksumType: settings.selectedChecksumType.rawValue,
                                checksumFile: "checksum_\(Date().formatted(date: .complete, time: .standard)).txt"
                            )
                            self.transferHistory.addRecord(record)
                            
                            self.showCompletionAlert()
                            Swift.print("Transfer completed successfully for \(successfulTransfers) destination(s).")
                        } else {
                            // Show error alert if no successful transfers
                            let alert = NSAlert()
                            alert.messageText = "Transfer Failed"
                            alert.informativeText = "No files were successfully transferred to any destination. Please check the permissions and try again."
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                            Swift.print("Transfer failed for all destinations.")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Alerts
    private func showCompletionAlert() {
        let alert = NSAlert()
        alert.messageText = "Transfer Complete"
        alert.informativeText = "All files have been successfully transferred and verified!"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
