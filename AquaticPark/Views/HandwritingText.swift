import CoreText
import SwiftUI

/// Lauren's hand. Four traced faces of the same letters, picked per character from a
/// hash of the string, so a word is never written the same way twice on screen but is
/// written the same way every time it is drawn.
///
/// The faces carry letters, digits and space — 63 glyphs, no punctuation at all. A
/// period, colon, comma or degree sign is therefore set in the printed serif at
/// `Theme.handPunctuationRatio` of the handwriting size rather than left to fall back
/// to the system face, which lands at the wrong weight and the wrong size.
struct HandwritingText: View {
    let text: String
    let size: CGFloat
    /// Defaults to the tight setting the headline sizes were tuned at. Small slots want
    /// a touch of air instead, or the loops close up.
    var tracking: CGFloat?

    var body: some View {
        Text(attributedText)
            .tracking(tracking ?? -size * 0.055)
            .padding(.horizontal, size * 0.12)
            .padding(.vertical, size * 0.08)
    }

    /// Letters and digits are everything the faces contain.
    private static func isWritten(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == " "
    }

    private var attributedText: AttributedString {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }

        return text.enumerated().reduce(into: AttributedString()) { result, item in
            let (index, character) = item
            var glyph = AttributedString(String(character))

            guard Self.isWritten(character) else {
                glyph.font = Theme.serif(size * Theme.handPunctuationRatio)
                result.append(glyph)
                return
            }

            var choice = Int((hash &+ UInt64(index) &* 2_654_435_761) % 4)
            if character.isNumber {
                // me1/me2 trace noticeably bolder and blobbier on digits than
                // me3/me4 (measured ink coverage: ~95% average vs ~78%) — numerals
                // read more consistent held to the two lighter faces.
                choice = 2 + choice % 2
            }
            if character == "W" {
                choice = 1 + choice % 3
            }
            if character == "e", choice == 3 {
                choice = Int((hash &+ UInt64(index)) % 3)
            }
            assert(character != "W" || choice != 0)

            glyph.font = .custom(Self.fontNames[choice], size: size)
            if character == "a", text.dropFirst(index + 1).first == "l" {
                glyph.kern = -size * 0.12
            }
            result.append(glyph)
        }
    }

    private static let fontNames: [String] = (1...4).map { number in
        let filename = "me\(number)"
        let url = Bundle.main.url(forResource: filename, withExtension: "ttf",
                                  subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: filename, withExtension: "ttf")
        guard let url, let provider = CGDataProvider(url: url as CFURL),
              let font = CGFont(provider),
              let postScriptName = font.postScriptName as String? else {
            assertionFailure("Missing or invalid bundled font: \(filename).ttf")
            return ".AppleSystemUIFont"
        }
        CTFontManagerRegisterGraphicsFont(font, nil)
        return postScriptName
    }
}
