import Foundation
import CoreGraphics
/// Queue-owned lease: old camera callbacks cannot unlock a new source's frame.
struct FrameLease {
    private(set) var generation=0
    private var busy=false
    mutating func reset(to generation: Int) {self.generation=generation;busy=false}
    mutating func claim(generation: Int) -> Bool {
        guard generation==self.generation,!busy else{return false}
        busy=true;return true
    }
    mutating func finish(generation: Int) {if generation==self.generation {busy=false}}
}
struct PermissionState {
    let accessibility: Bool
    let postEvents: Bool
    let listenEvents: Bool
    // AX trust and event-post authorization are separate capability checks.
    // The OS remains responsible for authorizing every posted event.
    var canControlPointer: Bool { accessibility || postEvents }
    var summary: String { "AX=\(accessibility ? "許可" : "未許可") / Post=\(postEvents ? "許可" : "未許可") / Listen=\(listenEvents ? "許可" : "未許可")" }
}
struct HandSample {
    var x: Double; var y: Double
    var pinch: Double; var rightPinch: Double?
    var scrollPosition: Double? = nil
    var palmX: Double? = nil
    var palmY: Double? = nil
    var wristX: Double? = nil
    var wristY: Double? = nil
    var wristPalmX: Double? = nil
    var wristPalmY: Double? = nil
}
enum MouseAction: Equatable { case move(Double, Double), down, up, click, rightClick, scroll(Int) }
enum PointerSafety {
    static func externalCorner(position: CGPoint, commanded: CGPoint?) -> Bool {
        guard position.x<3,position.y<3 else{return false}
        guard let commanded=commanded else{return true}
        return hypot(commanded.x-position.x,commanded.y-position.y)>5
    }
}
enum MouseEventOrigin {
    static let ownTag: Int64 = 0x54484D4F555345
    static func isOwn(tag: Int64, pid: Int64, processID: Int64) -> Bool {
        tag == ownTag || pid == processID
    }
}
struct MousePriority {
    private(set) var until = 0.0
    private(set) var buttons = Set<Int>()
    mutating func activity(time: Double, button: Int? = nil, pressed: Bool? = nil) {
        until=time+1.5
        if let button=button,let pressed=pressed {
            if pressed {buttons.insert(button)} else {buttons.remove(button)}
        }
    }
    func isActive(time: Double) -> Bool { !buttons.isEmpty || time<until }
}

/// Interpolate camera targets at display cadence; never extrapolate stale frames.
struct CursorInterpolator {
    private var current: CGPoint?, target: CGPoint?
    private var lastTick: Double?, received=0.0
    mutating func cancel() {current=nil;target=nil;lastTick=nil}
    mutating func setTarget(_ point: CGPoint, actual: CGPoint, time: Double) {
        if current == nil {current=actual;lastTick=time}
        target=point;received=time
    }
    mutating func tick(time: Double) -> CGPoint? {
        guard let position=current,let target=target,let previous=lastTick else{return nil}
        guard time-received<0.22 else{cancel();return nil}
        let dt=max(0,min(0.05,time-previous));lastTick=time
        let distance=hypot(target.x-position.x,target.y-position.y)
        guard distance>0.08 else{current=target;return nil}
        let alpha=1-exp(-dt/0.045)
        let next=CGPoint(x:position.x+(target.x-position.x)*alpha,y:position.y+(target.y-position.y)*alpha)
        current=next;return next
    }
}
/// Camera-space keyboard region, learned only at real keystrokes or set manually.
final class KeyboardGuard {
    private(set) var region: CGRect?
    private var learned: CGRect?, samples=0
    private(set) var manual=false
    private var clearSince: Double?
    private var occupied=false
    func clear() { region=nil;learned=nil;samples=0;manual=false;clearSince=nil;occupied=false }
    func setRegion(_ rect: CGRect) {
        let clipped=rect.standardized.intersection(CGRect(x:0,y:0,width:1,height:1))
        guard !clipped.isNull,clipped.width>=0.02,clipped.height>=0.02 else{return}
        region=clipped;manual=true;clearSince=nil
    }
    func learn(fingertips: [CGPoint]) {
        guard !manual,fingertips.count>=2 else{return}
        let xs=fingertips.map{$0.x},ys=fingertips.map{$0.y}
        let box=CGRect(x:xs.min()!,y:ys.min()!,width:xs.max()!-xs.min()!,height:ys.max()!-ys.min()!).insetBy(dx:-0.045,dy:-0.045)
        learned=learned.map{$0.union(box)} ?? box;samples += 1
        if samples>=3 { region=learned?.intersection(CGRect(x:0,y:0,width:1,height:1)) }
    }
    func shouldPause(fingertips: [CGPoint], time: Double) -> Bool {
        guard let region=region else{return false}
        // Pause immediately; require 0.4 seconds outside before rearming.
        if fingertips.contains(where:{region.contains($0)}) { occupied=true;clearSince=nil;return true }
        guard occupied else{return false}
        guard !fingertips.isEmpty else{clearSince=nil;return true}
        if clearSince == nil { clearSince=time }
        if time-clearSince!<0.4 { return true }
        occupied=false;clearSince=nil;return false
    }
}

