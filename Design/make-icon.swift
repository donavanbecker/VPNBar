// Generates the VPN Bar app icon as an Icon Composer document.
// Usage: swift Design/make-icon.swift Shared/AppIcon.icon
//
// macOS clips the icon to its own shape, so each layer fills the whole 1024pt canvas.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func shieldPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 512, y: 860))
    path.addCurve(to: CGPoint(x: 795, y: 751),
                  control1: CGPoint(x: 596, y: 798), control2: CGPoint(x: 696, y: 756))
    path.addCurve(to: CGPoint(x: 512, y: 135),
                  control1: CGPoint(x: 800, y: 463), control2: CGPoint(x: 708, y: 252))
    path.addCurve(to: CGPoint(x: 229, y: 751),
                  control1: CGPoint(x: 316, y: 252), control2: CGPoint(x: 224, y: 463))
    path.addCurve(to: CGPoint(x: 512, y: 860),
                  control1: CGPoint(x: 328, y: 756), control2: CGPoint(x: 428, y: 798))
    path.closeSubpath()
    return path
}

let keyholeCircle = CGPath(ellipseIn: CGRect(x: 512 - 87, y: 547 - 87, width: 174, height: 174), transform: nil)

func keyholeSlotPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 475, y: 497))
    path.addLine(to: CGPoint(x: 549, y: 497))
    path.addLine(to: CGPoint(x: 579, y: 326))
    path.addLine(to: CGPoint(x: 445, y: 326))
    path.closeSubpath()
    return path
}

func drawRings(in context: CGContext) {
    context.setLineWidth(32)
    for (radius, alpha) in [(429, 0.14), (559, 0.10), (690, 0.06)] as [(CGFloat, CGFloat)] {
        context.setStrokeColor(color(1, 1, 1, alpha))
        context.strokeEllipse(in: CGRect(x: 512 - radius, y: 512 - radius, width: radius * 2, height: radius * 2))
    }
}

func drawShield(in context: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let colors = [color(1, 1, 1), color(0.80, 0.88, 1.00)] as CFArray
    context.saveGState()
    context.addPath(shieldPath())
    context.clip()
    context.drawLinearGradient(
        CGGradient(colorsSpace: space, colors: colors, locations: nil)!,
        start: CGPoint(x: 512, y: 860), end: CGPoint(x: 512, y: 135), options: []
    )
    context.restoreGState()

    // Filled separately: overlapping subpaths of opposite direction would cancel out.
    context.setBlendMode(.clear)
    for part in [keyholeCircle, keyholeSlotPath()] {
        context.addPath(part)
        context.fillPath()
    }
}

func writeLayer(to url: URL, draw: (CGContext) -> Void) throws {
    guard
        let context = CGContext(
            data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { throw CocoaError(.fileWriteUnknown) }
    draw(context)

    guard
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let output = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
let assets = output.appending(path: "Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

try writeLayer(to: assets.appending(path: "rings.png"), draw: drawRings)
try writeLayer(to: assets.appending(path: "shield.png"), draw: drawShield)

let manifest = #"""
{
  "fill" : {
    "linear-gradient" : [
      "srgb:0.20000,0.47000,1.00000,1.00000",
      "srgb:0.06000,0.13000,0.55000,1.00000"
    ],
    "orientation" : {
      "start" : { "x" : 0.5, "y" : 0 },
      "stop" : { "x" : 0.5, "y" : 1 }
    }
  },
  "groups" : [
    {
      "layers" : [ { "image-name" : "shield.png", "name" : "shield" } ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : false, "value" : 0.5 }
    },
    {
      "layers" : [ { "image-name" : "rings.png", "name" : "rings" } ],
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "translucency" : { "enabled" : false, "value" : 0.5 }
    }
  ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}

"""#
try manifest.write(to: output.appending(path: "icon.json"), atomically: true, encoding: .utf8)
