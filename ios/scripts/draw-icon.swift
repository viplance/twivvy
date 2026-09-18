import AppKit
let size = 1024
let ctx = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext:ctx,flipped:false)
func color(_ h: UInt32) -> NSColor { NSColor(srgbRed:CGFloat((h>>16)&255)/255,green:CGFloat((h>>8)&255)/255,blue:CGFloat(h&255)/255,alpha:1) }
NSGradient(starting:color(0x142D4A),ending:color(0x090D24))!.draw(in:NSRect(x:0,y:0,width:1024,height:1024),angle:-55)
let tints: [UInt32] = [0x68EDD0,0x8CB9FF,0xC3A2FF,0xFF9DB7]
for index in 0..<4 {
 let x = CGFloat(index%2)*352+164, y = CGFloat(index/2)*352+164
 let rect=NSRect(x:x,y:y,width:330,height:330)
 color(0x03091A).setFill(); NSBezierPath(roundedRect:rect.offsetBy(dx:0,dy:-15),xRadius:48,yRadius:48).fill()
 NSGradient(starting:color(tints[index]).blended(withFraction:0.76,of:color(0x10233B))!,ending:color(0x15223E))!.draw(in:NSBezierPath(roundedRect:rect,xRadius:48,yRadius:48),angle:90)
 color(tints[index]).withAlphaComponent(0.5).setStroke(); let edge=NSBezierPath(roundedRect:rect,xRadius:48,yRadius:48);edge.lineWidth=3;edge.stroke()
}
let paths: [[CGPoint]] = [
 [CGPoint(x:164,y:330),CGPoint(x:330,y:330),CGPoint(x:330,y:494)],
 [CGPoint(x:330,y:846),CGPoint(x:330,y:680),CGPoint(x:494,y:680)],
 [CGPoint(x:516,y:330),CGPoint(x:680,y:330),CGPoint(x:680,y:164)],
 [CGPoint(x:680,y:516),CGPoint(x:680,y:680),CGPoint(x:846,y:680)]
]
for (index,points) in paths.enumerated() {
 let p=NSBezierPath();p.move(to:points[0]);p.line(to:points[1]);p.line(to:points[2]);p.lineCapStyle = .round;p.lineJoinStyle = .round
 color(0x071023).setStroke();p.lineWidth=64;p.stroke()
 color(tints[index]).withAlphaComponent(0.25).setStroke();p.lineWidth=43;p.stroke()
 color(tints[index]).setStroke();p.lineWidth=22;p.stroke()
 NSColor.white.withAlphaComponent(0.65).setStroke();p.lineWidth=4;p.stroke()
}
ctx.setShadow(offset:CGSize(width:0,height:0),blur:35,color:color(0xFFD886).cgColor)
color(0xFFD886).setFill();NSBezierPath(ovalIn:NSRect(x:626,y:276,width:108,height:108)).fill()
ctx.setShadow(offset:.zero,blur:0,color:nil)
NSGradient(starting:.white,ending:color(0xFFBE62))!.draw(in:NSBezierPath(ovalIn:NSRect(x:633,y:283,width:94,height:94)),angle:-70)
NSColor.white.setFill();NSBezierPath(ovalIn:NSRect(x:650,y:338,width:21,height:21)).fill()
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage:ctx.makeImage()!)
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
