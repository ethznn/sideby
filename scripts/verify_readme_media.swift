import Foundation
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let directory = root.appendingPathComponent("docs/images")
let work = ProcessInfo.processInfo.environment["SIDEBY_MEDIA_WORK_DIR"].map { URL(fileURLWithPath: $0) }
    ?? root.appendingPathComponent(".build/readme-media")
let timelineURL = work.appendingPathComponent("timeline.json")
let timeline: [[String: Any]]? = FileManager.default.fileExists(atPath: timelineURL.path)
    ? (try JSONSerialization.jsonObject(with: Data(contentsOf: timelineURL)) as! [[String: Any]])
    : nil
// Verify the archived demo from a clean checkout too. A fresh render supplies
// the full timeline for the additional per-frame timing comparison below.
let expectedFrameCount = timeline?.count ?? 62
let expectedDuration = timeline?.reduce(0.0) { $0 + ($1["seconds"] as! Double) } ?? 22.04
var expected: [String: (Int, Int)] = ["sideby-demo-poster-en.png": (960, 640)]
for language in ["en", "ko"] {
    expected["sideby-triptych-\(language).png"] = (1920, 1080)
    expected["sideby-brand-film-\(language).png"] = (1920, 1080)
    expected["sideby-readme-loop-\(language).png"] = (960, 540)
    expected["sideby-context-capture-\(language).png"] = (1360, 1280)
    expected["sideby-settings-workspaces-\(language).png"] = (1680, 1240)
    expected["sideby-onboarding-workspaces-\(language).png"] = (1280, 1520)
    expected["sideby-onboarding-roundtrip-\(language).png"] = (1280, 1040)
}
for (name, size) in expected.sorted(by: { $0.key < $1.key }) {
    let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(name) as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    precondition(image.width == size.0 && image.height == size.1, "Unexpected size: \(name)")
}

let gifURL = directory.appendingPathComponent("sideby-demo-en.gif")
let gif = CGImageSourceCreateWithURL(gifURL as CFURL, nil)!
precondition(CGImageSourceGetCount(gif) == expectedFrameCount, "Unexpected GIF frame count")
let properties = CGImageSourceCopyProperties(gif, nil)! as NSDictionary
let gifProperties = properties[kCGImagePropertyGIFDictionary] as! NSDictionary
precondition((gifProperties[kCGImagePropertyGIFLoopCount] as! NSNumber).intValue == 0)
var duration = 0.0
for index in 0..<CGImageSourceGetCount(gif) {
    let image = CGImageSourceCreateImageAtIndex(gif, index, nil)!
    precondition(image.width == 960 && image.height == 640)
    let frame = CGImageSourceCopyPropertiesAtIndex(gif, index, nil)! as NSDictionary
    let timing = frame[kCGImagePropertyGIFDictionary] as! NSDictionary
    let delay = (timing[kCGImagePropertyGIFUnclampedDelayTime] ?? timing[kCGImagePropertyGIFDelayTime]) as! NSNumber
    precondition(delay.doubleValue > 0, "GIF frame must have a positive duration")
    if let timeline {
        precondition(abs(delay.doubleValue - (timeline[index]["seconds"] as! Double)) < 0.011,
                     "GIF timing changed at frame \(index)")
    }
    duration += delay.doubleValue
}
precondition(abs(duration - expectedDuration) < 0.02)
precondition(duration >= 20 && duration <= 24)
let bytes = try FileManager.default.attributesOfItem(atPath: gifURL.path)[.size] as! Int
precondition(bytes <= 8 * 1024 * 1024, "GIF exceeds 8 MiB")

func pixels(_ image: CGImage) -> Data {
    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Data(bytes: context.data!, count: image.width * image.height * 4)
}
precondition(pixels(CGImageSourceCreateImageAtIndex(gif, 0, nil)!) == pixels(CGImageSourceCreateImageAtIndex(gif, expectedFrameCount - 1, nil)!),
             "The GIF must return to the starting scene for a clean loop")

