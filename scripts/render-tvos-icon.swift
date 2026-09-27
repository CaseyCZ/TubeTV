#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO

enum RenderError: Error { case context, image, destination, finalize }

let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func cg(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255,
            alpha: a)
}
func grad(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations)!
}
func round(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func makeContext(_ w: Int, _ h: Int) throws -> CGContext {
    guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw RenderError.context }
    c.setAllowsAntialiasing(true); c.setShouldAntialias(true)
    return c
}
func drawBack(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
    c.drawLinearGradient(grad([cg(0x343841), cg(0x111318), cg(0x050608)], [0, 0.52, 1]),
                         start: CGPoint(x: w/2, y: h), end: CGPoint(x: w/2, y: 0), options: [])
    c.drawRadialGradient(grad([cg(0xff1735, 0.26), cg(0x9b0b24, 0.12), cg(0x000000, 0)], [0, 0.48, 1]),
                         startCenter: CGPoint(x: w*0.5, y: h*0.45), startRadius: 0,
                         endCenter: CGPoint(x: w*0.5, y: h*0.45), endRadius: w*0.55, options: [])
}
func drawMiddle(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let tv = CGRect(x: w*0.105, y: h*0.195, width: w*0.79, height: h*0.66)
    let screen = tv.insetBy(dx: w*0.043, dy: h*0.065)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -h*0.012), blur: h*0.045, color: cg(0x000000, 0.78))
    c.addPath(round(screen, h*0.11)); c.clip()
    c.drawLinearGradient(grad([cg(0x30343c, 0.98), cg(0x0b0c10, 1)], [0,1]),
                         start: CGPoint(x: screen.minX, y: screen.maxY),
                         end: CGPoint(x: screen.maxX, y: screen.minY), options: [])
    c.restoreGState()
    c.saveGState(); c.addPath(round(screen, h*0.11)); c.clip()
    let p = CGMutablePath()
    p.move(to: CGPoint(x: screen.minX, y: screen.maxY))
    p.addLine(to: CGPoint(x: screen.minX + screen.width*0.72, y: screen.maxY))
    p.addLine(to: CGPoint(x: screen.minX + screen.width*0.28, y: screen.minY + screen.height*0.25))
    p.addLine(to: CGPoint(x: screen.minX, y: screen.minY + screen.height*0.08)); p.closeSubpath()
    c.addPath(p); c.setFillColor(cg(0xffffff, 0.075)); c.fillPath(); c.restoreGState()
    c.addPath(round(CGRect(x:w*0.455,y:h*0.095,width:w*0.09,height:h*0.14), w*0.018))
    c.setFillColor(cg(0x181a20)); c.fillPath()
    c.addPath(round(CGRect(x:w*0.315,y:h*0.075,width:w*0.37,height:h*0.055), h*0.022))
    c.setFillColor(cg(0x15171c)); c.fillPath()
}
func play(_ w: CGFloat, _ h: CGFloat) -> CGPath {
    let l=w*0.39, r=w*0.64, b=h*0.31, t=h*0.69, m=h*0.50, q=min(w,h)*0.035
    let p=CGMutablePath()
    p.move(to: CGPoint(x:l+q,y:b))
    p.addCurve(to: CGPoint(x:l,y:b+q), control1: CGPoint(x:l+q*0.35,y:b), control2: CGPoint(x:l,y:b+q*0.35))
    p.addLine(to: CGPoint(x:l,y:t-q))
    p.addCurve(to: CGPoint(x:l+q,y:t), control1: CGPoint(x:l,y:t-q*0.35), control2: CGPoint(x:l+q*0.35,y:t))
    p.addLine(to: CGPoint(x:r-q,y:m+q))
    p.addCurve(to: CGPoint(x:r-q,y:m-q), control1: CGPoint(x:r+q*0.25,y:m+q*0.55), control2: CGPoint(x:r+q*0.25,y:m-q*0.55))
    p.addLine(to: CGPoint(x:l+q,y:b)); p.closeSubpath(); return p
}
func drawFront(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let tv=CGRect(x:w*0.105,y:h*0.195,width:w*0.79,height:h*0.66)
    let inner=tv.insetBy(dx:w*0.033,dy:h*0.05)
    c.saveGState(); c.setShadow(offset:.zero, blur:h*0.055, color:cg(0xff102a,0.68))
    c.addPath(round(tv,h*0.14)); c.addPath(round(inner,h*0.105)); c.clip(using:.evenOdd)
    c.drawLinearGradient(grad([cg(0xffd09a),cg(0xff4b52),cg(0xff0927),cg(0x9e0923)],[0,0.24,0.64,1]),
                         start:CGPoint(x:tv.minX,y:tv.maxY), end:CGPoint(x:tv.maxX,y:tv.minY), options:[])
    c.restoreGState()
    let tri=play(w,h)
    c.saveGState(); c.setShadow(offset:.zero, blur:h*0.05, color:cg(0xff152f,0.82)); c.addPath(tri); c.clip()
    c.drawLinearGradient(grad([cg(0xffd18e),cg(0xff474c),cg(0xff002b),cg(0xc70025)],[0,0.24,0.70,1]),
                         start:CGPoint(x:w*0.40,y:h*0.70), end:CGPoint(x:w*0.63,y:h*0.30), options:[])
    c.restoreGState()
    c.addPath(tri); c.setStrokeColor(cg(0xfff1d6,0.72)); c.setLineWidth(max(1,w*0.0024)); c.strokePath()
    let stem=CGRect(x:w*0.455,y:h*0.095,width:w*0.09,height:h*0.14)
    let base=CGRect(x:w*0.315,y:h*0.075,width:w*0.37,height:h*0.055)
    let sg=grad([cg(0xff6170,0.76),cg(0x6e0a22,0.85)],[0,1])
    for r in [stem,base] { c.saveGState(); c.addPath(round(r,h*0.022)); c.clip()
        c.drawLinearGradient(sg,start:CGPoint(x:r.minX,y:r.maxY),end:CGPoint(x:r.maxX,y:r.minY),options:[]); c.restoreGState() }
}
enum Layer { case back, middle, front, composite }
func render(_ w:Int,_ h:Int,_ layer:Layer) throws -> CGImage {
    let c=try makeContext(w,h), wf=CGFloat(w), hf=CGFloat(h)
    c.clear(CGRect(x:0,y:0,width:wf,height:hf))
    if layer == .back || layer == .composite { drawBack(c,wf,hf) }
    if layer == .middle || layer == .composite { drawMiddle(c,wf,hf) }
    if layer == .front || layer == .composite { drawFront(c,wf,hf) }
    guard let image=c.makeImage() else { throw RenderError.image }; return image
}
func writePNG(_ image:CGImage,_ url:URL) throws {
    try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
    guard let d=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil) else { throw RenderError.destination }
    CGImageDestinationAddImage(d,image,nil); guard CGImageDestinationFinalize(d) else { throw RenderError.finalize }
}
func save(_ rel:String,_ w:Int,_ h:Int,_ layer:Layer) throws { try writePNG(try render(w,h,layer),root.appendingPathComponent(rel)) }
func info() -> [String:Any] { ["info":["author":"xcode","version":1]] }
func writeJSON(_ obj:Any,_ rel:String) throws {
    let u=root.appendingPathComponent(rel); try fm.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true)
    let d=try JSONSerialization.data(withJSONObject:obj,options:[.prettyPrinted,.sortedKeys]); try d.write(to:u)
}
func setJSON(_ one:String,_ two:String?) -> [String:Any] {
    var images:[[String:String]]=[["filename":one,"idiom":"tv","scale":"1x"]]
    if let two { images.append(["filename":two,"idiom":"tv","scale":"2x"]) } else { images.append(["idiom":"tv","scale":"2x"]) }
    return ["images":images,"info":["author":"xcode","version":1]]
}
func prepare() throws {
    try writeJSON(["assets":[
        ["filename":"App Icon - App Store.imagestack","idiom":"tv","role":"primary-app-icon","size":"1280x768"],
        ["filename":"App Icon.imagestack","idiom":"tv","role":"primary-app-icon","size":"400x240"],
        ["filename":"Top Shelf Image Wide.imageset","idiom":"tv","role":"top-shelf-image-wide","size":"2320x720"],
        ["filename":"Top Shelf Image.imageset","idiom":"tv","role":"top-shelf-image","size":"1920x720"]
    ],"info":["author":"xcode","version":1]],"Contents.json")
    let layers=["Front","Middle","Back"]
    for stack in ["App Icon.imagestack","App Icon - App Store.imagestack"] {
        try writeJSON(["layers":layers.map{["filename":"\($0).imagestacklayer"]},"info":["author":"xcode","version":1]],"\(stack)/Contents.json")
        for layer in layers {
            try writeJSON(info(),"\(stack)/\(layer).imagestacklayer/Contents.json")
            let n=layer.lowercased()
            try writeJSON(stack.hasPrefix("App Icon.") ? setJSON("\(n)@1x.png","\(n)@2x.png") : setJSON("\(n).png",nil),
                          "\(stack)/\(layer).imagestacklayer/Content.imageset/Contents.json")
        }
    }
    try writeJSON(setJSON("top-shelf.png",nil),"Top Shelf Image.imageset/Contents.json")
    try writeJSON(setJSON("top-shelf-wide.png",nil),"Top Shelf Image Wide.imageset/Contents.json")
}
try prepare()
try save("App Icon.imagestack/Back.imagestacklayer/Content.imageset/back@1x.png",400,240,.back)
try save("App Icon.imagestack/Middle.imagestacklayer/Content.imageset/middle@1x.png",400,240,.middle)
try save("App Icon.imagestack/Front.imagestacklayer/Content.imageset/front@1x.png",400,240,.front)
try save("App Icon.imagestack/Back.imagestacklayer/Content.imageset/back@2x.png",800,480,.back)
try save("App Icon.imagestack/Middle.imagestacklayer/Content.imageset/middle@2x.png",800,480,.middle)
try save("App Icon.imagestack/Front.imagestacklayer/Content.imageset/front@2x.png",800,480,.front)
try save("App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/back.png",1280,768,.back)
try save("App Icon - App Store.imagestack/Middle.imagestacklayer/Content.imageset/middle.png",1280,768,.middle)
try save("App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/front.png",1280,768,.front)
try save("Top Shelf Image.imageset/top-shelf.png",1920,720,.composite)
try save("Top Shelf Image Wide.imageset/top-shelf-wide.png",2320,720,.composite)
print("Rendered TubeTV tvOS brand assets")
