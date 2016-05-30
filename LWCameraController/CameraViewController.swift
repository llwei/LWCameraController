//
//  ViewController.swift
//  LWCameraController
//
//  Created by lailingwei on 16/5/24.
//  Copyright © 2016年 lailingwei. All rights reserved.
//

import UIKit
import AVFoundation
import AssetsLibrary

class CameraViewController: UIViewController {

    // 显示图像的视图
    @IBOutlet weak var previewView: LWVideoPreview!
    // 聚焦图片
    @IBOutlet weak var focusImgView: UIImageView!
    // 相机管理器
    lazy var cameraController: LWCameraController = {
        return LWCameraController(previewView: self.previewView, focusImageView: self.focusImgView, audioEnabled: false)
    }()
    
    
    // MARK: - Life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        // 开始捕捉视图
        cameraController.startRunning()
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        // 结束捕捉视图
        cameraController.stopRunning()
    }

    deinit {
        print("ViewController.deinit")
    }

    // MARK: - Target actions
    
    
    @IBAction func toggleCameraPosition(sender: UIButton) {
        // 切换摄像头
        switch cameraController.currentCameraPosition() {
        case .Back:
            cameraController.toggleCamera(.Front)
        case .Front:
            cameraController.toggleCamera(.Back)
        default:
            cameraController.toggleCamera(.Back)
        }
    }

    @IBAction func toggleTorchMode(sender: UIButton) {
        // 设置手电筒开关
        let torchMode = cameraController.currentTorchMode()
        cameraController.setTorchMode(torchMode == .On ? .Off : .On)
    }
    
    @IBAction func action(sender: UIButton) {
        // 拍照并保存至相册
        cameraController.snapStillImage(withFlashMode: .Off) { (imageData, error) in
            if let data = imageData {
                if let image = UIImage(data: data) {
                    // Save to Album
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    self.dismissViewControllerAnimated(true, completion: nil)
                }
            } else {
                print(error?.localizedDescription)
            }
        }
        
//        // 录像并保存至相册
//        if cameraController.isRecording() {
//            cameraController.stopMovieRecording({
//                [unowned self] (captureOutput, outputFileURL, connections, error) in
//                
//                print("end recording: \(outputFileURL)")
//                // Save to Album
//                let assetsLibrary = ALAssetsLibrary()
//                assetsLibrary.writeVideoAtPathToSavedPhotosAlbum(outputFileURL, completionBlock: { (assetURL: NSURL!, error: NSError!) -> Void in
//                    if error != nil {
//                        print("视频保存出错：\(error)")
//                    } else {
//                        print("视频保存成功")
//                    }
//                    do {
//                        try NSFileManager.defaultManager().removeItemAtURL(outputFileURL)
//                        self.dismissViewControllerAnimated(true, completion: nil)
//                    } catch {
//                        let nserror = error as NSError
//                        print(nserror.localizedDescription)
//                    }
//                })
//            })
//            
//        } else {
//            let tmpFilePath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("myMovie.mov")
//            cameraController.startMovieRecording(outputFilePath: tmpFilePath, startRecordingHandler: { (captureOutput, connections) in
//                print("start recording")
//            })
//        }
    }
    
    
}

