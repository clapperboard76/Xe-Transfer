import SwiftUI
import CryptoKit
import Security
import ServiceManagement
import UniformTypeIdentifiers

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
    @State private var isTargeted: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("SOURCE")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Source folders section")
                
                Button(action: { sourceFolders.append(nil) }) {
                    Image(systemName: "plus.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
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
                    .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                        handleSourceDrop(providers: providers, index: index)
                        return true
                    }
                    
                    if let folder = sourceFolders[safe: index], let folderPath = folder?.path {
                        Text(folderPath)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Button(action: { selectSourceFolder(index: index) }) {
                            Text("Select Source")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                            handleSourceDrop(providers: providers, index: index)
                            return true
                        }
                    }
                    
                    HStack(spacing: 5) {
                        if let folder = sourceFolders[safe: index], let folderURL = folder, folderURL.isExternalDrive() {
                            Button(action: {
                                driveToEject = folderURL
                                showEjectAlert = true
                            }) {
                                Image(systemName: "eject.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel("Eject drive \(folderURL.getVolumeName() ?? "")")
                        }
                        
                        Button(action: { removeSourceFolder(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.gray)
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
    
    private func handleSourceDrop(providers: [NSItemProvider], index: Int) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                    if let data = data as? Data,
                       let urlString = String(data: data, encoding: .utf8),
                       let url = URL(string: urlString) {
                        DispatchQueue.main.async {
                            var isDirectory: ObjCBool = false
                            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                                while sourceFolders.count <= index {
                                    sourceFolders.append(nil)
                                }
                                sourceFolders[index] = url
                            }
                        }
                    }
                }
            }
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
    @State private var isTargeted: Bool = false
    
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
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Add new destination folder")
            }
            
            ForEach(0..<destinationFolders.count, id: \.self) { index in
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 10) {
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
                        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                            handleDestinationDrop(providers: providers, index: index)
                            return true
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        if destinationFolders.indices.contains(index) && destinationFolders[index].path != "/" {
                            Text(destinationFolders[index].path)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            HStack {
                                Button(action: { selectDestinationFolder(index: index) }) {
                                    Text("Select Destination")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                                    handleDestinationDrop(providers: providers, index: index)
                                    return true
                                }
                            }
                            .frame(height: 50, alignment: .center)
                        }
                        
                        if destinationFolders.indices.contains(index) && destinationFolders[index].path != "/" {
                            let minutes = Int((estimatedTimeForFolder[safe: index] ?? 0.0) / 60)
                            let seconds = Int((estimatedTimeForFolder[safe: index] ?? 0.0).truncatingRemainder(dividingBy: 60))
                            
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
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel("Eject drive \(destinationFolders[index].getVolumeName() ?? "")")
                        }
                        
                        Button(action: { removeDestinationFolder(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.gray)
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
    
    private func handleDestinationDrop(providers: [NSItemProvider], index: Int) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                    if let data = data as? Data,
                       let urlString = String(data: data, encoding: .utf8),
                       let url = URL(string: urlString) {
                        DispatchQueue.main.async {
                            var isDirectory: ObjCBool = false
                            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                                while destinationFolders.count <= index {
                                    destinationFolders.append(URL(fileURLWithPath: "/"))
                                    destinationProgress.append(0.0)
                                    dataRemainingForFolder.append(0.0)
                                    estimatedTimeForFolder.append(0.0)
                                }
                                destinationFolders[index] = url
                            }
                        }
                    }
                }
            }
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
    @State private var showSpeedTest: Bool = false
    @State private var isPaused: [Bool] = []
    @State private var skippedFiles: Int = 0
    @State private var bytesTransferred: Int64 = 0
    @State private var currentFile: String = ""
    @State private var transferSpeed: Double = 0.0
    @State private var startTime: Date?
    
    private let fileManager = FileManager.default
    private let defaultOperationTimeout: TimeInterval = 60 // 1 minute default timeout
    private let largeFileOperationTimeout: TimeInterval = 1800 // 30 minutes for large files
    
    private enum FileTransferError: Error {
        case operationTimeout
        case fileOperationFailed(Error)
    }
    
    private func updateTransferSpeed() {
        // Calculate transfer speed based on bytes transferred and time elapsed
        if let startTime = startTime {
            let currentTime = Date()
            let timeElapsed = currentTime.timeIntervalSince(startTime)
            if timeElapsed > 0 {
                transferSpeed = Double(bytesTransferred) / timeElapsed / 1_000_000 // Convert to MB/s
            }
        }
    }
    
    private func fetchAllFiles(in directoryURL: URL) -> [URL] {
        var fileURLs: [URL] = []
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        
        if let enumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey], options: options) {
            while let fileURL = enumerator.nextObject() as? URL {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    if resourceValues.isRegularFile == true {
                        fileURLs.append(fileURL)
                        Swift.print("Found file: \(fileURL.path)")
                    }
                } catch {
                    Swift.print("Error reading file attributes: \(error)")
                }
            }
        }
        
        Swift.print("Total files found: \(fileURLs.count)")
        return fileURLs
    }

    // Add this helper function to properly handle relative paths
    private func getRelativePath(for fileURL: URL, relativeTo baseURL: URL) -> String {
        let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
        return String(fileURL.path.dropFirst(basePath.count))
    }
    
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
                        Button(action: { showSpeedTest = true }) {
                            Image(systemName: "gauge")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Run Speed Test")
                        
                        Button(action: { showHistory = true }) {
                            Image(systemName: "clock.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { showPreferences = true }) {
                            Image(systemName: "gearshape.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.trailing, 20)
                }
                
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        SourceFolderSection(sourceFolders: $sourceFolders, isHoveringSource: $isHoveringSource)
                            .frame(width: 200)
                            .padding(.trailing, 10)
                        
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
                    .padding(.top, 20)
                    .padding(.bottom, sourceFolders.count == 1 && destinationFolders.count == 1 ? 10 : 20)
                }
                .frame(minHeight: sourceFolders.count == 1 && destinationFolders.count == 1 ? 120 : 200)
                .frame(maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                
                // Transfer Button
                Button(action: { startTransfer() }) {
                    HStack(spacing: 12) {
                        if isTransferring {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundColor(.white)
                            Text("Transferring...")
                                .font(.body)
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundColor(.white)
                            Text("Start Transfer")
                                .font(.body)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(isTransferring ? Color.orange : Color.blue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isTransferring)
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity)
            
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
        .sheet(isPresented: $showSpeedTest) {
            SpeedTestView(sourceFolders: sourceFolders, destinationFolders: destinationFolders)
        }
    }
    
    private func performWithTimeout<T>(_ operation: @escaping () async throws -> T, timeout: TimeInterval? = nil) async throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
        let operationTimeout = timeout ?? defaultOperationTimeout
        
        Task {
            do {
                let value = try await operation()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        
        if semaphore.wait(timeout: .now() + operationTimeout) == .timedOut {
            throw FileTransferError.operationTimeout
        }
        
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw FileTransferError.fileOperationFailed(error)
        case .none:
            throw FileTransferError.fileOperationFailed(NSError(domain: "FileTransferManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error occurred"]))
        }
    }
    
    private func copyFileWithTimeout(from source: URL, to destination: URL) async throws {
        try await performWithTimeout {
            try await self.copyFile(from: source, to: destination)
        }
    }
    
    private func createDirectoryWithTimeout(at url: URL) async throws {
        try await performWithTimeout {
            try self.fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    private func fileExistsWithTimeout(at path: String) async throws -> Bool {
        try await performWithTimeout {
            self.fileManager.fileExists(atPath: path)
        }
    }
    
    private func copyFileAndCalculateChecksum(from source: URL, to destination: URL) async throws -> String {
        do {
            // Get file size for timeout determination
            let fileSize = try attributesWithTimeout(at: source.path)[.size] as? Int64 ?? 0
            let timeout = getTimeoutForFile(size: fileSize)
            
            // Update current file name for progress tracking
            await MainActor.run {
                self.currentFile = source.lastPathComponent
            }
            
            // Copy file with timeout and progress tracking
            try await performWithTimeout({
                try await self.copyFile(from: source, to: destination)
            }, timeout: timeout)
            
            // Calculate checksum with timeout
            return try await performWithTimeout({
                try await self.computeChecksum(for: destination)
            }, timeout: timeout)
        } catch {
            handleTransferError(error, for: source.lastPathComponent)
            throw error
        }
    }
    
    private func getTimeoutForFile(size: Int64) -> TimeInterval {
        // Use longer timeout for files larger than 500MB
        return size > 500 * 1024 * 1024 ? largeFileOperationTimeout : defaultOperationTimeout
    }
    
    private func attributesWithTimeout(at path: String) throws -> [FileAttributeKey: Any] {
        try fileManager.attributesOfItem(atPath: path)
    }
    
    private func handleTransferError(_ error: Error, for file: String) {
        DispatchQueue.main.async {
            let errorMessage: String
            switch error {
            case FileTransferError.operationTimeout:
                errorMessage = "Operation timed out while processing '\(file)'. The drive might be slow or unresponsive."
            case FileTransferError.fileOperationFailed(let underlyingError):
                errorMessage = "Failed to process '\(file)': \(underlyingError.localizedDescription)"
            default:
                errorMessage = "An unexpected error occurred while processing '\(file)': \(error.localizedDescription)"
            }
            
            let alert = NSAlert()
            alert.messageText = "Transfer Error"
            alert.informativeText = errorMessage
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            
            // Log the error for debugging
            Swift.print("Transfer Error: \(errorMessage)")
        }
    }
    
    private func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        
        Swift.print("Copying file from: \(sourceURL.path)")
        Swift.print("              to: \(destinationURL.path)")
        
        // Verify source file exists
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw NSError(domain: "com.xenon.transfer",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Source file does not exist at path: \(sourceURL.path)"])
        }
        
        // Create destination directory if it doesn't exist
        let destinationDir = destinationURL.deletingLastPathComponent()
        do {
            if !fileManager.fileExists(atPath: destinationDir.path) {
                try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                Swift.print("Created destination directory: \(destinationDir.path)")
            }
        } catch {
            throw NSError(domain: "com.xenon.transfer",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create destination directory: \(error.localizedDescription)"])
        }
        
        // Get file size for progress tracking
        let fileSize: Int64
        do {
            let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
            fileSize = attributes[.size] as? Int64 ?? 0
        } catch {
            throw NSError(domain: "com.xenon.transfer",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to get source file attributes: \(error.localizedDescription)"])
        }
        
        // If destination exists and sizes match, skip the file
        if fileManager.fileExists(atPath: destinationURL.path) {
            if let destAttributes = try? fileManager.attributesOfItem(atPath: destinationURL.path),
               let destSize = destAttributes[.size] as? Int64,
               destSize == fileSize {
                Swift.print("File already exists with matching size, skipping: \(destinationURL.path)")
                skippedFiles += 1
                return
            }
            
            // Try to remove existing file if different size
            do {
                try fileManager.removeItem(at: destinationURL)
                Swift.print("Removed existing file at: \(destinationURL.path)")
            } catch {
                throw NSError(domain: "com.xenon.transfer",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to replace existing file: \(error.localizedDescription)"])
            }
        }
        
        // Perform the actual file copy
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            Swift.print("Successfully copied file to: \(destinationURL.path)")
        } catch {
            throw NSError(domain: "com.xenon.transfer",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to copy file: \(error.localizedDescription)"])
        }
        
        // Verify the copy was successful
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            throw NSError(domain: "com.xenon.transfer",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "File copy verification failed - destination file does not exist"])
        }
        
        // Verify file sizes match
        if let destAttributes = try? fileManager.attributesOfItem(atPath: destinationURL.path),
           let destSize = destAttributes[.size] as? Int64,
           destSize != fileSize {
            throw NSError(domain: "com.xenon.transfer",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "File size mismatch after copy - expected: \(fileSize), got: \(destSize)"])
        }
    }
    
    private func computeChecksum(for fileURL: URL) throws -> String {
        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let bufferSize = 8 * 1024 * 1024  // 8MB buffer
        
        return try autoreleasepool {
            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            defer { try? fileHandle.close() }
            
            var hasher = SHA256()
            var bytesRead: Int64 = 0
            
            while let chunk = try? fileHandle.read(upToCount: bufferSize), !chunk.isEmpty {
                hasher.update(data: chunk)
                bytesRead += Int64(chunk.count)
                
                // Add a small delay for very large files
                if fileSize > 1024 * 1024 * 1024 { // If file is larger than 1GB
                    Thread.sleep(forTimeInterval: 0.0001) // 0.1ms delay
                }
            }
            
            let digest = hasher.finalize()
            return digest.map { String(format: "%02x", $0) }.joined()
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
    
    // MARK: - Disk Space Check
    private func checkAvailableSpace(for destination: URL, requiredSize: Double) -> Bool {
        do {
            let resourceValues = try destination.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let freeSpace = resourceValues.volumeAvailableCapacity {
                // Add a 10% buffer to required size
                let requiredWithBuffer = requiredSize * 1.1
                return Double(freeSpace) >= requiredWithBuffer
            }
        } catch {
            Swift.print("Error checking available space: \(error.localizedDescription)")
        }
        return false
    }
    
    private func calculateTotalSize(of url: URL) -> Double {
        var totalSize: Double = 0
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: options) {
            while let fileURL = enumerator.nextObject() as? URL {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Double(fileSize)
                }
            }
        }
        return totalSize
    }

    // MARK: - File Existence Check
    private func checkExistingFiles(sourceURL: URL, destinationURL: URL) -> (existingFiles: [String], newFiles: [String]) {
        var existingFiles: [String] = []
        var newFiles: [String] = []
        
        let sourceFiles = fetchAllFiles(in: sourceURL)
        for sourceFile in sourceFiles {
            let relativePath = getRelativePath(for: sourceFile, relativeTo: sourceURL)
            let destinationFile = destinationURL.appendingPathComponent(relativePath)
            
            if FileManager.default.fileExists(atPath: destinationFile.path) {
                existingFiles.append(relativePath)
            } else {
                newFiles.append(relativePath)
            }
        }
        
        return (existingFiles, newFiles)
    }
    
    private func showExistingFilesWarning(existingFiles: [String], newFiles: [String], completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Existing Files Found"
            alert.informativeText = """
                Some files already exist in one or more destination folders:
                
                Existing files: \(existingFiles.count)
                New files to transfer: \(newFiles.count)
                
                Transfer will proceed as follows:
                • Destinations with existing files will only receive missing files
                • Destinations without any files will receive all files
                
                Would you like to:
                1. Proceed with transfer
                2. Cancel
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Proceed with transfer")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            completion(response == .alertFirstButtonReturn)
        }
    }

    // MARK: - Transfer Logic
    private func verifyDestinationPermissions() async throws -> Bool {
        for destination in destinationFolders {
            let destinationPath = destination.path
            
            // Skip the default "/" path
            if destinationPath == "/" {
                continue
            }
            
            // Check if directory exists
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: destinationPath, isDirectory: &isDirectory) {
                if !isDirectory.boolValue {
                    // Path exists but is not a directory
                    await showPermissionAlert(message: "Selected path is not a directory: \(destinationPath)")
                    return false
                }
            } else {
                // Directory doesn't exist, try to create it
                do {
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                } catch {
                    await showPermissionAlert(message: "Cannot create directory at \(destinationPath): \(error.localizedDescription)")
                    return false
                }
            }
            
            // Check write permissions
            if !FileManager.default.isWritableFile(atPath: destinationPath) {
                await showPermissionAlert(message: """
                    No write permission for destination folder: \(destinationPath)
                    
                    To fix this:
                    1. Open Finder
                    2. Navigate to the folder
                    3. Right-click and select "Get Info"
                    4. Under "Sharing & Permissions":
                       - Click the lock icon to make changes
                       - Ensure your user has "Read & Write" access
                    5. Click "Apply to enclosed items" if needed
                    """)
                return false
            }
            
            // Try to create a test file
            let testFile = destination.appendingPathComponent(".xe_test")
            do {
                try "test".write(to: testFile, atomically: true, encoding: .utf8)
                try FileManager.default.removeItem(at: testFile)
            } catch {
                await showPermissionAlert(message: "Cannot write to destination folder \(destinationPath): \(error.localizedDescription)")
                return false
            }
        }
        return true
    }
    
    private func showPermissionAlert(message: String) async {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "Permission Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func startTransfer() {
        Task { @MainActor in
            Swift.print("Starting transfer...")
            isTransferring = true
            startTime = Date()
            
            // Reset progress arrays and control states
            destinationProgress = Array(repeating: 0.0, count: destinationFolders.count)
            estimatedTimeForFolder = Array(repeating: 0.0, count: destinationFolders.count)
            dataRemainingForFolder = Array(repeating: 0.0, count: destinationFolders.count)
            isPaused = Array(repeating: false, count: destinationFolders.count)
            
            // Check permissions first
            do {
                let hasPermissions = try await verifyDestinationPermissions()
                if !hasPermissions {
                    isTransferring = false
                    return
                }
            } catch {
                isTransferring = false
                let alert = NSAlert()
                alert.messageText = "Permission Error"
                alert.informativeText = "Failed to verify permissions: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }
            
            // Create a dedicated task for the transfer
            Task.detached(priority: .userInitiated) {
                // First, collect all source files and check for existing files
                var allSourceFiles: [(sourceURL: URL, relativePath: String)] = []
                var existingFiles: [String] = []
                var newFiles: [String] = []
                
                // Collect all source files first
                for sourceFolder in self.sourceFolders {
                    if let sourceURL = sourceFolder {
                        let sourceFiles = self.fetchAllFiles(in: sourceURL)
                        for sourceFile in sourceFiles {
                            let relativePath = self.getRelativePath(for: sourceFile, relativeTo: sourceURL)
                            Swift.print("Processing file: \(sourceFile.path) with relative path: \(relativePath)")
                            allSourceFiles.append((sourceFile, relativePath))
                        }
                    }
                }
                
                // Check each destination folder for existing files
                for destinationFolder in self.destinationFolders {
                    for (sourceFile, relativePath) in allSourceFiles {
                        let destinationFile = destinationFolder.appendingPathComponent(relativePath)
                        if FileManager.default.fileExists(atPath: destinationFile.path) {
                            if !existingFiles.contains(relativePath) {
                                existingFiles.append(relativePath)
                            }
                        } else {
                            if !newFiles.contains(relativePath) {
                                newFiles.append(relativePath)
                            }
                        }
                    }
                }
                
                // Prepare files to transfer based on user's decision
                var filesToTransfer: [(sourceURL: URL, relativePath: String, destinations: [URL])] = []
                
                // For each source file, determine which destinations need it
                for (sourceFile, relativePath) in allSourceFiles {
                    var destinationsNeedingFile: [URL] = []
                    
                    // Check each destination folder
                    for destinationFolder in self.destinationFolders {
                        let destinationFile = destinationFolder.appendingPathComponent(relativePath)
                        if !FileManager.default.fileExists(atPath: destinationFile.path) {
                            destinationsNeedingFile.append(destinationFolder)
                        }
                    }
                    
                    // If any destination needs this file, add it to transfer list
                    if !destinationsNeedingFile.isEmpty {
                        filesToTransfer.append((sourceFile, relativePath, destinationsNeedingFile))
                    }
                }
                
                // If there are existing files, show warning and wait for user decision
                if !existingFiles.isEmpty {
                    let shouldProceed = await withCheckedContinuation { continuation in
                        Task { @MainActor in
                            self.showExistingFilesWarning(existingFiles: existingFiles, newFiles: newFiles) { shouldProceed in
                                if !shouldProceed {
                                    self.isTransferring = false
                                }
                                continuation.resume(returning: shouldProceed)
                            }
                        }
                    }
                    
                    if !shouldProceed {
                        return
                    }
                }
                
                if filesToTransfer.isEmpty {
                    await MainActor.run {
                        self.isTransferring = false
                        let alert = NSAlert()
                        alert.messageText = "No Files to Transfer"
                        alert.informativeText = "All files already exist in the destination folders."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                    return
                }
                
                // Calculate total size for each destination
                var totalSizes: [Double] = Array(repeating: 0.0, count: self.destinationFolders.count)
                
                for (sourceFile, _, destinations) in filesToTransfer {
                    do {
                        let fileAttributes = try FileManager.default.attributesOfItem(atPath: sourceFile.path)
                        if let fileSize = fileAttributes[.size] as? Double {
                            for destination in destinations {
                                if let destIndex = self.destinationFolders.firstIndex(where: { $0.path == destination.path }) {
                                    totalSizes[destIndex] += fileSize
                                }
                            }
                        }
                    } catch {
                        await MainActor.run {
                            Swift.print("Error fetching file attributes for \(sourceFile.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                }
                
                // Check available space for each destination
                var spaceErrors: [String] = []
                for (index, destination) in self.destinationFolders.enumerated() {
                    if totalSizes[index] > 0 && !self.checkAvailableSpace(for: destination, requiredSize: totalSizes[index]) {
                        let formatter = ByteCountFormatter()
                        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
                        formatter.countStyle = .file
                        let requiredSpace = formatter.string(fromByteCount: Int64(totalSizes[index]))
                        spaceErrors.append("Not enough space in \(destination.path)\nRequired: \(requiredSpace)")
                        await MainActor.run {
                            self.destinationProgress[index] = -1
                        }
                    }
                }
                
                if !spaceErrors.isEmpty {
                    await MainActor.run {
                        self.isTransferring = false
                        let alert = NSAlert()
                        alert.messageText = "Insufficient Disk Space"
                        alert.informativeText = "The following destinations do not have enough space:\n\n" + spaceErrors.joined(separator: "\n\n")
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "Cancel")
                        alert.runModal()
                    }
                    return
                }
                
                // Perform transfers
                await withTaskGroup(of: Void.self) { group in
                    for (destIndex, destinationFolder) in self.destinationFolders.enumerated() {
                        group.addTask {
                            await self.performTransfer(
                                destIndex: destIndex,
                                destinationFolder: destinationFolder,
                                filesToTransfer: filesToTransfer,
                                totalSize: totalSizes[destIndex]
                            )
                        }
                    }
                }
                
                // Update UI on completion
                await MainActor.run {
                    self.isTransferring = false
                    self.showCompletionAlert()
                }
            }
        }
    }
    
    private func performTransfer(
        destIndex: Int,
        destinationFolder: URL,
        filesToTransfer: [(sourceURL: URL, relativePath: String, destinations: [URL])],
        totalSize: Double
    ) async {
        let startTime = Date()
        var bytesTransferred: Double = 0
        var transferErrors: [String] = []
        
        // Generate unique checksum file name with timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let checksumFileName = "checksum_\(timestamp).txt"
        let checksumFileURL = destinationFolder.appendingPathComponent(checksumFileName)
        
        // Create the checksum file with project details
        var projectDetails = """
            Transfer Details:
            ================
            Date: \(timestamp)
            
            Project Information:
            ==================
            """
        
        if !settings.projectName.isEmpty { projectDetails += "\nProject Name: \(settings.projectName)" }
        if !settings.date.isEmpty { projectDetails += "\nDate: \(settings.date)" }
        if !settings.director.isEmpty { projectDetails += "\nDirector: \(settings.director)" }
        if !settings.dop.isEmpty { projectDetails += "\nDirector of Photography: \(settings.dop)" }
        if !settings.soundRecordist.isEmpty { projectDetails += "\nSound Recordist: \(settings.soundRecordist)" }
        if !settings.dit.isEmpty { projectDetails += "\nDIT: \(settings.dit)" }
        if !settings.camera.isEmpty { projectDetails += "\nCamera: \(settings.camera)" }
        
        projectDetails += "\n\nChecksum Type: \(settings.selectedChecksumType.rawValue)"
        projectDetails += "\n\nTransfer Log:\n============="
        
        do {
            try projectDetails.write(to: checksumFileURL, atomically: true, encoding: .utf8)
        } catch {
            Swift.print("Error creating checksum file: \(error.localizedDescription)")
        }
        
        for (sourceFile, relativePath, destinations) in filesToTransfer {
            // Skip if this destination doesn't need this file
            if !destinations.contains(where: { $0.path == destinationFolder.path }) {
                continue
            }
            
            // Check if transfer is paused
            while await isPaused[destIndex] {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            let destinationFile = destinationFolder.appendingPathComponent(relativePath)
            
            do {
                // Get file size before transfer
                let fileSize = try FileManager.default.attributesOfItem(atPath: sourceFile.path)[.size] as? Double ?? 0
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
                formatter.countStyle = .file
                let formattedSize = formatter.string(fromByteCount: Int64(fileSize))
                
                // Start transfer
                let transferStartTime = Date()
                try await self.copyFile(from: sourceFile, to: destinationFile)
                
                // Calculate checksum
                let checksum = try await computeChecksum(for: destinationFile)
                
                // Calculate transfer duration
                let transferDuration = Date().timeIntervalSince(transferStartTime)
                let transferSpeed = fileSize / transferDuration / 1_000_000 // MB/s
                
                // Create success log entry
                let successLog = """
                    
                    [SUCCESS] \(relativePath)
                    Size: \(formattedSize)
                    Duration: \(String(format: "%.2f", transferDuration))s
                    Speed: \(String(format: "%.2f", transferSpeed)) MB/s
                    Checksum (\(settings.selectedChecksumType.rawValue)): \(checksum)
                    """
                
                // Append success log to file
                if let logData = successLog.data(using: .utf8) {
                    if let handle = try? FileHandle(forWritingTo: checksumFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(logData)
                        handle.closeFile()
                    }
                }
                
                // Update progress
                bytesTransferred += fileSize
                let progress = bytesTransferred / totalSize
                let elapsedTime = Date().timeIntervalSince(startTime)
                let bytesPerSecond = elapsedTime > 0 ? bytesTransferred / elapsedTime : 0
                let remainingBytes = totalSize - bytesTransferred
                let remainingSeconds = bytesPerSecond > 0 ? remainingBytes / bytesPerSecond : 0
                
                await MainActor.run {
                    self.destinationProgress[destIndex] = progress
                    self.estimatedTimeForFolder[destIndex] = remainingSeconds
                }
            } catch {
                transferErrors.append("Error transferring \(relativePath): \(error.localizedDescription)")
                Swift.print("Transfer error: \(error.localizedDescription)")
                
                // Add error log to file
                let errorLog = """
                    
                    [ERROR] \(relativePath)
                    Error: \(error.localizedDescription)
                    """
                
                if let logData = errorLog.data(using: .utf8) {
                    if let handle = try? FileHandle(forWritingTo: checksumFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(logData)
                        handle.closeFile()
                    }
                }
            }
        }
        
        // After all files are transferred, create transfer record
        await MainActor.run {
            if transferErrors.isEmpty && bytesTransferred > 0 {
                let duration = Date().timeIntervalSince(startTime)
                let record = TransferRecord(
                    id: UUID(),
                    timestamp: Date(),
                    sourceFolders: self.sourceFolders.compactMap { $0?.path },
                    destinationFolders: [destinationFolder.path],
                    totalSize: bytesTransferred,
                    duration: duration,
                    projectName: settings.projectName,
                    date: settings.date,
                    director: settings.director,
                    dop: settings.dop,
                    soundRecordist: settings.soundRecordist,
                    dit: settings.dit,
                    camera: settings.camera,
                    checksumType: settings.selectedChecksumType.rawValue,
                    checksumFile: checksumFileName
                )
                self.transferHistory.addRecord(record)
                Swift.print("Added transfer record for destination: \(destinationFolder.path)")
            }
        }
    }
    
    private func computeChecksum(for fileURL: URL) async throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }
        
        var hasher: HashFunction
        switch settings.selectedChecksumType {
        case .sha256:
            hasher = SHA256()
        case .md5:
            hasher = Insecure.MD5()
        case .sha1:
            hasher = Insecure.SHA1()
        }
        
        let bufferSize = 1024 * 1024 // 1MB chunks
        while let data = try fileHandle.read(upToCount: bufferSize) {
            hasher.update(data: data)
        }
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
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
    
    private func formatTimeRemaining(_ timeInterval: TimeInterval) -> String {
        if timeInterval.isInfinite || timeInterval.isNaN {
            return "Calculating..."
        }
        
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        let seconds = Int(timeInterval) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "%d sec", seconds)
        }
    }
}
