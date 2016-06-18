//
//  LWCameraController.swift
//  LWCameraController
//
//  Created by lailingwei on 16/5/24.
//  Copyright © 2016年 lailingwei. All rights reserved.
//
//  Github: https://github.com/llwei/LWCameraController

import UIKit
import AVFoundation
import CoreGraphics
import CoreImage

private var SessionQueue = "SessionQueue"
private var VideoDataOutputQueue = "VideoDataOutputQueue"
private var AudioDataOutputQueue = "AudioDataOutputQueue"
private let NotAuthorizedMessage = "\(NSBundle.mainBundle().infoDictionary?["CFBundleDisplayName"]) doesn't have permission to use the camera, please change privacy settings"
private let ConfigurationFailedMessage = "Unable to capture media"
private let CancelTitle = "OK"
private let SettingsTitle = "Settings"

private let FocusAnimateDuration: NSTimeInterval = 0.6


typealias StartRecordingHandler = ((captureOutput: AVCaptureFileOutput!, connections: [AnyObject]!) -> Void)
typealias FinishRecordingHandler = ((captureOutput: AVCaptureFileOutput!, outputFileURL: NSURL!, connections: [AnyObject]!, error: NSError!) -> Void)
typealias MetaDataOutputHandler = ((captureOutput: AVCaptureOutput!, metadataObjects: [AnyObject]!, connection: AVCaptureConnection!) -> Void)
typealias VideoDataOutputHandler = ((videoCaptureOutput: AVCaptureOutput?, audioCaptureOutput: AVCaptureOutput?, sampleBuffer: CMSampleBuffer!, connection: AVCaptureConnection!) -> Void)



private enum LWCamType: Int {
    case Default
    case MetaData
    case VideoData
}


private enum LWCamSetupResult: Int {
    case Success
    case CameraNotAuthorized
    case SessionConfigurationFailed
}


