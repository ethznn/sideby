import AppKit
import ImageIO
import UniformTypeIdentifiers

// An illustrated desktop simulation around an unmodified capture of the production matrix.
// This renderer never launches Sideby, queries user windows, or sends a Space command.
struct Fixture: Decodable {
    let version: String
    struct Display: Decodable { let name: String }
    struct Desktop: Decodable { let title: String; let kind: String; let heading: String; let lines: [String] }
    struct Workspace: Decodable { let en: String; let desktops: [Desktop] }
    let displays: [Display]
    let workspaces: [Workspace]
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("docs/images")
let work = ProcessInfo.processInfo.environment["SIDEBY_MEDIA_WORK_DIR"].map { URL(fileURLWithPath: $0) }
    ?? root.appendingPathComponent(".build/readme-media")
let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("docs/media/demo-data.json")))
guard fixture.displays.count == 2, fixture.workspaces.count == 2,
      fixture.workspaces.allSatisfy({ $0.desktops.count == 2 }),
      let matrix = NSImage(contentsOf: work.appendingPathComponent("native/matrix.png")),
      let icon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon.icns")) else {
    fatalError("Render the native views first and supply two complete sample workspaces.")
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let frames = work.appendingPathComponent("frames")
try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
let width = 960, height = 640

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let ink = color(0x20252D), muted = color(0x5D6673), blue = color(0x007AFF), paper = color(0xF3F5F8)

func box(_ rect: NSRect, _ fill: NSColor, radius: CGFloat = 0, stroke: NSColor? = nil) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill(); path.fill()
    if let stroke { stroke.setStroke(); path.lineWidth = 1; path.stroke() }
}

func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat,
          weight: NSFont.Weight = .regular, fill: NSColor = ink, mono: Bool = false) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingTail
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    (value as NSString).draw(in: NSRect(x: x, y: y, width: width, height: size * 1.7),
        withAttributes: [.font: font, .foregroundColor: fill, .paragraphStyle: style])
}

func drawImage(_ image: NSImage, in rect: NSRect, alpha: CGFloat = 1) {
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true,
               hints: [.interpolation: NSImageInterpolation.high])
}

func desktop(_ item: Fixture.Desktop, in r: NSRect) {
    let isCode = item.kind == "code" || item.kind == "review"
    let background = isCode ? color(0x202733) : NSColor.white
    let foreground = isCode ? color(0xDAE3EF) : ink
    box(r, background)
    box(NSRect(x: r.minX, y: r.minY, width: r.width, height: 34), isCode ? color(0x303949) : color(0xE9EDF3))
    for (i, dot) in [0xFF6259, 0xFFBD2E, 0x28C840].enumerated() {
        box(NSRect(x: r.minX + 13 + CGFloat(i) * 14, y: r.minY + 13, width: 8, height: 8), color(UInt32(dot)), radius: 4)
    }
    text(item.title, x: r.minX + 66, y: r.minY + 9, width: r.width - 80, size: 13, weight: .medium, fill: foreground)
    let x = r.minX + 20, y = r.minY + 53
    if item.kind == "preview" {
        text("Your order", x: x, y: y, width: 330, size: 22, weight: .semibold)
        box(NSRect(x: x, y: y + 43, width: 58, height: 69), color(0xDCE8F7), radius: 5)
        box(NSRect(x: x + 13, y: y + 52, width: 33, height: 48), color(0x566C8D), radius: 3)
        text(item.lines[1], x: x + 76, y: y + 44, width: 275, size: 17, weight: .medium)
        text(item.lines[2], x: x + 76, y: y + 73, width: 130, size: 14, fill: muted)
        text(item.lines[3], x: x + 283, y: y + 73, width: 75, size: 16, weight: .medium)
        box(NSRect(x: x, y: y + 132, width: r.width - 40, height: 37), blue, radius: 7)
        text("Checkout", x: x + 145, y: y + 140, width: 120, size: 15, weight: .semibold, fill: .white)
        text(item.lines.last!, x: x, y: y + 181, width: 330, size: 12, fill: muted)
    } else if item.kind == "docs" {
        text(item.heading, x: x, y: y, width: r.width - 40, size: 23, weight: .semibold)
        for (i, line) in item.lines.enumerated() {
            let cy = y + 40 + CGFloat(i) * 19
            text(line, x: x, y: cy, width: r.width - 40, size: i == 0 ? 14 : 12.5,
                 weight: i == 0 || i == 7 ? .semibold : .regular,
                 fill: i == 0 || i == 7 ? blue : muted, mono: i > 2 && i < 6)
        }
    } else {
        for (i, line) in item.lines.enumerated() {
            let lineColor = line.hasPrefix("+") ? color(0x7DDDA7) : line.hasPrefix("-") ? color(0xF3A7A7) : foreground
            if line.hasPrefix("+") || line.hasPrefix("-") {
                box(NSRect(x: r.minX, y: y + CGFloat(i) * 18.5 - 1, width: r.width, height: 18.5),
                    line.hasPrefix("+") ? color(0x294B3C) : color(0x50383E))
            }
            text(String(i + 1), x: r.minX + 13, y: y + CGFloat(i) * 18.5, width: 21, size: 11, fill: color(0x8996A9), mono: true)
            text(line, x: r.minX + 42, y: y + CGFloat(i) * 18.5, width: r.width - 52, size: 12, fill: lineColor, mono: true)
        }
    }
}

