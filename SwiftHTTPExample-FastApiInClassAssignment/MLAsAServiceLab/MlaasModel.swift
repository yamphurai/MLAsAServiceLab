//
//  MlaasModel.swift
//  HTTPSwiftExample
//
//  Created by Eric Cooper Larson on 6/5/24.
//  Copyright © 2024 Eric Larson. All rights reserved.
//




/// This model uses delegation to interact with the main controller. The two functions below are for notifying the user that an update was completed successfully on the server. They must be implemented.
protocol ClientDelegate{
    func updateDsid(_ newDsid:Int)          // method to update the DSID
    func receivedPrediction(_ prediction:[String:Any])  // method to receive the prediction data.
}


// enum with four cases representing different HTTP methods (GET, PUT, POST, and DELETE)
enum RequestEnum:String {
    case get = "GET"
    case put = "PUT"
    case post = "POST"
    case delete = "DELETE"
}

import UIKit


// class to handle HTTP requests and manages the connection to a server.
class MlaasModel: NSObject, URLSessionDelegate{
    
    //MARK: Properties and Delegation
    private let operationQueue = OperationQueue()  //used to manage tasks
    private var dsid:Int = 5  //private variable to store the DSID
    var delegate:ClientDelegate?  // create a delegate for using the protocol i.e. to communicate with the view controller
    
    // default ip, if you are unsure try: ifconfig |grep "inet " to see what your public facing IP address
    var server_ip: String = "192.168.1.210" {
        didSet {
            print("Server IP updated to: \(server_ip)")
        }
    }
    
    // updates the DSID value
    func updateDsid(_ newDsid:Int){
        dsid = newDsid
    }
    
    //returns current DSID value
    func getDsid()->(Int){
        return dsid
    }
    
    // a URL session with custom configs to handle requests with a timeout and max number of connections
    lazy var session = {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 5.0  //timeout for request
        sessionConfig.timeoutIntervalForResource = 8.0  //timeout for resource
        sessionConfig.httpMaximumConnectionsPerHost = 1  //max number of connections per host
        
        // initiate a temporary URS session with above configs. View controller is the delegate
        return URLSession(configuration: sessionConfig, delegate: self, delegateQueue:self.operationQueue)
    }()
    
    
    //MARK: Setters and Getters
    
    //check if the provided IP is valied and set it as the server IP
    func setServerIp(ip:String)->(Bool){
        
        // user is trying to set ip: make sure that it is valid ip address
        if matchIp(for:"((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\\.|$)){4}", in: ip){
            server_ip = ip
            return true  // return success
        }else{
            return false
        }
    }
    
    
    //MARK: Main Functions
    
    //Lab: Send image data to the server for prediction
    func sendImageData(_ imageData: Data) {
        let baseURL = "http://\(server_ip):8000/predict_image/"
        let postUrl = URL(string: "\(baseURL)")
        
        var request = URLRequest(url: postUrl!)
        
        // Create request body by encoding the image data into base64 format
        let requestBody: Data = try! JSONSerialization.data(withJSONObject: ["image": imageData.base64EncodedString(), "dsid": self.dsid])
        
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestBody
        
        let postTask: URLSessionDataTask = self.session.dataTask(with: request, completionHandler: { (data, response, error) in
            if error != nil {
                print("Error from server")
                if let res = response {
                    print("Response:\n", res)
                }
            } else {
                if let delegate = self.delegate {
                    let jsonDictionary = self.convertDataToDictionary(with: data)
                    delegate.receivedPrediction(jsonDictionary)
                }
            }
        })
        postTask.resume()
    }
    
    
    
    // get and store a new DSID. Update the UI with new DSID
    func getNewDsid(){
        let baseURL = "http://\(server_ip):8000/max_dsid/"  //construct base URL
        let postUrl = URL(string: "\(baseURL)")  //create URL object from base URL
        var request = URLRequest(url: postUrl!)  // create a custom HTTP POST request to configure and sent HTTP request
        
        request.httpMethod = "GET"  //set HTTP method to GET (requesting data from server)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")  //tell the server that the client expects and will send data in JSON format.
        
        //create URL session data task that will perform the HTTP request asynchronously.
        let getTask : URLSessionDataTask = self.session.dataTask(with: request, completionHandler:{(data, response, error) in
            let jsonDictionary = self.convertDataToDictionary(with: data)  //convert raw data returned from server into a dict
             
            // check if the delegate has been set to the view controller, if response from the server exists and the dict containts a vlid dsid field of type Int
            if let delegate = self.delegate, let resp=response, let dsid = jsonDictionary["dsid"] as? Int {
                self.dsid = dsid+1  //increase dsid value by 1 which represents new dsid
                delegate.updateDsid(self.dsid)  //update UI with new dsid
                print(resp)  //print response object for debugging purpose
            }
        })
        getTask.resume() // start the task to send the HTTP GET request to the server
        
    }
    
    
    // to send a GET request to the server to trigger the training of a model on the server-side identifed by DSID and retrieve a summary of the process
    func trainModel(){
        let baseURL = "http://\(server_ip):8000/train_model_turi/\(dsid)"
        let postUrl = URL(string: "\(baseURL)")
        var request = URLRequest(url: postUrl!)
        
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let getTask : URLSessionDataTask = self.session.dataTask(with: request, completionHandler:{(data, response, error) in
            let jsonDictionary = self.convertDataToDictionary(with: data)  //convert raw data from the server into a dict

            //check if the dict has key "summary" & value as string
            if let summary = jsonDictionary["summary"] as? String {
                print(summary)  //print the summary of the model training process on the console
            }

        })
        getTask.resume() // start the task to send the GET request to the server
        
    }
    
    
    //MARK: Utility Functions
    
    //check if a given text matches a pattern specified by the regex string.
    private func matchIp(for regex:String, in text:String)->(Bool){
        do {
            let regex = try NSRegularExpression(pattern: regex)  //create NSRegularExpression object
            let results = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))  //find matches of the regular expression in the given text
            if results.count > 0{return true}  //if any match found return true
        } catch _{
            return false  //no valid match was found due to error in processing
        }
        return false //not match was found in the text
    }
    
    
    // to convert raw JSON data into a dict
    private func convertDataToDictionary(with data:Data?)->[String:Any]{
        do {
            // deserialize the data object into a JSON object
            let jsonDictionary: [String:Any] =
                try JSONSerialization.jsonObject(with: data!, options: JSONSerialization.ReadingOptions.mutableContainers) as! [String : Any]
            return jsonDictionary //returned the parsed dict (JSON)
            
        } catch {
            print("json error: \(error.localizedDescription)")  //details if parsing fail
            
            // convert raw data into human readable format for debugging purpose
            if let strData = String(data:data!, encoding:String.Encoding(rawValue: String.Encoding.utf8.rawValue)){
                print("printing JSON received as string: "+strData)
            }
            return [String:Any]() // if error occurs, just return empty dict
        }
    }
}