// Finished README loops are repository assets; film production files are not required.
for language in ["en", "ko"] {
  for (stem, frameCount, seconds, matchingBoundaries) in [
    ("sideby-readme-loop", 100, 10.0, true),
    ("sideby-brand-film", 76, 7.6, false),
    ("sideby-triptych", 74, 7.4, false)
  ] {
    let url = directory.appendingPathComponent("\(stem)-\(language).gif")
    let loop = CGImageSourceCreateWithURL(url as CFURL, nil)!
    precondition(CGImageSourceGetCount(loop) == frameCount, "Unexpected frame count: \(url.lastPathComponent)")
    let properties = CGImageSourceCopyProperties(loop, nil)! as NSDictionary
    let timing = properties[kCGImagePropertyGIFDictionary] as! NSDictionary
    precondition((timing[kCGImagePropertyGIFLoopCount] as! NSNumber).intValue == 0)
    var loopDuration = 0.0
    for index in 0..<frameCount {
        let frame = CGImageSourceCreateImageAtIndex(loop, index, nil)!
        precondition(frame.width == 960 && frame.height == 540)
        let properties = CGImageSourceCopyPropertiesAtIndex(loop, index, nil)! as NSDictionary
        let timing = properties[kCGImagePropertyGIFDictionary] as! NSDictionary
        let delay = (timing[kCGImagePropertyGIFUnclampedDelayTime] ?? timing[kCGImagePropertyGIFDelayTime]) as! NSNumber
        precondition(abs(delay.doubleValue - 0.1) < 0.001)
        loopDuration += delay.doubleValue
    }
    precondition(abs(loopDuration - seconds) < 0.001)
    let first = pixels(CGImageSourceCreateImageAtIndex(loop, 0, nil)!)
    if matchingBoundaries {
        precondition(first == pixels(CGImageSourceCreateImageAtIndex(loop, frameCount - 1, nil)!), "Loop boundaries differ")
    }
    precondition(first != pixels(CGImageSourceCreateImageAtIndex(loop, frameCount / 2, nil)!), "Preview must animate")
    let loopBytes = try Data(contentsOf: url).count
    precondition(loopBytes <= 8 * 1024 * 1024, "GIF exceeds 8 MiB")
    print("Verified \(url.lastPathComponent): \(frameCount) frames, \(seconds)s, animated, \(loopBytes) bytes")
  }
}

// Ensure both READMEs use their localized repository assets.
let linkPattern = try NSRegularExpression(pattern: #"(?:\]\(|(?:src|href)=\")([^\)\"\s]+)"#)
for language in ["en", "ko"] {
    let name = language == "en" ? "README.md" : "README.ko.md"
    let body = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    for stem in ["triptych", "context-capture", "settings-workspaces", "onboarding-workspaces", "onboarding-roundtrip"] {
        let asset = "sideby-\(stem)-\(language).png"
        precondition(body.contains(asset), "\(name) does not use \(asset)")
    }
    precondition(body.contains("sideby-triptych-\(language).gif") && body.contains("⌥⇧Tab"))
    precondition(!body.contains("sideby-brand-film-") && !body.contains("sideby-readme-loop-"),
                 "README should use one current preview, without duplicate archived demos")
}

let releaseNotes = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("docs/releases"),
    includingPropertiesForKeys: nil).filter { $0.pathExtension == "md" }
let documents = ["README.md", "README.ko.md", "docs/DEVELOPMENT.md", "docs/media/README.md", "docs/media/preview.html"]
    .map { root.appendingPathComponent($0) } + releaseNotes
for document in documents {
    let body = try String(contentsOf: document, encoding: .utf8)
    for match in linkPattern.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
        let path = String(body[Range(match.range(at: 1), in: body)!])
        precondition(!(path.contains("github.com/ethznn/sideby/releases/download/") && path.hasSuffix(".mp4")),
                     "\(document.lastPathComponent) links to a promotional release attachment")
        if path.hasPrefix("https:") || path.hasPrefix("http:") || path.hasPrefix("#") { continue }
        let local = path.components(separatedBy: "#")[0].components(separatedBy: "?")[0]
        let target = document.deletingLastPathComponent().appendingPathComponent(local).standardizedFileURL
        for ignored in ["marketing"] {
            let excluded = root.appendingPathComponent(ignored).path
            precondition(target.path != excluded && !target.path.hasPrefix(excluded + "/"),
                         "\(document.lastPathComponent) links to local-only production files: \(local)")
        }
        precondition(FileManager.default.fileExists(atPath: target.path), "Broken link in \(document.lastPathComponent): \(local)")
    }
}
print("Verified \(expected.count) PNGs, local documentation links, and archived GIF: \(expectedFrameCount) frames, \(String(format: "%.2f", duration)) s, \(bytes) bytes. Release downloads, MP4s, and audio were not checked.")
