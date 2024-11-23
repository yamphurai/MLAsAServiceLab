import UIKit

class SettingsViewController: UIViewController {
    @IBOutlet weak var ipTextField: UITextField!
    @IBOutlet weak var dsidLabel: UILabel!
    @IBOutlet weak var dsidRequest: UIButton!
    @IBOutlet weak var ipSave: UIButton!
    
    private let plistFileName = "Data.plist"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadData(nil)
    }
    
    // Save User Entered IP Address
    @IBAction func saveIPAddress(_ sender: UIButton) {
        guard let ipAddress = ipTextField.text, !ipAddress.isEmpty else {
            ipTextField.text = "Enter IP address"
            return
        }
        saveData(key: "IPAddress", value: ipAddress)
    }
    
    // Request New DSID
    @IBAction func requestDSID(_ sender: UIButton) {
        // TODO: Need To Implement Get
        let dsid = "123456"
        saveData(key: "DSID", value: dsid)
        dsidLabel.text = dsid
    }
        
    // Populate Screen From PList
    private func loadData(_ sender: UIButton?) {
        let ipAddress = loadData(key: "IPAddress") as? String ?? "Enter IP Address"
        let dsid = loadData(key: "DSID") as? String ?? "No DSID"
        
        ipTextField.text = ipAddress
        dsidLabel.text = dsid
    }
    
    // Persist Date To PList To Use Across Sessions
    private func saveData(key: String, value: Any) {
        let plistPath = getPlistPath()
        var data = NSDictionary(contentsOfFile: plistPath) as? [String: Any] ?? [:]
        data[key] = value
        (data as NSDictionary).write(toFile: plistPath, atomically: true)
    }
    
    // Load Data From Persisted Storage
    private func loadData(key: String) -> Any? {
        let plistPath = getPlistPath()
        let data = NSDictionary(contentsOfFile: plistPath)
        return data?[key]
    }
    
    // Get Path To PList - From ChatGPT
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
