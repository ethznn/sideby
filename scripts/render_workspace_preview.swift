// Render a documentation walkthrough from opt-in production-view screenshots.
// Only fixture images are read; this script never captures the user's screen.
import AppKit
import AVFoundation
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let work = ProcessInfo.processInfo.environment["SIDEBY_MEDIA_WORK_DIR"].map { URL(fileURLWithPath: $0) }
    ?? root.appendingPathComponent(".build/readme-media")
let output = root.appendingPathComponent("docs/images")
let local = root.appendingPathComponent("marketing/workspace-save-0.13.0")
try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
let width = 960, height = 760, fps = 20, duration = 15, frames = 300

func png(_ image: CGImage, _ url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "PNG destination", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "PNG finalize", code: 1) }
}
func text(_ string: String, rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    (string as NSString).draw(in: rect, withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
    ])
}
let ink = NSColor(srgbRed: 0.12, green: 0.15, blue: 0.22, alpha: 1)
let muted = NSColor(srgbRed: 0.36, green: 0.40, blue: 0.49, alpha: 1)
let accent = NSColor(srgbRed: 0.23, green: 0.29, blue: 0.84, alpha: 1)

for language in ["en", "ko"] {
    let korean = language == "ko"
    let titles = korean ? ["지금 쓰는 구성부터.", "이름을 붙여 기억해 두세요.", "저장한 구성은 이곳에.", "다른 일도 같은 방식으로.", "하던 일로, 가볍게 돌아가기."]
        : ["Start with the setup you're using.", "Give it a name. Keep it for later.", "Your saved setup, right here.", "Save another when you need it.", "Come back in one action."]
    let subtitles = korean ? ["⌥⇧Space를 누른 채 ‘이 구성 저장’을 선택하세요.", "키를 놓고, 함께 기억할 화면을 확인한 뒤 저장하세요.", "평소처럼 일하다가 필요한 구성을 하나씩 추가하세요.", "결제 개발과 PR 리뷰. 각 구성의 화면을 기억합니다.", "구성을 고르거나, ⌥⇧Tab으로 직전 구성으로 돌아오세요."]
        : ["Hold ⌥⇧Space, then choose Save this setup.", "Release the keys. Choose the displays to remember. Save.", "Keep working. Add useful setups as you go.", "Checkout and PR review, each with its own desktops.", "Choose a setup, or return to the previous one with ⌥⇧Tab."]
    let urls = [work.appendingPathComponent("native/empty-\(language).png"),
                output.appendingPathComponent("sideby-save-workspace-\(language).png"),
                work.appendingPathComponent("native/first-\(language).png"),
                work.appendingPathComponent("native/review-\(language).png"),
                work.appendingPathComponent("native/return-\(language).png")]
    let images = try urls.map { url -> NSImage in
        guard let image = NSImage(contentsOf: url) else { throw NSError(domain: "Missing fixture: " + url.lastPathComponent, code: 1) }
        return image
    }
    func scene(_ stage: Int) throws -> CGImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        context.cgContext.translateBy(x: 0, y: CGFloat(height))
        context.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        NSColor(srgbRed: 0.96, green: 0.97, blue: 0.99, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        text("sideby", rect: NSRect(x: 36, y: 21, width: 150, height: 24), size: 17, weight: .semibold, color: accent)
        text(titles[stage], rect: NSRect(x: 36, y: 58, width: 900, height: 45), size: 31, weight: .semibold, color: ink)
        text(subtitles[stage], rect: NSRect(x: 36, y: 105, width: 900, height: 27), size: 16, weight: .regular, color: muted)
        let size = stage == 1 ? NSSize(width: 477, height: 432) : NSSize(width: 680, height: 560)
        let rect = NSRect(x: (CGFloat(width) - size.width) / 2, y: 155 + (560 - size.height) / 2, width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13).addClip()
        NSColor(srgbRed: 0.14, green: 0.16, blue: 0.19, alpha: 1).setFill()
        rect.fill()
        images[stage].draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
        text(korean ? "샘플 데이터로 구성한 실제 앱 화면" : "Production views · fictional sample data",
            rect: NSRect(x: 36, y: 730, width: 700, height: 20), size: 11, weight: .regular, color: muted)
        for index in 0..<5 {
            (index == stage ? accent : NSColor(srgbRed: 0.80, green: 0.82, blue: 0.89, alpha: 1)).setFill()
            NSBezierPath(roundedRect: NSRect(x: 824 + index * 20, y: 734, width: 13, height: 4), xRadius: 2, yRadius: 2).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage!
    }
    let scenes = try (0..<5).map(scene)
    for (index, scene) in scenes.enumerated() { try png(scene, local.appendingPathComponent("scene-\(language)-\(index).png")) }
    try png(scenes[4], output.appendingPathComponent("sideby-save-flow-\(language).png"))
    let movie = local.appendingPathComponent("sideby-save-flow-\(language).mp4")
    if FileManager.default.fileExists(atPath: movie.path) { try FileManager.default.removeItem(at: movie) }
    let writer = try AVAssetWriter(outputURL: movie, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000, AVVideoExpectedSourceFrameRateKey: fps]])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error! }
    writer.startSession(atSourceTime: .zero)
    let gifURL = output.appendingPathComponent("sideby-save-flow-\(language).gif")
    let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frames / 4, nil)!
    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for frame in 0..<frames {
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed { throw writer.error! }
            try await Task.sleep(for: .milliseconds(2))
        }
        try autoreleasepool {
            let stage = frame / (fps * 3)
            let localFrame = frame % (fps * 3)
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            context.draw(scenes[stage], in: bounds)
            if stage > 0 && localFrame < 6 {
                context.setAlpha(1 - CGFloat(localFrame) / 6)
                context.draw(scenes[stage - 1], in: bounds)
            }
            let rendered = context.makeImage()!
            if frame % 4 == 0 {
                CGImageDestinationAddImage(gif, rendered, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary)
            }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess, let buffer else {
                throw NSError(domain: "Pixel buffer", code: frame)
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            let pixels = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            pixels.draw(rendered, in: bounds)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps))) else { throw writer.error! }
        }
    }
    guard CGImageDestinationFinalize(gif) else { throw NSError(domain: "GIF finalize", code: 1) }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error! }
    let asset = AVURLAsset(url: movie)
    let length = try await asset.load(.duration)
    let track = try await asset.loadTracks(withMediaType: .video).first!
    let dimensions = try await track.load(.naturalSize)
    let rate = try await track.load(.nominalFrameRate)
    precondition(abs(length.seconds - Double(duration)) < 0.05 && dimensions == CGSize(width: width, height: height) && rate == Float(fps))
    let audio = try await asset.loadTracks(withMediaType: .audio)
    precondition(audio.isEmpty)
    print("Verified \(language): 15 s silent H.264, 960×760, 20 fps; GIF 75 frames at 5 fps.")
}
