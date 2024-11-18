//  Copyright © 2024 Eric Larson. All rights reserved.
// Citation: excerpted from "https://www.createwithswift.com/detecting-hand-pose-with-the-vision-framework/" by Luca Palmese

import SwiftUI
import AVFoundation
import Vision


struct ContentView: View {
    
    @State private var handPoseInfo: String = "Detecting hand poses..."  //msg to indicate if hand pose is detected
    @State private var handPoints: [CGPoint] = []   //array that stores joint points of the hand
    private var mlModel = MlaasModel() // Reference to MlaasModel for sending data to server
    
    var body: some View {
        
        //for layer views
        ZStack(alignment: .bottom) {
            
            //responsible for camera feed & hand detection
            ScannerView(handPoseInfo: $handPoseInfo, handPoints: $handPoints).onChange(of: handPoints) { newHandPoints in
                self.sendHandPoseDataToServer(handPoints: newHandPoints)  // Send hand pose data (or processed image) to the server
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
                
                if let wristIndex = handPoints.firstIndex(where: { $0 == handPoints.first }) {
                    for joints in fingerJoints {
                        guard joints.count > 1 else { continue }

                        // Connect wrist to the first joint of each finger
                        if joints[0] < handPoints.count {
                            let firstJoint = handPoints[joints[0]]
                            let wristPoint = handPoints[wristIndex]
                            path.move(to: wristPoint)
                            path.addLine(to: firstJoint)
                        }

                        // Connect the joints within each finger
                        for i in 0..<(joints.count - 1) {
                            if joints[i] < handPoints.count && joints[i + 1] < handPoints.count {
                                let startPoint = handPoints[joints[i]]
                                let endPoint = handPoints[joints[i + 1]]
                                path.move(to: startPoint)
                                path.addLine(to: endPoint)
                            }
                        }
                    }
                }
            }
            .stroke(Color.blue, lineWidth: 3)
            
            
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
    
    
    // Function to send hand pose data to the server
    private func sendHandPoseDataToServer(handPoints: [CGPoint]) {
        
        // Convert handPoints to a format suitable for your model, e.g., JSON or base64-encoded image
        let handData: [String: Any] = [
            "handPoints": handPoints.map { ["x": $0.x, "y": $0.y] },
            "dsid": mlModel.getDsid()
        ]
        
        // Send the hand pose data to the server via MlaasModel
        if let data = try? JSONSerialization.data(withJSONObject: handData, options: .prettyPrinted) {
            mlModel.sendImageData(data)
        }
    }
}
