//
//  LWCameraController.swift
//  LWCameraController
//
//  Created by lailingwei on 16/5/24.
//  Copyright © 2016年 lailingwei. All rights reserved.
//

import UIKit
import AVFoundation

private var SessionQueue = "SessionQueue"

@objc enum LWCamType: Int {
    case Default
    case QRCoder
}


private enum LWCamSetupResult: Int {
    case Success
    case CameraNotAuthorized
    case SessionConfigurationFailed
}


class LWCameraController: NSObject {
    

    // MARK: - Properties
    
    private var previewView: UIView! {
        didSet {
            let layer = (previewView.layer as! AVCaptureVideoPreviewLayer)
            layer.session = self.session
            // Add Tap gesture
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(LWCameraController.focusAndExposeTap(_:)))
            previewView.addGestureRecognizer(tapGesture)
        }
    }
    private var focusImageView: UIImageView?
    
    private let sessionQueue: dispatch_queue_t = dispatch_queue_create(SessionQueue, DISPATCH_QUEUE_SERIAL)
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    private var setupResult: LWCamSetupResult = .Success
    private var camType: LWCamType = .Default
    private var sessionRunning: Bool = false
    private var recording: Bool = false
    private var audioEnabled: Bool = true
    private var tapFocusEnabled: Bool = true
    
    private let session: AVCaptureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var stillImageOutput: AVCaptureStillImageOutput?
    
    
    
    
    // MARK: - Initial
    
    private override init() {
        super.init()
    
        // Check video authorization status
        checkVideoAuthoriztionStatus()
        
        dispatch_async(sessionQueue) {
            guard self.setupResult == .Success else { return }
            self.backgroundRecordingID = UIBackgroundTaskInvalid
        }
    }
    
    
    // Check video authorization status
    private func checkVideoAuthoriztionStatus() {
        
        switch AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo) {
        case .Authorized:
            break
        case .NotDetermined:
            dispatch_suspend(sessionQueue)
            AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo,
                                                      completionHandler: { (granted: Bool) in
                                                        if !granted {
                                                            self.setupResult = .CameraNotAuthorized
                                                        }
                                                        dispatch_resume(self.sessionQueue)
            })
        default:
            setupResult = .CameraNotAuthorized
        }
    }
    
    // Setup the capture session inputs
    private func setupCaptureSessionInputs() {
        
        dispatch_async(sessionQueue) { 
            guard self.setupResult == .Success else { return }
            
            self.session.beginConfiguration()
            
            // Add videoDevice input
            if let videoDevice = LWCameraController.device(mediaType: AVMediaTypeVideo, preferringPosition: .Back) {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    if self.session.canAddInput(videoDeviceInput) {
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                        // Use the status bar orientation as the initial video orientation.
                        dispatch_async(dispatch_get_main_queue(), {
                            let videoPreviewLayer = (self.previewView.layer as! AVCaptureVideoPreviewLayer)
                            videoPreviewLayer.connection.videoOrientation = LWCameraController.videoOrientationDependonStatusBarOrientation()
                        })
                    } else {
                        print("Could not add video device input to the session")
                        self.setupResult = .SessionConfigurationFailed
                    }
                } catch {
                    let nserror = error as NSError
                    print("Could not create audio device input: \(nserror.localizedDescription)")
                }
            }
            
            // Add audioDevice input
            if self.audioEnabled {
                let audioDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
                do {
                    let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
                    if self.session.canAddInput(audioDeviceInput) {
                        self.session.addInput(audioDeviceInput)
                        self.audioDeviceInput = audioDeviceInput
                    } else {
                        print("Could not add audio device input to the session")
                    }
                } catch {
                    let nserror = error as NSError
                    print("Could not create audio device input: \(nserror.localizedDescription)")
                }
            }
            
            self.session.commitConfiguration()
        }
    }
    
    // Setup the capture session outputs
    private func setupCaptureSessionOutputs() {
        
        dispatch_async(sessionQueue) { 
            guard self.setupResult == .Success else { return }
            
            self.session.beginConfiguration()
            
            // Add movieFileOutput
            let movieFileOutput = AVCaptureMovieFileOutput()
            if self.session.canAddOutput(movieFileOutput) {
                self.session.addOutput(movieFileOutput)
                // Setup videoStabilizationMode
                let connection = movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
                if connection.supportsVideoStabilization {
                    connection.preferredVideoStabilizationMode = .Auto
                }
                self.movieFileOutput = movieFileOutput
            } else {
                print("Could not add movie file output to the session")
                self.setupResult = .SessionConfigurationFailed
            }
            
            // Add stillImageOutput
            let stillImageOutput = AVCaptureStillImageOutput()
            if self.session.canAddOutput(stillImageOutput) {
                stillImageOutput.outputSettings = [AVVideoCodecKey : AVVideoCodecJPEG]
                self.session.addOutput(stillImageOutput)
                self.stillImageOutput = stillImageOutput
            } else {
                print("Could not add still image output to the session")
                self.setupResult = .SessionConfigurationFailed
            }
            
            self.session.commitConfiguration()
        }
    }
    
    
    // MARK: - Target actions
    
    func focusAndExposeTap(sender: UITapGestureRecognizer) {
        guard tapFocusEnabled else { return }
    }
    
}

