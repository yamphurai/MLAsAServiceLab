//
//  MlaasModel.swift
//  HTTPSwiftExample
//
//  Created by Eric Cooper Larson on 6/5/24.
//  Copyright © 2024 Eric Larson. All rights reserved.
//




/// This model uses delegation to interact with the main controller. The two functions below are for notifying the user that an update was completed successfully on the server. They must be implemented.
protocol ClientDelegate{
    func updateDsid(_ newDsid:Int) // if the delegate needs to update UI
    func receivedPrediction(_ prediction:[String:Any])
    func receiveModel(_ model:String)
}

enum RequestEnum:String {
    case get = "GET"
    case put = "PUT"
    case post = "POST"
    case delete = "DELETE"
}

import UIKit

class MlaasModel: NSObject, URLSessionDelegate{
    
    //MARK: Properties and Delegation
    private let operationQueue = OperationQueue()
    // default ip, if you are unsure try: ifconfig |grep "inet "
    // to see what your public facing IP address is
    var server_ip = "10.9.166.123" // this will be the default ip
    // create a delegate for using the protocol
    var delegate:ClientDelegate?
    private var dsid:Int = 5
    
    // public access methods
    func updateDsid(_ newDsid:Int){
        dsid = newDsid
    }
    func getDsid()->(Int){
        return dsid
    }
    
    lazy var session = {
        let sessionConfig = URLSessionConfiguration.ephemeral
        
        sessionConfig.timeoutIntervalForRequest = 5.0
        sessionConfig.timeoutIntervalForResource = 8.0
        sessionConfig.httpMaximumConnectionsPerHost = 1
        
        let tmp = URLSession(configuration: sessionConfig,
            delegate: self,
            delegateQueue:self.operationQueue)
        
        return tmp
        
    }()
    
    //MARK: Setters and Getters
    func setServerIp(ip:String)->(Bool){
        // user is trying to set ip: make sure that it is valid ip address
        if matchIp(for:"((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\\.|$)){4}", in: ip){
            server_ip = ip
            // return success
            return true
        }else{
            return false
        }
    }
    
    
    //MARK: Main Functions
    func sendData(_ array:[Double], withLabel label:String){
        let baseURL = "http://\(server_ip):8000/labeled_data/"
        let postUrl = URL(string: "\(baseURL)")
        
        // create a custom HTTP POST request
        var request = URLRequest(url: postUrl!)
        
        // utility method to use from below
        let requestBody:Data = try! JSONSerialization.data(withJSONObject: ["feature":array,
            "label":"\(label)",
            "dsid":self.dsid])
        
        // The Type of the request is given here
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestBody
        
        let postTask : URLSessionDataTask = self.session.dataTask(with: request,
                        completionHandler:{(data, response, error) in
            //TODO: notify delegate?
            if(error != nil){
                if let res = response{
                    print("Response:\n",res)
                }
            }
            else{
                let jsonDictionary = self.convertDataToDictionary(with: data)
                
                print(jsonDictionary["feature"]!)
                print(jsonDictionary["label"]!)
            }
        })
        postTask.resume() // start the task
    }
    
    // post data without a label
    func sendData(_ array:[Double]){
        let baseURL = "http://\(server_ip):8000/predict_turi/"
        let postUrl = URL(string: "\(baseURL)")
        
        // create a custom HTTP POST request
        var request = URLRequest(url: postUrl!)
        
        // utility method to use from below
        let requestBody:Data = try! JSONSerialization.data(withJSONObject: ["feature":array,
            "dsid":self.dsid])
        
        // The Type of the request is given here
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestBody
        
        let postTask : URLSessionDataTask = self.session.dataTask(with: request,
                        completionHandler:{(data, response, error) in
            
            if(error != nil){
                print("Error from server")
                if let res = response{
                    print("Response:\n",res)
                }
            }
            else{
                
                if let delegate = self.delegate {
                    let jsonDictionary = self.convertDataToDictionary(with: data)
                    delegate.receivedPrediction(jsonDictionary)
                }
            }
        })
        
        postTask.resume() // start the task
    }
    
    // New Method That Accepts Model Type
    func sendData(features: [Double], modelType: String){
        let baseURL = "http://\(server_ip):8000/predict_turi/\(modelType)"
        let postUrl = URL(string: "\(baseURL)")
        
        // create a custom HTTP POST request
        var request = URLRequest(url: postUrl!)
        
        // utility method to use from below
        let requestBody:Data = try! JSONSerialization.data(withJSONObject: ["feature":features,
            "dsid":self.dsid])
        
        // The Type of the request is given here
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestBody
        
        let postTask : URLSessionDataTask = self.session.dataTask(with: request,
                        completionHandler:{(data, response, error) in
            
            if(error != nil){
                print("Error from server")
                if let res = response{
                    print("Response:\n",res)
                }
            }
            else{
                
                if let delegate = self.delegate {
                    let jsonDictionary = self.convertDataToDictionary(with: data)
                    delegate.receivedPrediction(jsonDictionary)
                }
            }
        })
        
        postTask.resume() // start the task
    }
    
