import AppKit
import Vision
import ApplicationServices
import ImageIO
import Security
import AVFoundation

/// Image and joints share the same aspect-fit rectangle and bottom-left origin.
final class HandPreview: NSView {
    var frameImage: CGImage?
    var joints: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint] = [:]
    var showSkeleton = true
    var mirrored = false
    var keyboardRegion: CGRect?
    var selectingKeyboard=false, firstCorner: CGPoint?
    var onKeyboardRegion: ((CGRect)->Void)?
    private var imageRect: CGRect {
        guard let image=frameImage else{return .zero}
        let scale=min(bounds.width/CGFloat(image.width),bounds.height/CGFloat(image.height))
        return CGRect(x:(bounds.width-CGFloat(image.width)*scale)/2,y:(bounds.height-CGFloat(image.height)*scale)/2,width:CGFloat(image.width)*scale,height:CGFloat(image.height)*scale)
    }
    override func mouseDown(with event: NSEvent) {
        guard selectingKeyboard,frameImage != nil else{return}
        let p=convert(event.locationInWindow,from:nil),r=imageRect
        guard r.contains(p) else{return}
        let x=(p.x-r.minX)/r.width
        let normalized=CGPoint(x:mirrored ? 1-x : x,y:(p.y-r.minY)/r.height)
        if let first=firstCorner {
            let rect=CGRect(x:min(first.x,normalized.x),y:min(first.y,normalized.y),width:abs(first.x-normalized.x),height:abs(first.y-normalized.y))
            guard rect.width>=0.02,rect.height>=0.02 else{return}
            selectingKeyboard=false;firstCorner=nil;onKeyboardRegion?(rect)
        } else { firstCorner=normalized }
        needsDisplay=true
    }
    let fingers: [([VNHumanHandPoseObservation.JointName], NSColor)] = [
        ([.wrist,.thumbCMC,.thumbMP,.thumbIP,.thumbTip], .systemOrange),
        ([.wrist,.indexMCP,.indexPIP,.indexDIP,.indexTip], .systemCyan),
        ([.wrist,.middleMCP,.middlePIP,.middleDIP,.middleTip], .systemGreen),
        ([.wrist,.ringMCP,.ringPIP,.ringDIP,.ringTip], .systemPink),
        ([.wrist,.littleMCP,.littlePIP,.littleDIP,.littleTip], .systemPurple)
    ]
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite:0.07,alpha:1).setFill(); bounds.fill()
        guard let image=frameImage else {
            let message="THINKLETのUSB映像を待っています"
            (message as NSString).draw(at:NSPoint(x:24,y:bounds.midY),withAttributes:[.foregroundColor:NSColor.lightGray,.font:NSFont.systemFont(ofSize:18)])
            return
        }
        let scale=min(bounds.width/CGFloat(image.width),bounds.height/CGFloat(image.height))
        let rect=NSRect(x:(bounds.width-CGFloat(image.width)*scale)/2,y:(bounds.height-CGFloat(image.height)*scale)/2,width:CGFloat(image.width)*scale,height:CGFloat(image.height)*scale)
        NSGraphicsContext.current?.cgContext.draw(image,in:rect)
        if let region=keyboardRegion {
            let x=mirrored ? 1-region.maxX : region.minX
            let box=CGRect(x:rect.minX+x*rect.width,y:rect.minY+region.minY*rect.height,width:region.width*rect.width,height:region.height*rect.height)
            NSColor.systemYellow.withAlphaComponent(0.13).setFill();box.fill()
            NSColor.systemYellow.setStroke();let path=NSBezierPath(rect:box);path.lineWidth=1.5;path.stroke()
        }
        if selectingKeyboard {
            let text=firstCorner == nil ? "キーボードの左上をクリック（次に右下）" : "キーボードの反対側の角をクリック"
            (text as NSString).draw(at:CGPoint(x:rect.minX+10,y:rect.minY+10),withAttributes:[.font:NSFont.boldSystemFont(ofSize:14),.foregroundColor:NSColor.white,.backgroundColor:NSColor.black])
        }
        guard showSkeleton else { return }
        func location(_ name: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let p=joints[name],p.confidence>0.35 else{return nil}
            return CGPoint(x:rect.minX+(mirrored ? 1-p.location.x : p.location.x)*rect.width,y:rect.minY+p.location.y*rect.height)
        }
        for (names,color) in fingers {
            for (a,b) in zip(names,names.dropFirst()) {
                guard let p=location(a),let q=location(b) else{continue}
                let line=NSBezierPath();line.move(to:p);line.line(to:q)
                NSColor.black.withAlphaComponent(0.5).setStroke();line.lineWidth=3;line.stroke()
                color.setStroke();line.lineWidth=1.3;line.stroke()
            }
            for name in names {
                guard let p=location(name) else{continue}
                let dot=NSBezierPath(ovalIn:NSRect(x:p.x-2.5,y:p.y-2.5,width:5,height:5))
                color.setFill();dot.fill();NSColor.white.setStroke();dot.lineWidth=0.6;dot.stroke()
            }
        }
        if let p=location(.indexTip) {
            NSColor.systemCyan.setStroke()
            let ring=NSBezierPath(ovalIn:NSRect(x:p.x-9,y:p.y-9,width:18,height:18));ring.lineWidth=1;ring.stroke()
        }
    }
}

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let imageView=HandPreview(), status=NSTextField(labelWithString:"USB接続を待っています"), button=NSButton(title:"操作開始", target:nil, action:nil)
    let recognition=NSTextField(labelWithString:"関節 0 / 21"), gesture=NSTextField(labelWithString:"手をカメラに映してください")
    let skeleton=NSButton(checkboxWithTitle:"骨格を表示",target:nil,action:nil)
    let previewEngine=GestureEngine()
    let pointerSpeedSlider=NSSlider(value:1,minValue:0.4,maxValue:2.5,target:nil,action:nil)
    let scrollSpeedSlider=NSSlider(value:1,minValue:0.25,maxValue:3,target:nil,action:nil)
    let accelerationSlider=NSSlider(value:1.5,minValue:0,maxValue:3,target:nil,action:nil)
    let accelerationLabel=NSTextField(labelWithString:"加速 150%")
    let wristControl=NSButton(checkboxWithTitle:"手首で操作",target:nil,action:nil)
    let regionPause=NSButton(checkboxWithTitle:"キーボード範囲で停止",target:nil,action:nil)
    var savedControlIsWrist=true
    var pointerSpeedKey: String {wristControl.state == .on ? "wristPointerSpeed" : "pointerSpeed"}
    let pointerSpeedLabel=NSTextField(labelWithString:"ポインター 100%")
    let scrollSpeedLabel=NSTextField(labelWithString:"スクロール 100%")
    let imageContext=CIContext()
    let mirror=NSButton(checkboxWithTitle:"左右反転", target:nil, action:nil)
    let rotation=NSPopUpButton(), engine=GestureEngine()
    let controlHand=NSPopUpButton()
    var configurationVersion=0
    let videoSource=NSPopUpButton(),macCamera=MacCamera()
    var cameraDevices=[AVCaptureDevice]()
    var sourceGeneration=0,sourceReady=false
    var deviceObservers=[NSObjectProtocol]()
    var selectedSourceID: String {videoSource.selectedItem?.representedObject as? String ?? "thinklet"}
    var isThinkletSource: Bool {selectedSourceID == "thinklet"}
    let reconnect=NSButton(title:"再接続",target:nil,action:nil)
    let connection=NSTextField(wrappingLabelWithString:"THINKLETへ接続しています…")
    var connectionProcess: Process?
    let queue=DispatchQueue(label:"hand-vision",qos:.userInitiated)
    var enabled=false, held=false, alive=true, lastFrame=Date.distantPast
    var pendingStart=false
    var permissionAlert: NSAlert?
    let activity=NSTextField(labelWithString:"操作オフ • 「操作開始」を押してください")
    var lastStopReason="起動直後 • 「操作開始」を押してください"
    var isTestingPointer=false, pointerTestGeneration=0
    var testPreviousMode="未実行"
    var lastOutput="未送信"
    lazy var signingIdentity: String = {
        var code: SecStaticCode?
        let flags=SecCSFlags(rawValue:0)
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL,flags,&code)==errSecSuccess,let code=code else{return "取得できません"}
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code,flags,&requirement)==errSecSuccess,let requirement=requirement else{return "取得できません"}
        var result: CFString?
        guard SecRequirementCopyString(requirement,flags,&result)==errSecSuccess,let result=result else{return "取得できません"}
        return result as String
    }()
    var session: URLSession!
    var lastClick = 0.0, clickCount = 0
    var gestureFeedbackUntil = 0.0
    var typingUntil = 0.0
    let keyboardGuard=KeyboardGuard()
    var keyboardRotation=0
    let keyboardStatus=NSTextField(labelWithString:"キーボード位置：未学習（数文字入力すると自動学習）")
    let health=NSTextField(labelWithString:"権限を確認しています")
    var lastKeyboardCounter: UInt32=0
    var lastPermissions=(false,false)
    var lastFrameID: String?
    var lastCommandedPosition: CGPoint?
    var emittedEvents=0
    var localMonitor: Any?, globalMonitor: Any?
    var localMouseMonitor: Any?, globalMouseMonitor: Any?
    var mousePriority=MousePriority(), cursorOutput=CursorInterpolator()
    var outputTimer: Timer?
    func applicationDidFinishLaunching(_ notification:Notification) {
        let menu=NSMenu(); let item=NSMenuItem(); menu.addItem(item)
        let sub=NSMenu(); sub.addItem(withTitle:"終了",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"); item.submenu=sub; NSApp.mainMenu=menu
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:820,height:820),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        let appVersion=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "開発版"
        window.title="THINKLET Hand Mouse v\(appVersion)"; window.delegate=self
        let stack=NSStackView(); stack.orientation = .vertical; stack.spacing=8; stack.edgeInsets=NSEdgeInsets(top:18,left:18,bottom:18,right:18)
        skeleton.state = .on; skeleton.target=self; skeleton.action=#selector(overlayChanged)
        gesture.font=NSFont.boldSystemFont(ofSize:18)
        activity.font=NSFont.boldSystemFont(ofSize:16)
        for label in [gesture,status,health,keyboardStatus] {label.widthAnchor.constraint(equalToConstant:760).isActive=true;label.lineBreakMode = .byTruncatingTail}
        imageView.widthAnchor.constraint(equalToConstant:760).isActive=true; imageView.heightAnchor.constraint(equalToConstant:320).isActive=true
        let controls=NSStackView(); controls.orientation = .horizontal
        button.target=self; button.action=#selector(toggle)
        mirror.state = .off
        rotation.addItems(withTitles:["回転 0°","回転 90°","回転 180°","回転 270°"])
        controlHand.addItems(withTitles:["右手のみ","左手のみ"])
        controlHand.target=self;controlHand.action=#selector(configChanged)
        mirror.target=self; mirror.action=#selector(configChanged); rotation.target=self; rotation.action=#selector(configChanged)
        controls.addArrangedSubview(button); controls.addArrangedSubview(mirror); controls.addArrangedSubview(rotation); controls.addArrangedSubview(skeleton)
        controls.addArrangedSubview(controlHand)
        videoSource.target=self;videoSource.action=#selector(changeVideoSource)
        videoSource.widthAnchor.constraint(equalToConstant:300).isActive=true
        let refresh=NSButton(title:"カメラ更新",target:self,action:#selector(refreshCameraList))
        let desk=NSButton(title:"デスクビュー設定",target:self,action:#selector(openDeskView))
        let cameraPermission=NSButton(title:"カメラ設定",target:self,action:#selector(openCameraSettings))
        let sourceRow=NSStackView(views:[NSTextField(labelWithString:"映像"),videoSource,refresh,desk,cameraPermission]);sourceRow.orientation = .horizontal
        refreshCameras()
        reconnect.target=self;reconnect.action=#selector(connectDevice)
        let connectionRow=NSStackView(views:[connection,reconnect]);connectionRow.orientation = .horizontal
        connection.font=NSFont.systemFont(ofSize:12);connection.textColor = .secondaryLabelColor
        let help=NSTextField(wrappingLabelWithString:"手首で操作：腕を置き、手首を左右・上下に少し振って移動\n親指＋人差し指：離すとクリック／0.45秒以上保持＋手首を振るとドラッグ\n親指＋中指：短く離すと右クリック／手首を左右に振ってスクロール（右→下、左→上）\n物理マウス・トラックパッド優先：操作中と最後の入力後1.5秒は手を停止\n実際のキー入力中は停止。映像の重なりによる停止はチェックで切替\nEsc / ⌘⇧P：停止 ｜ 手を隠す：ボタン解放")
        let legend=NSTextField(labelWithString:"骨格：親指 オレンジ ／ 人差し指 水色 ／ 中指 緑 ／ 薬指 ピンク ／ 小指 紫\n手首→指先の向きで操作。基準姿勢の再設定でカーソルが飛ぶことはありません。")
        legend.font=NSFont.systemFont(ofSize:12);legend.textColor = .secondaryLabelColor
        let keyboardButton=NSButton(title:"キーボード範囲を指定",target:self,action:#selector(selectKeyboard))
        let clearKeyboard=NSButton(title:"学習をリセット",target:self,action:#selector(resetKeyboard))
        let keyboardRow=NSStackView(views:[keyboardButton,clearKeyboard]);keyboardRow.orientation = .horizontal
        let permissions=NSButton(title:"アクセシビリティ設定",target:self,action:#selector(openAccessibility))
        let inputPermission=NSButton(title:"入力監視設定",target:self,action:#selector(openInputMonitoring))
        let test=NSButton(title:"ポインター動作テスト",target:self,action:#selector(testPointer))
        let diagnostics=NSButton(title:"診断情報をコピー",target:self,action:#selector(copyDiagnostics))
        let permissionRow=NSStackView(views:[permissions,inputPermission,test,diagnostics]);permissionRow.orientation = .horizontal
        health.font=NSFont.monospacedSystemFont(ofSize:11,weight:.regular)
        keyboardStatus.font=NSFont.systemFont(ofSize:12)
        imageView.onKeyboardRegion={ [weak self] rect in
            guard let self=self else{return};self.keyboardGuard.setRegion(rect);self.imageView.keyboardRegion=self.keyboardGuard.region
            self.keyboardStatus.stringValue="キーボード範囲：手動設定済み • 黄色枠内の指で停止";self.imageView.needsDisplay=true
        }
        let defaults=UserDefaults.standard
        wristControl.state=(defaults.object(forKey:"wristControl") == nil || defaults.bool(forKey:"wristControl")) ? .on : .off
        savedControlIsWrist=wristControl.state == .on
        wristControl.target=self;wristControl.action=#selector(controlModeChanged)
        regionPause.state=(defaults.object(forKey:"keyboardRegionPause") == nil ? !savedControlIsWrist : defaults.bool(forKey:"keyboardRegionPause")) ? .on : .off
        regionPause.target=self;regionPause.action=#selector(regionPauseChanged)
        regionPause.toolTip="映像の重なりによる停止。オフでも、実際のキー入力中は停止します。"
        let recenter=NSButton(title:"この姿勢を基準にする",target:self,action:#selector(recenterWrist))
        let wristRow=NSStackView(views:[wristControl,recenter,regionPause]);wristRow.orientation = .horizontal;wristRow.spacing=12
        if defaults.object(forKey:pointerSpeedKey) != nil {pointerSpeedSlider.doubleValue=max(0.4,min(2.5,defaults.double(forKey:pointerSpeedKey)))}
        if defaults.object(forKey:"scrollSpeed") != nil {scrollSpeedSlider.doubleValue=max(0.25,min(3,defaults.double(forKey:"scrollSpeed")))}
        if defaults.object(forKey:"pointerAcceleration") != nil {accelerationSlider.doubleValue=max(0,min(3,defaults.double(forKey:"pointerAcceleration")))}
        for slider in [pointerSpeedSlider,scrollSpeedSlider,accelerationSlider] {
            slider.target=self;slider.action=#selector(speedChanged);slider.isContinuous=true;slider.widthAnchor.constraint(equalToConstant:160).isActive=true
        }
        let speedRow=NSStackView(views:[pointerSpeedLabel,pointerSpeedSlider,scrollSpeedLabel,scrollSpeedSlider]);speedRow.orientation = .horizontal;speedRow.spacing=10
        for label in [pointerSpeedLabel,scrollSpeedLabel] {label.widthAnchor.constraint(equalToConstant:140).isActive=true}
        pointerSpeedSlider.toolTip="手の移動量に対するポインターの移動量（40〜250%）"
        scrollSpeedSlider.toolTip="手の左右移動に対するスクロール量（25〜300%）"
        accelerationSlider.toolTip="0%で加速なし。強くするほど速い手の動きで大きく移動します（0〜300%）"
        accelerationLabel.widthAnchor.constraint(equalToConstant:140).isActive=true
        let accelerationHint=NSTextField(labelWithString:"ゆっくり＝精密 ／ 速く振る＝大きく移動")
        accelerationHint.font=NSFont.systemFont(ofSize:12);accelerationHint.textColor = .secondaryLabelColor
        let accelerationRow=NSStackView(views:[accelerationLabel,accelerationSlider,accelerationHint]);accelerationRow.orientation = .horizontal;accelerationRow.spacing=10
        applySpeeds()
        for view in [activity,imageView,gesture,recognition,status,health,permissionRow,sourceRow,connectionRow,controls,wristRow,speedRow,accelerationRow,keyboardStatus,keyboardRow,legend,help] {stack.addArrangedSubview(view)}
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.documentView=stack
        stack.translatesAutoresizingMaskIntoConstraints=false
        stack.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor).isActive=true
        stack.leadingAnchor.constraint(equalTo:scroll.contentView.leadingAnchor).isActive=true
        stack.topAnchor.constraint(equalTo:scroll.contentView.topAnchor).isActive=true
        window.contentView=scroll
        let height=min(CGFloat(900),NSScreen.main?.visibleFrame.height ?? 820)
        window.setContentSize(NSSize(width:820,height:height));window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        let config=URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest=0.7; config.timeoutIntervalForResource=1; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session=URLSession(configuration:config)
        installKeyMonitors()
        let outputTimer=Timer(timeInterval:1.0/60.0,repeats:true) { [weak self] _ in self?.tickPointer() }
        self.outputTimer=outputTimer;RunLoop.main.add(outputTimer,forMode:.common)
        lastKeyboardCounter=CGEventSource.counterForEventType(.hidSystemState,eventType:.keyDown)
        Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in
            guard let self=self else{return}
            self.refreshPermissions();self.pollKeyboard()
            if self.enabled && ProcessInfo.processInfo.systemUptime<self.typingUntil {self.cursorOutput.cancel();self.emit(self.engine.reset())}
            if Date().timeIntervalSince(self.lastFrame)>0.55 {
                self.cursorOutput.cancel();self.emit(self.engine.reset()); _ = self.previewEngine.reset()
                self.imageView.joints=[:]; self.imageView.needsDisplay=true
                self.recognition.stringValue="関節 0 / 21 • 映像待ち"
                self.gesture.stringValue="映像が届いていません"
            }
            if self.enabled, let p=CGEvent(source:nil)?.location,
               PointerSafety.externalCorner(position:p,commanded:self.lastCommandedPosition) { self.stop(reason:"左上隅へのマウス移動で停止");self.status.stringValue="左上隅へのマウス移動で停止しました" }
        }
        macCamera.onFrame={ [weak self] image,generation in
            DispatchQueue.main.async {
                guard let self=self else{return}
                guard self.alive,!self.isThinkletSource,self.sourceGeneration==generation else{self.macCamera.finishFrame(generation:generation);return}
                self.processFrame(image) {self.macCamera.finishFrame(generation:generation)}
            }
        }
        macCamera.onStatus={ [weak self] message,isError,generation in
            DispatchQueue.main.async {
                guard let self=self,self.alive,!self.isThinkletSource,self.sourceGeneration==generation else{return}
                self.connection.stringValue=message
                if isError {self.stop(reason:message);self.lastFrame = .distantPast;self.imageView.frameImage=nil;self.imageView.needsDisplay=true}
            }
        }
        for name in [AVCaptureDevice.wasConnectedNotification,AVCaptureDevice.wasDisconnectedNotification] {
            deviceObservers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in self?.refreshCameras() })
        }
        sourceReady=true;changeVideoSource()
    }
    @objc func refreshCameraList() {refreshCameras()}
    func refreshCameras(selectDesk: Bool = false) {
        let previous=videoSource.selectedItem?.representedObject as? String
        let preferred=previous ?? UserDefaults.standard.string(forKey:"videoSourceID")
        cameraDevices=MacCamera.devices();videoSource.removeAllItems()
        videoSource.addItem(withTitle:"THINKLET（USB）");videoSource.lastItem?.representedObject="thinklet"
        for device in cameraDevices {
            let title=MacCamera.isDeskView(device) ? "デスクビュー • \(device.localizedName)" : device.localizedName
            videoSource.addItem(withTitle:title);videoSource.lastItem?.representedObject="camera:\(device.uniqueID)"
        }
        let desk=cameraDevices.first(where:{MacCamera.isDeskView($0)}).map{"camera:\($0.uniqueID)"}
        let preferredIndex=videoSource.itemArray.firstIndex{($0.representedObject as? String)==preferred}
        if selectDesk,let desk=desk,let index=videoSource.itemArray.firstIndex(where:{($0.representedObject as? String)==desk}) {videoSource.selectItem(at:index)}
        else if let index=preferredIndex {videoSource.selectItem(at:index)}
        else if !cameraDevices.isEmpty {videoSource.selectItem(at:1)}
        if sourceReady,previous != selectedSourceID {changeVideoSource()}
    }
    @objc func changeVideoSource() {
        configurationVersion += 1;sourceGeneration += 1
        stop(reason:"映像入力を切り替えました • 映像を確認して「操作開始」")
        if let process=connectionProcess,process.isRunning {process.terminate()}
        connectionProcess=nil;reconnect.isEnabled=true;macCamera.stop()
        lastFrame = .distantPast;lastFrameID=nil;imageView.frameImage=nil;imageView.joints=[:];imageView.needsDisplay=true
        keyboardGuard.clear();imageView.keyboardRegion=nil
        UserDefaults.standard.set(selectedSourceID,forKey:"videoSourceID")
        if isThinkletSource {fetch();connectDevice()}
        else {
            connection.stringValue="\(videoSource.titleOfSelectedItem ?? "カメラ")へ接続中…"
            macCamera.start(deviceID:String(selectedSourceID.dropFirst("camera:".count)),generation:sourceGeneration)
        }
    }
    @objc func openCameraSettings() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Camera")!)
    }
    @objc func openDeskView() {
        guard #available(macOS 13,*) else {connection.stringValue="デスクビューにはmacOS 13以降が必要です";return}
        stop(reason:"デスクビューの構図を設定中")
        let configuration=AVCaptureDeskViewApplication.LaunchConfiguration();configuration.requiresSetUpModeCompletion=true
        AVCaptureDeskViewApplication().present(launchConfiguration:configuration) { [weak self] error in
            DispatchQueue.main.async {
                guard let self=self,self.alive else{return}
                if let error=error {self.connection.stringValue="デスクビュー設定：\(error.localizedDescription)";return}
                self.refreshCameras(selectDesk:true);self.recenterWrist()
                self.connection.stringValue="デスクビューの範囲を確認しました • 映像を確認して「操作開始」"
            }
        }
    }
    func key(_ e:NSEvent) {
        if e.type == .keyDown && (e.keyCode==53 || (e.charactersIgnoringModifiers=="p" && e.modifierFlags.contains([.command,.shift]))) { stop(reason:"停止キーを検出");return }
        typingUntil=ProcessInfo.processInfo.systemUptime+1.2
        cursorOutput.cancel()
        emit(engine.reset()); _ = previewEngine.reset();gestureFeedbackUntil=0
        if enabled { gesture.stringValue="キーボード入力中 • 操作を一時停止" }
    }
    func installKeyMonitors() {
        if let old=localMonitor { NSEvent.removeMonitor(old) }
        if let old=globalMonitor { NSEvent.removeMonitor(old) }
        localMonitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp]) { [weak self] event in self?.key(event);return event }
        globalMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.keyDown,.keyUp]) { [weak self] event in self?.key(event) }
        if let old=localMouseMonitor {NSEvent.removeMonitor(old)}
        if let old=globalMouseMonitor {NSEvent.removeMonitor(old)}
        let mask:NSEvent.EventTypeMask=[.mouseMoved,.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.otherMouseDown,.otherMouseUp,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged,.scrollWheel]
        localMouseMonitor=NSEvent.addLocalMonitorForEvents(matching:mask) { [weak self] event in self?.physicalMouse(event);return event }
        globalMouseMonitor=NSEvent.addGlobalMonitorForEvents(matching:mask) { [weak self] event in self?.physicalMouse(event) }
    }
    func physicalMouse(_ event:NSEvent) {
        if let cg=event.cgEvent,MouseEventOrigin.isOwn(tag:cg.getIntegerValueField(.eventSourceUserData),pid:cg.getIntegerValueField(.eventSourceUnixProcessID),processID:Int64(ProcessInfo.processInfo.processIdentifier)) {return}
        let now=ProcessInfo.processInfo.systemUptime
        switch event.type {
        case .leftMouseDown,.rightMouseDown,.otherMouseDown,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged:
            mousePriority.activity(time:now,button:event.buttonNumber,pressed:true)
        case .leftMouseUp,.rightMouseUp,.otherMouseUp:
            mousePriority.activity(time:now,button:event.buttonNumber,pressed:false)
        default:mousePriority.activity(time:now)
        }
        cursorOutput.cancel();emit(engine.reset());_ = previewEngine.reset()
        if isTestingPointer {stop(reason:"物理マウス入力でテストを中止")}
        if enabled {gesture.stringValue="物理マウス優先 • 手の操作を一時停止"}
    }
    func normalizedCursor() -> CGPoint {
        let bounds=CGDisplayBounds(CGMainDisplayID()),p=CGEvent(source:nil)?.location ?? .zero
        return CGPoint(x:(p.x-bounds.minX)/bounds.width,y:(p.y-bounds.minY)/bounds.height)
    }
    func tickPointer() {
        let now=ProcessInfo.processInfo.systemUptime
        guard alive,enabled,!isTestingPointer,!engine.pointerFrozen,!mousePriority.isActive(time:now),now>=typingUntil,Date().timeIntervalSince(lastFrame)<0.22 else{cursorOutput.cancel();return}
        guard let target=cursorOutput.tick(time:now) else{return}
        lastCommandedPosition=target
        post(CGEvent(mouseEventSource:nil,mouseType:held ? .leftMouseDragged : .mouseMoved,mouseCursorPosition:target,mouseButton:.left))
    }
    func post(_ event: CGEvent?) {
        guard let event=event else{return}
        event.setIntegerValueField(.eventSourceUserData,value:MouseEventOrigin.ownTag)
        event.post(tap:.cghidEventTap);emittedEvents += 1
    }
    func refreshPermissions() {
        let permission=permissionState()
        let post=permission.canControlPointer
        let listen=permission.listenEvents
        if post != lastPermissions.0 || listen != lastPermissions.1 {
            installKeyMonitors();lastPermissions=(post,listen)
        }
        if enabled && !post {stop(reason:"操作権限が無効になったため停止");status.stringValue="macOSが操作を許可していません。「診断情報をコピー」で状態を確認できます"}
        if pendingStart && post && Date().timeIntervalSince(lastFrame)<0.6 {
            if let alert=permissionAlert {window.endSheet(alert.window);permissionAlert=nil}
            startControl()
        }
        activity.stringValue=isTestingPointer ? "ポインター移動テスト中 • 1.5秒間、位置を確認します" : (enabled ? "操作オン • \(gesture.stringValue)" : (pendingStart ? "開始待ち • 操作許可と映像が揃ったら開始します" : "操作オフ • \(lastStopReason)"))
        activity.textColor=enabled ? .systemGreen : (isTestingPointer ? .systemOrange : .labelColor)
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "開発版"
        health.stringValue="v\(version)  \(permission.summary)  出力: \(emittedEvents)"
        health.toolTip=diagnosticText()
    }
    func permissionState() -> PermissionState {
        PermissionState(accessibility:AXIsProcessTrusted(),postEvents:CGPreflightPostEventAccess(),listenEvents:CGPreflightListenEventAccess())
    }
    func diagnosticText() -> String {
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "不明"
        return "THINKLET Hand Mouse v\(version)\n実行ファイル: \(Bundle.main.executablePath ?? "不明")\nアプリID: \(Bundle.main.bundleIdentifier ?? "不明")\n署名識別: \(signingIdentity)\nPID: \(ProcessInfo.processInfo.processIdentifier)\nOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n\(permissionState().summary)\n映像: \(Date().timeIntervalSince(lastFrame)<0.6 ? "受信中" : "未受信")\n操作開始: \(enabled)\n開始要求を保持: \(pendingStart)\n最後の停止理由: \(lastStopReason)\n認識: \(recognition.stringValue)\n状態: \(gesture.stringValue)\n出力イベント数: \(emittedEvents)\n最後の出力: \(lastOutput)\nテスト直前の操作開始: \(testPreviousMode)\n操作テスト: \(pointerTestResult)"
    }
    var pointerTestResult="未実行"
    @objc func copyDiagnostics() {
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(diagnosticText(),forType:.string)
        status.stringValue="診断情報をコピーしました • キーの内容やカメラ画像は含みません"
    }
    func pollKeyboard() {
        guard CGPreflightListenEventAccess() || AXIsProcessTrusted() else{return}
        let now=ProcessInfo.processInfo.systemUptime
        let down=CGEventSource.secondsSinceLastEventType(.hidSystemState,eventType:.keyDown)
        let up=CGEventSource.secondsSinceLastEventType(.hidSystemState,eventType:.keyUp)
        let heldKey=(0..<128).contains{CGEventSource.keyState(.hidSystemState,key:CGKeyCode($0))}
        if heldKey || min(down,up)<1.2 { typingUntil=max(typingUntil,now+max(0,1.2-min(down,up))) }
        // A held non-repeating key must remain paused until release.
        if heldKey { typingUntil=max(typingUntil,now+1.2) }
    }
    @objc func openAccessibility() {
        requestControlPermission()
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func requestControlPermission() {
        guard !permissionState().canControlPointer else{return}
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)
        if !permissionState().canControlPointer {_ = CGRequestPostEventAccess()}
    }
    @objc func openInputMonitoring() {
        _ = CGRequestListenEventAccess()
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    @objc func selectKeyboard() {
        stop(reason:"キーボード範囲の指定中");imageView.selectingKeyboard=true;imageView.firstCorner=nil;imageView.needsDisplay=true
        keyboardStatus.stringValue="映像のキーボードを囲む2つの角をクリックしてください"
    }
    @objc func resetKeyboard() {
        stop(reason:"キーボード学習をリセット");keyboardGuard.clear();imageView.keyboardRegion=nil;imageView.selectingKeyboard=false;imageView.firstCorner=nil;imageView.needsDisplay=true
        keyboardStatus.stringValue="キーボード位置：未学習（数文字入力すると自動学習）"
    }
    @objc func testPointer() {
        guard !isTestingPointer else{return}
        let wasEnabled=enabled
        testPreviousMode=String(wasEnabled)
        stop(reason:"ポインターテストのため一時停止");refreshPermissions()
        guard permissionState().canControlPointer else {pointerTestResult="権限チェックで停止: \(permissionState().summary)";showPermissionHelp();return }
        guard let start=CGEvent(source:nil)?.location else{return}
        var display=CGMainDisplayID(), count:UInt32=0
        _ = CGGetDisplaysWithPoint(start,1,&display,&count)
        let bounds=CGDisplayBounds(display)
        let offset=start.x+160<bounds.maxX-4 ? 160.0 : -160.0
        let target=CGPoint(x:start.x+offset,y:start.y)
        isTestingPointer=true;button.title="テスト停止"
        let generation=pointerTestGeneration
        pointerTestResult="テスト中（OS座標を確認します。目視での移動は未確認）"
        status.stringValue="ポインターを横へ160ポイント移動します • 元の位置には戻しません"
        post(CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:target,mouseButton:.left))
        DispatchQueue.main.asyncAfter(deadline:.now()+1.5) { [weak self] in
            guard let self=self,self.alive,self.pointerTestGeneration==generation else{return}
            self.isTestingPointer=false
            if let actual=CGEvent(source:nil)?.location {
                self.pointerTestResult="OS座標: 開始(\(Int(start.x)),\(Int(start.y))) → 要求(\(Int(target.x)),\(Int(target.y))) / 応答(\(Int(actual.x)),\(Int(actual.y))) • 目視は未確認"
            } else {self.pointerTestResult="OSから現在の座標を取得できません"}
            if wasEnabled && self.permissionState().canControlPointer && Date().timeIntervalSince(self.lastFrame)<0.6 {
                self.startControl()
                self.status.stringValue="テスト終了 • 操作オンに復帰。親指を離して手を映してください"
            } else {
                self.stop(reason:"テスト終了 • 手で動かすには「操作開始」を押してください")
                self.status.stringValue="テスト終了 • \(self.pointerTestResult)"
            }
        }
    }
    func showPermissionHelp() {
        guard permissionAlert == nil else{return}
        let alert=NSAlert();alert.messageText="実行中のアプリがmacOSから操作許可を受け取れていません"
        permissionAlert=alert
        alert.informativeText="\(permissionState().summary)\n\n実行中の場所：\n\(Bundle.main.bundlePath)\n\n設定画面の登録先と、この場所が一致するか確認してください。更新後の古い登録・反映待ちなどが考えられますが、原因はまだ確定していません。オンのまま動かない場合は「診断をコピー」で詳細を共有できます。"
        alert.addButton(withTitle:"設定を開く");alert.addButton(withTitle:"診断をコピー");alert.addButton(withTitle:"閉じる")
        alert.beginSheetModal(for:window) { [weak self] response in
            self?.permissionAlert=nil
            if response == .alertFirstButtonReturn {self?.openAccessibility()}
            else if response == .alertSecondButtonReturn {self?.copyDiagnostics()}
        }
    }
    @objc func overlayChanged() { imageView.showSkeleton=skeleton.state == .on;imageView.needsDisplay=true }
    func applySpeeds() {
        for e in [engine,previewEngine] {e.pointerSpeed=pointerSpeedSlider.doubleValue;e.scrollSpeed=scrollSpeedSlider.doubleValue;e.pointerAcceleration=accelerationSlider.doubleValue;e.wristControl=wristControl.state == .on}
        pointerSpeedLabel.stringValue="ポインター \(Int((pointerSpeedSlider.doubleValue*100).rounded()))%"
        scrollSpeedLabel.stringValue="スクロール \(Int((scrollSpeedSlider.doubleValue*100).rounded()))%"
        accelerationLabel.stringValue="加速 \(Int((accelerationSlider.doubleValue*100).rounded()))%"
    }
    @objc func speedChanged() {
        cursorOutput.cancel();emit(engine.reset());_ = previewEngine.reset();applySpeeds()
        UserDefaults.standard.set(pointerSpeedSlider.doubleValue,forKey:pointerSpeedKey)
        UserDefaults.standard.set(scrollSpeedSlider.doubleValue,forKey:"scrollSpeed")
        UserDefaults.standard.set(accelerationSlider.doubleValue,forKey:"pointerAcceleration")
    }
    @objc func controlModeChanged() {
        let defaults=UserDefaults.standard
        defaults.set(pointerSpeedSlider.doubleValue,forKey:savedControlIsWrist ? "wristPointerSpeed" : "pointerSpeed")
        savedControlIsWrist=wristControl.state == .on
        defaults.set(savedControlIsWrist,forKey:"wristControl")
        pointerSpeedSlider.doubleValue=defaults.object(forKey:pointerSpeedKey) == nil ? 1 : max(0.4,min(2.5,defaults.double(forKey:pointerSpeedKey)))
        if defaults.object(forKey:"keyboardRegionPause") == nil {regionPause.state=savedControlIsWrist ? .off : .on}
        applySpeeds();recenterWrist()
    }
    @objc func regionPauseChanged() {
        UserDefaults.standard.set(regionPause.state == .on,forKey:"keyboardRegionPause")
        recenterWrist()
    }
    @objc func recenterWrist() {
        cursorOutput.cancel();emit(engine.reset());_ = previewEngine.reset()
        engine.anchorCursor(normalizedCursor())
        status.stringValue="基準姿勢を再設定 • 指を離して、この位置で小さく手首を動かしてください"
    }
    @objc func configChanged() {
        configurationVersion += 1;stop(reason:"映像・操作する手の設定を変更");_ = previewEngine.reset();imageView.joints=[:];imageView.needsDisplay=true
        // Camera rotation invalidates the keyboard's coordinate system.
        if rotation.indexOfSelectedItem != keyboardRotation {resetKeyboard();keyboardRotation=rotation.indexOfSelectedItem}
    }
    @objc func toggle() {
        if enabled || isTestingPointer || pendingStart { stop(reason:"停止ボタンを押したため停止"); return }
        startControl()
    }
    func startControl() {
        pendingStart=true;button.title="開始待ちを解除"
        requestControlPermission()
        guard permissionState().canControlPointer else { showPermissionHelp(); return }
        guard Date().timeIntervalSince(lastFrame)<0.6 else { status.stringValue="映像を待っています。受信後に開始します"; return }
        pendingStart=false;cursorOutput.cancel();emit(engine.reset());engine.anchorCursor(normalizedCursor());enabled=true; button.title="操作停止"
        status.stringValue="操作開始 • 指を離して手を映してください"
    }
    func stop(reason: String = "操作を停止") {
        pendingStart=false;pointerTestGeneration += 1;isTestingPointer=false;enabled=false;lastStopReason=reason
        cursorOutput.cancel();emit(engine.reset());button.title="操作開始";activity.stringValue="操作オフ • \(reason)"
        status.stringValue="操作オフ • \(reason)"
    }
    @objc func connectDevice() {
        guard isThinkletSource else{changeVideoSource();return}
        guard connectionProcess == nil else{return}
        stop(reason:"USB接続を設定 • 接続後に「操作開始」を押してください")
        guard let script=Bundle.main.resourceURL?.appendingPathComponent("scripts/connect.sh"),FileManager.default.fileExists(atPath:script.path) else {
            connection.stringValue="接続用ファイルがありません。アプリを再ビルドしてください";return
        }
        let process=Process(), pipe=Pipe()
        process.executableURL=URL(fileURLWithPath:"/bin/bash");process.arguments=[script.path,"--prepare"]
        process.standardOutput=pipe;process.standardError=pipe
        connectionProcess=process;reconnect.isEnabled=false
        connection.stringValue="THINKLETへ接続しています…";connection.toolTip=nil
        do { try process.run() } catch {
            connectionProcess=nil;reconnect.isEnabled=true;connection.stringValue="接続処理を起動できません：\(error.localizedDescription)";return
        }
        DispatchQueue.global(qos:.utility).async { [weak self] in
            let data=pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let log=String(data:data,encoding:.utf8) ?? "接続に失敗しました"
            DispatchQueue.main.async {
                guard let self=self,self.alive else{return}
                guard self.connectionProcess === process else{return}
                self.connectionProcess=nil;self.reconnect.isEnabled=true;self.connection.toolTip=log
                if process.terminationStatus==0 { self.connection.stringValue="USB接続済み • 映像を確認して「操作開始」" }
                else {
                    let reason=log.split(separator:"\n").last.map(String.init) ?? "USBケーブルとデバッグ許可を確認してください"
                    self.connection.stringValue="接続失敗：\(reason.prefix(150))"
                }
            }
        }
    }
    func fetch() {
        guard alive,isThinkletSource else{return}
        let generation=sourceGeneration,previousFrameID=lastFrameID
        session.dataTask(with:URL(string:"http://127.0.0.1:18765/frame")!) { [weak self] data,response,error in
            guard let self=self else{return}
            let frameID=(response as? HTTPURLResponse)?.value(forHTTPHeaderField:"X-Frame-Id")
            self.queue.async {
                var raw: CGImage?
                if let data=data,(response as? HTTPURLResponse)?.statusCode==200,
                   let source=CGImageSourceCreateWithData(data as CFData,nil) {raw=CGImageSourceCreateImageAtIndex(source,0,nil)}
                DispatchQueue.main.async {
                    guard self.alive,self.isThinkletSource,generation==self.sourceGeneration else{return}
                    if let frameID=frameID,frameID==previousFrameID {self.nextUSBFrame(generation:generation);return}
                    self.processFrame(raw,frameID:frameID) {self.nextUSBFrame(generation:generation)}
                }
            }
        }.resume()
    }
    func nextUSBFrame(generation: Int) {
        DispatchQueue.main.asyncAfter(deadline:.now()+0.025) {
            if self.alive,self.isThinkletSource,self.sourceGeneration==generation {self.fetch()}
        }
    }
    func processFrame(_ raw: CGImage?,frameID: String? = nil,completion: @escaping ()->Void) {
        let mirrored=mirror.state == .on, turn=rotation.indexOfSelectedItem
        let selectedHand: VNChirality = controlHand.indexOfSelectedItem == 0 ? .right : .left
        let handName=controlHand.indexOfSelectedItem == 0 ? "右手" : "左手"
        let version=configurationVersion
        queue.async {
                var points: [VNHumanHandPoseObservation.JointName:VNRecognizedPoint]?
                var rendered: CGImage?
                var foundOtherHand=false
                var allFingertips=[CGPoint]()
                var detectedSides=""
                var aspect=1.0
                var visionError: String?
                if let raw=raw {
                    let ci=CIImage(cgImage:raw).oriented([CGImagePropertyOrientation.up,.right,.down,.left][turn])
                    aspect=ci.extent.width/ci.extent.height
                    let oriented=mirrored ? ci.transformed(by:CGAffineTransform(translationX:ci.extent.width,y:0).scaledBy(x:-1,y:1)) : ci
                    rendered=self.imageContext.createCGImage(oriented,from:oriented.extent)
                    // Classify anatomical handedness before applying the display mirror.
                    if let image=self.imageContext.createCGImage(ci,from:ci.extent) {
                        let request=VNDetectHumanHandPoseRequest(); request.maximumHandCount=2
                        do {try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])} catch {visionError=error.localizedDescription}
                        let observations=request.results ?? []
                        detectedSides=observations.map{$0.chirality == .right ? "右" : ($0.chirality == .left ? "左" : "不明")}.joined(separator:"・")
                        for hand in observations {
                            if let joints=try? hand.recognizedPoints(.all) {
                                for name: VNHumanHandPoseObservation.JointName in [.indexTip,.middleTip,.ringTip,.littleTip] {
                                    if let p=joints[name],p.confidence>0.45 {allFingertips.append(p.location)}
                                }
                            }
                        }
                        foundOtherHand = !observations.isEmpty
                        points=try? observations.first(where:{$0.chirality == selectedHand})?.recognizedPoints(.all)
                    }
                }
                let (sample, guidance)=self.sample(points,mirrored:mirrored,aspect:aspect)
                DispatchQueue.main.async {
                    defer {completion()}
                    guard self.alive,version==self.configurationVersion else{return}
                    if let cg=rendered {
                        self.lastFrame=Date();self.lastFrameID=frameID; self.imageView.frameImage=cg
                        self.imageView.joints=points ?? [:];self.imageView.mirrored=mirrored;self.imageView.needsDisplay=true
                        let count=points?.values.filter{$0.confidence>0.35}.count ?? 0
                        self.recognition.stringValue="\(handName)のみ • 関節 \(count) / 21 • \(self.enabled ? "マウス操作中" : "プレビューのみ")"
                        self.recognition.toolTip="検出した手：\(detectedSides.isEmpty ? "なし" : detectedSides)"
                    } else {
                        self.imageView.frameImage=nil; self.imageView.joints=[:];self.imageView.needsDisplay=true
                        self.recognition.stringValue="関節 0 / 21 • 未接続"
                    }
                    let now=ProcessInfo.processInfo.systemUptime
                    self.pollKeyboard()
                    let counter=CGEventSource.counterForEventType(.hidSystemState,eventType:.keyDown)
                    if counter != self.lastKeyboardCounter {
                        if CGEventSource.secondsSinceLastEventType(.hidSystemState,eventType:.keyDown)<0.35 {
                            self.keyboardGuard.learn(fingertips:allFingertips)
                        }
                        self.lastKeyboardCounter=counter
                    }
                    self.imageView.keyboardRegion=self.keyboardGuard.region
                    if self.keyboardGuard.region != nil && !self.imageView.selectingKeyboard {
                        self.keyboardStatus.stringValue="キーボード範囲：\(self.keyboardGuard.manual ? "手動" : "自動学習") • \(self.regionPause.state == .on ? "黄色枠内で停止" : "範囲停止オフ・キー入力では停止")"
                    } else if !self.imageView.selectingKeyboard {
                        self.keyboardStatus.stringValue="キーボード位置：未学習 • \(self.regionPause.state == .on ? "範囲停止オン" : "範囲停止オフ・キー入力では停止")"
                    }
                    let onKeyboard=self.regionPause.state == .on && self.keyboardGuard.shouldPause(fingertips:allFingertips,time:now)
                    let physicalMouse=self.mousePriority.isActive(time:now)
                    let typing=now<self.typingUntil || onKeyboard || self.imageView.selectingKeyboard || physicalMouse
                    let previewActions=self.previewEngine.update(sample,time:now,inputActive:typing)
                    if self.enabled && self.engine.needsPointerAnchor {self.engine.anchorCursor(self.normalizedCursor())}
                    let actions=self.enabled ? self.engine.update(sample,time:now,inputActive:typing) : previewActions
                    if self.enabled {
                        if self.engine.pointerFrozen {self.cursorOutput.cancel();self.engine.anchorCursor(self.normalizedCursor())}
                        self.emit(actions)
                    }
                    let activeEngine=self.enabled ? self.engine : self.previewEngine
                    if let error=visionError {self.gesture.stringValue="手認識エラー：\(error)"}
                    else if rendered == nil { self.gesture.stringValue="映像が届いていません • 再接続してください" }
                    else if self.imageView.selectingKeyboard {self.gesture.stringValue="映像内のキーボードを指定してください"}
                    else if physicalMouse {self.gesture.stringValue="物理マウス優先 • 手の操作を一時停止"}
                    else if onKeyboard {self.gesture.stringValue="キーボード上に指を検出 • 操作を一時停止"}
                    else if typing { self.gesture.stringValue="キーボード入力中 • 操作を一時停止" }
                    else if points == nil && foundOtherHand { self.gesture.stringValue="検出：\(detectedSides)手 • \(handName)を映してください" }
                    else if sample == nil { self.gesture.stringValue=guidance }
                    else if actions.contains(.click) { self.gesture.stringValue="左クリック ✓";self.gestureFeedbackUntil=now+0.5 }
                    else if actions.contains(.rightClick) { self.gesture.stringValue="右クリック ✓";self.gestureFeedbackUntil=now+0.5 }
                    else if now>=self.gestureFeedbackUntil { self.gesture.stringValue=activeEngine.gestureDescription }
                    if self.enabled {self.status.stringValue="操作中 • \(self.gesture.stringValue)"}
                }
        }
    }
    func sample(_ p:[VNHumanHandPoseObservation.JointName:VNRecognizedPoint]?, mirrored: Bool, aspect: Double) -> (HandSample?, String) {
        guard let p=p else{return (nil,"手をカメラに映してください")}
        func point(_ key:VNHumanHandPoseObservation.JointName)->CGPoint? { guard let v=p[key],v.confidence>0.35 else{return nil};return HandProjection.imagePoint(v.location,aspect:aspect) }
        guard let index=point(.indexTip),let thumb=point(.thumbTip),let wrist=point(.wrist),let base=point(.middleMCP),let ib=point(.indexMCP) else{return (nil,"指が隠れています • 手を少し回して映してください")}
        let little=point(.littleMCP)
        if let little=little,!HandProjection.isUsable(wrist:wrist,middle:base,index:ib,little:little) {
            return (nil,"手が横向きです • 手のひら／手の甲をカメラへ向けてください")
        }
        func d(_ a:CGPoint,_ b:CGPoint)->Double { hypot(a.x-b.x,a.y-b.y) }
        let scale=max(d(wrist,base),little.map{d(ib,$0)*0.75} ?? 0)
        guard scale>0.035 else{return (nil,"手が小さすぎます • カメラに近づけてください")}
        // A hidden middle finger need not disable index movement or left dragging.
        let rightPinch=point(.middleTip).map{d(thumb,$0)/scale}
        let palmX=mirrored ? 1-wrist.x/aspect : wrist.x/aspect
        let width=little.map{d(ib,$0)} ?? d(wrist,base)*0.65
        let pointing=HandProjection.wristDirection(wrist:wrist,point:index,palmWidth:width,palmLength:d(wrist,base),mirrored:mirrored,gain:0.35)
        // Use the same required knuckles every frame, avoiding membership-change jitter.
        let center=CGPoint(x:(ib.x+base.x)/2,y:(ib.y+base.y)/2)
        let palmDirection=HandProjection.wristDirection(wrist:wrist,point:center,palmWidth:width,palmLength:d(wrist,base),mirrored:mirrored,gain:0.5)
        return (HandSample(x:mirrored ? 1-index.x/aspect : index.x/aspect,y:1-index.y,pinch:d(thumb,index)/scale,rightPinch:rightPinch,scrollPosition:palmX,palmX:palmX,palmY:1-wrist.y,wristX:pointing.map{Double($0.x)},wristY:pointing.map{Double($0.y)},wristPalmX:palmDirection.map{Double($0.x)},wristPalmY:palmDirection.map{Double($0.y)}),"")
    }
    func emit(_ actions:[MouseAction]) {
        for action in actions {
            lastOutput="\(action) • \(Date())"
            let pos=CGEvent(source:nil)?.location ?? .zero
            switch action {
            case let .move(x,y):
                let bounds=CGDisplayBounds(CGMainDisplayID()); let target=CGPoint(x:bounds.minX+x*bounds.width,y:bounds.minY+y*bounds.height)
                cursorOutput.setTarget(target,actual:pos,time:ProcessInfo.processInfo.systemUptime)
            case .down: cursorOutput.cancel();held=true;mouse(.leftMouseDown,pos)
            case .up:
                held=false
                if !mousePriority.buttons.contains(0) {mouse(.leftMouseUp,pos)}
            case .click:
                let now=ProcessInfo.processInfo.systemUptime
                clickCount = now-lastClick < NSEvent.doubleClickInterval ? min(3,clickCount+1) : 1
                lastClick=now
                for type in [CGEventType.leftMouseDown,.leftMouseUp] {
                    let event=CGEvent(mouseEventSource:nil,mouseType:type,mouseCursorPosition:pos,mouseButton:.left)
                    event?.setIntegerValueField(.mouseEventClickState,value:Int64(clickCount))
                    post(event)
                }
            case .rightClick: mouse(.rightMouseDown,pos); mouse(.rightMouseUp,pos)
            case let .scroll(n): post(CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:Int32(n),wheel2:0,wheel3:0))
            }
        }
    }
    func mouse(_ type:CGEventType,_ p:CGPoint) { post(CGEvent(mouseEventSource:nil,mouseType:type,mouseCursorPosition:p,mouseButton:type == .rightMouseDown || type == .rightMouseUp ? .right : .left)) }
    func windowWillClose(_ n:Notification) { NSApp.terminate(nil) }
    func applicationWillTerminate(_ n:Notification) { alive=false;stop();macCamera.stop();outputTimer?.invalidate();for observer in deviceObservers {NotificationCenter.default.removeObserver(observer)};if let process=connectionProcess,process.isRunning{process.terminate()};session.invalidateAndCancel();for monitor in [localMonitor,globalMonitor,localMouseMonitor,globalMouseMonitor] {if let monitor=monitor{NSEvent.removeMonitor(monitor)}} }
}
let app=NSApplication.shared
let delegate=App(); app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
