import Foundation
import SwiftUI
import CryptoKit

enum ChecksumAlgorithm {
    case md5
    case sha1
    case sha256
}

class FileTransferManager: ObservableObject {
    @Published var isTransferring = false
    @Published var error: String?
    @Published var showError = false
    @Published var transferSummary: String?
    @Published var currentFile: String = ""
    @Published var progress: Double = 0.0
    @Published var transferSpeed: Double = 0.0  // MB/s
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var totalFiles: Int = 0
    @Published var processedFiles: Int = 0
    @Published var skippedFiles: Int = 0
    @Published var errorMessage: String?
    @Published var showSuccess: Bool = false
    @Published var successMessage: String = ""
    @Published var showChecksumOptions: Bool = false
    @Published var selectedChecksumAlgorithm: ChecksumAlgorithm = .sha256
    @Published var showTransferSummary: Bool = false
    @Published var showTransferSpeed: Bool = false  // New property for speed display
    
    private let fileManager = FileManager.default
    private let bufferSize = 8 * 1024 * 1024 // 8MB buffer for better performance with large files
    private let defaultOperationTimeout: TimeInterval = 60 // 1 minute default timeout
    private let largeFileOperationTimeout: TimeInterval = 1800 // 30 minutes for large files
    private var startTime: Date?
    private var lastUpdateTime: Date?
    private var bytesTransferred: Int64 = 0
    private var lastBytesTransferred: Int64 = 0
    private var totalBytes: Int64 = 0  // Total bytes to transfer
    
    // Structure to hold file information
    private struct FileInfo {
        let url: URL
        let relativePath: String
        let size: Int64
    }
    
    // Custom error for timeout
    private enum FileTransferError: Error {
        case operationTimeout
        case fileOperationFailed(Error)
    }
    
    private func getTimeoutForFile(size: Int64) -> TimeInterval {
        // Use longer timeout for files larger than 500MB
        return size > 500 * 1024 * 1024 ? largeFileOperationTimeout : defaultOperationTimeout
    }
    
    private func performWithTimeout<T>(_ operation: @escaping () throws -> T, timeout: TimeInterval? = nil) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
        let operationTimeout = timeout ?? defaultOperationTimeout
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let value = try operation()
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
    
    private func copyFileWithTimeout(from source: URL, to destination: URL) throws {
        try performWithTimeout {
            try self.fileManager.copyItem(at: source, to: destination)
        }
    }
    
    private func createDirectoryWithTimeout(at url: URL) throws {
        try performWithTimeout {
            try self.fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    private func fileExistsWithTimeout(at path: String) throws -> Bool {
        try performWithTimeout {
            self.fileManager.fileExists(atPath: path)
        }
    }
    
    private func attributesWithTimeout(at path: String) throws -> [FileAttributeKey: Any] {
        try performWithTimeout {
            try self.fileManager.attributesOfItem(atPath: path)
        }
    }
    
    private func createFolderStructure(from source: URL, to destination: URL) throws -> Int {
        var foldersCreated = 0
        let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        
        while let itemURL = enumerator?.nextObject() as? URL {
            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true {
                let relativePath = itemURL.path.replacingOccurrences(of: source.path, with: "")
                let destinationItem = destination.appendingPathComponent(relativePath)
                
                // Create the folder if it doesn't exist
                let exists = try self.fileExistsWithTimeout(at: destinationItem.path)
                if !exists {
                    try self.createDirectoryWithTimeout(at: destinationItem)
                    foldersCreated += 1
                    print("Created folder: \(destinationItem.path)") // Debug print
                }
            }
        }
        return foldersCreated
    }
    
    private func needsChanges(source: URL, destination: URL) throws -> Bool {
        var sourceEnumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles])
        var destinationEnumerator = FileManager.default.enumerator(at: destination, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles])
        
        // Get all items from source
        var sourceItems: Set<String> = []
        while let itemURL = sourceEnumerator?.nextObject() as? URL {
            let relativePath = itemURL.path.replacingOccurrences(of: source.path, with: "")
            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true {
                sourceItems.insert(relativePath)
            }
        }
        
