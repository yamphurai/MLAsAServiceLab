import Foundation

class AppSettings {
    static let shared = AppSettings() // Singleton instance
    private let plistFileName = "Data.plist"

    private init() {} // Prevent external instantiation

    // Save data to plist
    func saveData(key: String, value: Any) {
        let plistPath = getPlistPath()
        var data = NSDictionary(contentsOfFile: plistPath) as? [String: Any] ?? [:]
        data[key] = value
        (data as NSDictionary).write(toFile: plistPath, atomically: true)
    }

    // Load data from plist
    func loadData(key: String) -> Any? {
        let plistPath = getPlistPath()
        let data = NSDictionary(contentsOfFile: plistPath)
        return data?[key]
    }

    // Get the path to the plist file
    private func getPlistPath() -> String {
        let fileManager = FileManager.default
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        let plistPath = documentsDirectory.appendingPathComponent(plistFileName)
        
        if !fileManager.fileExists(atPath: plistPath.path) {
            if let bundlePath = Bundle.main.url(forResource: "Data", withExtension: "plist") {
                try? fileManager.copyItem(at: bundlePath, to: plistPath)
            } else {
                let emptyData: [String: Any] = [:]
                (emptyData as NSDictionary).write(to: plistPath, atomically: true)
            }
        }
        return plistPath.path
    }
}
