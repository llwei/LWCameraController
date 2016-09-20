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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 开始捕捉视图
        cameraController.startRunning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraController.stopRunning()
    }


    deinit {
        print("ViewController.deinit")
    }

    // MARK: - Target actions
    
    
    @IBAction func toggleCameraPosition(_ sender: UIButton) {
        // 切换摄像头
        switch cameraController.currentCameraPosition() {
        case .back:
            cameraController.toggleCamera(.front)
        case .front:
            cameraController.toggleCamera(.back)
        default:
            cameraController.toggleCamera(.back)
        }
    }

    @IBAction func toggleTorchMode(_ sender: UIButton) {
        // 设置手电筒开关
        let torchMode = cameraController.currentTorchMode()
        cameraController.setTorchMode(torchMode == .on ? .off : .on)
    }
    
    @IBAction func action(_ sender: UIButton) {
        // 拍照并保存至相册
        cameraController.snapStillImage(withFlashMode: .off) { (imageData, error) in
            if let data = imageData {
                if let image = UIImage(data: data as Data) {
                    // Save to Album
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    self.dismiss(animated: true, completion: nil)
                }
            } else {
                print(error?.localizedDescription)
            }
        }
        
        // 录像并保存至相册
        if cameraController.isRecording() {
            cameraController.stopMovieRecording({
                [unowned self] (captureOutput, outputFileURL, connections, error) in
                
                print("end recording: \(outputFileURL)")
                // Save to Album
                let assetsLibrary = ALAssetsLibrary()
                assetsLibrary.writeVideoAtPath(toSavedPhotosAlbum: outputFileURL, completionBlock: { (assertURL: URL?, error: Error?) in
                    if error != nil {
                        print("视频保存出错：\(error)")
                    } else {
                        print("视频保存成功")
                    }
                    do {
                        try FileManager.default.removeItem(at: outputFileURL)
                        self.dismiss(animated: true, completion: nil)
                    } catch {
                        let nserror = error as NSError
                        print(nserror.localizedDescription)
                    }
                })
            })
            
        } else {
            let tmpFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("myMovie.mov")
            cameraController.startMovieRecording(outputFilePath: tmpFilePath, startRecordingHandler: { (captureOutput, connections) in
                print("start recording")
            })
        }
    }
    
    
}