class LWCameraController: NSObject, AVCaptureFileOutputRecordingDelegate, AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    

    // MARK:  Properties
    
    private var previewView: LWVideoPreview?
    private var focusImageView: UIImageView?
    private var camType: LWCamType = .Default
    
    private let sessionQueue: dispatch_queue_t = dispatch_queue_create(SessionQueue, DISPATCH_QUEUE_SERIAL)
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    private var setupResult: LWCamSetupResult = .Success
    private var sessionRunning: Bool = false
    private var recording: Bool = false
    private var audioEnabled: Bool = true
    private var tapFocusEnabled: Bool = true
    
    private lazy var metadataObjectTypes: [AnyObject] = { return [AnyObject]() }()
    
    private let session: AVCaptureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var stillImageOutput: AVCaptureStillImageOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    
    private var startRecordingHandler: StartRecordingHandler?
    private var finishRecordingHandler: FinishRecordingHandler?
    private var metaDataOutputHandler: MetaDataOutputHandler?
    private var videoDataOutputHandler: VideoDataOutputHandler?
    
    
    // MARK:  Initial
    
    private override init() {
        super.init()
    
        if !UIDevice.currentDevice().generatesDeviceOrientationNotifications {
            UIDevice.currentDevice().beginGeneratingDeviceOrientationNotifications()
        }
        
        // Check video authorization status
        checkVideoAuthoriztionStatus()
        
        dispatch_async(sessionQueue) {
            guard self.setupResult == .Success else { return }
            self.backgroundRecordingID = UIBackgroundTaskInvalid
        }
    }
    
    deinit {
        print("NSStringFromClass(LWCameraController.self).deinit")
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
    
    // Setup the previewView and focusImageView
    private func setupPreviewView(previewView: LWVideoPreview, focusImageView: UIImageView?) {
        
        // Preview View
        self.previewView = previewView
        previewView.backgroundColor = UIColor.blackColor()
        previewView.session = session
        // Add Tap gesture
        let tapGesture = UITapGestureRecognizer(target: self,
                                                action: #selector(LWCameraController.focusAndExposeTap(_:)))
        previewView.addGestureRecognizer(tapGesture)
        
        // FocusImageView
        self.focusImageView = focusImageView
        if let focusLayer = focusImageView?.layer {
            focusImageView?.alpha = 0.0
            previewView.layer.addSublayer(focusLayer)
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
                        if let previewView = self.previewView {
                            // Use the status bar orientation as the initial video orientation.
                            dispatch_async(dispatch_get_main_queue(), {
                                let videoPreviewLayer = previewView.layer as! AVCaptureVideoPreviewLayer
                                videoPreviewLayer.connection.videoOrientation = LWCameraController.videoOrientationDependonStatusBarOrientation()
                            })
                        }
                        
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
            
            switch self.camType {
            case .Default:
                // Add movieFileOutput
                let movieFileOutput = AVCaptureMovieFileOutput()
                if self.session.canAddOutput(movieFileOutput) {
                    self.session.addOutput(movieFileOutput)
                    let connection = movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
                    // Setup videoStabilizationMode
                    if #available(iOS 8.0, *) {
                        if connection.supportsVideoStabilization {
                            connection.preferredVideoStabilizationMode = .Auto
                        }
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
                
            case .MetaData:
                // Add metaDataOutput
                let metaDataOutput = AVCaptureMetadataOutput()
                if self.session.canAddOutput(metaDataOutput) {
                    self.session.addOutput(metaDataOutput)
                    metaDataOutput.setMetadataObjectsDelegate(self, queue: dispatch_get_main_queue())
                    metaDataOutput.metadataObjectTypes = self.metadataObjectTypes
                } else {
                    print("Could not add metaData output to the session")
                    self.setupResult = .SessionConfigurationFailed
                }
                
            case .VideoData:
                // Add videoDataOutput
                let videoDataOutput = AVCaptureVideoDataOutput()
                videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey : Int(kCVPixelFormatType_32BGRA)]
                videoDataOutput.alwaysDiscardsLateVideoFrames = true
                if self.session.canAddOutput(videoDataOutput) {
                    self.session.addOutput(videoDataOutput)
                    videoDataOutput.setSampleBufferDelegate(self, queue: dispatch_queue_create(VideoDataOutputQueue, DISPATCH_QUEUE_SERIAL))
                    self.videoDataOutput = videoDataOutput
                    
                    // Use the status bar orientation as the initial video orientation.
                    let connection = videoDataOutput.connectionWithMediaType(AVMediaTypeVideo)
                    connection.videoOrientation = LWCameraController.videoOrientationDependonStatusBarOrientation()
                    
                } else {
                    print("Could not add videoData output to the session")
                    self.setupResult = .SessionConfigurationFailed
                }
                
                // Add audioDataOutput
                let audioDataOutput = AVCaptureAudioDataOutput()
                if self.session.canAddOutput(audioDataOutput) {
                    self.session.addOutput(audioDataOutput)
                    audioDataOutput.setSampleBufferDelegate(self, queue: dispatch_queue_create(AudioDataOutputQueue, DISPATCH_QUEUE_SERIAL))
                    self.audioDataOutput = audioDataOutput
                    
                } else {
                    print("Could not add audioData output to the session")
                    self.setupResult = .SessionConfigurationFailed
                }
                
            }
            
            self.session.commitConfiguration()
        }
    }
    
    
    // MARK:  Target actions
    
    func focusAndExposeTap(sender: UITapGestureRecognizer) {
        guard tapFocusEnabled, let previewView = previewView else { return }
        
        let layer = previewView.layer as! AVCaptureVideoPreviewLayer
        let devicePoint = layer.captureDevicePointOfInterestForPoint(sender.locationInView(sender.view))
        
        focus(withMode: .AutoFocus,
              exposureMode: .AutoExpose,
              atPoint: devicePoint,
              monitorSubjectAreaChange: true)
        
        if let focusCursor = focusImageView {
            focusCursor.center = sender.locationInView(sender.view)
            focusCursor.transform = CGAffineTransformMakeScale(1.5, 1.5)
            focusCursor.alpha = 1.0
            UIView.animateWithDuration(FocusAnimateDuration,
                                       animations: { 
                                        focusCursor.transform = CGAffineTransformIdentity
                }, completion: { (_) in
                    focusCursor.alpha = 0.0
            })
        }
    }
    
    
    // MARK:  Notifications
    
    private func addObservers() {
        
        NSNotificationCenter.defaultCenter().addObserver(self,
                                                         selector: #selector(LWCameraController.subjectAreaDidChange(_:)),
                                                         name: AVCaptureDeviceSubjectAreaDidChangeNotification,
                                                         object: videoDeviceInput?.device)
        
        NSNotificationCenter.defaultCenter().addObserver(self,
                                                         selector: #selector(LWCameraController.sessionRuntimeError(_:)),
                                                         name: AVCaptureSessionRuntimeErrorNotification,
                                                         object: session)
        
        NSNotificationCenter.defaultCenter().addObserver(self,
                                                         selector: #selector(LWCameraController.deviceOrientationDidChange(_:)),
                                                         name: UIDeviceOrientationDidChangeNotification,
                                                         object: nil)
    }
    
    func subjectAreaDidChange(notification: NSNotification) {
        
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(withMode: .AutoFocus, exposureMode: .AutoExpose, atPoint: devicePoint, monitorSubjectAreaChange: false)
    }
    
    func sessionRuntimeError(notification: NSNotification) {
        
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError {
            print("Capture session runtime error: \(error.localizedDescription)")
            
            if error.code == AVError.MediaServicesWereReset.rawValue {
                dispatch_async(self.sessionQueue, {
                    if self.sessionRunning {
                        self.session.startRunning()
                        self.sessionRunning = self.session.running
                    }
                })
            }
        }
    }
    
    func deviceOrientationDidChange(notification: NSNotification) {
        guard !recording else { return }
        
        // Note that the app delegate controls the device orientation notifications required to use the device orientation.
        let deviceOrientation = UIDevice.currentDevice().orientation
        if UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation) {
            // Preview
            if let previewView = previewView {
                let layer = previewView.layer as! AVCaptureVideoPreviewLayer
                let videoOrientation = LWCameraController.videoOrientationDependonStatusBarOrientation()
                if layer.connection.videoOrientation != videoOrientation {
                    layer.connection.videoOrientation = videoOrientation
                }
            }
            // VideoDataOutput
            if let videoDataOutput = videoDataOutput {
                let connect = videoDataOutput.connectionWithMediaType(AVMediaTypeVideo)
                let videoOrientation = LWCameraController.videoOrientationDependonStatusBarOrientation()
                if connect.videoOrientation != videoOrientation {
                    connect.videoOrientation = videoOrientation
                }
            }
        }
    }
    
    
    
    private func removeObservers() {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    

    
    
    // MARK:  Helper methods
    
    
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
    
    
    private class func setFlashMode(flashMode: AVCaptureFlashMode, forDevice device: AVCaptureDevice) {
        guard device.hasFlash && device.isFlashModeSupported(flashMode) else { return }
        
        do {
            try device.lockForConfiguration()
            device.flashMode = flashMode
            device.unlockForConfiguration()
        } catch {
            let nserror = error as NSError
            print("Could not lock device for configuration: \(nserror.localizedDescription)")
        }
    }
    
    
    private func focus(withMode focusMode: AVCaptureFocusMode,
                                exposureMode: AVCaptureExposureMode,
                                atPoint point: CGPoint,
                                monitorSubjectAreaChange: Bool) {
        
        dispatch_async(sessionQueue) { 
            guard self.setupResult == .Success else { return }
            
            if let device = self.videoDeviceInput?.device {
                do {
                    try device.lockForConfiguration()
                    // focus
                    if device.focusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                        device.focusPointOfInterest = point
                        device.focusMode = focusMode
                    }
                    // exposure
                    if device.exposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                        device.exposurePointOfInterest = point
                        device.exposureMode = exposureMode
                    }
                    // If subject area change monitoring is enabled, the receiver
                    // sends an AVCaptureDeviceSubjectAreaDidChangeNotification whenever it detects
                    // a change to the subject area, at which time an interested client may wish
                    // to re-focus, adjust exposure, white balance, etc.
                    device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                    device.unlockForConfiguration()
                } catch {
                    let nserror = error as NSError
                    print("Could not lock device for configuration: \(nserror.localizedDescription)")
                }
            }
        }
    }
    
    
    private func showAlertView(withMessage message: String, showSettings: Bool) {
     
        let rootViewController = UIApplication.sharedApplication().keyWindow?.rootViewController
        
        if #available(iOS 8.0, *) {
            let alertController = UIAlertController(title: nil,
                                                    message: message,
                                                    preferredStyle: .Alert)
            let cancelAction = UIAlertAction(title: CancelTitle,
                                             style: .Cancel,
                                             handler: nil)
            alertController.addAction(cancelAction)
            if showSettings {
                let settingsAction = UIAlertAction(title: SettingsTitle,
                                                   style: .Default,
                                                   handler: { (_) in
                                                    UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
                })
                alertController.addAction(settingsAction)
            }
            rootViewController?.presentViewController(alertController,
                                                      animated: true,
                                                      completion: nil)
            
        } else {
            let alertView = UIAlertView(title: nil,
                                        message: message,
                                        delegate: nil,
                                        cancelButtonTitle: CancelTitle)
            alertView.show()
        }
    }
    
  
    // MARK:  AVCaptureFileOutputRecordingDelegate
    
    func captureOutput(captureOutput: AVCaptureFileOutput!,
                       didStartRecordingToOutputFileAtURL fileURL: NSURL!,
                                                          fromConnections connections: [AnyObject]!) {
        
        recording = true
        startRecordingHandler?(captureOutput: captureOutput, connections: connections)
    }
    
    func captureOutput(captureOutput: AVCaptureFileOutput!,
                       didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!,
                                                           fromConnections connections: [AnyObject]!,
                                                                           error: NSError!) {
        
        if let currentBackgroundRecordingID = backgroundRecordingID {
            backgroundRecordingID = UIBackgroundTaskInvalid
            if currentBackgroundRecordingID != UIBackgroundTaskInvalid {
                UIApplication.sharedApplication().endBackgroundTask(currentBackgroundRecordingID)
            }
        }
        
        recording = false
        finishRecordingHandler?(captureOutput: captureOutput,
                                outputFileURL: outputFileURL,
                                connections: connections,
                                error: error)
    }

    
    // MARK:  AVCaptureMetadataOutputObjectsDelegate
    
    func captureOutput(captureOutput: AVCaptureOutput!,
                       didOutputMetadataObjects metadataObjects: [AnyObject]!,
                                                fromConnection connection: AVCaptureConnection!) {
        
        metaDataOutputHandler?(captureOutput: captureOutput,
                               metadataObjects: metadataObjects,
                               connection: connection)
    }
    
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate / AVCaptureAudioDataOutputSampleBufferDelegate
    
    func captureOutput(captureOutput: AVCaptureOutput!,
                       didOutputSampleBuffer sampleBuffer: CMSampleBuffer!,
                                             fromConnection connection: AVCaptureConnection!) {
        
        if captureOutput == videoDataOutput {
            videoDataOutputHandler?(videoCaptureOutput: captureOutput,
                                    audioCaptureOutput: nil,
                                    sampleBuffer: sampleBuffer,
                                    connection: connection)
            
        } else if captureOutput == audioDataOutput {
            videoDataOutputHandler?(videoCaptureOutput: nil,
                                    audioCaptureOutput: captureOutput,
                                    sampleBuffer: sampleBuffer,
                                    connection: connection)
        }
        
    }
    
    
}



