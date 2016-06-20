//
//  VideoDataOutputViewController.swift
//  LWCameraController
//
//  Created by lailingwei on 16/5/26.
//  Copyright © 2016年 lailingwei. All rights reserved.
//

import UIKit
import AVFoundation


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
                
                if let filter = self.filter {
                    // 实时滤镜
                    if let ciImage = LWCameraController.ciImage(fromSampleBuffer: sampleBuffer,
                        filter: filter) {
                        dispatch_async(dispatch_get_main_queue(), {
                            self.view.layer.contents = self.context.createCGImage(ciImage, fromRect: ciImage.extent)
                        })
                    }
                    
                } else {
                    // 正常模式
                    let image = LWCameraController.image(fromSampleBuffer: sampleBuffer)
                    dispatch_async(dispatch_get_main_queue(), {
                        self.view.layer.contents = image?.CGImage
                    })
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
    
    @IBAction func toggleRecordAction(sender: UIButton) {
        
        sender.selected = !sender.selected
        navigationItem.rightBarButtonItem?.enabled = !sender.selected
        
        
    }

}
