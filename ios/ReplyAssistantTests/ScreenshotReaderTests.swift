import UIKit
import XCTest

/// Draws a fake iPhone chat screenshot and checks that on-device text
/// recognition plus the bubble layout read it back with the right speakers.
final class ScreenshotReaderTests: XCTestCase {
    private struct Bubble {
        enum Kind { case them, you, centered }
        var kind: Kind
        var text: String
    }

    /// A 1179 x 2556 image, the size of an iPhone 15 screenshot.
    private func renderChat(_ bubbles: [Bubble], extras: Bool = false) -> UIImage {
        let size = CGSize(width: 1179, height: 2556)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let small = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 40, weight: .semibold),
                         .foregroundColor: UIColor.black]
            ("9:41" as NSString).draw(at: CGPoint(x: 90, y: 50), withAttributes: small)
            ("Sam" as NSString).draw(at: CGPoint(x: 545, y: 230), withAttributes: small)

            var y: CGFloat = 400
            let maxText: CGFloat = size.width * 0.62
            for bubble in bubbles {
                let font = UIFont.systemFont(ofSize: bubble.kind == .centered ? 34 : 51)
                let color: UIColor = bubble.kind == .you ? .white : (bubble.kind == .centered ? .gray : .black)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let text = bubble.text as NSString
                let bounds = text.boundingRect(with: CGSize(width: maxText, height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
                let pad: CGFloat = 36
                let w = ceil(bounds.width) + pad * 2
                let h = ceil(bounds.height) + pad
                let x: CGFloat
                switch bubble.kind {
                case .them: x = 48
                case .you: x = size.width - 48 - w
                case .centered: x = (size.width - w) / 2
                }
                let rect = CGRect(x: x, y: y, width: w, height: h)
                if bubble.kind != .centered {
                    (bubble.kind == .you ? UIColor.systemBlue : UIColor(white: 0.9, alpha: 1)).setFill()
                    UIBezierPath(roundedRect: rect, cornerRadius: 54).fill()
                }
                text.draw(with: rect.insetBy(dx: pad, dy: pad / 2), options: [.usesLineFragmentOrigin],
                          attributes: attrs, context: nil)
                y += h + 30
            }

            guard extras else { return }
            // App text that isn't a message: a plain left-aligned prompt with no
            // bubble, and an input field with a greyed-out placeholder.
            let plain: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 46), .foregroundColor: UIColor.black]
            ("Your move, ask about her trip" as NSString).draw(at: CGPoint(x: 60, y: y + 40), withAttributes: plain)
            let field = CGRect(x: 48, y: size.height - 260, width: size.width - 96, height: 120)
            UIColor(white: 0.95, alpha: 1).setFill()
            UIBezierPath(roundedRect: field, cornerRadius: 60).fill()
            let placeholder: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 48),
                                                              .foregroundColor: UIColor(white: 0.56, alpha: 1)]
            ("Type something fun" as NSString).draw(at: CGPoint(x: 100, y: field.minY + 32), withAttributes: placeholder)
        }
    }

    private func words(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0 == " " }
    }

    func testReadsSpeakersFromAFakeScreenshot() async throws {
        let image = renderChat([
            Bubble(kind: .centered, text: "Today 9:41 PM"),
            Bubble(kind: .them, text: "are you free this weekend"),
            Bubble(kind: .you, text: "maybe, what did you have in mind"),
            Bubble(kind: .them, text: "there is a night market downtown on Saturday and I heard the dumplings are great"),
            Bubble(kind: .you, text: "ok"),
            Bubble(kind: .centered, text: "Delivered"),
        ])
        let messages = try await ScreenshotReader().read(image)

        XCTAssertEqual(messages.map(\.speaker), [.them, .you, .them, .you],
                       "Read: \(messages.map { "\($0.speaker): \($0.text)" })")
        guard messages.count == 4 else { return }
        XCTAssertTrue(words(messages[0].text).contains("free this weekend"))
        XCTAssertTrue(words(messages[2].text).contains("dumplings"), "A wrapped bubble should stay one message")
        XCTAssertFalse(messages.contains { words($0.text).contains("delivered") })
    }

    func testSkipsTextOutsideBubblesAndGreyPlaceholders() async throws {
        let image = renderChat([
            Bubble(kind: .them, text: "are you free this weekend"),
            Bubble(kind: .you, text: "maybe, what did you have in mind"),
        ], extras: true)
        let messages = try await ScreenshotReader().read(image)
        let read = messages.map { "\($0.speaker): \($0.text)" }
        XCTAssertEqual(messages.count, 2, "Read: \(read)")
        XCTAssertFalse(messages.contains { words($0.text).contains("something fun") }, "Placeholder kept: \(read)")
        XCTAssertFalse(messages.contains { words($0.text).contains("your move") }, "Bubble-less text kept: \(read)")
    }
}