// MARK: - ============== Public methods ==============


// MARK: Common

extension LWCameraController {
    
    /**
     开始捕捉画面
     */
    func startRunning() {
        guard !sessionRunning else { return }
        
        dispatch_async(sessionQueue) { 
            switch self.setupResult {
            case .Success:
                self.addObservers()
                self.session.startRunning()
                self.sessionRunning = self.session.running
                
            case .CameraNotAuthorized:
                dispatch_async(dispatch_get_main_queue(), { 
                    self.showAlertView(withMessage: NotAuthorizedMessage, showSettings: true)
                })
                
            case .SessionConfigurationFailed:
                dispatch_async(dispatch_get_main_queue(), { 
                    self.showAlertView(withMessage: ConfigurationFailedMessage, showSettings: false)
                })
            }
        }
    }
    
    /**
     结束画面的捕捉
     */
    func stopRunning() {
        guard sessionRunning else { return }
        
        dispatch_async(sessionQueue) { 
            guard self.setupResult == .Success else { return }
            
            self.session.stopRunning()
            self.sessionRunning = self.session.running
            self.removeObservers()
        }
    }
    
    
    
    // MARK:  Camera
    
    func currentCameraInputDevice() -> AVCaptureDevice? {
        return videoDeviceInput?.device
    }