    // get and store a new DSID
    func getNewDsid(){
        let baseURL = "http://\(server_ip):8000/max_dsid/"
        let postUrl = URL(string: "\(baseURL)")
        
        // create a custom HTTP POST request
        var request = URLRequest(url: postUrl!)
        
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let getTask : URLSessionDataTask = self.session.dataTask(with: request,
                        completionHandler:{(data, response, error) in
            // TODO: handle error!
            let jsonDictionary = self.convertDataToDictionary(with: data)
                            
            if let delegate = self.delegate,
                let resp=response,
                let dsid = jsonDictionary["dsid"] as? Int {
                // tell delegate to update interface for the Dsid
                self.dsid = dsid+1
                delegate.updateDsid(self.dsid)
                
                print(resp)
            }

        })
        
        getTask.resume() // start the task
        
    }
    
    func trainModel(){
        let baseURL = "http://\(server_ip):8000/train_model_turi/\(dsid)"
        let postUrl = URL(string: "\(baseURL)")
        
        // create a custom HTTP POST request
        var request = URLRequest(url: postUrl!)
        
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let getTask : URLSessionDataTask = self.session.dataTask(with: request,
                        completionHandler:{(data, response, error) in
            // TODO: handle error!
            let jsonDictionary = self.convertDataToDictionary(with: data)
                            
            if let summary = jsonDictionary["summary"] as? String {
                // tell delegate to update interface for the Dsid
                print(summary)
                
                if let classValue = self.extractClassValue(from: summary) {
                    if let delegate = self.delegate {
                        delegate.receiveModel(classValue)
                    }
                }
            }

        })
        
        getTask.resume() // start the task
        
    }
    
    // New Method To Train A Specific Model
    func trainModel(modelType: String) {
        let baseURL = "http://\(server_ip):8000/train_model_turi/\(dsid)/\(modelType)"
        guard let getUrl = URL(string: "\(baseURL)") else {
            print("Invalid URL.")
            return
        }
        
        // Create a custom HTTP GET request
        var request = URLRequest(url: getUrl)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let getTask : URLSessionDataTask = self.session.dataTask(with: request,
                        completionHandler:{(data, response, error) in
            
            // TODO: handle error!
            let jsonDictionary = self.convertDataToDictionary(with: data)
            
            if let summary = jsonDictionary["summary"] as? String {
                // tell delegate to update interface for the Dsid
                print(summary)
                
                if let classValue = self.extractClassValue(from: summary) {
                    if let delegate = self.delegate {
                        delegate.receiveModel(classValue)
                    }
                }
            }
        })
        
        // Start the task
        getTask.resume()
    }

    
    //MARK: Utility Functions
    private func matchIp(for regex:String, in text:String)->(Bool){
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let results = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            if results.count > 0{return true}
            
        } catch _{
            return false
        }
        return false
    }
    
    private func convertDataToDictionary(with data:Data?)->[String:Any]{
        // convenience function for getting Dictionary from server data
        
        // I was getting an error due to null data
        guard let validData = data else {
            print("Error: Data is nil.")
            return [:] // Return empty dictionary
        }
        
        do { // try to parse JSON and deal with errors using do/catch block
            let jsonDictionary: [String:Any] =
                try JSONSerialization.jsonObject(with: data!,
                                                 options: JSONSerialization.ReadingOptions.mutableContainers) as! [String : Any]
            
            return jsonDictionary
            
        } catch {
            print("json error: \(error.localizedDescription)")
            if let strData = String(data:data!, encoding:String.Encoding(rawValue: String.Encoding.utf8.rawValue)){
                print("printing JSON received as string: "+strData)
            }
            return [String:Any]() // just return empty
        }
    }
    
    // Get Selected Model From Response
    // From ChatGPT
    func extractClassValue(from string: String) -> String? {
        let regexPattern = #"Class\s+:\s+([^\n]+)"#
        do {
            let regex = try NSRegularExpression(pattern: regexPattern)
            if let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) {
                // Extract the captured group (value after "Class :")
                if let range = Range(match.range(at: 1), in: string) {
                    return String(string[range]).trimmingCharacters(in: .whitespaces)
                }
            }
        } catch {
            print("Regex error: \(error.localizedDescription)")
        }
        return nil
    }

}
