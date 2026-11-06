import UIKit
import Vision

enum ScreenshotReaderError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return "That image couldn't be opened."
        }
    }
}

/// Reads a chat screenshot on the phone with Apple Vision (nothing is uploaded
/// at this step) and turns it into messages.
struct ScreenshotReader {
    func read(_ image: UIImage) async throws -> [ChatMessage] {
        try await readChat(image).messages
    }

    struct Chat {
        var messages: [ChatMessage]
        /// What the user has started replying to, from the bar above the text box.
        var replyingTo: String?
        /// The screenshot shows Coax's own screens (its app or keyboard), not a chat.
        var isCoax = false
    }

    func readChat(_ image: UIImage) async throws -> Chat {
        let lines = try await recognizeLines(in: image)
        if BubbleLayout.isCoaxScreen(lines) { return Chat(messages: [], replyingTo: nil, isCoax: true) }
        return Chat(messages: BubbleLayout.messages(from: lines), replyingTo: BubbleLayout.replyingTo(in: lines))
    }

    /// Screenshots are downscaled to this width first. Text stays readable and
    /// memory stays low enough for the keyboard, which iOS keeps on a tight budget.
    static let maxWidth: CGFloat = 900

    func recognizeLines(in original: UIImage) async throws -> [TextLine] {
        let image = Self.downscaled(original)
        guard let cgImage = image.cgImage else { throw ScreenshotReaderError.unreadableImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([request])

            let observations = request.results ?? []
            let pixels = PixelGrid(cgImage)
            return observations.compactMap { observation -> TextLine? in
                guard let best = observation.topCandidates(1).first else { return nil }
                // Vision's origin is bottom-left; flip to top-left.
                let b = observation.boundingBox
                let box = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
                var line = TextLine(text: best.string, box: box, confidence: best.confidence)
                if let pixels {
                    line.onBubble = pixels.isOnBubble(box)
                    line.isFaint = pixels.isFaintText(box)
                    if line.onBubble == true, let span = pixels.bubbleSpan(box) {
                        line.bubbleMinX = span.lowerBound
                        line.bubbleMaxX = span.upperBound
                    }
                }
                return line
            }
        }.value
    }
}

extension ScreenshotReader {
    static func downscaled(_ image: UIImage) -> UIImage {
        let width = image.size.width
        guard width > maxWidth else { return image }
        let size = CGSize(width: maxWidth, height: (image.size.height * maxWidth / width).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// The screenshot's pixels, for telling chat bubbles from the rest of the app.
/// Coordinates are normalized with the origin at the top-left, like TextLine.
struct PixelGrid {
    private let data: [UInt8]
    private let width: Int
    private let height: Int

    init?(_ image: CGImage) {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        width = w
        height = h
        data = buffer
    }

    struct RGB { var r, g, b: Double }

    /// Colour at a normalized point (top-left origin). CGContext rows run top to bottom here.
    func color(_ x: CGFloat, _ y: CGFloat) -> RGB {
        let px = min(max(Int(x * CGFloat(width)), 0), width - 1)
        let py = min(max(Int(y * CGFloat(height)), 0), height - 1)
        let i = (py * width + px) * 4
        return RGB(r: Double(data[i]) / 255, g: Double(data[i + 1]) / 255, b: Double(data[i + 2]) / 255)
    }

    static func distance(_ a: RGB, _ b: RGB) -> Double {
        max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
    }

    /// True when the space just beside the text differs from the screen's edge
    /// colour on the same row, i.e. the text sits inside a bubble.
    func isOnBubble(_ box: CGRect) -> Bool {
        let y = box.midY
        let edges = [color(0.004, y), color(0.996, y)]
        let gap: CGFloat = 0.012
        let beside = [color(box.minX - gap, y), color(box.maxX + gap, y)]
        return beside.contains { b in edges.allSatisfy { Self.distance(b, $0) > 0.03 } }
    }

    /// How far the bubble around the text reaches left and right, found by
    /// walking out from the text until the colour changes. nil if unclear.
    func bubbleSpan(_ box: CGRect) -> ClosedRange<CGFloat>? {
        let y = box.midY
        let step = 1 / CGFloat(width)
        func walk(from x: CGFloat, by dx: CGFloat) -> CGFloat {
            let fill = color(x, y)
            var edge = x
            while edge + dx > 0, edge + dx < 1, Self.distance(color(edge + dx, y), fill) < 0.06 {
                edge += dx
            }
            return edge
        }
        let gap: CGFloat = 0.012
        // Both sides must start on bubble colour, not the screen background.
        let edges = [color(0.004, y), color(0.996, y)]
        for x in [box.minX - gap, box.maxX + gap] where edges.contains(where: { Self.distance(color(x, y), $0) <= 0.03 }) {
            return nil
        }
        let left = walk(from: box.minX - gap, by: -step)
        let right = walk(from: box.maxX + gap, by: step)
        guard right > left else { return nil }
        return left...right
    }

    /// Greyed-out text: the pixels that differ most from the background are a
    /// mid, colourless grey (real message text is near black or near white).
    func isFaintText(_ box: CGRect) -> Bool {
        let background = color(box.minX - 0.006, box.midY)
        var ink = background
        var best = 0.0
        for row in 0..<7 {
            for col in 0..<40 {
                let p = color(box.minX + box.width * (CGFloat(col) + 0.5) / 40,
                              box.minY + box.height * (CGFloat(row) + 0.5) / 7)
                let d = Self.distance(p, background)
                if d > best { best = d; ink = p }
            }
        }
        guard best > 0.15 else { return false }
        let luma = 0.299 * ink.r + 0.587 * ink.g + 0.114 * ink.b
        let saturation = max(ink.r, ink.g, ink.b) - min(ink.r, ink.g, ink.b)
        return luma > 0.3 && luma < 0.75 && saturation < 0.12
    }
}
