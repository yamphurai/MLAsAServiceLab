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

class HandPoseViewController: UIViewController {
    
    private var handPoseInfo: String = "Detecting hand poses..."  // message to indicate if hand pose is detected
    private var handPoints: [CGPoint] = []   // array that stores joint points of the hand
    private var mlModel = MlaasModel() // Reference to MlaasModel for sending data to the server
    private var captureSession: AVCaptureSession? = AVCaptureSession()  // Create an instance of capture session
    
    // to update the hand pose label
    private let handPoseLabel: UILabel = {
        let label = UILabel()  //define the label as UIlabel
        label.text = "Detecting hand poses..."  //default text label
        return label
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.addSubview(handPoseLabel)  // Add the hand pose label to the view
        setupCamera()  // Start the capture session
    }
    
    // Set up the camera for video capture session
    private func setupCamera() {
        guard let captureSession = captureSession else { return }  //check if the capture session object exists before continuing
        
        //try to get the camera as video capture device & check if the session can accept video input
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
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
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)  //create layer to display live video feed from camera on screen
        previewLayer.frame = self.view.bounds  //set size & position of the preview layer (cover entire screen)
        previewLayer.videoGravity = .resizeAspectFill  //ensure that video fills the screen while maintining aspect ratio
        self.view.layer.addSublayer(previewLayer)  //add this layer as sublayer allowing the camera feed to be shown on screen
        
        captureSession.startRunning()  //start the capture session
    }
    
    // Send hand pose datapoint to the server
    private func sendHandPoseDataToServer(handPoints: [CGPoint]) {
        
        //define a dict with keys of type String & values of type any to send to the server
        let handData: [String: Any] = [
            "handPoints": handPoints.map { ["x": $0.x, "y": $0.y] },   //map each x & y coordinates into an arry of dicts
            "dsid": mlModel.getDsid()  //key is the dsid & value is the model name
        ]
        
        //try to serialize the above hand data dict into JSON data
        if let data = try? JSONSerialization.data(withJSONObject: handData, options: .prettyPrinted) {
            mlModel.sendImageData(data)  //pass the serialized JSON data as an argument to the server
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
                let firstJoint = handPoints[joints[0]]      //get the coordinates of the fisrt joint of the current finger
                let wristPoint = handPoints[wristIndex]     //get the coordinates of the writst
                drawLine(from: wristPoint, to: firstJoint)  //draw the line between these two joints
            }
            
            // Connect the joints within each finger
            //iterate over each joint indices of current finger excetp for last joint
            for i in 0..<(joints.count - 1) {
                
                //if both current joint index & next joint index are within bounds of the array
                if joints[i] < handPoints.count && joints[i + 1] < handPoints.count {
                    let startPoint = handPoints[joints[i]]     //get the coordinates of the current joint
                    let endPoint = handPoints[joints[i + 1]]   //get the coordinates of the next joint
                    drawLine(from: startPoint, to: endPoint)   //draw a line between these two joints
                }
            }
        }
    }
    
    // Helper function to draw lines between two points
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
    
    // Update hand pose info and points
    private func updateHandPoseInfo(info: String, points: [CGPoint]) {
        handPoseInfo = info
        handPoints = points
        handPoseLabel.text = info
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension HandPoseViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    
    //call detect hand pose when a new video frame is captured
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        //try to get the image buffer (pixels) from the sample buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        detectHandPose(in: pixelBuffer)  //use the pixels to detect hand pose
    }
    
    
    //use the pixels to detect the hand pose
    func detectHandPose(in pixelBuffer: CVPixelBuffer) {
        
        //define the request for the hand pose request
        let request = VNDetectHumanHandPoseRequest { (request, error) in
            
            //results are the observations. Check if they are not empty
            guard let observations = request.results as? [VNHumanHandPoseObservation], !observations.isEmpty else {
                
                //if empty, dpate the hand pose info in main asynchronously no hand pose detected
                DispatchQueue.main.async {
                    self.updateHandPoseInfo(info: "No hand detected", points: [])
                }
                return
            }
            
            //since we're working with one hand only, get the first observation
            if let observation = observations.first {
                var points: [CGPoint] = []   //to store joint coordinates
                
                //get the coordinates of the joints of each finger
                let handJoints: [VNHumanHandPoseObservation.JointName] = [
                    .wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
                    .indexMCP, .indexPIP, .indexDIP, .indexTip,
                    .middleMCP, .middlePIP, .middleDIP, .middleTip,
                    .ringMCP, .ringPIP, .ringDIP, .ringTip,
                    .littleMCP, .littlePIP, .littleDIP, .littleTip
                ]
                
                //go thru each joint & add them to the array "points" if the confidence is greater than 50%
                for joint in handJoints {
                    if let recognizedPoint = try? observation.recognizedPoint(joint), recognizedPoint.confidence > 0.5 {
                        points.append(recognizedPoint.location)
                    }
                }
                self.updateHandPoseInfo(info: "Hand detected with \(points.count) points", points: points)  //update the hand pose info
            }
        }
        
        request.maximumHandCount = 1   //reques is only for one hand
        
        //create img request handler to process img data using the pixels. Keep the image normally oriented (no rotation), options is for additional settings
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        //try to run vision request by processing the img pixels to detect hand poses
        do {
            try handler.perform([request])   //results is passed inside an array since handler can process multiple requests at once
        } catch {
            print("Hand pose detection failed: \(error)")
        }
    }
}
