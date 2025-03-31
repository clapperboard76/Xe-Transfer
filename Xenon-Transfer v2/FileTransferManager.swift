import Foundation
import SwiftUI
import CryptoKit

class FileTransferManager: ObservableObject {
    @Published var isTransferring = false
    @Published var error: String?
    @Published var showError = false
    
    private let fileManager = FileManager.default
    private let bufferSize = 1024 * 1024 // 1MB buffer
    
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
        
        // Start transfer in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Calculate total size for each destination
            let totalSizes = destinationFolders.map { destination in
                sourceFolders.reduce(0) { total, source in
                    total + self.calculateTotalSize(of: source)
                }
            }
            
            // Update initial progress
            DispatchQueue.main.async {
                for i in 0..<destinationFolders.count {
                    progress.wrappedValue[i] = 0.0
                    estimatedTime.wrappedValue[i] = "Starting transfer..."
                }
            }
            
            for (index, destination) in destinationFolders.enumerated() {
                var bytesTransferred: Int64 = 0
                let startTime = Date()
                var checksumEntries: [String] = []
                
                for source in sourceFolders {
                    do {
                        // Create destination directory if it doesn't exist
                        try self.fileManager.createDirectory(
                            at: destination,
                            withIntermediateDirectories: true,
                            attributes: nil
                        )
                        
                        // Get all files from source
                        let files = try self.fetchAllFiles(from: source)
                        
                        for file in files {
                            let relativePath = file.path.replacingOccurrences(of: source.path, with: "")
                            let destinationFile = destination.appendingPathComponent(relativePath)
                            
                            // Create intermediate directories if needed
                            try self.fileManager.createDirectory(
                                at: destinationFile.deletingLastPathComponent(),
                                withIntermediateDirectories: true,
                                attributes: nil
                            )
                            
                            // Copy file and calculate checksum
                            let checksum = try self.copyFileAndCalculateChecksum(from: file, to: destinationFile)
                            
                            // Add to checksum entries
                            let entry = "\(relativePath) - SHA256: \(checksum)"
                            checksumEntries.append(entry)
                            
                            // Update progress
                            let fileSize = try self.fileManager.attributesOfItem(atPath: file.path)[.size] as? Int64 ?? 0
                            bytesTransferred += fileSize
                            
                            // Update progress and estimated time more frequently
                            DispatchQueue.main.async {
                                let progressValue = Double(bytesTransferred) / Double(totalSizes[index])
                                progress.wrappedValue[index] = progressValue
                                
                                // Calculate remaining time
                                let elapsedTime = Date().timeIntervalSince(startTime)
                                if elapsedTime > 0 {
                                    let bytesPerSecond = Double(bytesTransferred) / elapsedTime
                                    let remainingBytes = totalSizes[index] - bytesTransferred
                                    let remainingSeconds = Double(remainingBytes) / bytesPerSecond
                                    
                                    estimatedTime.wrappedValue[index] = self.formatTime(remainingSeconds)
                                }
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.error = error.localizedDescription
                            self.showError = true
                            self.isTransferring = false
                        }
                        return
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
                enumerator?.skipDescendants()
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
        alert.informativeText = "All files have been transferred successfully."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
