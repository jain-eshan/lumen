// Cuts each pose out of a generated pose sheet into a transparent PNG, using Apple's Vision.
// Usage: swiftc -O art/cutout.swift -o /tmp/cutout && /tmp/cutout sheet.png outdir name1 name2 ...
// Poses are named in reading order (top row left to right, then the next row).
// Every frame shares one canvas and one scale, with the feet on the bottom edge, so swapping frames never jumps.
import AppKit
import Vision

let args = CommandLine.arguments
guard args.count > 3, let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("usage: cutout sheet.png outdir name1 name2 ..."); exit(1)
}
let outDir = URL(fileURLWithPath: args[2])
let names = Array(args.dropFirst(3))
let targetHeight = 240.0  // pixels for the tallest standing pose, about 120 points on a Retina screen

let handler = VNImageRequestHandler(cgImage: sheet)
let request = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([request])
guard let result = request.results?.first else { print("no subjects found"); exit(1) }

struct Pose { var image: CGImage; var box: CGRect }

// Vision may see a prop resting beside a pose (a lantern on the ground) as its own subject.
// Small subjects join the nearest large one, so each pose comes out whole.
var boxes: [Int: CGRect] = [:]
let mask = result.instanceMask
CVPixelBufferLockBaseAddress(mask, .readOnly)
let maskW = CVPixelBufferGetWidth(mask), maskH = CVPixelBufferGetHeight(mask)
let maskRow = CVPixelBufferGetBytesPerRow(mask)
let labels = CVPixelBufferGetBaseAddress(mask)!.assumingMemoryBound(to: UInt8.self)
for y in 0..<maskH { for x in 0..<maskW {
    let label = Int(labels[y * maskRow + x])
    guard label > 0 else { continue }
    boxes[label] = (boxes[label] ?? CGRect(x: x, y: y, width: 0, height: 0)).union(CGRect(x: x, y: y, width: 1, height: 1))
} }
CVPixelBufferUnlockBaseAddress(mask, .readOnly)
let areas = boxes.mapValues { $0.width * $0.height }
let typical = areas.values.sorted()[areas.count / 2]
var groups: [Int: IndexSet] = [:]
for (label, area) in areas where area >= typical * 0.35 { groups[label] = [label] }
for (label, area) in areas where area < typical * 0.35 {
    let centre = CGPoint(x: boxes[label]!.midX, y: boxes[label]!.midY)
    if let owner = groups.keys.min(by: { hypot(boxes[$0]!.midX - centre.x, boxes[$0]!.midY - centre.y) < hypot(boxes[$1]!.midX - centre.x, boxes[$1]!.midY - centre.y) }) {
        groups[owner]!.insert(label)
    }
}

var poses: [Pose] = []
for group in groups.values {
    let buffer = try result.generateMaskedImage(ofInstances: group, from: handler, croppedToInstancesExtent: false)
    let full = CIImage(cvPixelBuffer: buffer)
    guard let cg = CIContext().createCGImage(full, from: full.extent) else { continue }
    // Find the pixels this pose covers.
    let width = cg.width, height = cg.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    var minX = width, minY = height, maxX = 0, maxY = 0
    for y in 0..<height { for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 24 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    guard maxX > minX, maxY > minY else { continue }
    // Rows in the buffer run top to bottom, which is what the crop expects.
    let box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    if box.width * box.height < 2000 { continue }  // stray specks
    poses.append(Pose(image: cg.cropping(to: box)!, box: box))
}
print("found \(poses.count) poses, expected \(names.count)")
guard poses.count == names.count else { exit(2) }

// Reading order: group into rows by vertical centre, then left to right.
poses.sort { $0.box.midY < $1.box.midY }
var rows: [[Pose]] = []
for pose in poses {
    if let last = rows.last?.last, abs(last.box.midY - pose.box.midY) < last.box.height * 0.5 { rows[rows.count - 1].append(pose) } else { rows.append([pose]) }
}
let ordered = rows.flatMap { $0.sorted { $0.box.minX < $1.box.minX } }

let scale = targetHeight / Double(ordered.map(\.box.height).max()!)
let canvasW = Int((Double(ordered.map(\.box.width).max()!) * scale).rounded(.up)) + 4
let canvasH = Int(targetHeight) + 4
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (pose, name) in zip(ordered, names) {
    let w = Double(pose.image.width) * scale, h = Double(pose.image.height) * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvasW, pixelsHigh: canvasH, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    // Feet on the bottom edge, centred horizontally.
    ctx.cgContext.draw(pose.image, in: CGRect(x: (Double(canvasW) - w) / 2, y: 2, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.bitmapData!
    // Background trapped in a gap (between two antennae, say) comes out solid white.
    // Eat inward from the transparent outside through neutral, nearly pure white pixels; cream fur stops it.
    func isTrappedWhite(_ i: Int) -> Bool {
        let alpha = Double(data[i + 3])
        guard alpha >= 128 else { return false }
        let r = Double(data[i]) / alpha, g = Double(data[i + 1]) / alpha, b = Double(data[i + 2]) / alpha
        return min(r, g, b) > 0.95 && max(r, g, b) - min(r, g, b) < 0.05
    }
    var queue: [Int] = []
    for p in 0..<(canvasW * canvasH) where data[p * 4 + 3] < 128 { queue.append(p) }
    var head = 0
    while head < queue.count {
        let p = queue[head]; head += 1
        let x = p % canvasW, y = p / canvasW
        for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < canvasW && ny < canvasH {
            let n = ny * canvasW + nx
            if isTrappedWhite(n * 4) {
                for c in 0..<4 { data[n * 4 + c] = 0 }
                queue.append(n)
            }
        }
    }
    // Soft edges still carry some of the white background, which shows as a halo on dark wallpapers.
    // Fade out edge pixels that are almost pure white; cream and pale fur stays.
    for i in stride(from: 0, to: canvasW * canvasH * 4, by: 4) {
        let alpha = Double(data[i + 3])
        guard alpha > 0, alpha < 250 else { continue }
        let lightest = Double(min(data[i], data[i + 1], data[i + 2])) / alpha
        let keep = min(max((0.985 - lightest) / 0.06, 0), 1)
        for c in 0..<4 { data[i + c] = UInt8(Double(data[i + c]) * keep) }
    }
    try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("\(name).png"))
    print("\(name): \(Int(w))x\(Int(h)) on \(canvasW)x\(canvasH)")
}
