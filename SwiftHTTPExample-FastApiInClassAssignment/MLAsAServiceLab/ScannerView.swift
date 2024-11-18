
//  Copyright © 2024 Eric Larson. All rights reserved.
//

import SwiftUI
import AVFoundation
import Vision


struct ContentView: View {
    
    @State private var handPoseInfo: String = "Detecting hand poses..."  //msg to indicate if hand pose is detected
    @State private var handPoints: [CGPoint] = []   //array that stores joint points of the hand
    private var mlModel = MlaasModel() // Reference to MlaasModel for sending data to server
    
    private var captureSession: AVCaptureSession? = AVCaptureSession()  // Create an instance of capture session
    
    //view's layout & content
    var body: some View {
        
        //for layer views
        ZStack(alignment: .bottom) {
            
            //Add scanner view to zstack: responsible for camera feed & hand detection
            ScannerView(handPoseInfo: $handPoseInfo, handPoints: $handPoints, captureSession: captureSession).onChange(of: handPoints) { newHandPoints in
                self.sendHandPoseDataToServer(handPoints: newHandPoints)  // watch handpoints array for change & send hand pose data "newHandPoints" to the server
            }
            
            // Draw lines between finger joints and the wrist for visual representation of hand's sekeleton
            Path { path in
                let fingerJoints = [
                    [1, 2, 3, 4],    // Thumb joints (thumbCMC -> thumbMP -> thumbIP -> thumbTip)
                    [5, 6, 7, 8],    // Index finger joints
                    [9, 10, 11, 12],  // Middle finger joints
                    [13, 14, 15, 16],// Ring finger joints
                    [17, 18, 19, 20] // Little finger joints
                ]
                
                //find the index of the wrist point (handPoints.first) in the handPoints array
                if let wristIndex = handPoints.firstIndex(where: { $0 == handPoints.first }) {
                    
                    //loop thru each joints and join at least two joints in the array to draw the line
                    for joints in fingerJoints {
                        guard joints.count > 1 else { continue }

                        // Connect wrist to the first joint of each finger
                        // if the index of the first joint is valid
                        if joints[0] < handPoints.count {
                            let firstJoint = handPoints[joints[0]]   //get the CGPoint of the first joint
                            let wristPoint = handPoints[wristIndex]  //get the CGPoint of the writs joint
                            path.move(to: wristPoint)  //move the drawing cursor to the wrist point
                            path.addLine(to: firstJoint) //draw the line from wrist to the first joint of the finger
                        }

                        // Connect the joints within each finger
                        // loop thru all indices of the joints except for the last one
                        for i in 0..<(joints.count - 1) {
                            
                            //check if the current joint & the next joint indices are valid
                            if joints[i] < handPoints.count && joints[i + 1] < handPoints.count {
                                let startPoint = handPoints[joints[i]]     //get the CGPoint for the current joint
                                let endPoint = handPoints[joints[i + 1]]   //get the CGpoint for hte next joint
                                path.move(to: startPoint)   //move the drawing cursor to the current joint
                                path.addLine(to: endPoint)  //draw a line from the current joint to the next joint
                            }
                        }
                    }
                }
            }
            .stroke(Color.blue, lineWidth: 3)  //line setting
            
            
            // Draw circles for the hand points, including the wrist for representation of the finger joints
            ForEach(handPoints, id: \.self) { point in Circle()
                    .fill(.red)
                    .frame(width: 15)
                    .position(x: point.x, y: point.y)
            }
            
            //to show the status of the hand detection
            Text(handPoseInfo)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 50)
        }
        .edgesIgnoringSafeArea(.all)
    }
    
    
    // Function to send hand pose data "handPoints" to the server
    private func sendHandPoseDataToServer(handPoints: [CGPoint]) {
        
        //create dict with hand points & dsid from the model. Convert the handpoints to array dict (Json) with x & y as keys
        let handData: [String: Any] = [
            "handPoints": handPoints.map { ["x": $0.x, "y": $0.y] },
            "dsid": mlModel.getDsid()  //dsid of the model
        ]
        
        // Serialize the handData dict to JSON & Send the it to the server via MlaasModel
        if let data = try? JSONSerialization.data(withJSONObject: handData, options: .prettyPrinted) {
            mlModel.sendImageData(data)
        }
    }
}



//manage camera feed & hand pose detectiion using vision, capture video frames, process them to detect hand poses, update UI
struct ScannerView: UIViewControllerRepresentable {
    
    //update parent view with hand pose info & points
    @Binding var handPoseInfo: String
    @Binding var handPoints: [CGPoint]
    
    let captureSession: AVCaptureSession?  //manage the capture of the video
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        
        // try to create AVCaptureDevice for the video from device & add that to the capture session as input
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              captureSession!.canAddInput(videoInput) else {
            return viewController  //return UIViewController with no config if this fails
        }
        
        //add the vide input to the capture session & capture video frames for the output
        captureSession!.addInput(videoInput)
        let videoOutput = AVCaptureVideoDataOutput()
        
