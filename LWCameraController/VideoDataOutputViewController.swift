//
//  VideoDataOutputViewController.swift
//  LWCameraController
//
//  Created by lailingwei on 16/5/26.
//  Copyright © 2016年 lailingwei. All rights reserved.
//

import UIKit
import AVFoundation
import MediaPlayer

class VideoDataOutputViewController: UIViewController {

    private var cameraController: LWCameraController!
    private let filterNames = ["None",
                               "CIPhotoEffectChrome",
                               "CIPhotoEffectFade",
                               "CIPhotoEffectInstant",
                               "CIPhotoEffectTonal"]
    
    private var filter: CIFilter?
    private let context = CIContext(EAGLContext: EAGLContext(API: .OpenGLES2))
    
    // MARK: - Life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
             
        cameraController = LWCameraController(withVideoDataOutputHandler: {
            [unowned self] (videoCaptureOutput, audioCaptureOutput, sampleBuffer, connection) in
            
            // 对拿回的视频 sampleBuffer 进行处理
            if let _ = videoCaptureOutput {
                var pixelBuffer: CVPixelBufferRef?
                
                if let filter = self.filter {
                    // 实时滤镜
                    if let ciImage = LWCameraController.ciImage(fromSampleBuffer: sampleBuffer,
                        filter: filter) {
                        dispatch_async(dispatch_get_main_queue(), {
                            self.view.layer.contents = self.context.createCGImage(ciImage, fromRect: ciImage.extent)
                        })
                        
                        // Record
                        if self.isWriting {
                            CVPixelBufferPoolCreatePixelBuffer(nil, self.videoWriterInputAdaptor.pixelBufferPool!, &pixelBuffer)
                            self.context.render(ciImage, toCVPixelBuffer: pixelBuffer!, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
                        }
                    }
                    
                } else {
                    // 正常模式
                    let image = LWCameraController.image(fromSampleBuffer: sampleBuffer)
                    dispatch_async(dispatch_get_main_queue(), {
                        self.view.layer.contents = image?.CGImage
                    })
                    
                    // Record
                    pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
                }
                
                // Record
                let description = CMSampleBufferGetFormatDescription(sampleBuffer)!
                self.videoDimensions = CMVideoFormatDescriptionGetDimensions(description)
                self.sourceTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
                if self.isWriting {
                    if self.videoWriterInputAdaptor.assetWriterInput.readyForMoreMediaData {
                        let time = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
                        self.videoWriterInputAdaptor.appendPixelBuffer(pixelBuffer!, withPresentationTime: time)
                    }
                }
            }
            
            // Record
            if let _ = audioCaptureOutput {
                if self.isWriting {
                    if self.audioWriterInput.readyForMoreMediaData {
                        self.audioWriterInput.appendSampleBuffer(sampleBuffer)
                    }
                }
            }
        })

      
    }


    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        cameraController.startRunning()
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        cameraController.stopRunning()
    }

    
    deinit {
        print("VideoDataOutputViewController deinit")
    }
    
    
    // MARK: - Target actions
    
    @IBAction func chnageFilter(sender: UIBarButtonItem) {
        
        if #available(iOS 8.0, *) {
            let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .ActionSheet)
            
            for filterName in filterNames {
                let filterAction = UIAlertAction(title: filterName,
                                                 style: .Default,
                                                 handler: { (_) in
                                                    self.filter = CIFilter(name: filterName)
                })
                alertController.addAction(filterAction)
            }
            
            let cancelAction = UIAlertAction(title: "Cancel",
                                             style: .Cancel,
                                             handler: nil)
            alertController.addAction(cancelAction)
            
            presentViewController(alertController, animated: true, completion: nil)
        }
    }
    
    
    // MARK: - Record
    
    private var isWriting = false
    private let savePath = NSTemporaryDirectory().stringByAppendingString("\record.mov")
    private var videoDimensions: CMVideoDimensions!
    private var sourceTime: CMTime!
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput!
    private var videoWriterInputAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    private var audioWriterInput: AVAssetWriterInput!
    
    
    @IBAction func toggleRecordAction(sender: UIButton) {
        
        sender.selected = !sender.selected
        navigationItem.rightBarButtonItem?.enabled = !sender.selected
        sender.selected ? startRecord() : endRecord()
    }

    private func startRecord() {
        
        if NSFileManager.defaultManager().fileExistsAtPath(savePath) {
            try! NSFileManager.defaultManager().removeItemAtPath(savePath)
        }
        
        initialWriter()
        
        assetWriter?.startWriting()
        assetWriter?.startSessionAtSourceTime(sourceTime)
        isWriting = true
    }
    
    private func endRecord() {
        
        isWriting = false
        assetWriter?.finishWritingWithCompletionHandler({ [unowned self] in
            dispatch_async(dispatch_get_main_queue(), {
                let mediaPlayer = MPMoviePlayerViewController(contentURL: NSURL(fileURLWithPath: self.savePath))
                self.presentViewController(mediaPlayer, animated: true, completion: nil)
            })
        })
        
    }
    
    
    private func initialWriter() {
        
        // AVAssetWriter
        do {
            assetWriter = try AVAssetWriter(URL: NSURL(fileURLWithPath: self.savePath), fileType: AVFileTypeQuickTimeMovie)
        } catch {}
        
        
        // video AVAssetWriterInput
        let settings: [String : AnyObject] = [AVVideoCodecKey : AVVideoCodecH264,
                                              AVVideoWidthKey : Int(self.videoDimensions.width),
                                              AVVideoHeightKey: Int(self.videoDimensions.height)]
        videoWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: settings)
        videoWriterInput.expectsMediaDataInRealTime = true
        assetWriter?.addInput(videoWriterInput)
        
        
        // AVAssetWriterInputPixelBufferAdaptor
        let attributesDictionary: [String : AnyObject] = [String(kCVPixelBufferPixelFormatTypeKey) : Int(kCVPixelFormatType_32BGRA),
                                                          String(kCVPixelBufferWidthKey) : Int(self.videoDimensions.width),
                                                          String(kCVPixelBufferHeightKey) : Int(self.videoDimensions.height),
                                                          String(kCVPixelFormatOpenGLESCompatibility) : kCFBooleanTrue]
        videoWriterInputAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.videoWriterInput, sourcePixelBufferAttributes: attributesDictionary)
        
        
        // audio AVAssetWriterInput
        let audioSettings: [String : AnyObject] = [AVFormatIDKey : Int(kAudioFormatMPEG4AAC),
                                                   AVSampleRateKey : 44100,
                                                   AVNumberOfChannelsKey : 1]
        audioWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: audioSettings)
        audioWriterInput.expectsMediaDataInRealTime = true
        assetWriter?.addInput(audioWriterInput)
        
    }
    
    
}
