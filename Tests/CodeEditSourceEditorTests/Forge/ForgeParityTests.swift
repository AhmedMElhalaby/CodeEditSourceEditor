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

    /// FP21: an opt-in arrows style puts a disclosure arrow on each fold's first line instead of the ribbon.
    @MainActor
    func test_foldArrowsAreOptIn() async throws {
        XCTAssertEqual(SourceEditorConfiguration.Peripherals().foldIndicatorStyle, .ribbon)
        let controller = TextViewController(
            string: "func a() {\n    if x {\n        y()\n    }\n}\n", language: .swift, configuration: Mock.config(),
            cursorPositions: [], highlightProviders: [])
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), styleMask: .borderless, backing: .buffered,
            defer: false)
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        controller.textView.layoutManager.layoutLines()
        let gutter = try XCTUnwrap(controller.gutterView)
        let ribbon = gutter.foldingRibbon
        XCTAssertEqual(ribbon.width, LineFoldRibbonView.width)
        let ribbonGutterWidth = gutter.frame.width

        controller.configuration.peripherals.foldIndicatorStyle = .arrows
        XCTAssertEqual(gutter.foldIndicatorStyle, .arrows)
        XCTAssertEqual(ribbon.width, LineFoldRibbonView.arrowsWidth)
        XCTAssertEqual(gutter.frame.width, ribbonGutterWidth + LineFoldRibbonView.arrowsWidth - LineFoldRibbonView.width)

        let model = try XCTUnwrap(ribbon.model)
        var updates = model.$foldCache.values.makeAsyncIterator()
        while model.getFolds(in: 0..<controller.textView.length).count < 2 { _ = await updates.next() }

        let layoutManager = controller.textView.layoutManager!
        let all = 0..<controller.textView.length
        XCTAssertEqual(Set(ribbon.arrowFolds(forTextRange: all, using: layoutManager).keys), [0, 1])
        let outer = try XCTUnwrap(ribbon.foldStarting(onLine: 0, layoutManager: layoutManager))
        XCTAssertEqual(outer.depth, 1)
        XCTAssertNil(ribbon.foldStarting(onLine: 2, layoutManager: layoutManager), "no arrow inside a fold")

        // Folding the outer fold leaves one ▸ arrow, and hides the inner fold's.
        model.foldCache.toggleCollapse(forFold: outer)
        let arrows = ribbon.arrowFolds(forTextRange: all, using: layoutManager)
        XCTAssertEqual(Set(arrows.keys), [0])
        XCTAssertEqual(arrows[0]?.fold.isCollapsed, true)
    }
}
