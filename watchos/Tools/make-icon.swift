import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// The stacker.news "SN" bolt, transcribed from svgs/sn.svg. All straight segments,
// two subpaths, in a 256x256 viewBox.
let bolt: [[CGPoint]] = [
    [(46.7, 96.4), (84.558, 150.237), (12.771, 213.171),
     (117.5, 155.4), (77.425, 102.546), (126.837, 43.054)],
    [(203.05, 137.946), (153.634, 79.437), (118.725, 196.208),
     (162.975, 128.85), (221.484, 188.1), (241.4, 47.725)]
].map { $0.map { CGPoint(x: $0.0, y: $0.1) } }

let snYellow = CGColor(red: 0.980, green: 0.855, blue: 0.369, alpha: 1)
let ink = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

/// Furthest the artwork reaches from the centre of the 256 box.
func boltRadius() -> CGFloat {
    bolt.flatMap { $0 }.map { hypot($0.x - 128, $0.y - 128) }.max()!
}

/// - markFraction: where the bolt's furthest tip lands, as a fraction of the
///   circular crop radius. watchOS clips icons to a circle, so anything past 1.0
///   is cut off.
/// - ring: bezel ring as (radiusFraction, widthFraction), or nil for none.
func render(size: Int, markFraction: CGFloat, ring: (CGFloat, CGFloat)?, to path: String) {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(snYellow)
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

    let crop = s / 2                              // circular crop radius
    let scale = (crop * markFraction) / boltRadius()

    if let (radiusFraction, widthFraction) = ring {
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(s * widthFraction)
        let r = crop * radiusFraction
        ctx.strokeEllipse(in: CGRect(x: s / 2 - r, y: s / 2 - r, width: r * 2, height: r * 2))
    }

    // SVG y grows downward, CoreGraphics upward, so flip about the centre.
    ctx.setFillColor(ink)
    let p = CGMutablePath()
    for poly in bolt {
        let mapped = poly.map { pt in
            CGPoint(x: s / 2 + (pt.x - 128) * scale,
                    y: s / 2 - (pt.y - 128) * scale)
        }
        p.move(to: mapped[0])
        for q in mapped.dropFirst() { p.addLine(to: q) }
        p.closeSubpath()
    }
    ctx.addPath(p)
    ctx.fillPath(using: .evenOdd)

    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(path)")
}

let r = boltRadius()
print(String(format: "bolt reaches %.1f of 128 in the source art (%.0f%% past the circular crop)",
             r, (r / 128 - 1) * 100))

// The shipping icon: a bezel ring so it reads as the watch edition, with the bolt
// pulled inside it. Run from `watchos/`:
//     swift Tools/make-icon.swift
render(size: 1024, markFraction: 0.74, ring: (0.90, 0.030),
       to: "StackerWatch/StackerWatch/Assets.xcassets/AppIcon.appiconset/icon.png")

// Without the ring, the bolt can sit a little larger. Kept for comparison.
// render(size: 1024, markFraction: 0.86, ring: nil, to: "/tmp/icon_plain.png")
