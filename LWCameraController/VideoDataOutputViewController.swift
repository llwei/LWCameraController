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

    var cameraController: LWCameraController!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        cameraController = LWCameraController(withVideoDataOutputHandler: {
            [unowned self] (videoCaptureOutput, audioCaptureOutput, sampleBuffer, connection) in
            
            // 对拿回的视频 sampleBuffer 进行处理
            if let _ = videoCaptureOutput {
                let image = LWCameraController.image(fromSampleBuffer: sampleBuffer)
                
                dispatch_async(dispatch_get_main_queue(), {
                    self.view.layer.contents = image?.CGImage
                })
            }
        })

      
    }


    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        cameraController.startRunning()
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        cameraController.stopRunning()
    }

}
