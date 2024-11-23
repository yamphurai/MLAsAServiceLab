//
//  HandPoseViewController.swift
//  MLAsAServiceLab
//
//  Created by Reshma Shrestha on 11/17/24.
//  Copyright © 2024 Eric Larson. All rights reserved.
//

import UIKit
import AVFoundation
import Vision
import CoreMotion

class HandPoseViewController: UIViewController, ClientDelegate, UITextFieldDelegate, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate{
    
    private var handPoseInfo: String = "Detecting hand poses..."  // message to indicate if hand pose is detected
    private var handPoints: [CGPoint] = []   // array that stores joint points of the hand
    private var captureSession: AVCaptureSession?  //capture session
    let client = MlaasModel()  // interacting with server
    
    var ringBuffer = RingBuffer()  // motion data properties
    var captureTimer: Timer?   //timer for the image capture to collect joints coordinates
    var handPoseData: [[String: Any]] = []   // To store hand pose data points
    
    // Camera properties
    var videoPreviewFrame: CGRect!  //custom video preview frame
    var photoOutput: AVCapturePhotoOutput!         //captured photo output
    var previewLayer: AVCaptureVideoPreviewLayer!  //video preview layer
    let animation = CATransition()
    
    //MARK: - UI Buttons
    @IBOutlet weak var dsidLabel: UILabel!
    
    @IBOutlet weak var IPAddress: UILabel!
    @IBOutlet weak var ipAddressTextField: UITextField! // Add an IBOutlet for the text field
    @IBOutlet weak var handPoseLabel: UILabel!  //Lab: Label to display hand pose detection result
    //@IBOutlet weak var cameraView: UIView!  //UI view for the camera
    

    //update the default IP address with one that the user enters
    @IBAction func ipAddressTextFieldEditingDidEnd(_ sender: UITextField) {
        if let newIp = sender.text, !newIp.isEmpty {
            if client.setServerIp(ip: newIp) {
                print("IP address updated successfully.")
            } else {
                print("Invalid IP address provided.")
            }
        }
    }
    
    //to get new dataset ID from the server
    @IBAction func getDataSetId(_ sender: AnyObject) {
        client.getNewDsid() // protocol used to update dsid
    }
    
    //tell the client to train the model
    @IBAction func makeModel(_ sender: AnyObject) {
        client.trainModel()
    }
    
    //button to start camera and image collection
    @IBAction func startCollect(_ sender: Any) {
        setupCamera(videoPreviewFrame: videoPreviewFrame)  //start the camera setup
    }
    
