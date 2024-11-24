import UIKit

class SettingsViewController: UIViewController, ClientDelegate  {
    @IBOutlet weak var ipTextField: UITextField!
    @IBOutlet weak var dsidLabel: UILabel!
    @IBOutlet weak var dsidRequest: UIButton!
    @IBOutlet weak var ipSave: UIButton!
    
    private let plistFileName = "Data.plist"
    
    let client = MlaasModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        client.delegate = self
        loadData()
        
    }
    
    // Save User Entered IP Address
    @IBAction func saveIPAddress(_ sender: UIButton) {
        guard let ipAddress = ipTextField.text, !ipAddress.isEmpty else {
            ipTextField.text = "Enter IP address"
            return
        }
        AppSettings.shared.saveData(key: "IPAddress", value: ipAddress)
        _ = client.setServerIp(ip: ipAddress)
    }
    
    // Request New DSID
    @IBAction func requestDSID(_ sender: UIButton) {
        client.getNewDsid()
        let dsid = client.getDsid()
        AppSettings.shared.saveData(key: "DSID", value: dsid)
        dsidLabel.text = String(dsid)
    }
    
    // Populate Screen From PList
    private func loadData() {
        let ipAddress = AppSettings.shared.loadData(key: "IPAddress") as? String
        let dsid = AppSettings.shared.loadData(key: "DSID") as? Int
        
        ipTextField.text = ipAddress ?? "Enter IP Address"
        dsidLabel.text = dsid != nil ? String(dsid!) : "Enter DSID"
        
        if let validIpAddress = ipAddress, !validIpAddress.isEmpty {
            _ = client.setServerIp(ip: validIpAddress)
        }
        
        if let validDsid = dsid {
            client.updateDsid(validDsid)
        }
    }
    
    // Delegate From Model Class
    func updateDsid(_ newDsid:Int){
        DispatchQueue.main.async{
            self.dsidLabel.text = String(newDsid)
        }
    }
    
    // Delegate From Model Class - Not Handler In This Controller - Do Nothing
    func receivedPrediction(_ prediction:[String:Any]){

    }
    
    // Delegate From Model Class - Not Handler In This Controller - Do Nothing
    func receiveModel(_ model:String){

    }
}
