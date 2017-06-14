//
//  ViewController.swift
//  ObjectTracker
//
//  Created by Jeffrey Bergier on 6/8/17.
//  Copyright © 2017 Saturday Apps. All rights reserved.
//

import AVFoundation
import Vision
import UIKit

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet private weak var cameraView: UIView?
    @IBOutlet private weak var highlightView: UIView? {
        didSet {
            self.highlightView?.layer.borderColor = UIColor.green.cgColor
            self.highlightView?.layer.borderWidth = 2
            self.highlightView?.layer.cornerRadius = 6
            self.highlightView?.backgroundColor = UIColor(red: 0, green: 1, blue: 0, alpha: 0.2)
        }
    }
    
    private let visionSequenceHandler = VNSequenceRequestHandler()
    private lazy var cameraLayer: AVCaptureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
    private lazy var captureSession: AVCaptureSession = {
        let session = AVCaptureSession()
        session.sessionPreset = AVCaptureSession.Preset.hd1920x1080
        guard
            let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: backCamera)
            else { return session }
        session.addInput(input)
        return session
    }()
    
    lazy var originPoint = CGPoint()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // hide the red focus area on load
        self.highlightView?.frame = .zero
        
        // make the camera appear on the screen
        self.cameraView?.layer.addSublayer(self.cameraLayer)
        
        // register to receive buffers from the camera
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "MyQueue"))
        self.captureSession.addOutput(videoOutput)
        
        // begin the session
        self.captureSession.startRunning()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // make sure the layer is the correct size
        self.cameraLayer.frame = self.cameraView?.bounds ?? .zero
    }
    
    private var lastObservation: VNDetectedObjectObservation?
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard
            // make sure the pixel buffer can be converted
            let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            // make sure that there is a previous observation we can feed into the request
            let lastObservation = self.lastObservation
            else { return }
        
        // create the request
        let request = VNTrackObjectRequest(detectedObjectObservation: lastObservation, completionHandler: self.handleVisionRequestUpdate)
        // set the accuracy to high
        // this is slower, but it works a lot better
        request.trackingLevel = .accurate
        
        // perform the request
        do {
            try self.visionSequenceHandler.perform([request], on: pixelBuffer)
        } catch {
            print("Throws: \(error)")
        }
    }
    
    private func handleVisionRequestUpdate(_ request: VNRequest, error: Error?) {
        // Dispatch to the main queue because we are touching non-atomic, non-thread safe properties of the view controller
        DispatchQueue.main.async {
            // make sure we have an actual result
            guard let newObservation = request.results?.first as? VNDetectedObjectObservation else { return }
            
            // prepare for next loop
            self.lastObservation = newObservation
            
            // check the confidence level before updating the UI
            if newObservation.confidence >= 0.3 {
                self.highlightView?.layer.borderColor = UIColor.green.cgColor
                self.highlightView?.backgroundColor = UIColor(red: 0, green: 1, blue: 0, alpha: 0.2)
            } else {
                self.highlightView?.layer.borderColor = UIColor.gray.cgColor
                self.highlightView?.backgroundColor = UIColor(white: 1, alpha: 0.2)
                return
            }
            
            // calculate view rect
            var transformedRect = newObservation.boundingBox
            transformedRect.origin.y = 1 - transformedRect.origin.y
            let convertedRect = self.cameraLayer.layerRectConverted(fromMetadataOutputRect: transformedRect)
            
            // move the highlight view
            self.highlightView?.frame = convertedRect
        }
    }
    
    @IBAction func userDragged(_ sender: UIPanGestureRecognizer) {
        // get the center of the tap
        
        switch sender.state {
        case .began:
            self.lastObservation = nil
            self.highlightView?.frame = .zero
            self.highlightView?.layer.borderColor = UIColor.green.cgColor
            self.highlightView?.backgroundColor = UIColor(red: 0, green: 1, blue: 0, alpha: 0.2)
            originPoint = sender.location(in: self.view)
        case .changed:
            self.highlightView?.frame = calculateRectangle(firstPoint: originPoint, translationX: sender.translation(in: self.view).x, translationY: sender.translation(in: self.view).y)
        case .ended:
            let originalRect = self.highlightView?.frame ?? .zero
            var convertedRect = self.cameraLayer.metadataOutputRectConverted(fromLayerRect: originalRect)
            convertedRect.origin.y = 1 - convertedRect.origin.y
            
            // set the observation
            let newObservation = VNDetectedObjectObservation(boundingBox: convertedRect)
            self.lastObservation = newObservation
        default:
            print("unexpected error")
        }
    }
    
    func calculateRectangle(firstPoint: CGPoint, translationX: CGFloat, translationY: CGFloat) -> CGRect {
        let size = CGSize(width: abs(translationX), height: abs(translationY))
        
        return CGRect(origin: firstPoint, size: size)
    }
    
    @IBAction private func resetTapped(_ sender: UIBarButtonItem) {
        self.lastObservation = nil
        self.highlightView?.frame = .zero
        print("reset observation")
    }
}