/// Time-based smoothing: steady hands get more filtering, fast motion less lag.
struct PointerFilter {
    private var position: CGPoint?, lastTime: Double?
    mutating func reset() { position=nil;lastTime=nil }
    mutating func update(x: Double,y: Double,time: Double) -> CGPoint {
        let target=CGPoint(x:x,y:y)
        guard let old=position,let previous=lastTime else{position=target;lastTime=time;return target}
        let dt=max(0.001,min(0.2,time-previous))
        let distance=hypot(target.x-old.x,target.y-old.y)
        let speed=distance/dt
        let alpha=1-exp(-2 * Double.pi * (1.4+min(speed,4)*4) * dt)
        let next=distance<0.0015 ? old : CGPoint(x:old.x+(x-old.x)*alpha,y:old.y+(y-old.y)*alpha)
        position=next;lastTime=time;return next
    }
}
/// Relative motion preserves the real mouse position when hand control resumes.
struct RelativePointer {
    private(set) var cursor=CGPoint(x:0.5,y:0.5)
    private var last: CGPoint?, lastTime: Double?, speed=0.0
    private var filter=PointerFilter()
    mutating func anchor(_ point: CGPoint) {
        cursor=CGPoint(x:max(0,min(1,point.x)),y:max(0,min(1,point.y)));rebase()
    }
    mutating func rebase() {last=nil;lastTime=nil;speed=0;filter.reset()}
    static func gain(speed: Double, sensitivity: Double, acceleration: Double) -> Double {
        let t=max(0,min(1,(speed-0.04)/0.36))
        let response=t*t*(3-2*t)
        return max(0.4,min(2.5,sensitivity))*(1+max(0,min(3,acceleration))*4*response)
    }
    mutating func update(x: Double,y: Double,time: Double,sensitivity: Double,acceleration: Double = 1.5) -> CGPoint {
        let p=filter.update(x:x,y:y,time:time)
        defer {last=p;lastTime=time}
        guard let old=last,let previous=lastTime else{return cursor}
        let dt=max(0.01,min(0.2,time-previous)),dx=p.x-old.x,dy=p.y-old.y
        let velocity=hypot(dx,dy)/dt
        // Build acceleration gradually, but shed it immediately when slowing to aim.
        // Otherwise the previous flick amplifies the following fine corrections.
        speed = velocity < speed ? velocity : speed+(velocity-speed)*(1-exp(-dt/0.08))
        let gain=Self.gain(speed:speed,sensitivity:sensitivity,acceleration:acceleration)
        cursor=CGPoint(x:max(0,min(1,cursor.x+dx*gain)),y:max(0,min(1,cursor.y+dy*gain)))
        return cursor
    }
}
/// Reject edge-on palms: projected fingertip proximity is not proof of a pinch.
enum HandProjection {
    /// Hand-relative direction, invariant to camera translation and uniform distance changes.
    static func wristDirection(wrist: CGPoint, point: CGPoint, palmWidth: Double, palmLength: Double, mirrored: Bool, gain: Double) -> CGPoint? {
        // Projected palm width changes with wrist roll and when the little MCP
        // disappears. Dividing a long wrist-tip vector by that width converts
        // those recognition changes into large, accelerated cursor movements.
        // The always-required wrist/middle MCP pair gives a consistent reference.
        let scale=palmLength*1.2
        guard scale>0.025 else{return nil}
        return CGPoint(x:(point.x-wrist.x)/scale*gain*(mirrored ? -1 : 1),y:(wrist.y-point.y)/scale*gain)
    }
    static func imagePoint(_ normalized: CGPoint, aspect: Double) -> CGPoint {
        CGPoint(x:normalized.x*aspect,y:normalized.y)
    }
    static func isUsable(wrist: CGPoint, middle: CGPoint, index: CGPoint, little: CGPoint) -> Bool {
        func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x-b.x,a.y-b.y) }
        let length=max(distance(wrist,middle),max(distance(wrist,index),distance(wrist,little)))
        return length>0.035 && distance(index,little)>length*0.28
    }
}
/// Pure state machine, with hysteresis and loss cancellation. Coordinates normalized.
final class GestureEngine {
    var pointerSpeed=1.0, scrollSpeed=1.0, pointerAcceleration=1.5
    var wristControl=true
    private var pinching = false, right = false, dragging = false
    private var since = 0.0, middleSince = 0.0
    private var middleOrigin = 0.0, lastScroll = 0.0
    private var scrolling=false, middleBlocked=false
    private var scrollRemainder = 0.0
    private var motion=RelativePointer()
    private var pinchOrigin=CGPoint.zero, freezeUntil=0.0
    private var previousPinch: Double?
    private(set) var pointerFrozen=true
    private(set) var needsPointerAnchor=true
    func anchorCursor(_ point: CGPoint) {motion.anchor(point);needsPointerAnchor=false}
    private var frames = 0, blocked = false
    var gestureDescription: String {
        if blocked || frames < 3 { return "親指を指先から離して待機" }
        if dragging { return "ドラッグ中" }
        if pinching { return wristControl ? "離すとクリック • 保持して手首を振るとドラッグ" : "離すとクリック • 0.45秒以上保持＋手を動かすとドラッグ" }
        if scrolling { return "スクロール中 • 右へ動かすと下／左へ動かすと上" }
        if right { return "中指ピンチ • 短く離すと右クリック／左右移動でスクロール" }
        if pointerFrozen {return "クリック準備 • 位置を固定"}
        return wristControl ? "手首を少し振って移動" : "ポインター移動"
    }
    func reset() -> [MouseAction] {
        let actions: [MouseAction] = dragging ? [.up] : []
        pinching=false; right=false; dragging=false; scrolling=false; middleBlocked=true; scrollRemainder=0; motion.rebase(); frames=0; blocked=true;pointerFrozen=true;needsPointerAnchor=true;freezeUntil=0;previousPinch=nil
        return actions
    }
    func update(_ s: HandSample?, time: Double, inputActive: Bool = false) -> [MouseAction] {
        if inputActive { return reset() }
        guard let s = s else { return reset() }
        if right && s.rightPinch == nil {return reset()}
        defer {previousPinch=s.pinch}
        frames += 1
        let middleDistance=s.rightPinch ?? Double.infinity
        if s.rightPinch == nil {
            // Loss of the middle fingertip cancels a pending right click.
            right=false;scrolling=false;middleBlocked=true;scrollRemainder=0
        } else if middleDistance>0.5 { middleBlocked=false }
        // Following a pause/loss, require an open pinch before any click.
        if blocked { if s.pinch > 0.5 && middleDistance > 0.5 { blocked=false }; return [] }
        guard frames >= 3 else { return [] }
        var result: [MouseAction] = []
        // Keep the active pinch in charge until it is released.
        let newPinch = !right && s.pinch < (pinching ? 0.5 : 0.30)
        let newRight = !pinching && !newPinch && !middleBlocked && middleDistance < (right ? 0.5 : 0.27)
        let pointer=CGPoint(x:wristControl ? (s.wristX ?? s.x) : s.x,y:wristControl ? (s.wristY ?? s.y) : s.y)
        let palm=CGPoint(x:wristControl ? (s.wristPalmX ?? s.palmX ?? s.x) : (s.palmX ?? s.x),y:wristControl ? (s.wristPalmY ?? s.palmY ?? s.y) : (s.palmY ?? s.y))
        if newPinch && !pinching {since=time;pinchOrigin=palm}
        // Holding a click is not a drag. Require both time and deliberate palm travel.
        if newPinch && time-since >= 0.45 && hypot(palm.x-pinchOrigin.x,palm.y-pinchOrigin.y)>=0.025 && !dragging {
            dragging=true;freezeUntil=time;motion.rebase();result.append(.down)
        }
        let releasedLeft = !newPinch && pinching
        if !newPinch && pinching {
            if dragging { result.append(.up) } else if time-since >= 0.06 { result.append(.click) }
            dragging=false
            freezeUntil=time+0.12
        }
        let horizontal=wristControl ? (s.wristPalmX ?? s.scrollPosition ?? s.x) : (s.scrollPosition ?? s.x)
        if newRight && !right {
            middleSince=time;middleOrigin=horizontal;lastScroll=horizontal;scrolling=false;scrollRemainder=0
        }
        if newRight {
            // A moving pinch becomes scrolling and can never also right-click.
            if !scrolling && abs(horizontal-middleOrigin)>=0.018 { scrolling=true }
            if scrolling {
                // Quartz positive wheel values scroll upward; rightward motion goes down.
                scrollRemainder -= (horizontal-lastScroll)*900*max(0.25,min(3,scrollSpeed));lastScroll=horizontal
                let pixels=Int(scrollRemainder.rounded())
                if pixels != 0 {result.append(.scroll(pixels));scrollRemainder -= Double(pixels)}
            }
        }
        if !newRight && right {
            if !scrolling && (0.06...0.35).contains(time-middleSince) {result.append(.rightClick)}
            scrolling=false;scrollRemainder=0
            freezeUntil=time+0.12
        }
        let releasedMiddle = right && !newRight
        right=newRight; pinching=newPinch
        // Freeze before fingertips touch, and briefly after release, to avoid click drift.
        if !dragging && !newRight && s.pinch<0.75,let old=previousPinch,old-s.pinch>=0.025 {freezeUntil=max(freezeUntil,time+0.12)}
        pointerFrozen=newRight || releasedMiddle || releasedLeft || (newPinch && !dragging) || time<freezeUntil
        if pointerFrozen {motion.rebase()}
        else {
            let input=dragging ? palm : pointer
            let p=motion.update(x:input.x,y:input.y,time:time,sensitivity:pointerSpeed,acceleration:pointerAcceleration)
            result.append(.move(p.x,p.y))
        }
        return result
    }
}
