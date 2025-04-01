import Foundation
import SwiftUI

struct TransferRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let sourceFolders: [String]
    let destinationFolders: [String]
    let totalSize: Double
    let duration: TimeInterval
    let projectName: String
    let date: String
    let director: String
    let dop: String
    let soundRecordist: String
    let dit: String
    let camera: String
    let checksumType: String
    let checksumFile: String
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(totalSize))
    }
    
    // Add Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: TransferRecord, rhs: TransferRecord) -> Bool {
        lhs.id == rhs.id
    }
}

class TransferHistory: ObservableObject {
    @Published var records: [TransferRecord] = []
    private let saveKey = "TransferHistory"
    
    init() {
        loadHistory()
    }
    
    func addRecord(_ record: TransferRecord) {
        records.insert(record, at: 0)
        saveHistory()
    }
    
    func clearHistory() {
        records.removeAll()
        saveHistory()
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([TransferRecord].self, from: data) {
            records = decoded
        }
    }
}

struct TransferHistoryView: View {
    @ObservedObject var history: TransferHistory
    @Environment(\.dismiss) var dismiss
    @State private var selectedRecordId: UUID?
    @State private var showClearConfirmation = false
    
    private var selectedRecord: TransferRecord? {
        history.records.first { $0.id == selectedRecordId }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Clear History Button at the top
                Button(action: {
                    showClearConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear History")
                    }
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                }
                .buttonStyle(PlainButtonStyle())
                
                List(selection: $selectedRecordId) {
                    ForEach(history.records) { record in
                        TransferRecordRow(record: record)
                            .tag(record.id)
                    }
                    .onDelete { indexSet in
                        history.records.remove(atOffsets: indexSet)
                    }
                }
                .listStyle(InsetListStyle())
                .frame(minWidth: 300)
            }
            
            if let record = selectedRecord {
                TransferRecordDetail(record: record)
            } else {
                Text("Select a transfer record")
                    .foregroundColor(.gray)
                    .font(.system(size: 12))
            }
        }
        .frame(width: 800, height: 500)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: {
                    dismiss()
                }) {
                    Label("Close", systemImage: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .alert("Clear History", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                history.clearHistory()
            }
        } message: {
            Text("Are you sure you want to clear all transfer history? This action cannot be undone.")
        }
    }
}

struct TransferRecordRow: View {
    let record: TransferRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(record.formattedDate)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(record.formattedDuration)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            
            Text(record.formattedSize)
                .font(.system(size: 11))
                .foregroundColor(.gray)
            
            if !record.projectName.isEmpty {
                Text(record.projectName)
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 2)
    }
}

struct TransferRecordDetail: View {
    let record: TransferRecord
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header Section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transfer Details")
                        .font(.system(size: 14, weight: .bold))
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Date")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            Text(record.formattedDate)
                                .font(.system(size: 12))
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Duration")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            Text(record.formattedDuration)
                                .font(.system(size: 12))
                        }
                    }
                }
                
                // Project Information
                if !record.projectName.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project Information")
                            .font(.system(size: 14, weight: .bold))
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 2) {
                            if !record.projectName.isEmpty {
                                DetailRow(title: "Project", value: record.projectName)
                            }
                            if !record.date.isEmpty {
                                DetailRow(title: "Date", value: record.date)
                            }
                            if !record.director.isEmpty {
                                DetailRow(title: "Director", value: record.director)
                            }
                            if !record.dop.isEmpty {
                                DetailRow(title: "DOP", value: record.dop)
                            }
                            if !record.soundRecordist.isEmpty {
                                DetailRow(title: "Sound", value: record.soundRecordist)
                            }
                            if !record.dit.isEmpty {
                                DetailRow(title: "DIT", value: record.dit)
                            }
                            if !record.camera.isEmpty {
                                DetailRow(title: "Camera", value: record.camera)
                            }
                        }
                    }
                }
                
                // Transfer Information
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transfer Information")
                        .font(.system(size: 14, weight: .bold))
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 2) {
                        DetailRow(title: "Total Size", value: record.formattedSize)
                        DetailRow(title: "Checksum Type", value: record.checksumType)
                        DetailRow(title: "Checksum File", value: record.checksumFile)
                    }
                }
                
                // Source and Destination
                VStack(alignment: .leading, spacing: 6) {
                    Text("Locations")
                        .font(.system(size: 14, weight: .bold))
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Source Folders")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        ForEach(record.sourceFolders, id: \.self) { folder in
                            Text(folder)
                                .font(.system(size: 11))
                        }
                        
                        Text("Destination Folders")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        ForEach(record.destinationFolders, id: \.self) { folder in
                            Text(folder)
                                .font(.system(size: 11))
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 11))
        }
    }
} 