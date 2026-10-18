import AppKit

// Original vector artwork for HamsterLab, rendered as an opaque App Store icon.
let context=CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:4096,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
func color(_ hex: UInt32) -> NSColor { NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1) }
func oval(_ rect: NSRect,_ tint: NSColor) { tint.setFill(); NSBezierPath(ovalIn:rect).fill() }
func gradientOval(_ rect: NSRect,_ a: UInt32,_ b: UInt32) { NSGradient(starting:color(a),ending:color(b))!.draw(in:NSBezierPath(ovalIn:rect),angle:-75) }
NSGradient(starting:color(0x27526B),ending:color(0x10273C))!.draw(in:NSRect(x:0,y:0,width:1024,height:1024),angle:-60)
for (x,y,r) in [(150,820,20),(872,810,13),(830,220,22),(135,320,11)] {
    oval(NSRect(x:x,y:y,width:r*2,height:r*2),color(0x94F4D3).withAlphaComponent(0.25))
}
// A transparent laboratory tube behind the mascot.
let tube=NSBezierPath(roundedRect:NSRect(x:-60,y:260,width:1144,height:410),xRadius:180,yRadius:180)
color(0xB8EAFF).withAlphaComponent(0.12).setFill(); tube.fill()
color(0xE5FAFF).withAlphaComponent(0.65).setStroke(); tube.lineWidth=10; tube.stroke()
for x in [70,850] {
    let collar=NSBezierPath(roundedRect:NSRect(x:x,y:248,width:105,height:434),xRadius:48,yRadius:48)
    color(0x93F2D0).withAlphaComponent(0.7).setStroke(); collar.lineWidth=22; collar.stroke()
}
context.setShadow(offset:CGSize(width:0,height:-20),blur:32,color:color(0x000E24).cgColor)
gradientOval(NSRect(x:230,y:170,width:570,height:630),0xFFE2A3,0xCF8C4D)
context.setShadow(offset:.zero,blur:0,color:nil)
for x in [225,630] {
    gradientOval(NSRect(x:x,y:660,width:175,height:200),0xFFDF9C,0xDC9D60)
    gradientOval(NSRect(x:x+35,y:695,width:108,height:127),0xFBC0BE,0xE78C9C)
}
gradientOval(NSRect(x:232,y:305,width:560,height:430),0xFFDEA0,0xE5AB64)
for x in [240,506] { gradientOval(NSRect(x:x,y:220,width:280,height:248),0xFFFAE7,0xEDD7B9) }
for x in [338,566] {
    gradientOval(NSRect(x:x,y:442,width:118,height:152),0x554451,0x201D32)
    oval(NSRect(x:x+20,y:522,width:38,height:44),.white)
    oval(NSRect(x:x+75,y:462,width:17,height:20),color(0xC0E7ED))
    let brow=NSBezierPath();brow.move(to:NSPoint(x:x+10,y:628));brow.curve(to:NSPoint(x:x+105,y:635),controlPoint1:NSPoint(x:x+35,y:650),controlPoint2:NSPoint(x:x+72,y:651))
    color(0x976B4F).setStroke();brow.lineWidth=12;brow.lineCapStyle = .round;brow.stroke()
}
for x in [274,660] { oval(NSRect(x:x,y:365,width:83,height:30),color(0xEFA1A7).withAlphaComponent(0.65)) }
for sign: CGFloat in [-1,1] {
    for index in 0..<3 {
        let whisker=NSBezierPath();let y=CGFloat(340+index*35)
        whisker.move(to:NSPoint(x:512+sign*190,y:y));whisker.line(to:NSPoint(x:512+sign*325,y:y+CGFloat(index-1)*20))
        color(0xEBD8CA).setStroke();whisker.lineWidth=5;whisker.lineCapStyle = .round;whisker.stroke()
    }
}
let smile=NSBezierPath();smile.move(to:NSPoint(x:455,y:331));smile.curve(to:NSPoint(x:569,y:331),controlPoint1:NSPoint(x:486,y:298),controlPoint2:NSPoint(x:538,y:298))
color(0x805566).setStroke();smile.lineWidth=9;smile.lineCapStyle = .round;smile.stroke()
for x in [487,515] {
    color(0xFFFEF5).setFill();NSBezierPath(roundedRect:NSRect(x:x,y:279,width:23,height:54),xRadius:6,yRadius:6).fill()
}
gradientOval(NSRect(x:472,y:362,width:82,height:58),0xF6A9AF,0xCF7A8C)
for x in [310,620] { gradientOval(NSRect(x:x,y:186,width:97,height:73),0xFFC7B8,0xE69DA2) }
NSGraphicsContext.restoreGraphicsState()
let bitmap=NSBitmapImageRep(cgImage:context.makeImage()!)
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
