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

    fileprivate var cameraController: LWCameraController!
    fileprivate let filterNames = ["None",
                               "CIPhotoEffectChrome",
                               "CIPhotoEffectFade",
                               "CIPhotoEffectInstant",
                               "CIPhotoEffectTonal"]
    
    fileprivate var filter: CIFilter?
    fileprivate let context = CIContext(eaglContext: EAGLContext(api: .openGLES2)!)
    
    // MARK: - Life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
             
        cameraController = LWCameraController(withVideoDataOutputHandler: {
            [unowned self] (videoCaptureOutput, audioCaptureOutput, sampleBuffer, connection) in
            
            // 对拿回的视频 sampleBuffer 进行处理
            if let _ = videoCaptureOutput {
                var pixelBuffer: CVPixelBuffer?
                
                if let filter = self.filter {
                    // 实时滤镜
                    if let ciImage = LWCameraController.ciImage(fromSampleBuffer: sampleBuffer,
                        filter: filter) {
                        DispatchQueue.main.async(execute: {
                            self.view.layer.contents = self.context.createCGImage(ciImage, from: ciImage.extent)
                        })
                        
                        // Record
                        if self.isWriting {
                            CVPixelBufferPoolCreatePixelBuffer(nil, self.videoWriterInputAdaptor.pixelBufferPool!, &pixelBuffer)
                            self.context.render(ciImage, to: pixelBuffer!, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
                        }
                    }
                    
                } else {
                    // 正常模式
                    let image = LWCameraController.image(fromSampleBuffer: sampleBuffer)
                    DispatchQueue.main.async(execute: {
                        self.view.layer.contents = image?.cgImage
                    })
                    
                    // Record
                    pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
                }
                
                // Record
                let description = CMSampleBufferGetFormatDescription(sampleBuffer)!
                self.videoDimensions = CMVideoFormatDescriptionGetDimensions(description)
                self.sourceTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
                if self.isWriting {
                    if self.videoWriterInputAdaptor.assetWriterInput.isReadyForMoreMediaData {
                        let time = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
                        self.videoWriterInputAdaptor.append(pixelBuffer!, withPresentationTime: time)
                    }
                }
            }
            
            // Record
            if let _ = audioCaptureOutput {
                if self.isWriting {
                    if self.audioWriterInput.isReadyForMoreMediaData {
                        self.audioWriterInput.append(sampleBuffer)
                    }
                }
            }
        })

      
    }


    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cameraController.startRunning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraController.stopRunning()
    }

    
    deinit {
        print("VideoDataOutputViewController deinit")
    }
    
    
    // MARK: - Target actions
    
    @IBAction func chnageFilter(_ sender: UIBarButtonItem) {
        
        if #available(iOS 8.0, *) {
            let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            
            for filterName in filterNames {
                let filterAction = UIAlertAction(title: filterName,
                                                 style: .default,
                                                 handler: { (_) in
                                                    self.filter = CIFilter(name: filterName)
                })
                alertController.addAction(filterAction)
            }
            
            let cancelAction = UIAlertAction(title: "Cancel",
                                             style: .cancel,
                                             handler: nil)
            alertController.addAction(cancelAction)
            
            present(alertController, animated: true, completion: nil)
        }
    }
    
    
    // MARK: - Record
    
    fileprivate var isWriting = false
    fileprivate let savePath = NSTemporaryDirectory() + "\record.mov"
    fileprivate var videoDimensions: CMVideoDimensions!
    fileprivate var sourceTime: CMTime!
    fileprivate var assetWriter: AVAssetWriter?
    fileprivate var videoWriterInput: AVAssetWriterInput!
    fileprivate var videoWriterInputAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    fileprivate var audioWriterInput: AVAssetWriterInput!
    
    
    @IBAction func toggleRecordAction(_ sender: UIButton) {
        
        sender.isSelected = !sender.isSelected
        navigationItem.rightBarButtonItem?.isEnabled = !sender.isSelected
        sender.isSelected ? startRecord() : endRecord()
    }

    fileprivate func startRecord() {
        
        if FileManager.default.fileExists(atPath: savePath) {
            try! FileManager.default.removeItem(atPath: savePath)
        }
        
        initialWriter()
        
        assetWriter?.startWriting()
        assetWriter?.startSession(atSourceTime: sourceTime)
        isWriting = true
    }
    
    fileprivate func endRecord() {
        
        isWriting = false
        assetWriter?.finishWriting(completionHandler: { [unowned self] in
            DispatchQueue.main.async(execute: {
                let mediaPlayer = MPMoviePlayerViewController(contentURL: URL(fileURLWithPath: self.savePath))
                self.present(mediaPlayer!, animated: true, completion: nil)
            })
        })
        
    }
    
    
    fileprivate func initialWriter() {
        
        // AVAssetWriter
        do {
            assetWriter = try AVAssetWriter(outputURL: URL(fileURLWithPath: self.savePath), fileType: AVFileType.mov)
        } catch {}
        
        
        // video AVAssetWriterInput
        let settings: [String : AnyObject] = [AVVideoCodecKey : AVVideoCodecH264 as AnyObject,
                                              AVVideoWidthKey : Int(self.videoDimensions.width) as AnyObject,
                                              AVVideoHeightKey: Int(self.videoDimensions.height) as AnyObject]
        videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: settings)
        videoWriterInput.expectsMediaDataInRealTime = true
        assetWriter?.add(videoWriterInput)
        
        
        // AVAssetWriterInputPixelBufferAdaptor
        let attributesDictionary: [String : AnyObject] = [String(kCVPixelBufferPixelFormatTypeKey) : Int(kCVPixelFormatType_32BGRA) as AnyObject,
                                                          String(kCVPixelBufferWidthKey) : Int(self.videoDimensions.width) as AnyObject,
                                                          String(kCVPixelBufferHeightKey) : Int(self.videoDimensions.height) as AnyObject,
                                                          String(kCVPixelFormatOpenGLESCompatibility) : kCFBooleanTrue]
        videoWriterInputAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.videoWriterInput, sourcePixelBufferAttributes: attributesDictionary)
        
        
        // audio AVAssetWriterInput
        let audioSettings: [String : AnyObject] = [AVFormatIDKey : Int(kAudioFormatMPEG4AAC) as AnyObject,
                                                   AVSampleRateKey : 44100 as AnyObject,
                                                   AVNumberOfChannelsKey : 1 as AnyObject]
        audioWriterInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
        audioWriterInput.expectsMediaDataInRealTime = true
        assetWriter?.add(audioWriterInput)
        
    }
    
    
}
