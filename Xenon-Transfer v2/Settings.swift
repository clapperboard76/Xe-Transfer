import Foundation

class Settings: ObservableObject {
    @Published var projectName: String {
        didSet {
            UserDefaults.standard.set(projectName, forKey: "projectName")
        }
    }
    
    @Published var date: String {
        didSet {
            UserDefaults.standard.set(date, forKey: "date")
        }
    }
    
    @Published var director: String {
        didSet {
            UserDefaults.standard.set(director, forKey: "director")
        }
    }
    
    @Published var dop: String {
        didSet {
            UserDefaults.standard.set(dop, forKey: "dop")
        }
    }
    
    @Published var soundRecordist: String {
        didSet {
            UserDefaults.standard.set(soundRecordist, forKey: "soundRecordist")
        }
    }
    
    @Published var dit: String {
        didSet {
            UserDefaults.standard.set(dit, forKey: "dit")
        }
    }
    
    @Published var camera: String {
        didSet {
            UserDefaults.standard.set(camera, forKey: "camera")
        }
    }
    
    @Published var selectedChecksumType: ChecksumType {
        didSet {
            UserDefaults.standard.set(selectedChecksumType.rawValue, forKey: "selectedChecksumType")
        }
    }
    
    @Published var showMatrixOverlay: Bool {
        didSet {
            UserDefaults.standard.set(showMatrixOverlay, forKey: "showMatrixOverlay")
        }
    }
    
    init() {
        // Initialize with saved values or defaults
        self.projectName = UserDefaults.standard.string(forKey: "projectName") ?? ""
        
        // Set default date to current date if not saved
        if let savedDate = UserDefaults.standard.string(forKey: "date") {
            self.date = savedDate
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            self.date = formatter.string(from: Date())
        }
        
        self.director = UserDefaults.standard.string(forKey: "director") ?? ""
        self.dop = UserDefaults.standard.string(forKey: "dop") ?? ""
        self.soundRecordist = UserDefaults.standard.string(forKey: "soundRecordist") ?? ""
        self.dit = UserDefaults.standard.string(forKey: "dit") ?? ""
        self.camera = UserDefaults.standard.string(forKey: "camera") ?? ""
        
        // Load checksum type
        if let savedChecksumType = UserDefaults.standard.string(forKey: "selectedChecksumType"),
           let checksumType = ChecksumType(rawValue: savedChecksumType) {
            self.selectedChecksumType = checksumType
        } else {
            self.selectedChecksumType = .sha256
        }
        
        self.showMatrixOverlay = UserDefaults.standard.bool(forKey: "showMatrixOverlay")
    }
} 