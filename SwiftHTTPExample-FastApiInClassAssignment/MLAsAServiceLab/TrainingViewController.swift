import UIKit
import AVFoundation
import Vision

class TrainingViewController: UIViewController, ClientDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private var captureSession: AVCaptureSession?   //Manages the flow of data from the camera
    private var videoDeviceInput: AVCaptureDeviceInput?  //Represents the camera device input
    private var previewLayer: AVCaptureVideoPreviewLayer!  //Displays the camera feed
    private var currentCameraPosition: AVCaptureDevice.Position = .front  //use front camera
    private var handPoseData: [[String: Any]] = []   //Stores dict data related to hand poses
    private var labelForCapture: String = "Rock"  //Label for the captured data
    private var shouldCaptureData = false  //to control data capture
    
    //Maps joint names from Vision framework to human-readable names
    private let jointNameMapping: [String: String] = [
        "VNHLKTTIP": "thumbTip",
        "VNHLKTIP": "thumbIP",
        "VNHLKTMP": "thumbMP",
        "VNHLKTCMC": "thumbCMC",
        "VNHLKITIP": "indexTip",
        "VNHLKIDIP": "indexDIP",
        "VNHLKIPIP": "indexPIP",
        "VNHLKIMCP": "indexMCP",
        "VNHLKMTIP": "middleTip",
        "VNHLKMDIP": "middleDIP",
        "VNHLKMIP": "middlePIP",
        "VNHLKMMCP": "middleMCP",
        "VNHLKRTIP": "ringTip",
        "VNHLKRDIP": "ringDIP",
        "VNHLKRPIP": "ringPIP",
        "VNHLKRMCP": "ringMCP",
        "VNHLKPTIP": "pinkyTip",
        "VNHLKPDIP": "pinkyDIP",
        "VNHLKPPIP": "pinkyPIP",
        "VNHLKPMCP": "pinkyMCP",
        "VNHLKWRI": "wrist"
    ]
    
    private let handPoseRequest = VNDetectHumanHandPoseRequest()  //Request to detect hand poses
    private var handPoints: [CGPoint] = []  //Stores the coordinates of detected hand points
    private let coordinateConfidence: Float = 0.5 //Confidence threshold for detected points
    
    @IBOutlet weak var cameraView: UIView!  //displaying the camera feed
    @IBOutlet weak var rockButton: UIButton!  //to initiate collecting data for rock hand pose
    @IBOutlet weak var paperButton: UIButton!  //to initiate collecting data for paper hand pose
    @IBOutlet weak var scissorsButton: UIButton!  //to initiate collecting data for scissors hand pose
    @IBOutlet weak var switchCameraButton: UIButton!  //to switch between front & rear camera
    @IBOutlet weak var trainTuriButton: UIButton!  //to initiate training
    @IBOutlet weak var trainKnnButton: UIButton!  //KNN classifier
    @IBOutlet weak var trainXGBoostButton: UIButton!  //XGBoost classifier
    @IBOutlet weak var modelLabel: UILabel!  //model name
    
    let client = MlaasModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()  //initialize the camera
        setupUI()  //setup the UI elements
        client.delegate = self  //set the view controller as delegate
        
        //Loads the IP address from settings and sets it in the client
        if let ipAddress = AppSettings.shared.loadData(key: "IPAddress") as? String {
            _ = client.setServerIp(ip: ipAddress)
        }
        
        // Set DSID Based On Local Storaage
        if let dsid = AppSettings.shared.loadData(key: "DSID") as? Int {
            client.updateDsid(dsid)
        }
    }
    
    // Set Up Camera To Capture Video
    private func setupCamera() {
        captureSession = AVCaptureSession()  //initialize the capture session
        guard let captureSession = captureSession else { return }
        
        //try to get front camera as the input device
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoDeviceInput) else {
            return
        }

        self.videoDeviceInput = videoDeviceInput  //add the video input to the capture session
        captureSession.addInput(videoDeviceInput)  //for capturing video frames from the captured video data

        //check if the capture session can accept the video output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))  //set the viewcontroller as the delegate to handle sample video buffer
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput) //add video output to capture session to start receiving video data & send it to the view controller for processing
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession) //create layer to display live video feed from camera on screen
        previewLayer.videoGravity = .resizeAspect  //ensure that video fills the screen while maintining aspect ratio
        previewLayer.frame = cameraView.bounds
        cameraView.layer.addSublayer(previewLayer)  //add this layer as sublayer allowing the camera feed to be shown on screen

        captureSession.startRunning() //start the capture session
    }
    
    // Configure Event Handlers
    private func setupUI() {
        rockButton.addTarget(self, action: #selector(captureRock), for: .touchUpInside)
        paperButton.addTarget(self, action: #selector(capturePaper), for: .touchUpInside)
        scissorsButton.addTarget(self, action: #selector(captureScissors), for: .touchUpInside)
        switchCameraButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        trainTuriButton.addTarget(self, action: #selector(trainTuriModel), for: .touchUpInside)
        trainKnnButton.addTarget(self, action: #selector(trainRandomForestModel), for: .touchUpInside)
        trainXGBoostButton.addTarget(self, action: #selector(trainXGBoostModel), for: .touchUpInside)
    }
    
    // Capture Image And Label As Rock
    @objc private func captureRock() {
        labelForCapture = "Rock"
        shouldCaptureData = true
    }
    
    // Capture Image And Label As Paper
    @objc private func capturePaper() {
        labelForCapture = "Paper"
        shouldCaptureData = true
    }
    
    // Capture Image And Label As Scissors
    @objc private func captureScissors() {
        labelForCapture = "Scissors"
        shouldCaptureData = true
    }
    
    // Submit Request To Train Model Letting Turi Choose The Model Type
    @objc private func trainTuriModel() {
        self.client.trainModel()
    }
    
    // Submit Request To Train Model Using KNN
    @objc private func trainRandomForestModel() {
        self.client.trainModel(modelType: "random_forest")
    }
    
    // Submit Request To Train Model Using XGBoost
    //IMPORTANT - XGBOOST AND BOOSTED TREE ARE NOT THE SAME THING
    //HOWEVER TOO MANY CHANGES TO CHANGE VARIABLES AND LABELS
    @objc private func trainXGBoostModel() {
        self.client.trainModel(modelType: "xgboost")
    }
    
    // Rotate Camera From Front To Back and Vice Versa
    // It Is Easier To Use The Front Camera
    @objc private func switchCamera() {
        guard let captureSession = captureSession, let videoDeviceInput = videoDeviceInput else { return }
        captureSession.beginConfiguration()
        
        captureSession.removeInput(videoDeviceInput)
        currentCameraPosition = currentCameraPosition == .front ? .back : .front
        
        guard let newVideoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition),
              let newVideoDeviceInput = try? AVCaptureDeviceInput(device: newVideoDevice),
              captureSession.canAddInput(newVideoDeviceInput) else {
            captureSession.commitConfiguration()
            return
        }
        
        captureSession.addInput(newVideoDeviceInput)
        self.videoDeviceInput = newVideoDeviceInput
        captureSession.commitConfiguration()
    }

    //when video frame is captured, process it to detect hand poses
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        //extract the pixel buffer from the sample buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])  //create img request handler to perform vision request on img data
        do {
            try requestHandler.perform([handPoseRequest])  //try to perform hand pose request using the img handler
            
            //checi if the request has results with observations
            if let observations = handPoseRequest.results, !observations.isEmpty {
                processHandPoseForModel(observations.first!)  // Process To Capture Data For Model (first observation because one hand)
                processHandPose(observations.first!)  // Process To Show Position On Screen
            }
        } catch {
            print("Error performing hand pose request: \(error)")
        }
    }
    

    // Capture Data And Update Screen
    private func processHandPose(_ observation: VNHumanHandPoseObservation) {
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else { return }  //get recognized points from the observation
        
        handPoints.removeAll()  //clear the points first
        
        //from each recognized points, check if its confidence > 50%, then only add them to the handpoints dict
        for (_, point) in recognizedPoints {
            if point.confidence > coordinateConfidence {
                 handPoints.append(point.location)
            }
        }
        
        DispatchQueue.main.async {
            self.displayHandPoints()  //display the hand points
        }
    }
    
    // Capture Data And Convert Coordinates Into A Vector That We Can Use For Training
    private func processHandPoseForModel(_ observation: VNHumanHandPoseObservation) {
        guard shouldCaptureData else { return } // Only process if capture is enabled
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else { return }

        var featureVector: [Double] = []
        var columnNames: [String] = []

        // I Think They Should Always Be In The Same Order But
        // Sort By Name To Be Sure
        let sortedPoints = recognizedPoints
            .map { (jointName, point) -> (String, CGPoint) in
                let humanReadableName = jointNameMapping[jointName.rawValue.rawValue] ?? jointName.rawValue.rawValue
                if point.confidence > coordinateConfidence {
                    return (humanReadableName, point.location)
                } else {
                    // Set values to (0, 0) if confidence is low
                    // TODO: Need To Review This Logic
                    return (humanReadableName, CGPoint(x: 0, y: 0))
                }
            }
            .sorted { $0.0 < $1.0 }

        for (humanReadableName, location) in sortedPoints {
            // Create A Feature For The X and Y For Each Point
            featureVector.append(Double(location.x))
            featureVector.append(Double(location.y))
            
            // Columns For Debugging
            columnNames.append("\(humanReadableName)_x")
            columnNames.append("\(humanReadableName)_y")
        }

        // Output For Debugging
        print("Feature Vector for Label: \(labelForCapture)")
        print("Columns: \(columnNames.joined(separator: ", "))")
        print("Values: \(featureVector)")

        // Send To Server
        self.client.sendData(featureVector, withLabel: labelForCapture)
        
        // Indicate To Stop Capturing
        shouldCaptureData = false
    }

    //display red circles at hand points for visual feedback
    private func displayHandPoints() {
        cameraView.layer.sublayers?.removeAll(where: { $0 is CAShapeLayer })  //to ensure old hand points are cleared before drawing new ones
        
        guard let previewLayer = previewLayer else { return }  //ensure that preview layer is not nil
        
        //iterate over each hand point
        for point in handPoints {
            let normalizedPoint = CGPoint(x: point.x, y: 1 - point.y)  //invert y coordinates of normalized point from vision framework for visualization
            let convertedPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)  //convert normalized points to coordinate space of preview layer

            let circleLayer = CAShapeLayer()  //create new shaper layer for each hand point
            
            // circular path of 5 pts radius and fill color as red going clockwise
            let circlePath = UIBezierPath(
                arcCenter: convertedPoint,
                radius: 5,
                startAngle: 0,
                endAngle: CGFloat.pi * 2,
                clockwise: true
            )
            circleLayer.path = circlePath.cgPath
            circleLayer.fillColor = UIColor.red.cgColor
            cameraView.layer.addSublayer(circleLayer)  //overlay circles on hand joints
        }
    }
    
    // Delegate From Model Class - Not Handled In This Controller - Do Nothing
    func updateDsid(_ newDsid:Int){
    }
    
    // Delegate From Model Class - Not Handled In This Controller - Do Nothing
    func receivedPrediction(_ prediction:[String:Any]){

    }
    
    // Display Selected Model
    func receiveModel(_ model:String){
        DispatchQueue.main.async{
            self.modelLabel.text = model
        }
    }
}
