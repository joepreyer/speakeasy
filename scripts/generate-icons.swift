// Generates Resources/AppIcon.icns and the menu bar template icon.
// Usage: swift scripts/generate-icons.swift [preview-dir]
import AppKit
import CoreText

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let previewDir = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : nil

// MARK: - The mark: an "S" drawn as vertical rounded bars, like the dictation pill's waveform.

func glyphPath(_ character: String, height: CGFloat) -> CGPath {
    let base = NSFont.systemFont(ofSize: 100, weight: .heavy)
    let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    let font = CTFontCreateWithFontDescriptor(descriptor as CTFontDescriptor, 100, nil)
    var unichar = Array(character.utf16)
    var glyph = CGGlyph()
    CTFontGetGlyphsForCharacters(font, &unichar, &glyph, 1)
    let path = CTFontCreatePathForGlyph(font, glyph, nil)!
    let bounds = path.boundingBoxOfPath
    let scale = height / bounds.height
    var transform = CGAffineTransform(scaleX: scale, y: scale)
        .translatedBy(x: -bounds.minX, y: -bounds.minY)
    return path.copy(using: &transform)!
}

/// Rounded vertical bars covering the parts of `shape` they pass through.
func barSegments(in shape: CGPath, barWidth: CGFloat, pitch: CGFloat) -> [CGRect] {
    let bounds = shape.boundingBoxOfPath
    let count = Int(((bounds.width - barWidth) / pitch).rounded(.down)) + 1
    let offset = (bounds.width - (CGFloat(count - 1) * pitch + barWidth)) / 2
    var segments: [CGRect] = []
    let step = max(0.25, bounds.height / 2000)
    for index in 0..<count {
        let x = bounds.minX + offset + CGFloat(index) * pitch + barWidth / 2
        var runStart: CGFloat?
        var y = bounds.minY
        while y <= bounds.maxY + step {
            let inside = y <= bounds.maxY && shape.contains(CGPoint(x: x, y: y))
            if inside, runStart == nil { runStart = y }
            if !inside, let start = runStart {
                if y - start >= barWidth * 0.9 {
                    segments.append(CGRect(x: x - barWidth / 2, y: start, width: barWidth, height: y - start))
                }
                runStart = nil
            }
            y += step
        }
    }
    return segments
}

func drawMark(in context: CGContext, center: CGPoint, height: CGFloat, bars: Int?, color: CGColor) {
    let path = glyphPath("S", height: height)
    let bounds = path.boundingBoxOfPath
    var move = CGAffineTransform(translationX: center.x - bounds.width / 2, y: center.y - bounds.height / 2)
    let placed = path.copy(using: &move)!
    context.setFillColor(color)
    guard let bars else {
        context.addPath(placed)
        context.fillPath()
        return
    }
    let pitch = bounds.width / (CGFloat(bars) - 0.35)
    let barWidth = pitch * 0.62
    for segment in barSegments(in: placed, barWidth: barWidth, pitch: pitch) {
        context.addPath(CGPath(roundedRect: segment, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    }
    context.fillPath()
}

// MARK: - Rendering

func bitmap(pixels: Int, draw: (CGContext, CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    draw(context, CGFloat(pixels))
    return rep
}

func appIcon(pixels: Int) -> NSBitmapImageRep {
    bitmap(pixels: pixels) { context, size in
        let s = size / 1024
        // macOS icon grid: 824pt squircle centered on a 1024pt canvas.
        let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let radius = 186 * s
        let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s,
                          color: CGColor(gray: 0, alpha: 0.35))
        context.addPath(tilePath)
        context.setFillColor(CGColor(gray: 0.1, alpha: 1))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(tilePath)
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            CGColor(red: 0.19, green: 0.19, blue: 0.2, alpha: 1),
            CGColor(red: 0.05, green: 0.05, blue: 0.055, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
        context.restoreGState()

        // Hairline border, echoing the pill's outline.
        let inset = tile.insetBy(dx: 3 * s, dy: 3 * s)
        context.addPath(CGPath(roundedRect: inset, cornerWidth: radius - 3 * s, cornerHeight: radius - 3 * s, transform: nil))
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
        context.setLineWidth(max(1, 4 * s))
        context.strokePath()

        // Bars only read at larger sizes; small icons get a solid S.
        drawMark(in: context, center: CGPoint(x: size / 2, y: size / 2), height: 470 * s,
                 bars: pixels >= 128 ? 9 : nil, color: CGColor(gray: 1, alpha: 1))
    }
}

func menuBarIcon(pixels: Int) -> NSBitmapImageRep {
    bitmap(pixels: pixels) { context, size in
        drawMark(in: context, center: CGPoint(x: size / 2, y: size / 2), height: size * 0.84,
                 bars: 6, color: CGColor(gray: 0, alpha: 1))
    }
}

func write(_ rep: NSBitmapImageRep, to url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - Output

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    write(appIcon(pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    write(appIcon(pixels: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()

write(menuBarIcon(pixels: 18), to: resources.appendingPathComponent("MenuBarIcon.png"))
write(menuBarIcon(pixels: 36), to: resources.appendingPathComponent("MenuBarIcon@2x.png"))

if let previewDir {
    try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
    write(appIcon(pixels: 1024), to: previewDir.appendingPathComponent("icon-1024.png"))
    write(appIcon(pixels: 64), to: previewDir.appendingPathComponent("icon-64.png"))
    write(appIcon(pixels: 32), to: previewDir.appendingPathComponent("icon-32.png"))
    write(menuBarIcon(pixels: 144), to: previewDir.appendingPathComponent("menubar-large.png"))
    write(menuBarIcon(pixels: 36), to: previewDir.appendingPathComponent("menubar-36.png"))
}
print("Wrote AppIcon.icns and MenuBarIcon.png")