    func currentCameraPosition() -> AVCaptureDevicePosition {
        return videoDeviceInput?.device.position ?? .Unspecified
    }
    
    /**
     切换摄像头
     
     - parameter position: 要切换到的摄像头位置
     */
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
    
    
    // MARK:  Flash
    
    func currentFlashAvailable() -> Bool {
        guard let device = currentCameraInputDevice() else { return false }
        return device.flashAvailable
    }
    
    func isFlashModeSupported(flashMode: AVCaptureFlashMode) -> Bool {
        guard let device = currentCameraInputDevice() else { return false }
        return device.isFlashModeSupported(flashMode)
    }
    
    func currentFlashMode() -> AVCaptureFlashMode {
        guard let device = currentCameraInputDevice() else { return .Off }
        return device.flashMode
    }
    
    
    // MARK:  Torch
    
    func currentTorchAvailable() -> Bool {
        guard let device = currentCameraInputDevice() else { return false }
        return device.torchAvailable
    }
    
    func isTorchModeSupported(torchMode: AVCaptureTorchMode) -> Bool {
        guard let device = currentCameraInputDevice() else { return false }
        return device.isTorchModeSupported(torchMode)
    }
    
    func currentTorchMode() -> AVCaptureTorchMode {
        guard let device = currentCameraInputDevice() else { return .Off }
        return device.torchMode
    }
    
