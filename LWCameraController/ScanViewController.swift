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
                                              metadataObjectTypes: [AVMetadataObject.ObjectType.qr,
                                                                    AVMetadataObject.ObjectType.code128,
                                                                    AVMetadataObject.ObjectType.face],
                                              metaDataOutputHandler: {
                                                [unowned self] (captureOutput, metadataObjects, connection) in
                                                
                                                if let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject {
                                                    switch object.type {
                                                    case AVMetadataObject.ObjectType.qr:
                                                        print("AVMetadataObjectTypeQRCode: \(object.stringValue)")
                                                        self.cameraController.stopRunning()
                                                        self.dismiss(animated: true, completion: nil)
                                                    case AVMetadataObject.ObjectType.code128:
                                                        print("AVMetadataObjectTypeCode128Code: \(object.stringValue)")
                                                        self.cameraController.stopRunning()
                                                        self.dismiss(animated: true, completion: nil)
                                                    default:
                                                        break
                                                    }
                                                } else if let object = metadataObjects.first as? AVMetadataFaceObject {
                                                    print("AVMetadataFaceObject:\(object.bounds)")
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
        print("ScanViewController.deinit")
    }

    
    @IBAction func dismiss(_ sender: UIButton) {
        
        self.dismiss(animated: true, completion: nil)
    }

}
