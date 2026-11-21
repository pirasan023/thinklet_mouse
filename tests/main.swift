import Foundation
import CoreGraphics
var checks=0
func check(_ condition:Bool,_ name:String) { checks += 1; if !condition { fatalError(name) } }
func hand(_ pinch:Double=1,_ right:Double?=1,_ x:Double=0.5)->HandSample { HandSample(x:x,y:0.5,pinch:pinch,rightPinch:right) }
func ready()->GestureEngine { let e=GestureEngine(); for i in 0..<3 { _=e.update(hand(),time:Double(i)*0.1) };return e }
let click=ready()
_=click.update(hand(0.2),time:1)
check(click.update(hand(),time:1.12).contains(.click),"Short pinch clicks")
let drag=ready()
_=drag.update(hand(0.2),time:1)
check(drag.update(hand(0.2,1,0.6),time:1.6).contains(.down),"Hold plus deliberate palm travel begins drag")
check(drag.update(hand(),time:1.7).contains(.up),"Release ends drag")
let loss=ready()
_=loss.update(hand(0.2),time:1);_=loss.update(hand(0.2,1,0.6),time:1.6)
check(loss.update(nil,time:1.7)==[.up],"Loss releases held button")
check(loss.update(hand(0.2),time:2).isEmpty,"Loss cannot start accidental drag")
let right=ready()
check(!right.update(hand(1,0.2),time:1).contains(.rightClick),"Middle pinch waits for release before right clicking")
check(right.update(hand(),time:1.12).contains(.rightClick),"Short middle pinch right clicks on release")
let scroll=ready()
_=scroll.update(hand(1,0.2,0.5),time:1)
check(scroll.update(hand(1,0.2,0.6),time:1.1).contains(.scroll(-90)),"Rightward middle pinch scrolls down")
let jitter=ready()
_=jitter.update(hand(0.2),time:1)
check(!jitter.update(hand(0.4),time:1.12).contains(.click),"Pinch hysteresis")
check(jitter.update(hand(),time:1.2).contains(.click),"Hysteresis release")
let cancel=ready()
_=cancel.update(hand(0.2),time:1)
check(!cancel.reset().contains(.click),"Pause cancels pending click")
let typing=ready()
_=typing.update(hand(0.2),time:1);_=typing.update(hand(0.2,1,0.6),time:1.6)
check(typing.update(hand(0.2),time:1.7,inputActive:true)==[.up],"Typing immediately releases drag")
check(typing.update(hand(),time:1.8,inputActive:true).isEmpty,"Typing blocks movement even with open hand")
check(typing.update(hand(0.2),time:3).isEmpty,"Held pinch cannot resume after typing")
_=typing.update(hand(),time:3.1);_=typing.update(hand(),time:3.2)
check(typing.update(hand(),time:3.3).contains{if case .move = $0{return true};return false},"Open hand resumes after typing")
let pending=ready();_=pending.update(hand(0.2),time:1)
check(!pending.update(hand(),time:1.15,inputActive:true).contains(.click),"Typing cancels pending click")
check(HandProjection.isUsable(wrist:CGPoint(x:0.5,y:0.2),middle:CGPoint(x:0.5,y:0.5),index:CGPoint(x:0.35,y:0.5),little:CGPoint(x:0.65,y:0.5)),"Visible palm accepted")
check(!HandProjection.isUsable(wrist:CGPoint(x:0.5,y:0.2),middle:CGPoint(x:0.5,y:0.5),index:CGPoint(x:0.49,y:0.5),little:CGPoint(x:0.51,y:0.5)),"Edge-on overlapping palm rejected")
let overlap=ready();_=overlap.update(hand(0.2),time:1);_=overlap.update(hand(0.2,1,0.6),time:1.6)
check(overlap.update(nil,time:1.7)==[.up],"Rejected view releases drag")
let keyboard=KeyboardGuard()
let tips=[CGPoint(x:0.3,y:0.3),CGPoint(x:0.6,y:0.4)]
keyboard.learn(fingertips:tips)
check(keyboard.region == nil,"One keystroke cannot establish keyboard region")
keyboard.learn(fingertips:tips);keyboard.learn(fingertips:tips)
check(keyboard.region != nil,"Keyboard learns after three observed keystrokes")
check(keyboard.shouldPause(fingertips:[CGPoint(x:0.4,y:0.35)],time:1),"Resting finger pauses without a key event")
check(keyboard.shouldPause(fingertips:[],time:1.1),"Invisible hand cannot clear occupied keyboard")
let away=[CGPoint(x:0.8,y:0.8)]
check(keyboard.shouldPause(fingertips:away,time:1.2),"Leaving keyboard starts debounce")
check(!keyboard.shouldPause(fingertips:away,time:1.7),"Lifting hand clears after stable interval")
keyboard.setRegion(CGRect(x:0.7,y:0.7,width:0.2,height:0.2))
keyboard.learn(fingertips:tips)
check(keyboard.manual && keyboard.region!.minX==0.7,"Manual region overrides automatic learning")
keyboard.clear()
check(keyboard.region == nil && !keyboard.shouldPause(fingertips:tips,time:2),"Reset removes keyboard inhibition")
let resting=ready();_=resting.update(hand(0.2),time:1);_=resting.update(hand(0.2,1,0.6),time:1.6)
check(resting.update(hand(),time:1.7,inputActive:true)==[.up],"Keyboard overlap releases drag instead of clicking")
let pixelX=HandProjection.imagePoint(CGPoint(x:0.1,y:0),aspect:4.0/3.0)
let pixelY=HandProjection.imagePoint(CGPoint(x:0,y:0.1*4.0/3.0),aspect:4.0/3.0)
check(abs(hypot(pixelX.x,pixelX.y)-hypot(pixelY.x,pixelY.y))<0.000001,"Equal pixel distances stay equal at non-square aspect")
var filter=PointerFilter()
_=filter.update(x:0.5,y:0.5,time:1)
check(filter.update(x:0.5005,y:0.5005,time:1.067)==CGPoint(x:0.5,y:0.5),"Small stationary jitter is suppressed")
let fast=filter.update(x:0.8,y:0.5,time:1.134)
check(fast.x>0.7 && fast.x<0.8,"Fast motion follows promptly without overshooting")
filter.reset()
check(filter.update(x:0.2,y:0.3,time:3)==CGPoint(x:0.2,y:0.3),"Tracking reset discards old cursor position")
check(!PointerSafety.externalCorner(position:.zero,commanded:.zero),"App reaching corner must not stop itself")
check(PointerSafety.externalCorner(position:.zero,commanded:CGPoint(x:500,y:500)),"Physical movement to corner still stops")
check(!PointerSafety.externalCorner(position:CGPoint(x:200,y:100),commanded:nil),"Regular external mouse movement does not stop")
let boundsBeforeInvalid=keyboard.region
keyboard.setRegion(CGRect(x:0.2,y:0.2,width:0,height:0))
check(keyboard.region==boundsBeforeInvalid,"Accidental single-point calibration is ignored")
check(scroll.update(hand(1,0.2,0.5),time:1.2).contains(.scroll(90)),"Leftward middle pinch scrolls up")
check(!scroll.update(hand(),time:1.3).contains(.rightClick),"Scrolling release must not right-click")
let noise=ready();_=noise.update(hand(1,0.2),time:1)
check(noise.update(hand(1,0.2,0.505),time:1.06).isEmpty,"Middle pinch jitter does not scroll or move pointer")
check(noise.update(hand(1,1,0.505),time:1.12)==[.rightClick],"Small jitter still permits deliberate right-click")
check(!noise.update(hand(),time:1.15).contains(.rightClick),"Right-click fires only once")
let longMiddle=ready();_=longMiddle.update(hand(1,0.2),time:1)
check(!longMiddle.update(hand(),time:2).contains(.rightClick),"Long stationary middle pinch does not right-click")
let middleLoss=ready();_=middleLoss.update(hand(1,0.2),time:1)
check(!middleLoss.update(hand(1,nil),time:1.12).contains(.rightClick),"Occluded middle finger cannot produce a right-click")
check(middleLoss.update(hand(1,0.2),time:1.2).isEmpty,"Occluded middle pinch must rearm before scrolling")
let middlePause=ready();_=middlePause.update(hand(1,0.2),time:1)
check(!middlePause.update(hand(),time:1.12,inputActive:true).contains(.rightClick),"Typing cancels pending middle click")
let scrollPause=ready();_=scrollPause.update(hand(1,0.2),time:1);_=scrollPause.update(hand(1,0.2,0.6),time:1.1)
check(scrollPause.update(hand(1,0.2,0.7),time:1.2,inputActive:true).isEmpty,"Typing stops middle-pinched scroll")
let arbitration=ready();_=arbitration.update(hand(1,0.2),time:1)
check(!arbitration.update(hand(0.2,0.2,0.6),time:1.3).contains(.down),"Middle scroll cannot turn into left drag")
let leftArbitration=ready();_=leftArbitration.update(hand(0.2,0.2),time:1)
check(leftArbitration.update(hand(0.2,0.2,0.6),time:1.6).contains(.down),"Index pinch wins when both pinches first close together")
let fasterScroll=ready();fasterScroll.scrollSpeed=2
_=fasterScroll.update(hand(1,0.2),time:1)
check(fasterScroll.update(hand(1,0.2,0.6),time:1.1).contains(.scroll(-180)),"Scroll speed doubles emitted distance")
func firstMove(_ speed:Double) -> Double {
    let e=ready();e.pointerSpeed=speed
    let actions=e.update(hand(1,1,0.52),time:0.3)
    for a in actions {if case let .move(x,_) = a {return x}}
    fatalError("Expected movement")
}
check(firstMove(2)>firstMove(1),"Higher pointer speed increases cursor travel")
check(firstMove(0.5)<firstMove(1),"Lower pointer speed reduces cursor travel")
let wristScroll=ready()
var fingerMotion=hand(1,0.2);fingerMotion.scrollPosition=0.5
_=wristScroll.update(fingerMotion,time:1)
fingerMotion.x=0.8
check(wristScroll.update(fingerMotion,time:1.1).isEmpty,"Index motion alone cannot scroll when wrist is stationary")
fingerMotion.y=0.9
check(wristScroll.update(fingerMotion,time:1.2).isEmpty,"Vertical hand motion does not cause horizontal-pinch scrolling")
check(PermissionState(accessibility:true,postEvents:false,listenEvents:false).canControlPointer,"AX permission alone must not be rejected by second preflight")
check(PermissionState(accessibility:false,postEvents:true,listenEvents:false).canControlPointer,"Post permission alone enables pointer output")
check(PermissionState(accessibility:true,postEvents:true,listenEvents:false).canControlPointer,"Both control grants enable output")
check(!PermissionState(accessibility:false,postEvents:false,listenEvents:true).canControlPointer,"Input monitoring alone is not pointer authorization")
check(!PermissionState(accessibility:false,postEvents:false,listenEvents:false).canControlPointer,"No permissions still blocks pointer output")
let slowClick=ready()
_=slowClick.update(hand(0.2),time:1)
check(!slowClick.update(hand(0.2),time:1.8).contains(.down),"Stationary long pinch is not a drag")
check(slowClick.update(hand(),time:1.9).contains(.click),"Slow stationary click still clicks on release")
let quickTravel=ready();_=quickTravel.update(hand(0.2),time:1)
check(!quickTravel.update(hand(0.2,1,0.7),time:1.2).contains(.down),"Quick click movement cannot initiate a drag")
let palmStable=ready()
var pose=hand(0.2);pose.palmX=0.5;pose.palmY=0.5
_=palmStable.update(pose,time:1);pose.x=0.8
check(!palmStable.update(pose,time:1.8).contains(.down),"Finger folding without palm movement is not a drag")
let closePreparation=ready()
_=closePreparation.update(hand(0.6,1,0.55),time:1)
check(closePreparation.pointerFrozen,"Closing approach freezes the pointer before contact")
check(!closePreparation.update(hand(0.6),time:1.3).isEmpty,"Neutral partially open pinch does not freeze forever")
_=closePreparation.update(hand(0.2,1,0.6),time:1.4)
check(closePreparation.pointerFrozen,"Closed click keeps the cursor frozen")
_=closePreparation.update(hand(),time:1.55)
check(closePreparation.pointerFrozen,"Click release is also frozen")
let resumed=ready();resumed.anchorCursor(CGPoint(x:0.8,y:0.3))
let resumedActions=resumed.update(hand(1,1,0.1),time:1)
check(resumedActions.contains(.move(0.8,0.3)),"Reacquisition stays at physical mouse location")
let anchoredAfterClick=ready()
_=anchoredAfterClick.update(hand(0.2),time:1)
anchoredAfterClick.anchorCursor(CGPoint(x:0.7,y:0.6))
_=anchoredAfterClick.update(hand(1,1,0.8),time:1.1)
let afterFreeze=anchoredAfterClick.update(hand(1,1,0.8),time:1.3)
check(afterFreeze.contains(.move(0.7,0.6)),"Release does not snap to the finger's new absolute location")
var manual=MousePriority()
manual.activity(time:1)
check(manual.isActive(time:1.1),"Physical mouse movement immediately has priority")
check(!manual.isActive(time:2.6),"Hand control can resume after mouse idle interval")
manual.activity(time:3,button:0,pressed:true)
check(manual.isActive(time:20),"Physical mouse drag retains priority even when stationary")
check(manual.buttons.contains(0),"Physical left button remains owned by real mouse")
manual.activity(time:20,button:0,pressed:false)
check(!manual.isActive(time:21.6),"Physical release eventually gives hand control back")
check(MouseEventOrigin.isOwn(tag:MouseEventOrigin.ownTag,pid:0,processID:123),"Tagged cursor interpolation is not physical input")
check(MouseEventOrigin.isOwn(tag:0,pid:123,processID:123),"Own event PID is also recognized")
check(!MouseEventOrigin.isOwn(tag:0,pid:0,processID:123),"Untagged hardware event takes priority")
var interpolation=CursorInterpolator()
interpolation.setTarget(CGPoint(x:100,y:50),actual:.zero,time:1)
let interpolated1=interpolation.tick(time:1+1.0/60.0)!
let interpolated2=interpolation.tick(time:1+2.0/60.0)!
check(interpolated1.x>0 && interpolated1.x<100,"Display ticks interpolate instead of teleporting")
check(interpolated2.x>interpolated1.x && interpolated2.x<100,"Interpolated movement is monotonic without overshoot")
interpolation.cancel()
check(interpolation.tick(time:1.06)==nil,"Click or physical input cancels pending interpolation immediately")
interpolation.setTarget(CGPoint(x:200,y:100),actual:CGPoint(x:150,y:100),time:2)
check(interpolation.tick(time:2.3)==nil,"Old camera target cannot keep moving after a stall")
var acceleratedSlow=RelativePointer(),acceleratedFast=RelativePointer()
var slowPoint=CGPoint.zero,fastPoint=CGPoint.zero
for i in 0...10 {
    let x=0.5+Double(i)*0.006
    slowPoint=acceleratedSlow.update(x:x,y:0.5,time:Double(i)*0.2,sensitivity:1)
    fastPoint=acceleratedFast.update(x:x,y:0.5,time:Double(i)*0.02,sensitivity:1)
}
check(fastPoint.x>slowPoint.x,"Faster hand motion gains more cursor travel for the same displacement")
var stationary=RelativePointer();stationary.anchor(CGPoint(x:0.6,y:0.4))
_=stationary.update(x:0.5,y:0.5,time:1,sensitivity:1)
check(stationary.update(x:0.5005,y:0.5005,time:1.06,sensitivity:1)==CGPoint(x:0.6,y:0.4),"Tiny camera jitter does not accumulate relative drift")
let fineGain=RelativePointer.gain(speed:0.02,sensitivity:1,acceleration:1.5)
let mediumGain=RelativePointer.gain(speed:0.2,sensitivity:1,acceleration:1.5)
let flickGain=RelativePointer.gain(speed:0.4,sensitivity:1,acceleration:1.5)
check(fineGain==1,"Fine motion retains baseline sensitivity")
check(flickGain/fineGain>=6,"Quick flick gains enough travel to cross the screen")
check(mediumGain>fineGain && mediumGain<flickGain,"Acceleration increases progressively at everyday speeds")
check(RelativePointer.gain(speed:0.4,sensitivity:1,acceleration:0)==fineGain,"Acceleration can be disabled independently of speed")
check(RelativePointer.gain(speed:0.02,sensitivity:1,acceleration:3)==fineGain,"Stronger acceleration does not spoil fine pointing")
check(RelativePointer.gain(speed:0.4,sensitivity:1,acceleration:3)>flickGain,"Acceleration slider increases flick response")
check(abs(RelativePointer.gain(speed:0.2,sensitivity:2,acceleration:1.5)-mediumGain*2)<0.000001,"Baseline sensitivity remains independent from acceleration")
check(RelativePointer.gain(speed:100,sensitivity:1,acceleration:1.5)==flickGain,"Very fast input has a bounded gain")
let wrist0=CGPoint(x:0.5,y:0.3),tip0=CGPoint(x:0.5,y:0.5)
let direction0=HandProjection.wristDirection(wrist:wrist0,point:tip0,palmWidth:0.08,palmLength:0.1,mirrored:false,gain:0.35)!
let translated=HandProjection.wristDirection(wrist:CGPoint(x:0.7,y:0.4),point:CGPoint(x:0.7,y:0.6),palmWidth:0.08,palmLength:0.1,mirrored:false,gain:0.35)!
check(hypot(direction0.x-translated.x,direction0.y-translated.y)<0.000001,"Whole-hand translation does not affect wrist direction")
let scaled=HandProjection.wristDirection(wrist:CGPoint(x:1,y:0.6),point:CGPoint(x:1,y:1),palmWidth:0.16,palmLength:0.2,mirrored:false,gain:0.35)!
check(hypot(direction0.x-scaled.x,direction0.y-scaled.y)<0.000001,"Uniform camera distance change preserves wrist sensitivity")
let angled=HandProjection.wristDirection(wrist:wrist0,point:CGPoint(x:0.52,y:0.5),palmWidth:0.08,palmLength:0.1,mirrored:false,gain:0.35)!
check(angled.x>0.05,"Small fingertip deflection has useful hand-relative travel")
let flipped=HandProjection.wristDirection(wrist:wrist0,point:CGPoint(x:0.52,y:0.5),palmWidth:0.08,palmLength:0.1,mirrored:true,gain:0.35)!
check(abs(flipped.x+angled.x)<0.000001 && flipped.y==angled.y,"Mirror flips horizontal wrist direction only")
check(HandProjection.wristDirection(wrist:.zero,point:.zero,palmWidth:0.001,palmLength:0.001,mirrored:false,gain:0.35)==nil,"Tiny unreliable hand direction is rejected")
// Recognition-width noise must not become motion of a stationary hand.
let narrowPalm=HandProjection.wristDirection(wrist:wrist0,point:tip0,palmWidth:0.055,palmLength:0.1,mirrored:false,gain:0.35)!
check(narrowPalm==direction0,"Wrist roll changing projected palm width cannot move the pointer")
let hiddenLittle=HandProjection.wristDirection(wrist:wrist0,point:tip0,palmWidth:0.065,palmLength:0.1,mirrored:false,gain:0.35)!
check(hiddenLittle==direction0,"Losing the little knuckle cannot change wrist coordinates")
var widthNoisePointer=RelativePointer();widthNoisePointer.anchor(CGPoint(x:0.5,y:0.5))
var widthNoiseResult=CGPoint.zero
for i in 0..<60 {
    let width=i%2 == 0 ? 0.08 : 0.055
    let direction=HandProjection.wristDirection(wrist:wrist0,point:tip0,palmWidth:width,palmLength:0.1,mirrored:false,gain:0.35)!
    widthNoiseResult=widthNoisePointer.update(x:direction.x,y:direction.y,time:Double(i)/15,sensitivity:1,acceleration:3)
}
check(widthNoiseResult==CGPoint(x:0.5,y:0.5),"Stationary width jitter stays still even with maximum acceleration")
func wristHand(_ pinch:Double=1,_ right:Double=1,_ rotation:Double=0)->HandSample {
    var s=hand(pinch,right)
    s.palmX=0.5;s.palmY=0.5;s.wristX=rotation;s.wristY=0;s.wristPalmX=rotation;s.wristPalmY=0
    return s
}
func wristReady()->GestureEngine {
    let e=GestureEngine()
    for i in 0..<3 {_=e.update(wristHand(),time:Double(i)*0.1)}
    return e
}
let wristPointer=wristReady()
let smallRotation=wristPointer.update(wristHand(1,1,0.025),time:0.3)
check(smallRotation.contains{if case let .move(x,_) = $0{return x>0.5};return false},"Pointer responds while wrist position is stationary")
let wristOnly=wristReady()
var translatedSample=wristHand();translatedSample.x=0.8;translatedSample.palmX=0.8
check(wristOnly.update(translatedSample,time:0.3).contains(.move(0.5,0.5)),"Arm translation is ignored in wrist mode")
let wristDrag=wristReady();_=wristDrag.update(wristHand(0.2),time:1)
check(wristDrag.update(wristHand(0.2,1,0.04),time:1.6).contains(.down),"Wrist rotation initiates drag without lifting the forearm")
check(wristDrag.update(wristHand(),time:1.7).contains(.up),"Wrist drag releases normally")
let rotationScroll=wristReady();_=rotationScroll.update(wristHand(1,0.2),time:1)
check(rotationScroll.update(wristHand(1,0.2,0.04),time:1.1).contains(.scroll(-36)),"Wrist rotation scrolls while arm stays still")
let stablePalm=wristReady();_=stablePalm.update(wristHand(0.2),time:1)
var fingerCurl=wristHand(0.2);fingerCurl.wristX=0.3
check(!stablePalm.update(fingerCurl,time:1.7).contains(.down),"Folding finger does not drag when wrist-palm direction is unchanged")
let legacyMode=ready();legacyMode.wristControl=false
var legacyMove=wristHand();legacyMove.x=0.52
check(legacyMode.update(legacyMove,time:0.3).contains{if case let .move(x,_) = $0{return x>0.5};return false},"Camera displacement mode remains available")
print("Passed \(checks) gesture and input checks")
