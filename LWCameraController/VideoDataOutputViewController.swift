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
            [unowned self] (captureOutput, sampleBuffer, connection) in
            
            // 对拿回的 sampleBuffer 进行处理
            let image = LWCameraController.image(fromSampleBuffer: sampleBuffer)
   
            dispatch_async(dispatch_get_main_queue(), {
                self.view.layer.contents = image?.CGImage
            })
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
