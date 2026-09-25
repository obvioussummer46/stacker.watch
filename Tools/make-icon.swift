// Renders the watch app icon: the stacker.news lightning mark with the "N" swapped
// for a "W", so it reads SW for Stacker Watch.
//
// Run from the repo root:
//     swift Tools/make-icon.swift
//
// Two things this exists to get right. First, watchOS clips app icons to a circle
// inscribed in the square, and the mark at its natural size reaches past that circle
// — the site's art loses both lightning tips on a watch. Second, the "W" has to carry
// the same weight as the hand-drawn "S" next to it, which is a number to tune rather
// than something to eyeball.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// The "S" of the stacker.news mark, transcribed from `svgs/sn.svg` in
/// stackernews/stacker.news. Untouched: the whole point is that this still looks
/// like stacker.news. 256x256 viewBox, y down.
let letterS: [CGPoint] = [
    (46.7, 96.4), (84.558, 150.237), (12.771, 213.171),
    (117.5, 155.4), (77.425, 102.546), (126.837, 43.054)
].map { CGPoint(x: $0.0, y: $0.1) }

func norm(_ v: CGPoint) -> CGPoint {
    let l = hypot(v.x, v.y)
    return CGPoint(x: v.x / l, y: v.y / l)
}

/// Turns a zigzag centreline into a closed tapered ribbon: a single point at each
/// end, mitred corners in between. That's how the mark's letters are built — thick
/// through the bends, pinched to a spike at the tips.
func ribbon(_ centre: [CGPoint], halfWidth h: CGFloat) -> [CGPoint] {
    func offsets(_ sign: CGFloat) -> [CGPoint] {
        (1..<centre.count - 1).map { i in
            let d1 = norm(CGPoint(x: centre[i].x - centre[i-1].x, y: centre[i].y - centre[i-1].y))
            let d2 = norm(CGPoint(x: centre[i+1].x - centre[i].x, y: centre[i+1].y - centre[i].y))
            let n1 = CGPoint(x: -d1.y * sign, y: d1.x * sign)
            let n2 = CGPoint(x: -d2.y * sign, y: d2.x * sign)
            let m = norm(CGPoint(x: n1.x + n2.x, y: n1.y + n2.y))
            // Clamped so a tight bend produces a blunt mitre instead of a long spear.
            let cosHalf = max(0.25, m.x * n1.x + m.y * n1.y)
            let len = h / cosHalf
            return CGPoint(x: centre[i].x + m.x * len, y: centre[i].y + m.y * len)
        }
    }
    return [centre.first!] + offsets(1) + [centre.last!] + offsets(-1).reversed()
}

/// The "W", sitting in the box the original "N" occupied.
///
/// `halfWidth` is the weight dial. Below about 10 the strokes go spindly and vanish
/// at the ~50px the icon is actually drawn at; above about 15 the W reads as a solid
/// blob next to the airy S. 12 balances the two.
func letterW(halfWidth: CGFloat = 12) -> [CGPoint] {
    let centre: [CGPoint] = [
        (128, 50),    // top-left spike
        (152, 186),   // first valley
        (185, 104),   // middle peak
        (214, 186),   // second valley
        (243, 46)     // top-right spike
    ].map { CGPoint(x: $0.0, y: $0.1) }
    return ribbon(centre, halfWidth: halfWidth)
}

let snYellow = CGColor(red: 0.980, green: 0.855, blue: 0.369, alpha: 1)
let ink = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

/// - markFraction: where the art's furthest point lands as a fraction of the
///   circular crop radius. Past 1.0 and watchOS cuts it off.
func render(_ glyphs: [[CGPoint]], size: Int, markFraction: CGFloat, to path: String) {
    let s = CGFloat(size)
    let radius = glyphs.flatMap { $0 }.map { hypot($0.x - 128, $0.y - 128) }.max()!
    let scale = (s / 2 * markFraction) / radius

    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(snYellow)
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

    // SVG y grows downward, CoreGraphics upward, so flip about the centre.
    ctx.setFillColor(ink)
    let p = CGMutablePath()
    for glyph in glyphs {
        let mapped = glyph.map {
            CGPoint(x: s / 2 + ($0.x - 128) * scale, y: s / 2 - ($0.y - 128) * scale)
        }
        p.move(to: mapped[0])
        for q in mapped.dropFirst() { p.addLine(to: q) }
        p.closeSubpath()
    }
    ctx.addPath(p)
    ctx.fillPath(using: .evenOdd)

    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(path)")
}

let glyphs = [letterS, letterW()]
let natural = glyphs.flatMap { $0 }.map { hypot($0.x - 128, $0.y - 128) }.max()!
print(String(format: "art reaches %.1f of 128 at natural size (%.0f%% past the circular crop)",
             natural, (natural / 128 - 1) * 100))

render(glyphs, size: 1024, markFraction: 0.86,
       to: "StackerWatch/StackerWatch/Assets.xcassets/AppIcon.appiconset/icon.png")
