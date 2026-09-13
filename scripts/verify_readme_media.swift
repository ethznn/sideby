import Foundation
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let directory = root.appendingPathComponent("docs/images")
let timeline = try JSONSerialization.jsonObject(with: Data(contentsOf:
    root.appendingPathComponent(".build/readme-media/timeline.json"))) as! [[String: Any]]
let expectedDuration = timeline.reduce(0.0) { $0 + ($1["seconds"] as! Double) }
var expected: [String: (Int, Int)] = ["sideby-demo-poster-en.png": (960, 640)]
for language in ["en", "ko"] {
    expected["sideby-context-capture-\(language).png"] = (1360, 1180)
    expected["sideby-settings-workspaces-\(language).png"] = (1680, 1240)
    expected["sideby-onboarding-workspaces-\(language).png"] = (1280, 1400)
    expected["sideby-onboarding-roundtrip-\(language).png"] = (1280, 1040)
}
for (name, size) in expected.sorted(by: { $0.key < $1.key }) {
    let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(name) as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    precondition(image.width == size.0 && image.height == size.1, "Unexpected size: \(name)")
}

let gifURL = directory.appendingPathComponent("sideby-demo-en.gif")
let gif = CGImageSourceCreateWithURL(gifURL as CFURL, nil)!
precondition(CGImageSourceGetCount(gif) == timeline.count, "GIF frame count differs from source timeline")
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
    precondition(abs(delay.doubleValue - (timeline[index]["seconds"] as! Double)) < 0.011,
                 "GIF timing changed at frame \(index)")
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
precondition(pixels(CGImageSourceCreateImageAtIndex(gif, 0, nil)!) == pixels(CGImageSourceCreateImageAtIndex(gif, timeline.count - 1, nil)!),
             "The GIF must return to the starting scene for a clean loop")

// Ensure both READMEs actually use all localized assets and have no broken local links.
let linkPattern = try NSRegularExpression(pattern: #"(?:\]\(|(?:src|href)=\")([^\)\"\s]+)"#)
for language in ["en", "ko"] {
    let name = language == "en" ? "README.md" : "README.ko.md"
    let body = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    for asset in expected.keys where asset.contains("-\(language).") || asset.contains("poster") {
        precondition(body.contains(asset), "\(name) does not use \(asset)")
    }
    precondition(body.contains("sideby-demo-en.gif") && body.contains("⌥⇧Tab"))
    for match in linkPattern.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
        let path = String(body[Range(match.range(at: 1), in: body)!])
        if path.hasPrefix("https:") || path.hasPrefix("http:") || path.hasPrefix("#") { continue }
        let local = path.components(separatedBy: "#")[0]
        precondition(FileManager.default.fileExists(atPath: root.appendingPathComponent(local).path), "Broken link: \(local)")
    }
}
print("Verified 9 PNGs, bilingual README links, and GIF: \(timeline.count) frames, \(String(format: "%.2f", duration)) s, \(bytes) bytes. First and last frames match.")