    // MARK: - Setup and Initialization Functions
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupCamera(videoPreviewFrame: videoPreviewFrame)
    }
    
    private func setupView() {
        self.view.addSubview(handPoseLabel)
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.type = .fade
        animation.duration = 0.5
        client.delegate = self
        client.updateDsid(5)
        ipAddressTextField.delegate = self
        setupToolbar()
        videoPreviewFrame = CGRect(x: 20, y: 200, width: self.view.frame.width - 40, height: 550)  //customer video preview frame
    }
    
    private func setupToolbar() {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        ipAddressTextField.inputAccessoryView = toolbar
    }
    
    // Set up the camera for video capture session
    private func setupCamera(videoPreviewFrame: CGRect) {
        let captureSession = AVCaptureSession() //create capture session
        self.captureSession = captureSession
        
        //try to get the front camera as video capture device & check if the session can accept video input
        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              captureSession.canAddInput(videoInput) else {
            return
        }
        
        captureSession.addInput(videoInput) //add the video input to the capture session
        let videoOutput = AVCaptureVideoDataOutput()  //for capturing video frames from the captured video data
        
        //check if the capture session can accept the video output
        if captureSession.canAddOutput(videoOutput) {
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))  //set the viewcontroller as the delegate to handle sample video buffer
            captureSession.addOutput(videoOutput)  //add video output to capture session to start receiving video data & send it to the view controller for processing
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)  //create layer to display live video feed from camera on screen
        previewLayer.frame = videoPreviewFrame //use custom video preview frame
        previewLayer.videoGravity = .resizeAspectFill  //ensure that video fills the screen while maintining aspect ratio
        self.view.layer.addSublayer(previewLayer)  //add this layer as sublayer allowing the camera feed to be shown on screen
        
        captureSession.startRunning()  //start the capture session
    }
    
    
    // MARK: -Core Functionalities (Detection and Processing)
    
    //request handler for captured image to process the image to get hand pose observations
    func handleCapturedImage(_ cgImage: CGImage) {
        
        //request to detect hand pose in the image
        let request = VNDetectHumanHandPoseRequest { request, error in
            
            //results of the request is checked if it's an array of hand pose observations
            guard let observations = request.results as? [VNHumanHandPoseObservation], error == nil else {
                print("Hand pose detection error: \(String(describing: error))")
                return
            }
            
            //process each hand pose observation from the observations array
            for observation in observations {
                self.handleHandPoseObservation(observation)  //process teh detected hand pose
            }
        }
        
        //create a request handler with captured image to perform vision request asynchronously on a global background
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global().async {
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform hand pose request: \(error.localizedDescription)")
            }
        }
    }
    
    // extract recognized hand joint points from each observation and pass those point for further processing
    func handleHandPoseObservation (_ observation: VNHumanHandPoseObservation) {
        
        //try to extract recognized joints from each observation
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else { return }
        extractHandPoseData(points: recognizedPoints)   //add the recognized points with their confidence values to the points dict
    }
    
    
    // Write the hand pose data (coordinates, confidence, names) to a CSV file
    func saveHandPoseDataToCSV() {
        let fileName = "hand_pose_data.csv"   //name of the csv file
        let documentDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!   //save the file in the app's doc directory
        let fileURL = documentDirectoryURL.appendingPathComponent(fileName)  //combine doc directory URL with file name to create full path to the csv file

        var csvText = "jointName,x,y,confidence\n"  //names of the header row in the csv file
        
        //iterate over each entry in the handPoseData dict to get joint data
        for data in handPoseData {
            
            // iterate over each joint's data
            for (jointName, jointData) in data {
                
                //check if the coordinates & confidence are of required type, extract them
                if let jointDataDict = jointData as? [String: Any],
                   let x = jointDataDict["x"] as? CGFloat,
                   let y = jointDataDict["y"] as? CGFloat,
                   let confidence = jointDataDict["confidence"] as? Float {
                    let newLine = "\(jointName),\(x),\(y),\(confidence)\n"   //concatenate joint name with its coordinates & confidence level for the csv file
                    csvText.append(newLine)
                }
            }
        }
        
        //try to write the data to the csv file
        do {
            try csvText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("CSV file saved successfully at \(fileURL.path)")
        } catch {
            print("Failed to create CSV file: \(error.localizedDescription)")
        }
    }
    
    // process recognized points/coordinates & store them in a dict eery 100 frames
    func extractHandPoseData(points: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) {
        var handPose: [String: Any] = [:]   //dict to store joint names (keys), and x & y coordinates with confidence level (values)
        
        //iterate over each value of the above dict to get the coordiantes & confidence level
        for (jointName, point) in points {
            handPose[jointName.rawValue.rawValue] = ["x": point.location.x, "y": point.location.y, "confidence": point.confidence]
        }
        handPoseData.append(handPose)
        
        // Save to CSV every 100 frames/poses
        if handPoseData.count % 100 == 0 {
            saveHandPoseDataToCSV()
        }
    }

    // Subarray array represents indices of joints for each finger. Draw hand pose skeleton and points
    private func drawHandSkeleton() {
        let fingerJoints = [
            [1, 2, 3, 4],    // Thumb joints
            [5, 6, 7, 8],    // Index finger joints
            [9, 10, 11, 12], // Middle finger joints
            [13, 14, 15, 16],// Ring finger joints
            [17, 18, 19, 20] // Little finger joints
        ]
        
        //try to find first element in the handpoints array which is assigned as wrist index
        guard let wristIndex = handPoints.firstIndex(where: { $0 == handPoints.first }) else { return }
        
        //check if there is at least one element in the fingerJoints array to iterate over each joint
        for joints in fingerJoints {
            guard joints.count > 1 else { continue }
            
            //if first joint (wrist) index of current finger is within bounds of the array, Connect wrist to the first joint of each finger
            if joints[0] < handPoints.count {
                drawLine(from: handPoints[wristIndex], to: handPoints[joints[0]])  //draw the line between these two joints
            }
            
            // Connect the joints within each finger. iterate over each joint indices of current finger excetp for last joint
            for i in 0..<(joints.count - 1) {
                
                //if both current joint index & next joint index are within bounds of the array
                if joints[i] < handPoints.count && joints[i + 1] < handPoints.count {
                    drawLine(from: handPoints[joints[i]], to: handPoints[i+1])   //draw a line between these two joints
                }
            }
        }
    }
    
    // to draw lines between two points
    private func drawLine(from start: CGPoint, to end: CGPoint) {
        let path = UIBezierPath()  //create object to define a vector-based path used for drawing a line
        path.move(to: start)  //set the starting point of the line
        path.addLine(to: end)  //add line to the path from current point to the end point
        
        let shapeLayer = CAShapeLayer()  //layer that can draw a vector shape
        shapeLayer.path = path.cgPath  //set the path of the shapeLayer (view of the path)
        shapeLayer.strokeColor = UIColor.blue.cgColor  //color of the stroke
        shapeLayer.lineWidth = 3.0  //width of the line
        self.view.layer.addSublayer(shapeLayer)  //add the shapelayer to the view's layers as sublayer
    }
    

    // MARK: - Data Updates and Server Communication
    
    // Update hand pose info and points
    private func updateHandPoseInfo(info: String, points: [CGPoint]) {
        handPoseLabel.text = info   //update the hand pose UI text label
        if info == "Scissors" {
            sendHandPoseDataToServer(handPoints: points)  // Send hand pose data to server if "scissors" pose detected
        }
    }
    
    // Send hand pose datapoint to the server
    private func sendHandPoseDataToServer(handPoints: [CGPoint]) {
        
        //define a dict with keys of type String & values of type any to send to the server
        let handData: [String: Any] = [
            "handPoints": handPoints.map { ["x": $0.x, "y": $0.y] },   //map each x & y coordinates into an arry of dicts
            "dsid": client.getDsid()  //key is the dsid & value is the model name
        ]
        
        //try to serialize the above hand data dict into JSON data
        if let data = try? JSONSerialization.data(withJSONObject: handData, options: .prettyPrinted) {
            client.sendImageData(data)  //pass the serialized JSON data as an argument to the server
        }
    }
    
    //callback for receiving the result of a model prediction
    func clientDidReceiveResponse(response: [String: Any]) {
        DispatchQueue.main.async {
            if let prediction = response["prediction"] as? String {
                self.handPoseLabel.text = prediction
            }
        }
    }
    
    //callback when the client fails to connect or get a response
    func clientDidFailWithError(error: Error) {
        DispatchQueue.main.async {
            self.handPoseLabel.text = "Failed to connect to server"
        }
    }
    
    // MARK: Camera Output Handling
    
    //callback when photo is captured
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else {
            print("Failed to get photo data representation")
            return
        }
        if let image = UIImage(data: data), let cgImage = image.cgImage {
            handleCapturedImage(cgImage)
        }
    }
    
    
    // MARK: -User Input and UI Updates
    
    //update the dsid label and text field when the user begins editing
    func textFieldDidBeginEditing(_ textField: UITextField) {
        dsidLabel.text = "DSID: \(client.getDsid())"
    }
    
    //When user ends editing and the text field is not empty
    func textFieldDidEndEditing(_ textField: UITextField) {
        guard let text = textField.text, !text.isEmpty else { return }
        client.updateDsid(Int(text) ?? 5)  //update the dsid of the model with the entered value or set it to default value 5
    }
    
    //when user taps the 'return' key on the keyboard while editing the text field
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()  //dismiss the keyboard
        return true
    }

    //update the dsid label on the main thread
    func updateDsid(_ newDsid:Int){
        
        // delegate function completion handler
        DispatchQueue.main.async{
            self.dsidLabel.layer.add(self.animation, forKey: nil)  //update the label with animation
            self.dsidLabel.text = "Current DSID: \(newDsid)"   //update the label to current dsid
        }
    }
    
    //show the predicted label response
    func displayLabelResponse(_ response:String){
        switch response {
        case "Scissors":
            handPoseLabel.text = "Scissors"
            break
        case "Paper":
            handPoseLabel.text = "Paper"
            break
        case "Rock":
            handPoseLabel.text = "Rock"
            break
        default:
            print("Unknown")
            break
        }
    }
    
    //handle the received prediction from the server
    func receivedPrediction(_ prediction:[String:Any]){
        
        //if the response has the prediction
        if let labelResponse = prediction["prediction"] as? String{
            self.displayLabelResponse(labelResponse)
        }
        else{
            print("Received prediction data without label.")
        }
    }
    
    
    //MARK: - Motion Updates
    
    private func updateMotionLabel(with message: String) {
        DispatchQueue.main.async {
            self.handPoseLabel.layer.add(self.animation, forKey: nil)
            self.handPoseLabel.text = message
        }
    }

}

