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
        let lines = try await recognizeLines(in: image)
        return BubbleLayout.messages(from: lines)
    }

    func recognizeLines(in image: UIImage) async throws -> [TextLine] {
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
            return observations.compactMap { observation -> TextLine? in
                guard let best = observation.topCandidates(1).first else { return nil }
                // Vision's origin is bottom-left; flip to top-left.
                let b = observation.boundingBox
                let box = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
                return TextLine(text: best.string, box: box)
            }
        }.value
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