        //if capture capture session can accept video output:
        if captureSession!.canAddOutput(videoOutput) {
            videoOutput.setSampleBufferDelegate(context.coordinator, queue: DispatchQueue(label: "videoQueue"))  //set sample buffere delegate to the coordinator
            captureSession!.addOutput(videoOutput)  //add the video output to the capture session
        }
        
        //create the video preview layer to display the video feed & add it to the view controller's view
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer.frame = viewController.view.bounds  //set the frame of the preview layer (equal to the bound of the view controller view)
        previewLayer.videoGravity = .resizeAspectFill  //set the video gravity
        viewController.view.layer.addSublayer(previewLayer)  //add the layer as sublayer to the controller's view
        
        //Start the capture session in an asynchronous task & return the configured view controller
        Task {
            captureSession!.startRunning()
        }
        return viewController
    }
    
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    //create & return instance of "Coordinator class" that handles the video output processing
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    
    //responsible for handling the vide frame capture
    class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        var parent: ScannerView  //parent is the ScannerView. This lets the coordinator to update the ScannerView
        
        //initialize the parent property as the ScannerView
        init(_ parent: ScannerView) {
            self.parent = parent
        }
        
        //gets called when a new video frame is captured by the camera
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            
            //tries to get the img pixels buffer from the sample buffer
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return  //return nil if it fails
            }
            self.detectHandPose(in: pixelBuffer)
        }
        
        //detect hand pose using the image pixels
        func detectHandPose(in pixelBuffer: CVPixelBuffer) {
            
            //create the request to detect the hand poses in the image
            let request = VNDetectHumanHandPoseRequest { (request, error) in
                
                //results are the observations that contain detect hand poses (joint coordinates)
                guard let observations = request.results as? [VNHumanHandPoseObservation], !observations.isEmpty else {
                    
                    //if no hands (observation=empty)detected, update the UI on main thread
                    DispatchQueue.main.async {
                        self.parent.handPoseInfo = "No hand detected"  //set the hand pose info
                        self.parent.handPoints = []  //leave the hand points array empty
                    }
                    return
                }
                
                //get the first observation (i.e. only one hand is detected)
                if let observation = observations.first {
                    var points: [CGPoint] = []  //array to store the coordinates of the hand joints
                    
                    // Loop through all recognized points for each finger, including wrist
                    let handJoints: [VNHumanHandPoseObservation.JointName] = [
                        .wrist,  // Wrist joint
                        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,   // Thumb joints
                        .indexMCP, .indexPIP, .indexDIP, .indexTip, // Index finger joints
                        .middleMCP, .middlePIP, .middleDIP, .middleTip, // Middle finger joints
                        .ringMCP, .ringPIP, .ringDIP, .ringTip,     // Ring finger joints
                        .littleMCP, .littlePIP, .littleDIP, .littleTip // Little finger joints
                    ]
                    
                    //go through each defined joints
                    for joint in handJoints {
                        
                        //if the joint is recognized with 50% confidence, add them to the array
                        if let recognizedPoint = try? observation.recognizedPoint(joint), recognizedPoint.confidence > 0.5 {
                            points.append(recognizedPoint.location)
                        }
                    }
                    
                    // Convert normalized Vision points to screen coordinates and update coordinates
                    self.parent.handPoints = points.map { self.convertVisionPoint($0) }
                    self.parent.handPoseInfo = "Hand detected with \(points.count) points"
                }
            }
            
            request.maximumHandCount = 1  //request is only for one hand
            
            //create img request handler to process img data using the pixels. Keep the image normally oriented (no rotation), options is for additional settings
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            
            //try to run vision request by processing the img pixels to detect hand poses
            do {
                try handler.perform([request]) //results is passes inside an array since handler can process multiple requests at once
            } catch {
                print("Hand pose detection failed: \(error)")
            }
        }
        
        // Convert Vision's normalized coordinates to screen coordinates
        func convertVisionPoint(_ point: CGPoint) -> CGPoint {
            let screenSize = UIScreen.main.bounds.size  //get the width & height of the screen to scale the noramlized coordinates
            let y = point.y * screenSize.height  //map normalized y value to screen's height
            let x = point.x * screenSize.width   //map normalized x value to screen's width
            return CGPoint(x: x, y: y)  //return the newly calculated x & y screen coordinages
        }
    }
}


//custom view "CameraPreviewView" for displaying the camera feed
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession  //capture session to get access to the camera
    
    //responsible for creating the UIView (required for UIViewRepresentable protocol)
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)  //create new UIView with the frame set to size of the screen
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)  //create the video preview layer used to display live camera feed
        previewLayer.frame = view.frame  //set the frame of the preview layer to the size of the view
        previewLayer.videoGravity = .resizeAspectFill  //ensure that camera preview maintains its aspect ratio while filling the screen
        view.layer.addSublayer(previewLayer)  //add the preview layer as the sublayer to the view's layer
        return view  //return the view
    }
    //update the existing view when the SwiftUI view's state changes (equired for UIViewRepresentable protocol)
    func updateUIView(_ uiView: UIView, context: Context) {}
}