    func setTorchModeOnWithLevel(torchLevel: Float) {
        guard let device = currentCameraInputDevice() where device.isTorchModeSupported(.On) else { return }
        
        dispatch_async(sessionQueue) { 
            guard self.setupResult == .Success else { return }
            
            do {
                try device.lockForConfiguration()
                do {
                    try device.setTorchModeOnWithLevel(torchLevel)
                } catch {
                    let nserror = error as NSError
                    print("Could not set torchModeOn with level \(torchLevel): \(nserror.localizedDescription)")
                }
                device.unlockForConfiguration()
            } catch {
                let nserror = error as NSError
                print("Could not lock device for configuration: \(nserror.localizedDescription)")
            }
        }
    }
    
    func setTorchMode(torchMode: AVCaptureTorchMode) {
        guard let device = currentCameraInputDevice() where device.isTorchModeSupported(torchMode) else { return }
        
        dispatch_async(sessionQueue) {
            guard self.setupResult == .Success else { return }
            
            do {
                try device.lockForConfiguration()
                device.torchMode = torchMode
                device.unlockForConfiguration()
            } catch {
                let nserror = error as NSError
                print("Could not lock device for configuration: \(nserror.localizedDescription)")
            }
        }
    }
    
}

// MARK: - MovieFileOutput、StillImageOutput

extension LWCameraController {

