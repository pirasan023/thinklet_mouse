import AVFoundation
import CoreImage
import ImageIO

/// Video only. Capture and recognition are bounded to one pending frame.
final class MacCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((CGImage, Int) -> Void)?
    var onStatus: ((String, Bool, Int) -> Void)?
    private let queue=DispatchQueue(label:"local-camera",qos:.userInitiated)
    private let context=CIContext()
    private var session: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var lease=FrameLease()
    private var observers=[NSObjectProtocol]()
    private var lastAccepted=0.0

    static func devices() -> [AVCaptureDevice] {
        var types:[AVCaptureDevice.DeviceType]=[.builtInWideAngleCamera]
        if #available(macOS 14,*) {types += [.external,.continuityCamera]} else {types.append(.externalUnknown)}
        if #available(macOS 13,*) {types.append(.deskViewCamera)}
        var devices=AVCaptureDevice.DiscoverySession(deviceTypes:types,mediaType:.video,position:.unspecified).devices
        if #available(macOS 13,*) {
            for device in devices {if let desk=device.companionDeskViewCamera,!devices.contains(where:{$0.uniqueID==desk.uniqueID}) {devices.append(desk)}}
        }
        return devices.sorted {a,b in
            if #available(macOS 13,*), (a.deviceType == .deskViewCamera) != (b.deviceType == .deskViewCamera) {return a.deviceType == .deskViewCamera}
            return a.localizedName.localizedStandardCompare(b.localizedName) == .orderedAscending
        }
    }
    static func isDeskView(_ device: AVCaptureDevice) -> Bool {
        if #available(macOS 13,*) {return device.deviceType == .deskViewCamera}
        return false
    }
    func start(deviceID: String, generation: Int) {
        queue.async {
            self.stopSession();self.lease.reset(to:generation);self.lastAccepted=0
            switch AVCaptureDevice.authorizationStatus(for:.video) {
            case .authorized:self.configure(deviceID:deviceID,generation:generation)
            case .notDetermined:
                self.onStatus?("macOSのカメラ許可を待っています",false,generation)
                AVCaptureDevice.requestAccess(for:.video) {allowed in
                    self.queue.async {
                        guard self.lease.generation==generation else{return}
                        if allowed {self.configure(deviceID:deviceID,generation:generation)}
                        else {self.onStatus?("カメラが未許可です。「カメラ設定」から許可してください",true,generation)}
                    }
                }
            default:self.onStatus?("カメラが未許可です。「カメラ設定」から許可してください",true,generation)
            }
        }
    }
    func stop() {queue.async {self.stopSession();self.lease.reset(to:self.lease.generation+1)}}
    func finishFrame(generation: Int) {queue.async {self.lease.finish(generation:generation)}}
    private func stopSession() {
        for observer in observers {NotificationCenter.default.removeObserver(observer)}
        observers=[];videoOutput=nil;session?.stopRunning();session=nil
    }
    private func configure(deviceID: String, generation: Int) {
        guard let device=Self.devices().first(where:{$0.uniqueID==deviceID}) else {
            onStatus?("選択したカメラがありません。「カメラ更新」を押してください",true,generation);return
        }
        do {
            let capture=AVCaptureSession(),input=try AVCaptureDeviceInput(device:device),output=AVCaptureVideoDataOutput()
            guard capture.canAddInput(input) else{throw NSError(domain:"Camera",code:1,userInfo:[NSLocalizedDescriptionKey:"このカメラを入力として追加できません"])}
            capture.addInput(input)
            if capture.canSetSessionPreset(.hd1280x720) {capture.sessionPreset = .hd1280x720}
            output.alwaysDiscardsLateVideoFrames=true
            output.videoSettings=[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self,queue:queue)
            guard capture.canAddOutput(output) else{throw NSError(domain:"Camera",code:2,userInfo:[NSLocalizedDescriptionKey:"映像出力を追加できません"])}
            capture.addOutput(output)
            if let connection=output.connection(with:.video),connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring=false;connection.isVideoMirrored=false
            }
            session=capture;videoOutput=output
            for name in [AVCaptureSession.runtimeErrorNotification,AVCaptureSession.wasInterruptedNotification] {
                observers.append(NotificationCenter.default.addObserver(forName:name,object:capture,queue:nil) { [weak self,weak capture] _ in
                    guard let self=self,let capture=capture else{return}
                    self.queue.async {
                        guard self.session === capture,self.lease.generation==generation else{return}
                        self.onStatus?("カメラの映像が中断されました。「再接続」を押してください",true,generation)
                    }
                })
            }
            capture.startRunning()
            onStatus?("\(device.localizedName) • 映像を確認して「操作開始」",false,generation)
        } catch {onStatus?("カメラ接続失敗：\(error.localizedDescription)",true,generation)}
    }
    func captureOutput(_ output: AVCaptureOutput,didOutput sampleBuffer: CMSampleBuffer,from connection: AVCaptureConnection) {
        let now=ProcessInfo.processInfo.systemUptime
        guard output === videoOutput,now-lastAccepted>=1.0/30.0,let buffer=CMSampleBufferGetImageBuffer(sampleBuffer) else{return}
        let generation=lease.generation
        guard lease.claim(generation:generation) else{return}
        let input=CIImage(cvPixelBuffer:buffer)
        guard let image=context.createCGImage(input,from:input.extent) else{lease.finish(generation:generation);return}
        lastAccepted=now;onFrame?(image,generation)
    }
}
