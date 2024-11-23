//  Created by Eric Larson on 3/30/15.
//  Copyright (c) 2015 Eric Larson. All rights reserved.
//  Updated 2024

// This example is meant to be run with the python example:
//              fastapi_turicreate.py
//              from the course GitHub repository


import UIKit
import CoreMotion
import AVFoundation
import Vision


class ViewController: UIViewController, ClientDelegate, UITextFieldDelegate, AVCapturePhotoCaptureDelegate{
    
    // MARK: Class Properties
    
    // interacting with server
    let client = MlaasModel()
    
    // operation queues
    let motionOperationQueue = OperationQueue()      //handling motion updates
    
    // motion data properties
    var ringBuffer = RingBuffer()
    let motion = CMMotionManager()
    
    // state variables
    var isWaitingForMotionData = false   //indicate if app is ready to process motion data
    
    // User Interface properties
    let animation = CATransition()
    @IBOutlet weak var dsidLabel: UILabel!
    @IBOutlet weak var largeMotionMagnitude: UIProgressView!
    @IBOutlet weak var ipAddressTextField: UITextField! // Add an IBOutlet for the text field
    @IBOutlet weak var handPoseLabel: UILabel!  //Lab: Label to display hand pose detection result
        
    //update the default IP address with one that the user enters
    @IBAction func ipAddressTextFieldEditingDidEnd(_ sender: UITextField) {
        
        //if the new IP is the one that the user enters (checks if not empty)
        if let newIp = sender.text, !newIp.isEmpty {
            
            //update the IP with the user entered IP
            if client.setServerIp(ip: newIp) {
                        print("IP address updated successfully.")
                    } else {
                        print("Invalid IP address provided.")
                    }
                }
    }
    
    //Lab: Camera properties
    var captureSession: AVCaptureSession!          //video capture session
    var photoOutput: AVCapturePhotoOutput!         //captured photo output
    var previewLayer: AVCaptureVideoPreviewLayer!  //video preview layer
    
    
    // MARK: View Controller Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()

        // create reusable animation
        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
        animation.type = CATransitionType.fade
        animation.duration = 0.5
 
        client.delegate = self   // use delegation for interacting with client
        client.updateDsid(5) // set default dsid to start with
        
        ipAddressTextField.delegate = self   // Set the view controller as the delegate for the text field
        
        // Add a toolbar with a done button to dismiss the number pad
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        ipAddressTextField.inputAccessoryView = toolbar
        
        setupCamera()   //Lab:Initialize the camera session for pose detection
    }
    
    
    //MARK: UI Buttons
    
    //to get new dataset ID from the server
    @IBAction func getDataSetId(_ sender: AnyObject) {
        client.getNewDsid() // protocol used to update dsid
    }
    
    //tell the client to train the model
    @IBAction func makeModel(_ sender: AnyObject) {
        client.trainModel()
    }
    
    // MARK: Camera Setup
    func setupCamera() {
 
        captureSession = AVCaptureSession()  // Create capture session
            
            // Set up the front camera for input
            guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return }
            let videoDeviceInput: AVCaptureDeviceInput
            
            //try to capture the video input
            do {
                videoDeviceInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            } catch {
                return
            }
            
            //if we can add the input to the capture session
            if (captureSession.canAddInput(videoDeviceInput)) {
                captureSession.addInput(videoDeviceInput)  //add the input to the capture session
            } else {
                return
            }

            photoOutput = AVCapturePhotoOutput()   // Set up photo output
            
            //if we can add the vide output to the capture session
            if (captureSession.canAddOutput(photoOutput)) {
                captureSession.addOutput(photoOutput)  //add the video output to the session
            } else {
                return
            }
            
            // Set up the preview layer
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = view.layer.bounds   //set the layer frame (equal to the view bounds)
            previewLayer.videoGravity = .resizeAspectFill  //ensure that camera preview maintains its aspect ratio while filling the screen
            view.layer.addSublayer(previewLayer)  //add the layer as the sublayer

            captureSession.startRunning()  // Start the capture session
        }
    
    // Capture the image and detect hand pose
    @IBAction func captureImage(_ sender: UIButton) {
        let settings = AVCapturePhotoSettings()  //setting for the captured imaged
        photoOutput.capturePhoto(with: settings, delegate: self)  //apply the settings to the output. Delegate to the viewcontroller
    }
    
    
    // MARK: AVCapturePhotoCaptureDelegate Method
    // take the processed output image, detect the hand pose & update the handpose label
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        //check if the capture is successful
        if let error = error {
            print("Error capturing photo: \(error)")
            return
        }
        
        //try to get the image from the captured photo
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("Failed to get image from photo output")
            return
        }

        let detectedPose = detectHandPose(from: image)  // Detect hand pose from captured image
        
        // Update the label with the detected pose in the many queue asynchornously
        DispatchQueue.main.async {
            self.handPoseLabel.text = "Detected Pose: \(detectedPose)"
        }
    }
}

//MARK: Protocol Required Functions
extension ViewController {
    
    //update the dsid label on the main thread
    func updateDsid(_ newDsid:Int){
        
        // delegate function completion handler
        DispatchQueue.main.async{
            self.dsidLabel.layer.add(self.animation, forKey: nil)  //update the label with animation
            self.dsidLabel.text = "Current DSID: \(newDsid)"   //update the label to current dsid
        }
    }
    
    //make the corresponding arrow blink based on direction indicated by the response
    func displayLabelResponse(_ response:String){
        switch response {
        case "['Rock']","Rock":
            break
        case "['Paper']","Paper":
            break
        case "['Scissors']","Scissors":
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
            print(labelResponse)
            self.displayLabelResponse(labelResponse)
        }
        else{
            print("Received prediction data without label.")
        }
    }
}


//MARK: Motion Extension Functions
extension ViewController {
    
    // Core Motion Updates
    func startMotionUpdates(){
        
        //if device motion is available
        if self.motion.isDeviceMotionAvailable{
            self.motion.deviceMotionUpdateInterval = 1.0/200  //setting the update interval
        }
    }
    
    
    // A function to detect the hand pose from an image (placeholder for actual pose detection logic)
    func detectHandPose(from image: UIImage) -> String {
        // This is a placeholder function where you would call your pose detection model
        // For example, this could involve CoreML or a custom-trained model to classify the pose
        // Here, we simply return a random pose for demonstration purposes
        
        // Replace with your pose detection logic
        let poses = ["Rock", "Paper", "Scissors"]
        return poses.randomElement() ?? "Unknown"
    }
    

}
