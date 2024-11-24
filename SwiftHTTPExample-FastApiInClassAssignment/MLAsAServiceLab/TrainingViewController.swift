import UIKit
import AVFoundation
import Vision

class TrainingViewController: UIViewController, ClientDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private var captureSession: AVCaptureSession?
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var currentCameraPosition: AVCaptureDevice.Position = .front
    private var handPoseData: [[String: Any]] = []
    private var labelForCapture: String = "Rock"
    private var shouldCaptureData = false
    
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
    @IBOutlet weak var rockButton: UIButton!
    @IBOutlet weak var paperButton: UIButton!
    @IBOutlet weak var scissorsButton: UIButton!
    @IBOutlet weak var switchCameraButton: UIButton!
    @IBOutlet weak var trainButton: UIButton!
    @IBOutlet weak var modelLabel: UILabel!
    
    let client = MlaasModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
        
        client.delegate = self
        
        if let ipAddress = AppSettings.shared.loadData(key: "IPAddress") as? String {
            _ = client.setServerIp(ip: ipAddress)
        }
    }
    
    
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
    
    private func setupUI() {
        rockButton.addTarget(self, action: #selector(captureRock), for: .touchUpInside)
        paperButton.addTarget(self, action: #selector(capturePaper), for: .touchUpInside)
        scissorsButton.addTarget(self, action: #selector(captureScissors), for: .touchUpInside)
        switchCameraButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        trainButton.addTarget(self, action: #selector(trainModel), for: .touchUpInside)
    }
    
    @objc private func captureRock() {
        labelForCapture = "Rock"
        shouldCaptureData = true
    }
    
    @objc private func capturePaper() {
        labelForCapture = "Paper"
        shouldCaptureData = true
    }
    
    @objc private func captureScissors() {
        labelForCapture = "Scissors"
        shouldCaptureData = true
    }
    
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
    
    @objc private func trainModel() {
        self.client.trainModel()
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try requestHandler.perform([handPoseRequest])
            if let observations = handPoseRequest.results, !observations.isEmpty {
                // Process To Capture Data For Model
                processHandPoseForModel(observations.first!)
                
                // Process To Show Position On Screen
                processHandPose(observations.first!)
            }
        } catch {
            print("Error performing hand pose request: \(error)")
        }
    }
    
    // Capture Data And Update Screen
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
    
    // Capture Data And Convert Coordinates Into A Flat Record That We Can Use For Training
    private func processHandPoseForModel(_ observation: VNHumanHandPoseObservation) {
        guard shouldCaptureData else { return } // Only process if capture is enabled
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else { return }

        var featureVector: [Double] = [] // Coordinates As Vectors
        var columnNames: [String] = []  // Column Names For Debugging

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
    
    // Delegate From Model Class - Not Handler In This Controller - Do Nothing
    func updateDsid(_ newDsid:Int){
    }
    
    // Delegate From Model Class - Not Handler In This Controller - Do Nothing
    func receivedPrediction(_ prediction:[String:Any]){

    }
    
    // Display Selected Model
    func receiveModel(_ model:String){
        DispatchQueue.main.async{
            self.modelLabel.text = model
        }
    }
}
