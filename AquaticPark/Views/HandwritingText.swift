import CoreText
import SwiftUI

struct HandwritingText: View {
    let text: String
    let size: CGFloat

    var body: some View {
        Text(attributedText)
            .tracking(-size * 0.055)
            .padding(.horizontal, size * 0.12)
            .padding(.vertical, size * 0.08)
    }

    private var attributedText: AttributedString {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }

        var result = text.enumerated().reduce(into: AttributedString()) { result, item in
            let (index, character) = item
            var choice = Int((hash &+ UInt64(index) &* 2_654_435_761) % 4)
            if character == "W" { choice = 1 + choice % 3 }
            if character == "e", choice == 3 { choice = Int((hash &+ UInt64(index)) % 3) }
            assert(character != "W" || choice != 0)
            var glyph = AttributedString(String(character))
            glyph.font = .custom(Self.fontNames[choice], size: size)
            if character == "a", text.dropFirst(index + 1).first == "l" {
                glyph.kern = -size * 0.12
            }
            result.append(glyph)
        }
        return result
    }

    private static let fontNames: [String] = (1...4).map { number in
        let filename = "me\(number)"
        let url = Bundle.main.url(forResource: filename, withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: filename, withExtension: "ttf")
        guard let url,
              let provider = CGDataProvider(url: url as CFURL),
              let font = CGFont(provider),
              let postScriptName = font.postScriptName as String? else {
            assertionFailure("Missing or invalid bundled font: \(filename).ttf")
            return ".AppleSystemUIFont"
        }
        CTFontManagerRegisterGraphicsFont(font, nil)
        return postScriptName
    }
}