    /**
     初始化一个自定义相机，用于普通的拍照和录像
     
     - parameter view:           预览图层
     - parameter focusImageView: 点击聚焦时显示的图片
     - parameter audioEnabled:   录像时是否具有录音功能
     
     */
    convenience init(previewView view: LWVideoPreview,
                                 focusImageView: UIImageView?,
                                 audioEnabled: Bool) {
        self.init()
        
        self.camType = .Default
        self.audioEnabled = audioEnabled
        
        // Setup the previewView and focusImageView
        setupPreviewView(view, focusImageView: focusImageView)
        
        // Setup the capture session inputs
        setupCaptureSessionInputs()
        
        // Setup the capture session outputs
        setupCaptureSessionOutputs()
    }
    
    /**
     设置录像是否具有录音功能，默认值: 参考初始化传入的参数audioEnabled（录像期间使用无效）
     */
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
    
    /**
     设置点击聚焦手势的开关，默认为true
     */
    func setTapToFocusEnabled(enabled: Bool) {
        tapFocusEnabled = enabled
    }

    
    /**
     拍照
     
     - parameter mode:            设置拍照时闪光灯模式
     - parameter completeHandler: 拍照结果回调
     */
    func snapStillImage(withFlashMode mode: AVCaptureFlashMode,
                                      completeHandler: ((imageData: NSData?, error: NSError?) -> Void)?) {
        
        guard sessionRunning && !recording, let previewView = previewView else { return }
        
        dispatch_async(sessionQueue) {
            guard self.setupResult == .Success else { return }
            
            if let connection = self.stillImageOutput?.connectionWithMediaType(AVMediaTypeVideo), device = self.videoDeviceInput?.device {
                // Update the orientation on the still image output video connection before capturing
                connection.videoOrientation = (previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation
                // Flash set to Auto for Still Capture.
                LWCameraController.setFlashMode(mode, forDevice: device)
                // Capture a still image.
                self.stillImageOutput?.captureStillImageAsynchronouslyFromConnection(connection,
                                                                                     completionHandler: {
                                                                                        (buffer: CMSampleBuffer!, error: NSError!) in
                                                                                        
                                                                                        var imageData: NSData?
                                                                                        if buffer != nil {
                                                                                            imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(buffer)
                                                                                        }
                                                                                        dispatch_async(dispatch_get_main_queue(), {
                                                                                            completeHandler?(imageData: imageData, error: error)
                                                                                        })
                })
                dispatch_async(dispatch_get_main_queue(), {
                    let layer = previewView.layer
                    layer.opacity = 0.0
                    UIView.animateWithDuration(0.25, animations: {
                        layer.opacity = 1.0
                    })
                })
            }
        }
    }
    
    /**
     判断当前是否正在录像
     */
    func isRecording() -> Bool {
        return recording
    }
    
    /**
     开始录像
     
     - parameter path:                  录像文件保存地址
     - parameter startRecordingHandler: 开始录像时触发的回调
     */
    func startMovieRecording(outputFilePath path: String,
                                            startRecordingHandler: StartRecordingHandler?) {
        
        guard sessionRunning && !recording, let previewView = previewView else { return }
        
        dispatch_async(sessionQueue) {
            guard self.setupResult == .Success, let movieFileOutput = self.movieFileOutput else { return }
            
            if UIDevice.currentDevice().multitaskingSupported {
                // Setup background task. This is needed because the -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:]
                // callback is not received until AVCam returns to the foreground unless you request background execution time.
                // This also ensures that there will be time to write the file to the photo library when AVCam is backgrounded.
                // To conclude this background execution, -endBackgroundTask is called in
                // -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:] after the recorded file has been saved.
                self.backgroundRecordingID = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler(nil)
            }
            // Update the orientation on the movie file output video connection before starting recording.
            let connection = movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
            connection.videoOrientation = (previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation
            
            // Turn Off flash for video recording
            if let device = self.videoDeviceInput?.device {
                LWCameraController.setFlashMode(.Off, forDevice: device)
            }
            // Start recording
            dispatch_async(dispatch_get_main_queue(), {
                self.startRecordingHandler = startRecordingHandler
            })
            movieFileOutput.startRecordingToOutputFileURL(NSURL(fileURLWithPath: path), recordingDelegate: self)
        }
    }
    
    /**
     结束录像
     
     - parameter finishRecordingHandler: 结束录像时触发的回调
     */
    func stopMovieRecording(finishRecordingHandler: FinishRecordingHandler?) {
        guard sessionRunning && recording else { return }
        
        dispatch_async(sessionQueue) {
            guard self.setupResult == .Success, let movieFileOutput = self.movieFileOutput else { return }
            
            movieFileOutput.stopRecording()
            self.finishRecordingHandler = finishRecordingHandler
        }
    }
    
}


// MARK: - MetaDataOutput

extension LWCameraController {
    
    
    /**
     初始化一个MetaData输出的控制器，主要用于扫描二维码、条形码等
     
     - parameter view:                  预览图层
     - parameter metadataObjectTypes:   二维码（AVMetadataObjectTypeQRCode）
                                        人脸（AVMetadataObjectTypeFace）
                                        条形码（AVMetadataObjectTypeCode128Code）
     - parameter metaDataOutputHandler: 扫描到数据时的回调
     
     */
    convenience init(metaDataPreviewView view: LWVideoPreview,
                                         metadataObjectTypes: [AnyObject],
                                         metaDataOutputHandler: MetaDataOutputHandler?) {
        self.init()
        
        self.camType = .MetaData
        self.audioEnabled = false
        self.metadataObjectTypes = metadataObjectTypes
        
        // Setup the previewView and focusImageView
        setupPreviewView(view, focusImageView: focusImageView)
        
        // Setup the capture session inputs
        setupCaptureSessionInputs()
        
        // Setup the capture session outputs
        setupCaptureSessionOutputs()
        
        self.metaDataOutputHandler = metaDataOutputHandler
    }
    
}


// MARK: - VideoDataOutput

extension LWCameraController {
    
    convenience init(withVideoDataOutputHandler handler: VideoDataOutputHandler) {
        self.init()
        
        self.camType = .VideoData
        self.audioEnabled = true
        
        // Setup the capture session inputs
        setupCaptureSessionInputs()
        
        // Setup the capture session outputs
        setupCaptureSessionOutputs()
        
        self.videoDataOutputHandler = handler
    }
    
    
    /**
     Create a UIImage from sample buffer data
     */
    class func image(fromSampleBuffer sampleBuffer: CMSampleBufferRef) -> UIImage? {
        
        // Get a CMSampleBuffer's Core Video image buffer for the media data
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil}
        
        // Lock the base address of the pixel buffer
        CVPixelBufferLockBaseAddress(imageBuffer, 0)
        
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let bitsPerComponent: Int = 8
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.ByteOrder32Little.rawValue | CGImageAlphaInfo.PremultipliedFirst.rawValue
        
        // Create a bitmap graphics context with the sample buffer data
        let context = CGBitmapContextCreate(baseAddress,
                                            width,
                                            height,
                                            bitsPerComponent,
                                            bytesPerRow,
                                            colorSpace,
                                            bitmapInfo)
        
        // Unlock the pixel buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0)
        
        // Create a Quartz image from the pixel data in the bitmap graphics context
        guard let quartzImage = CGBitmapContextCreateImage(context) else { return nil }
        
        // Create an image object from the Quartz image
        let image = UIImage(CGImage: quartzImage)
        
        return image
    }
    
    
    class func cgImage(fromSampleBuffer sampleBuffer: CMSampleBufferRef,
                                        filter: CIFilter,
                                        context: CIContext) -> CGImage? {
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        let inputImage = CIImage(CVPixelBuffer: imageBuffer)
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        let output = filter.outputImage!
        
        return context.createCGImage(output, fromRect: inputImage.extent)
    }

    
}



// MARK: - ========== LWVideoPreview ===========

// 用来显示session捕捉到的画面
class LWVideoPreview: UIView {
    
    override class func layerClass() -> AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var session: AVCaptureSession {
        set {
            let previewLayer = layer as! AVCaptureVideoPreviewLayer
            previewLayer.session = newValue
            previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
        }
        get {
            let previewLayer = layer as! AVCaptureVideoPreviewLayer
            return previewLayer.session
        }
    }
}








