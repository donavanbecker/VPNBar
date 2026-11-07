// Generates the VPN Bar app icon set.
// Usage: swift Design/make-icon.swift App/Assets.xcassets/AppIcon.appiconset

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// The macOS icon tile: a superellipse on the standard 824pt grid.
func tilePath() -> CGPath {
    let path = CGMutablePath()
    let center: CGFloat = 512, radius: CGFloat = 412, exponent: CGFloat = 5
    for step in 0..<720 {
        let angle = CGFloat(step) / 720 * 2 * .pi
        let c = cos(angle), s = sin(angle)
        let x = center + radius * copysign(pow(abs(c), 2 / exponent), c)
        let y = center + radius * copysign(pow(abs(s), 2 / exponent), s)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func shieldPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 512, y: 800))
    path.addCurve(to: CGPoint(x: 740, y: 712),
                  control1: CGPoint(x: 580, y: 750), control2: CGPoint(x: 660, y: 716))
    path.addCurve(to: CGPoint(x: 512, y: 216),
                  control1: CGPoint(x: 744, y: 480), control2: CGPoint(x: 670, y: 310))
    path.addCurve(to: CGPoint(x: 284, y: 712),
                  control1: CGPoint(x: 354, y: 310), control2: CGPoint(x: 280, y: 480))
    path.addCurve(to: CGPoint(x: 512, y: 800),
                  control1: CGPoint(x: 364, y: 716), control2: CGPoint(x: 444, y: 750))
    path.closeSubpath()
    return path
}

let keyholeCircle = CGPath(ellipseIn: CGRect(x: 512 - 70, y: 540 - 70, width: 140, height: 140), transform: nil)

func keyholeSlotPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 482, y: 500))
    path.addLine(to: CGPoint(x: 542, y: 500))
    path.addLine(to: CGPoint(x: 566, y: 362))
    path.addLine(to: CGPoint(x: 458, y: 362))
    path.closeSubpath()
    return path
}

func drawIcon(in context: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = { (colors: [CGColor]) in
        CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    }

    // Tile, with the standard soft drop shadow.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35))
    context.addPath(tilePath())
    context.setFillColor(color(0.07, 0.16, 0.62))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath())
    context.clip()
    context.drawLinearGradient(
        gradient([color(0.20, 0.47, 1.00), color(0.06, 0.13, 0.55)]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: []
    )

    // Rings radiating from the shield, suggesting a tunnel.
    context.setLineWidth(26)
    for (radius, alpha) in [(345, 0.11), (450, 0.08), (555, 0.05)] as [(CGFloat, CGFloat)] {
        context.setStrokeColor(color(1, 1, 1, alpha))
        context.strokeEllipse(in: CGRect(x: 512 - radius, y: 512 - radius, width: radius * 2, height: radius * 2))
    }
    context.restoreGState()

    // Shield, with the keyhole cut through to the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0.01, 0.04, 0.25, 0.5))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.saveGState()
    context.addPath(shieldPath())
    context.clip()
    context.drawLinearGradient(
        gradient([color(1, 1, 1), color(0.80, 0.88, 1.00)]),
        start: CGPoint(x: 512, y: 800), end: CGPoint(x: 512, y: 216), options: []
    )
    context.restoreGState()
    context.setBlendMode(.clear)
    // Filled separately: overlapping subpaths of opposite direction would cancel out.
    for part in [keyholeCircle, keyholeSlotPath()] {
        context.addPath(part)
        context.fillPath()
    }
    context.endTransparencyLayer()
    context.restoreGState()
}

func writePNG(pixels: Int, to url: URL) throws {
    guard
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { throw CocoaError(.fileWriteUnknown) }
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: context)

    guard
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let output = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

var entries: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try writePNG(pixels: points * scale, to: output.appending(path: name))
        entries.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}

let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appending(path: "Contents.json"))
