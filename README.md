# LWCameraController
基于AVFoundation的自定义相机/二维码扫描

Deployment Target iOS 7.0

一、自定义相机：
    
1、初始化并显示捕捉到的画面

    class ViewController: UIViewController {

        // 显示图像的视图
        @IBOutlet weak var previewView: LWPreviewView!
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

    }

2、切换摄像头：

    // 获取当前相机位置
    switch cameraController.currentCameraPosition() {
    case .Back:
        cameraController.toggleCamera(.Front)
    case .Front:
        cameraController.toggleCamera(.Back)
    default:
        cameraController.toggleCamera(.Back)
    }


3、拍照：
    
    cameraController.snapStillImage(withFalshMode: .Off) { (imageData, error) in
        if let data = imageData {
            if let image = UIImage(data: data) {
                // Save to Album
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        } else {
            print(error?.localizedDescription)
        }
    }


4、录像：

    // 判断当前是否正在录像
    if cameraController.isRecording() {
        // 结束录像
        cameraController.stopMovieRecording({ [unowned self] (captureOutput, outputFileURL, connections, error) in

            print("end recording: \(outputFileURL)")
            // Save to Album
            let assetsLibrary = ALAssetsLibrary()
            assetsLibrary.writeVideoAtPathToSavedPhotosAlbum(outputFileURL, completionBlock: { (assetURL: NSURL!, error: NSError!) -> Void in
                if error != nil {
                    print("视频保存出错：\(error)")
                } else {
                    print("视频保存成功")
                }
                do {
                    try NSFileManager.defaultManager().removeItemAtURL(outputFileURL)
                } catch {
                    let nserror = error as NSError
                    print(nserror.localizedDescription)
                }
            })
        })

    } else {
        // 开始录像
        let tmpFilePath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("myMovie.mov")
        cameraController.startMovieRecording(outputFilePath: tmpFilePath, startRecordingHandler: { (captureOutput, connections) in
            print("start recording")
        })
    }


    // 录像是否开启/关闭录音功能
    cameraController.setAudioEnabled(false)


5、手电筒相关：

    // 当前设备手电筒是否可用
    let flag = cameraController.currentTorchAvailable()

    // 当前设备是否支持对应的手电筒模式
    let flag = cameraController.isTorchModeSupported(.On)

    // 获取当前设备的手电筒模式
    cameraController.currentTorchMode()

    // 为当前设备设置手电筒模式
    cameraController.setTorchMode(.Auto)

    // 设置手电筒亮度
    cameraController.setTorchModeOnWithLevel(0.7)


6、闪光灯相关：

    // 当前设备闪关灯是否可用
    let flag = cameraController.currentTorchAvailable()

    // 当前设备是否支持对应的闪关灯模式
    let flag = cameraController.isFlashModeSupported(.On)

    // 获取当前设备的闪光灯模式
    cameraController.currentFlashMode()



