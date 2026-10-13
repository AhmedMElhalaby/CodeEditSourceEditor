import XCTest
import CodeEditTextView
@testable import CodeEditSourceEditor

/// Opt-in looks Ainkrad Forge needs to match its mockup (design parity FP20, FP21). Each default must stay upstream's.
final class ForgeParityTests: XCTestCase {
    override func tearDown() {
        TreeSitterClient.Constants.highlightsCalls = false
    }

    /// FP20: functions, calls and properties get their own theme attributes; left `nil` they map as before.
    func test_newThemeAttributesFallBackToTodaysColours() {
        var theme = Mock.theme()
        XCTAssertEqual(theme.colorFor(.function), theme.variables.color)
        XCTAssertEqual(theme.colorFor(.method), theme.variables.color)
        XCTAssertEqual(theme.colorFor(.property), theme.variables.color)
        XCTAssertEqual(theme.colorFor(.functionCall), theme.text.color)

        theme.functions = .init(color: .systemPurple)
        theme.functionCalls = .init(color: .systemBlue)
        theme.properties = .init(color: .systemBrown)
        XCTAssertEqual(theme.colorFor(.function), .systemPurple)
        XCTAssertEqual(theme.colorFor(.method), .systemPurple)
        XCTAssertEqual(theme.colorFor(.functionCall), .systemBlue)
        XCTAssertEqual(theme.colorFor(.property), .systemBrown)
        XCTAssertEqual(theme.colorFor(.variable), theme.variables.color)
    }

    /// FP20: Swift calls stay unhighlighted unless `highlightsCalls` is on; then `HStack(...)` is a type and
    /// `.padding()` a call.
    func test_callsAreHighlightedOnlyWhenOptedIn() throws {
        let source = "HStack { Text(\"a\").padding() }"
        var theme = Mock.theme()
        theme.functionCalls = .init(color: .systemBlue)
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        func color(_ word: String) throws -> NSColor? {
            let string = try XCTUnwrap(
                TreeSitterClient.quickHighlight(string: source, theme: theme, font: font, language: .swift))
            let location = (source as NSString).range(of: word).location
            return string.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        }

        XCTAssertNil(try color("HStack"))
        XCTAssertNil(try color("padding"))

        TreeSitterClient.Constants.highlightsCalls = true
        XCTAssertEqual(try color("HStack"), theme.types.color)
        XCTAssertEqual(try color("Text"), theme.types.color)
        XCTAssertEqual(try color("padding"), .systemBlue)
    }

    /// FP20: the editor's own highlight path (text read back from the text view) makes the same call.
    @MainActor
    func test_editorHighlightsCallsWhenOptedIn() {
        let source = "HStack { x.padding() }"
        let textView = Mock.textView()
        textView.setText(source)
        let client = Mock.treeSitterClient(forceSync: true)
        client.setUp(textView: textView, codeLanguage: .swift)
        func capture(_ word: String) -> CaptureName? {
            let range = (source as NSString).range(of: word)
            return client.queryHighlightsForRange(range: NSRange(location: 0, length: source.utf16.count))
                .first { $0.range == range }?.capture
        }

        XCTAssertNil(capture("HStack"))
        XCTAssertNil(capture("padding"))
        TreeSitterClient.Constants.highlightsCalls = true
        XCTAssertEqual(capture("HStack"), .type)
        XCTAssertEqual(capture("padding"), .functionCall)
    }
}
