import AppKit
import CoreGraphics
import Foundation

enum AppIconError: Error, CustomStringConvertible {
    case missingArgument
    case unreadableSource(String)
    case missingCGImage
    case cannotReadPixels
    case cannotDetectArtworkBounds
    case cannotRenderPNG(Int)
    case iconutilFailed(Int32)

    var description: String {
        switch self {
        case .missingArgument:
            return "usage: swift scripts/generate_app_icon.swift <source-png> <output-icns>"
        case .unreadableSource(let path):
            return "cannot read app icon source: \(path)"
        case .missingCGImage:
            return "cannot create CGImage from app icon source"
        case .cannotReadPixels:
            return "cannot read source pixels"
        case .cannotDetectArtworkBounds:
            return "cannot detect dark rounded-square artwork bounds"
        case .cannotRenderPNG(let size):
            return "cannot render \(size)x\(size) icon PNG"
        case .iconutilFailed(let status):
            return "iconutil failed with status \(status)"
        }
    }
}

struct IconLayer {
    let filename: String
    let pixels: Int
}

let layers = [
    IconLayer(filename: "icon_16x16.png", pixels: 16),
    IconLayer(filename: "icon_16x16@2x.png", pixels: 32),
    IconLayer(filename: "icon_32x32.png", pixels: 32),
    IconLayer(filename: "icon_32x32@2x.png", pixels: 64),
    IconLayer(filename: "icon_128x128.png", pixels: 128),
    IconLayer(filename: "icon_128x128@2x.png", pixels: 256),
    IconLayer(filename: "icon_256x256.png", pixels: 256),
    IconLayer(filename: "icon_256x256@2x.png", pixels: 512),
    IconLayer(filename: "icon_512x512.png", pixels: 512),
    IconLayer(filename: "icon_512x512@2x.png", pixels: 1024)
]

func fail(_ error: AppIconError) -> Never {
    fputs("generate_app_icon: \(error.description)\n", stderr)
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail(.missingArgument)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fail(.unreadableSource(sourceURL.path))
}

var proposedRect = NSRect(origin: .zero, size: sourceImage.size)
guard let sourceCGImage = sourceImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
    fail(.missingCGImage)
}

func darkArtworkBounds(in image: CGImage) throws -> CGRect {
    let width = image.width
    let height = image.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw AppIconError.cannotReadPixels
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var minX = width
    var minY = height
    var maxX = 0
    var maxY = 0

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * bytesPerPixel
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            let alpha = Int(pixels[offset + 3])
            let brightness = (red + green + blue) / 3

            if alpha > 8 && brightness < 96 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }

    guard minX <= maxX, minY <= maxY else {
        throw AppIconError.cannotDetectArtworkBounds
    }

    let detected = CGRect(
        x: minX,
        y: minY,
        width: maxX - minX + 1,
        height: maxY - minY + 1
    )
    // The source artwork includes an outer preview frame. App icons should use
    // the tighter inner artwork so the symbol reads clearly in Dock/Finder.
    let side = min(max(detected.width, detected.height) * 0.94, CGFloat(min(width, height)))
    let center = CGPoint(x: detected.midX, y: detected.midY)
    let origin = CGPoint(
        x: min(max(center.x - side / 2, 0), CGFloat(width) - side),
        y: min(max(center.y - side / 2, 0), CGFloat(height) - side)
    )

    return CGRect(origin: origin, size: CGSize(width: side, height: side)).integral
}

let cropRect: CGRect
do {
    cropRect = try darkArtworkBounds(in: sourceCGImage)
} catch let error as AppIconError {
    fail(error)
} catch {
    fail(.cannotReadPixels)
}

guard let croppedCGImage = sourceCGImage.cropping(to: cropRect) else {
    fail(.missingCGImage)
}
let croppedImage = NSImage(cgImage: croppedCGImage, size: NSSize(width: cropRect.width, height: cropRect.height))

func renderIcon(size pixels: Int) throws -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw AppIconError.cannotRenderPNG(pixels)
    }

    rep.size = NSSize(width: pixels, height: pixels)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw AppIconError.cannotRenderPNG(pixels)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSColor.clear.setFill()
    rect.fill(using: .copy)

    NSBezierPath(
        roundedRect: rect,
        xRadius: CGFloat(pixels) * 0.215,
        yRadius: CGFloat(pixels) * 0.215
    ).addClip()

    croppedImage.draw(
        in: rect,
        from: NSRect(origin: .zero, size: croppedImage.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw AppIconError.cannotRenderPNG(pixels)
    }
    return png
}

let fileManager = FileManager.default
let tempRoot = fileManager.temporaryDirectory
    .appendingPathComponent("SidebyAppIcon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = tempRoot.appendingPathComponent("AppIcon.iconset", isDirectory: true)

do {
    try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    for layer in layers {
        let data = try renderIcon(size: layer.pixels)
        try data.write(to: iconsetURL.appendingPathComponent(layer.filename))
    }

    if fileManager.fileExists(atPath: outputURL.path) {
        try fileManager.removeItem(at: outputURL)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = [
        "-c", "icns",
        iconsetURL.path,
        "-o", outputURL.path
    ]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw AppIconError.iconutilFailed(process.terminationStatus)
    }

    try? fileManager.removeItem(at: tempRoot)
} catch let error as AppIconError {
    fail(error)
} catch {
    fputs("generate_app_icon: \(error)\n", stderr)
    exit(1)
}
