import UIKit
import AVFoundation
import Vision

class PredictionViewController: UIViewController, ClientDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private var captureSession: AVCaptureSession?
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var currentCameraPosition: AVCaptureDevice.Position = .front
    private var handPoseData: [[String: Any]] = []
    private var shouldPredict = false
    private var modelName: String = ""
    
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
    
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    private var handPoints: [CGPoint] = []
    
    private let coordinateConfidence: Float = 0.5
    
    @IBOutlet weak var cameraView: UIView!
    @IBOutlet weak var predictTuriButton: UIButton!
    @IBOutlet weak var predictXGBoostButton: UIButton!
    @IBOutlet weak var predictRandomForestButton: UIButton!
    @IBOutlet weak var switchCameraButton: UIButton!
    @IBOutlet weak var modelLabel: UILabel!
    
    let client = MlaasModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
        
        client.delegate = self
        
        // Set IP Based On Local Storage
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
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoDeviceInput) else {
            return
        }

        self.videoDeviceInput = videoDeviceInput
        captureSession.addInput(videoDeviceInput)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspect
        previewLayer.frame = cameraView.bounds
        cameraView.layer.addSublayer(previewLayer)

        captureSession.startRunning()
    }
    
    // Configure Event Handlers
    private func setupUI() {
        switchCameraButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        predictTuriButton.addTarget(self, action: #selector(predictTuri), for: .touchUpInside)
        predictXGBoostButton.addTarget(self, action: #selector(predictXGBoost), for: .touchUpInside)
        predictRandomForestButton.addTarget(self, action: #selector(predictRandomForest), for: .touchUpInside)
    }
    
    // Capture Image And Predict Letting Turi Choose The Model Type
    @objc private func predictTuri() {
        shouldPredict = true
        modelName = "Turi"
    }
    
    // Capture Image And Predict Using XGBoost
    @objc private func predictXGBoost() {
        shouldPredict = true
        modelName = "XGBoost"
    }
    
    // Capture Image And Predict Using Random Forest
    @objc private func predictRandomForest() {
        shouldPredict = true
        modelName = "Random_Forest"
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
    
    // Capture Video And Process Hand Pose Data
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try requestHandler.perform([handPoseRequest])
            if let observations = handPoseRequest.results, !observations.isEmpty {
                // Predict Based On Current Observation
                predict(observations.first!)
                
                // Process To Show Position On Screen
                processHandPose(observations.first!)
            }
        } catch {
            print("Error performing hand pose request: \(error)")
        }
    }
    
    // Capture Hand Position Data And Use Coordinates To Create An Overlay
    // Displaying The Joints In The Hand
    // Used To Help Make Sure We Are Capturing The Correct Information
    private func processHandPose(_ observation: VNHumanHandPoseObservation) {
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else { return }
        
        handPoints.removeAll()
        
        for (_, point) in recognizedPoints {
            if point.confidence > coordinateConfidence {
                 handPoints.append(point.location)
            }
        }
        
        DispatchQueue.main.async {
            self.displayHandPoints()
        }
    }
    
    // Capture Data And Convert Coordinates Into A Vector That We Can Use For Training
    private func predict(_ observation: VNHumanHandPoseObservation) {
        guard shouldPredict else { return } // Only process if capture is enabled
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
        print("Columns: \(columnNames.joined(separator: ", "))")
        print("Values: \(featureVector)")

        // Send To Server
        if self.modelName.lowercased() == "turi" {
            self.client.sendData(featureVector)
        } else if self.modelName.lowercased()  == "xgboost" {
            self.client.sendData(features: featureVector, modelType: self.modelName.lowercased())
        }
        else if self.modelName.lowercased() == "random_forest" {
            self.client.sendData(features: featureVector, modelType: self.modelName.lowercased())
        }
        else {
            print("Unknown Model: \(modelName)")
        }

        
        // Indicate To Stop Capturing
        shouldPredict = false
    }
    
    

    // Generate Overlay On The Video Showing The Hand Points That Are Being Tracked
    // And There Position. Useful For Debugging.
    private func displayHandPoints() {
        cameraView.layer.sublayers?.removeAll(where: { $0 is CAShapeLayer })
        
        guard let previewLayer = previewLayer else { return }

        for point in handPoints {
            let normalizedPoint = CGPoint(x: point.x, y: 1 - point.y)
            let convertedPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)

            let circleLayer = CAShapeLayer()
            let circlePath = UIBezierPath(
                arcCenter: convertedPoint,
                radius: 5,
                startAngle: 0,
                endAngle: CGFloat.pi * 2,
                clockwise: true
            )
            circleLayer.path = circlePath.cgPath
            circleLayer.fillColor = UIColor.red.cgColor
            cameraView.layer.addSublayer(circleLayer)
        }
    }
    
    // Delegate From Model Class - Not Handled In This Controller - Do Nothing
    func updateDsid(_ newDsid:Int){
    }
    
    // Display Prediction To User
    func receivedPrediction(_ prediction:[String:Any]){
        DispatchQueue.main.async {
            let predictionString = prediction.map { "\($0.key): \($0.value)" }.joined(separator: "\n")

            self.modelLabel.text = predictionString
        }
    }
    
    // Delegate From Model Class - Not Handled In This Controller - Do Nothing
    func receiveModel(_ model:String){
    }
}
