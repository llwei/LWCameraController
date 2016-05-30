//
//  ScanViewController.swift
//  LWCameraController
//
//  Created by lailingwei on 16/5/25.
//  Copyright © 2016年 lailingwei. All rights reserved.
//

import UIKit
import AVFoundation

class ScanViewController: UIViewController {
    
    @IBOutlet weak var preview: LWVideoPreview!
    var cameraController: LWCameraController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        cameraController = LWCameraController(metaDataPreviewView: preview,
                                              metadataObjectTypes: [AVMetadataObjectTypeQRCode,
                                                                    AVMetadataObjectTypeCode128Code,
                                                                    AVMetadataObjectTypeFace],
                                              metaDataOutputHandler: {
                                                [unowned self] (captureOutput, metadataObjects, connection) in
                                                
                                                if let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject {
                                                    switch object.type {
                                                    case AVMetadataObjectTypeQRCode:
                                                        print("AVMetadataObjectTypeQRCode: \(object.stringValue)")
                                                        self.cameraController.stopRunning()
                                                        self.dismissViewControllerAnimated(true, completion: nil)
                                                    case AVMetadataObjectTypeCode128Code:
                                                        print("AVMetadataObjectTypeCode128Code: \(object.stringValue)")
                                                        self.cameraController.stopRunning()
                                                        self.dismissViewControllerAnimated(true, completion: nil)
                                                    default:
                                                        break
                                                    }
                                                } else if let object = metadataObjects.first as? AVMetadataFaceObject {
                                                    print("AVMetadataFaceObject:\(object.bounds)")
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

    deinit {
        print("ScanViewController.deinit")
    }

    
    @IBAction func dismiss(sender: UIButton) {
        
        dismissViewControllerAnimated(true, completion: nil)
    }

}
