import Foundation
import SwiftUI
import CryptoKit

class FileTransferManager: ObservableObject {
    @Published var isTransferring = false
    @Published var error: String?
    @Published var showError = false
    @Published var transferSummary: String?
    
    private let fileManager = FileManager.default
    private let bufferSize = 1024 * 1024 // 1MB buffer
    
    // Structure to hold file information
    private struct FileInfo {
        let url: URL
        let relativePath: String
        let size: Int64
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
        
        // Start transfer in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // First, collect all files from all source folders
            var allSourceFiles: [FileInfo] = []
            var totalSize: Int64 = 0
            
            for source in sourceFolders {
                do {
                    let files = try self.fetchAllFiles(from: source)
                    for file in files {
                        let relativePath = file.path.replacingOccurrences(of: source.path, with: "")
                        let fileSize = try self.fileManager.attributesOfItem(atPath: file.path)[.size] as? Int64 ?? 0
                        allSourceFiles.append(FileInfo(url: file, relativePath: relativePath, size: fileSize))
                        totalSize += fileSize
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
                    // Create destination directory if it doesn't exist
                    try self.fileManager.createDirectory(
                        at: destination,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    
                    // Check which files need to be copied to this destination
                    for fileInfo in allSourceFiles {
                        let destinationFile = destination.appendingPathComponent(fileInfo.relativePath)
                        
                        // Check if file exists and has the same size
                        if self.fileManager.fileExists(atPath: destinationFile.path) {
                            if let existingSize = try? self.fileManager.attributesOfItem(atPath: destinationFile.path)[.size] as? Int64,
                               existingSize == fileInfo.size {
                                filesSkipped += 1
                                continue
                            }
                        }
                        
                        // Create intermediate directories if needed
                        try self.fileManager.createDirectory(
                            at: destinationFile.deletingLastPathComponent(),
                            withIntermediateDirectories: true,
                            attributes: nil
                        )
                        
                        // Copy file and calculate checksum
                        let checksum = try self.copyFileAndCalculateChecksum(from: fileInfo.url, to: destinationFile)
                        filesCopied += 1
                        
                        // Add to checksum entries
                        let entry = "\(fileInfo.relativePath) - SHA256: \(checksum)"
                        checksumEntries.append(entry)
                        
                        // Update progress
                        bytesTransferred += fileInfo.size
                        
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
                        self.transferSummary = "Transfer Complete\nFiles copied: \(filesCopied)\nFiles skipped (already exist): \(filesSkipped)"
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
        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else { continue }
            
            if isDirectory.boolValue {
                // Don't skip descendants anymore - we want all files
                continue
            } else {
                files.append(fileURL)
            }
        }
        
        return files
    }
    
    private func copyFileAndCalculateChecksum(from source: URL, to destination: URL) throws -> String {
        let sourceHandle = try FileHandle(forReadingFrom: source)
        let destinationHandle = try FileHandle(forWritingTo: destination)
        var hasher = SHA256()
        
        defer {
            try? sourceHandle.close()
            try? destinationHandle.close()
        }
        
        while let data = try? sourceHandle.read(upToCount: bufferSize), !data.isEmpty {
            try destinationHandle.write(contentsOf: data)
            hasher.update(data: data)
        }
        
        try destinationHandle.synchronize()
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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
}