        // Get all items from destination
        var destinationItems: Set<String> = []
        while let itemURL = destinationEnumerator?.nextObject() as? URL {
            let relativePath = itemURL.path.replacingOccurrences(of: destination.path, with: "")
            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true {
                destinationItems.insert(relativePath)
            }
        }
        
        // Check if there are any folders in source that aren't in destination
        if !sourceItems.isSubset(of: destinationItems) {
            print("Found missing folders: \(sourceItems.subtracting(destinationItems))") // Debug print
            return true
        }
        
        // If we get here, all folders exist. Now check files
        sourceEnumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])
        destinationEnumerator = FileManager.default.enumerator(at: destination, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])
        
        // Get all files from source
        sourceItems.removeAll()
        while let itemURL = sourceEnumerator?.nextObject() as? URL {
            let relativePath = itemURL.path.replacingOccurrences(of: source.path, with: "")
            let resourceValues = try itemURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues.isRegularFile == true {
                sourceItems.insert(relativePath)
            }
        }
        
        // Get all files from destination
        destinationItems.removeAll()
        while let itemURL = destinationEnumerator?.nextObject() as? URL {
            let relativePath = itemURL.path.replacingOccurrences(of: destination.path, with: "")
            let resourceValues = try itemURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues.isRegularFile == true {
                destinationItems.insert(relativePath)
            }
        }
        
        // Check if there are any files in source that aren't in destination
        if !sourceItems.isSubset(of: destinationItems) {
            print("Found missing files: \(sourceItems.subtracting(destinationItems))") // Debug print
            return true
        }
        
        return false
    }
    
    func transferFiles(
        from sourceFolders: [URL],
        to destinationFolders: [URL],
        progress: Binding<[Double]>,
        estimatedTime: Binding<[String]>
    ) {
        guard !sourceFolders.isEmpty && !destinationFolders.isEmpty else {
            self.error = "Please select at least one source and destination folder"
            self.showError = true
            return
        }
        
        isTransferring = true
        transferSummary = nil
        startTime = Date()
        lastUpdateTime = Date()
        bytesTransferred = 0
        lastBytesTransferred = 0
        totalBytes = 0  // Reset total bytes
        showTransferSpeed = true
        
        // Start transfer in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // First, create all folders from all source folders
            var foldersCreated = 0
            for (index, source) in sourceFolders.enumerated() {
                if index < destinationFolders.count {
                    do {
                        foldersCreated += try self.createFolderStructure(from: source, to: destinationFolders[index])
                    } catch {
                        print("Error creating folders: \(error)")
                    }
                }
            }
            
            // If we only created folders and no files to transfer, show summary and exit
            if foldersCreated > 0 {
                DispatchQueue.main.async {
                    self.transferSummary = "Transfer Complete\nFolders created: \(foldersCreated)"
                    self.isTransferring = false
                    self.showCompletionAlert()
                }
                return
            }
            
            // Now collect all files and folders from all source folders
            var allSourceItems: [(url: URL, relativePath: String, size: Int64)] = []
            var totalSize: Int64 = 0
            
            for source in sourceFolders {
                do {
                    // Get all items from source, including empty folders
                    let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
                    
                    while let itemURL = enumerator?.nextObject() as? URL {
                        let relativePath = itemURL.path.replacingOccurrences(of: source.path, with: "")
                        let resourceValues = try itemURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey])
                        
                        if resourceValues.isRegularFile == true {
                            // Add file with its size
                            let size = resourceValues.fileSize ?? 0
                            allSourceItems.append((url: itemURL, relativePath: relativePath, size: Int64(size)))
                            totalSize += Int64(size)
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.error = "Error scanning source folder: \(error.localizedDescription)"
                        self.showError = true
                        self.isTransferring = false
                    }
                    return
                }
            }
            
            // Set total bytes for transfer speed calculation
            DispatchQueue.main.async {
                self.totalBytes = totalSize
            }
            
            // Update initial progress
            DispatchQueue.main.async {
                for i in 0..<destinationFolders.count {
                    progress.wrappedValue[i] = 0.0
                    estimatedTime.wrappedValue[i] = "Starting transfer..."
                }
            }
            
            // Process each destination folder
            for (index, destination) in destinationFolders.enumerated() {
                var bytesTransferred: Int64 = 0
                let startTime = Date()
                var checksumEntries: [String] = []
                var filesSkipped = 0
                var filesCopied = 0
                
                    do {
                    // Process all items (files and folders)
                    for itemInfo in allSourceItems {
                        let destinationItem = destination.appendingPathComponent(itemInfo.relativePath)
                        let resourceValues = try itemInfo.url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                        
                        if resourceValues.isRegularFile == true {
                            // Check if file exists and has the same size
                            if try self.fileExistsWithTimeout(at: destinationItem.path) {
                                if let existingSize = try? self.attributesWithTimeout(at: destinationItem.path)[.size] as? Int64,
                                   existingSize == itemInfo.size {
                                    filesSkipped += 1
                                    continue
                                }
                            }
                            
                            // Create intermediate directories if needed
                            try self.createDirectoryWithTimeout(at: destinationItem.deletingLastPathComponent())
                            
                            // Copy file and calculate checksum
                            let checksum = try self.copyFileAndCalculateChecksum(from: itemInfo.url, to: destinationItem)
                            filesCopied += 1
                            
                            // Add to checksum entries
                            let entry = "\(itemInfo.relativePath) - SHA256: \(checksum)"
                            checksumEntries.append(entry)
                            
                            // Update progress
                            bytesTransferred += itemInfo.size
                            
                            // Update progress and estimated time more frequently
                            DispatchQueue.main.async {
                                let progressValue = Double(bytesTransferred) / Double(totalSize)
                                progress.wrappedValue[index] = progressValue
                                
                                // Calculate remaining time
                                let elapsedTime = Date().timeIntervalSince(startTime)
                                if elapsedTime > 0 {
                                    let bytesPerSecond = Double(bytesTransferred) / elapsedTime
                                    let remainingBytes = totalSize - bytesTransferred
                                    let remainingSeconds = Double(remainingBytes) / bytesPerSecond
                                    
                                    estimatedTime.wrappedValue[index] = self.formatTime(remainingSeconds)
                                }
                            }
                    }
                }
                
                // Create checksum file
                if !checksumEntries.isEmpty {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                    let timestamp = dateFormatter.string(from: Date())
                    let checksumFileName = "transfer_checksum_\(timestamp).txt"
                    let checksumFile = destination.appendingPathComponent(checksumFileName)
                    
                    let checksumContent = checksumEntries.joined(separator: "\n")
                    try? checksumContent.write(to: checksumFile, atomically: true, encoding: .utf8)
                    }
                    
                    // Update transfer summary
                    DispatchQueue.main.async {
                        var summary = "Transfer Complete\n"
                        if foldersCreated > 0 {
                            summary += "Folders created: \(foldersCreated)\n"
                        }
                        if filesCopied > 0 {
                            summary += "Files copied: \(filesCopied)\n"
                        }
                        if filesSkipped > 0 {
                            summary += "Files skipped (already exist): \(filesSkipped)\n"
                        }
                        if foldersCreated == 0 && filesCopied == 0 && filesSkipped == 0 {
                            summary += "No changes needed - all files and folders already exist"
                        }
                        self.transferSummary = summary
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.error = "Error processing destination folder: \(error.localizedDescription)"
                        self.showError = true
                        self.isTransferring = false
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                self.isTransferring = false
                self.showCompletionAlert()
            }
        }
    }
    
    private func calculateTotalSize(of url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            guard let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continue }
            totalSize += Int64(fileSize)
        }
        
        return totalSize
    }
    
    private func fetchAllFiles(from url: URL) throws -> [URL] {
        var files: [URL] = []
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            
            if resourceValues.isDirectory == true {
                // Add the directory URL
                files.append(fileURL)
            } else if resourceValues.isRegularFile == true {
                // Add the file URL
                files.append(fileURL)
            }
        }
        
        return files
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
            
            self.error = errorMessage
            self.showError = true
            self.isTransferring = false
        }
    }
    
    private func copyFileAndCalculateChecksum(from source: URL, to destination: URL) throws -> String {
        do {
            // Get file size for timeout determination
            let fileSize = try attributesWithTimeout(at: source.path)[.size] as? Int64 ?? 0
            let timeout = getTimeoutForFile(size: fileSize)
            
            // Update current file name for progress tracking
            DispatchQueue.main.async {
                self.currentFile = source.lastPathComponent
            }
            
            // Copy file with timeout and progress tracking
            try performWithTimeout({
        let sourceHandle = try FileHandle(forReadingFrom: source)
        let destinationHandle = try FileHandle(forWritingTo: destination)
        defer {
            try? sourceHandle.close()
            try? destinationHandle.close()
        }
        
                var bytesRead: Int64 = 0
                while let data = try? sourceHandle.read(upToCount: self.bufferSize), !data.isEmpty {
            try destinationHandle.write(contentsOf: data)
                    bytesRead += Int64(data.count)
                    
                    // Update progress for all files
                    DispatchQueue.main.async {
                        self.progress = Double(bytesRead) / Double(fileSize)
                        self.updateTransferSpeed()
                    }
        }
        
        try destinationHandle.synchronize()
            }, timeout: timeout)
            
            // Calculate checksum with timeout
            return try performWithTimeout({
                let fileHandle = try FileHandle(forReadingFrom: destination)
                defer { try? fileHandle.close() }
                
                var hasher = SHA256()
                var bytesRead: Int64 = 0
                
                while let data = try? fileHandle.read(upToCount: self.bufferSize), !data.isEmpty {
                    hasher.update(data: data)
                    bytesRead += Int64(data.count)
                    
                    // Update progress during checksum calculation
                    DispatchQueue.main.async {
                        self.progress = Double(bytesRead) / Double(fileSize)
                    }
                }
                
                let digest = hasher.finalize()
                return digest.map { String(format: "%02x", $0) }.joined()
            }, timeout: timeout)
        } catch {
            handleTransferError(error, for: source.lastPathComponent)
            throw error
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, remainingSeconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, remainingSeconds)
        } else {
            return String(format: "%ds", remainingSeconds)
        }
    }
    
    private func showCompletionAlert() {
        let alert = NSAlert()
        alert.messageText = "Transfer Complete"
        alert.informativeText = transferSummary ?? "All files have been transferred successfully."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func updateTransferSpeed() {
        guard let lastUpdate = lastUpdateTime else {
            lastUpdateTime = Date()
            return
        }
        
        let currentTime = Date()
        let timeInterval = currentTime.timeIntervalSince(lastUpdate)
        
        if timeInterval >= 1.0 {  // Update every second
            let bytesDelta = bytesTransferred - lastBytesTransferred
            transferSpeed = Double(bytesDelta) / timeInterval / (1024 * 1024)  // Convert to MB/s
            
            // Calculate estimated time remaining
            if transferSpeed > 0 {
                let remainingBytes = totalBytes - bytesTransferred
                estimatedTimeRemaining = TimeInterval(remainingBytes) / (transferSpeed * 1024 * 1024)
            }
            
            lastBytesTransferred = bytesTransferred
            lastUpdateTime = currentTime
        }
    }

    private func copyFile(from sourceURL: URL, to destinationURL: URL) async throws {
        let fileManager = FileManager.default
        let fileSize = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        
        // Create destination directory if it doesn't exist
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(),
                                      withIntermediateDirectories: true)
        
        // Check if file exists and compare sizes
        if fileManager.fileExists(atPath: destinationURL.path) {
            if let destSize = try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               destSize == fileSize {
                skippedFiles += 1
                return
            }
        }
        
        // Copy file with progress tracking
        let source = try FileHandle(forReadingFrom: sourceURL)
        let destination = try FileHandle(forWritingTo: destinationURL)
        
        defer {
            try? source.close()
            try? destination.close()
        }
        
        let bufferSize = 1024 * 1024  // 1MB buffer
        var buffer = Data(capacity: bufferSize)
        var bytesRead: Int64 = 0
        
        while let chunk = try? source.read(upToCount: bufferSize) {
            try destination.write(contentsOf: chunk)
            bytesRead += Int64(chunk.count)
            bytesTransferred += Int64(chunk.count)
            
            await MainActor.run {
                progress = Double(bytesRead) / Double(fileSize)
                updateTransferSpeed()
            }
        }
        
        try destination.truncate(atOffset: 0)
        try destination.close()
        try source.close()
    }
}