extension LWCameraController {
    
    // MARK: - Helper methods
    
    private class func device(mediaType type: String, preferringPosition position: AVCaptureDevicePosition) -> AVCaptureDevice? {
        
        if let devices = AVCaptureDevice.devicesWithMediaType(type) as? [AVCaptureDevice] {
            var captureDevice = devices.first
            for device in devices {
                if device.position == position {
                    captureDevice = device
                    break
                }
            }
            return captureDevice
        }
        return nil
    }
    
    private class func videoOrientationDependonStatusBarOrientation() -> AVCaptureVideoOrientation {
        var inititalVideoOrientation = AVCaptureVideoOrientation.Portrait
        switch UIApplication.sharedApplication().statusBarOrientation {
        case .Portrait:
            inititalVideoOrientation = .Portrait
        case .PortraitUpsideDown:
            inititalVideoOrientation = .PortraitUpsideDown
        case .LandscapeLeft:
            inititalVideoOrientation = .LandscapeLeft
        case .LandscapeRight:
            inititalVideoOrientation = .LandscapeRight
        default:
            break
        }
        return inititalVideoOrientation
    }
    
    
}



extension LWCameraController {
    
    
    // MARK: - Public methods

    
    convenience init(previewView view: UIView, focusImageView: UIImageView?, audioEnabled: Bool) {
        self.init()
        
        self.previewView = view
        self.focusImageView = focusImageView
        self.audioEnabled = audioEnabled
        if let focusLayer = focusImageView?.layer {
            self.previewView.layer.addSublayer(focusLayer)
        }
        
        // Setup the capture session inputs
        setupCaptureSessionInputs()
        
        // Setup the capture session outputs
        setupCaptureSessionOutputs()
    }
    
    
    func setAudioEnabled(enabled: Bool) {
        guard !recording else {
            print("The session is recording, can not complete the operation!")
            return
        }
        
        dispatch_async(sessionQueue) { 
            guard self.setupResult == .Success else { return }
            
            if self.audioEnabled  {
                // Add audioDevice input
                if let _ = self.audioDeviceInput {
                    print("The session already added aduioDevice input")
                } else {
                    self.session.beginConfiguration()
                    let audioDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
                    do {
                        let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
                        if self.session.canAddInput(audioDeviceInput) {
                            self.session.addInput(audioDeviceInput)
                            self.audioDeviceInput = audioDeviceInput
                        } else {
                            print("Could not add audio device input to the session")
                        }
                    } catch {
                        let nserror = error as NSError
                        print("Could not create audio device input: \(nserror.localizedDescription)")
                    }
                    self.session.commitConfiguration()
                }
            } else {
                // Remove audioDevice input
                if let audioDeviceInput = self.audioDeviceInput {
                    self.session.beginConfiguration()
                    self.session.removeInput(audioDeviceInput)
                    self.session.commitConfiguration()
                    self.audioDeviceInput = nil
                } else {
                    print("AduioDevice input was already removed")
                }
            }
            self.audioEnabled = enabled
        }
    }
    
    func setTapToFocusEnabled(enabled: Bool) {
        tapFocusEnabled = enabled
    }
    
    func toggleCamera(position: AVCaptureDevicePosition) {
        guard !recording else {
            print("The session is recording, can not complete the operation!")
            return
        }
        
        dispatch_async(sessionQueue) { 
            guard self.setupResult == .Success else { return }
        
            // Return if it is the same position
            if let currentVideoDevice = self.videoDeviceInput?.device {
                if currentVideoDevice.position == position {
                    return
                }
            }
            
            if let videoDevice = LWCameraController.device(mediaType: AVMediaTypeVideo, preferringPosition: position) {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.session.beginConfiguration()
                    // Remove old videoDeviceInput
                    if let oldDeviceInput = self.videoDeviceInput {
                        self.session.removeInput(oldDeviceInput)
                    }
                    // Add new videoDeviceInput
                    if self.session.canAddInput(videoDeviceInput) {
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                        print("Could not add movie file output to the session")
                    }
                    self.session.commitConfiguration()
                } catch {
                    let nserror = error as NSError
                    print("Could not add video device input to the session: \(nserror.localizedDescription)")
                    return
                }
            }
        }
    }
    
    
    
}