struct Scene {
    var workspace = 0
    var caption = "Code and docs, together."
    var shortcut = false
    var matrixOpacity: CGFloat = 0
    var cursorProgress: CGFloat? = nil
    var click = false
    var destination: Int? = nil
    var transition: CGFloat = 0
}

func render(_ scene: Scene) -> CGImage {
    let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    cg.translateBy(x: 0, y: CGFloat(height)); cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    defer { NSGraphicsContext.restoreGraphicsState() }
    box(NSRect(x: 0, y: 0, width: width, height: height), paper)
    drawImage(icon, in: NSRect(x: 38, y: 34, width: 38, height: 38))
    text("Sideby", x: 87, y: 36, width: 200, size: 26, weight: .bold)
    text("SIDEBY \(fixture.version)", x: 800, y: 46, width: 120, size: 11, weight: .semibold, fill: muted)
    text("Back to your work, in one action.", x: 40, y: 105, width: 880, size: 33, weight: .bold)
    text(scene.caption, x: 40, y: 153, width: 760, size: 22, fill: muted)
    for index in 0..<2 {
        let r = NSRect(x: index == 0 ? 40 : 498, y: 233, width: 422, height: 270)
        text(fixture.displays[index].name, x: r.minX, y: 205, width: r.width, size: 14, weight: .semibold, fill: muted)
        cg.saveGState()
        let path = CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil)
        cg.addPath(path); cg.clip()
        if let destination = scene.destination {
            // Sequential illustrative motion: do not imply simultaneous hardware commands.
            let progress = max(0, min(1, (scene.transition - CGFloat(index) * 0.4) / 0.6))
            let eased = progress * progress * (3 - 2 * progress)
            let offset = (scene.workspace < destination ? 1.0 : -1.0) * r.width
            desktop(fixture.workspaces[scene.workspace].desktops[index], in: r.offsetBy(dx: -offset * eased, dy: 0))
            desktop(fixture.workspaces[destination].desktops[index], in: r.offsetBy(dx: offset * (1 - eased), dy: 0))
        } else { desktop(fixture.workspaces[scene.workspace].desktops[index], in: r) }
        cg.restoreGState()
        box(r, .clear, radius: 10, stroke: color(0xB7C1CF))
    }
    box(NSRect(x: 40, y: 527, width: 183, height: 42), color(0xE0EBFA), radius: 9)
    text(fixture.workspaces[scene.destination ?? scene.workspace].en, x: 58, y: 537, width: 156, size: 17, weight: .semibold, fill: color(0x005ABA))
    text("Checkout  ⇄  PR review", x: 246, y: 540, width: 390, size: 15, fill: muted)
    box(NSRect(x: 681, y: 523, width: 239, height: 50), scene.shortcut ? blue : .white, radius: 10,
        stroke: scene.shortcut ? blue : color(0xC9D2DE))
    text("⌥ ⇧ Tab", x: 699, y: 534, width: 117, size: 22, weight: .semibold, fill: scene.shortcut ? .white : ink)
    text("back & forth", x: 812, y: 543, width: 103, size: 12, fill: scene.shortcut ? .white : muted)
    if scene.matrixOpacity > 0 {
        box(NSRect(x: 22, y: 195, width: 916, height: 396), color(0x111720, 0.76 * scene.matrixOpacity), radius: 15)
        drawImage(matrix, in: NSRect(x: 60, y: 216, width: 840, height: 372), alpha: scene.matrixOpacity)
        if let progress = scene.cursorProgress {
            let x = 812 - progress * 304, y = 510 - progress * 133
            if scene.click {
                box(NSRect(x: x - 17, y: y - 16, width: 54, height: 45), color(0x007AFF, 0.25), radius: 10, stroke: color(0x69AEFF))
            }
            let cursor = NSBezierPath()
            cursor.move(to: NSPoint(x: x, y: y)); cursor.line(to: NSPoint(x: x + 1, y: y + 28))
            cursor.line(to: NSPoint(x: x + 8, y: y + 21)); cursor.line(to: NSPoint(x: x + 14, y: y + 31))
            cursor.line(to: NSPoint(x: x + 20, y: y + 28)); cursor.line(to: NSPoint(x: x + 14, y: y + 18))
            cursor.line(to: NSPoint(x: x + 25, y: y + 17)); cursor.close()
            NSColor.white.setFill(); cursor.fill(); ink.setStroke(); cursor.lineWidth = 1.5; cursor.stroke()
        }
    }
    text("Simulated demo · Sample workspaces", x: 40, y: 604, width: 430, size: 12, fill: muted)
    text("Existing desktops, grouped by task.", x: 660, y: 604, width: 270, size: 12, fill: muted)
    return cg.makeImage()!
}

func savePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}

var timeline: [(Scene, Double)] = []
func hold(_ scene: Scene, _ seconds: Double) { timeline.append((scene, seconds)) }
hold(Scene(), 3)
var menu = Scene(caption: "Choose PR review in the menu matrix.", matrixOpacity: 1)
hold(menu, 2.2)
for i in 0...8 { menu.cursorProgress = CGFloat(i) / 8; hold(menu, 0.08) }
menu.click = true; hold(menu, 0.6)
func move(from: Int, to: Int, caption: String, shortcut: Bool) {
    var scene = Scene(workspace: from, caption: caption, shortcut: shortcut, destination: to)
    for i in 0...10 { scene.transition = CGFloat(i) / 10; hold(scene, 0.08) }
}
move(from: 0, to: 1, caption: "Your review screens are ready.", shortcut: false)
hold(Scene(workspace: 1, caption: "Your review screens are ready."), 2.6)
hold(Scene(workspace: 1, caption: "Back to Checkout. Same shortcut, every time.", shortcut: true), 0.5)
move(from: 1, to: 0, caption: "Back to Checkout. Same shortcut, every time.", shortcut: true)
hold(Scene(caption: "Back to Checkout. Same shortcut, every time.", shortcut: true), 2.3)
move(from: 0, to: 1, caption: "Press it again. Back to PR review.", shortcut: true)
hold(Scene(workspace: 1, caption: "Press it again. Back to PR review.", shortcut: true), 2.3)
move(from: 1, to: 0, caption: "Pick up where you left off.", shortcut: true)
hold(Scene(caption: "Pick up where you left off.", shortcut: true), 2.3)
hold(Scene(), 2)

let gifURL = output.appendingPathComponent("sideby-demo-en.gif")
let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, timeline.count, nil)!
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
var manifest: [[String: Any]] = []
for (index, frame) in timeline.enumerated() {
    autoreleasepool {
        let image = render(frame.0)
        CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary:
            [kCGImagePropertyGIFDelayTime: frame.1, kCGImagePropertyGIFUnclampedDelayTime: frame.1]] as CFDictionary)
        // Keep representative native source frames for visual review, not hundreds of duplicate PNGs.
        if index == 0 || frame.1 >= 0.5 {
            savePNG(image, to: frames.appendingPathComponent(String(format: "%03d.png", index)))
        }
        manifest.append(["frame": index, "seconds": frame.1, "caption": frame.0.caption,
                         "workspace": frame.0.workspace, "destination": frame.0.destination as Any? ?? NSNull(),
                         "matrix": frame.0.matrixOpacity > 0, "shortcut": frame.0.shortcut])
    }
}
precondition(CGImageDestinationFinalize(gif))
savePNG(render(Scene()), to: output.appendingPathComponent("sideby-demo-poster-en.png"))
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: work.appendingPathComponent("timeline.json"))
let bytes = try FileManager.default.attributesOfItem(atPath: gifURL.path)[.size] as! Int
precondition(bytes <= 8 * 1024 * 1024, "GIF exceeds the 8 MiB review limit")
print("Rendered \(timeline.count) frames · \(timeline.reduce(0) { $0 + $1.1 }) seconds · \(bytes) bytes · \(width)×\(height)")
