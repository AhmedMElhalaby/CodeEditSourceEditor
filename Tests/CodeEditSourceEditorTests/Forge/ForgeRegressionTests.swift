import XCTest
@testable import CodeEditTextView
@testable import CodeEditSourceEditor

/// Regressions found by Ainkrad Forge's E1 spike.
final class ForgeRegressionTests: XCTestCase {
    private var maxSyncContentLength: Int = 0

    override func setUp() {
        // Every document counts as long, so edits take the async path.
        maxSyncContentLength = TreeSitterClient.Constants.maxSyncContentLength
        TreeSitterClient.Constants.maxSyncContentLength = 0
    }

    override func tearDown() {
        TreeSitterClient.Constants.maxSyncContentLength = maxSyncContentLength
    }

    /// `applyEdit`'s completion is `@MainActor`, but the async path called it on the executor thread, racing
    /// `HighlightProviderState`'s `IndexSet` (EXC_BAD_ACCESS while typing in large files).
    @MainActor
    func test_asyncEditCompletesOnMainThread() async {
        let client = Mock.treeSitterClient()
        let textView = Mock.textView()
        client.setUp(textView: textView, codeLanguage: .swift)
        while client.state == nil { try? await Task.sleep(for: .milliseconds(50)) }

        let done = XCTestExpectation(description: "edit completes")
        var onMain = false
        textView.replaceString(in: NSRange(location: 0, length: 0), with: "let x = 1\n")
        client.applyEdit(textView: textView, range: NSRange(location: 0, length: 0), delta: 10) { _ in
            onMain = Thread.isMainThread
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertTrue(onMain)
    }

    /// The suggestion window took its screen from its own frame, so once it sat off-screen (`screen == nil`)
    /// positioning bailed out and every later completion opened off-screen (Forge E0, FD3).
    @MainActor
    func test_offScreenSuggestionWindowIsBroughtBackToTheCursor() throws {
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let controller = SuggestionController()
        let window = try XCTUnwrap(controller.window)
        window.setFrame(NSRect(x: screen.minX + 100, y: screen.minY - 5_000, width: 300, height: 200), display: false)
        XCTAssertNil(window.screen)

        let cursor = NSRect(x: screen.midX, y: screen.midY, width: 1, height: 16)
        controller.constrainWindowToScreenEdges(cursorRect: cursor, font: .monospacedSystemFont(ofSize: 12, weight: .regular))

        XCTAssertTrue(screen.contains(window.frame), "\(window.frame) is not on \(screen)")
        XCTAssertEqual(window.frame.maxY, cursor.minY, accuracy: 0.5, "drops down from the cursor")
    }

    /// `MinimapView.setTheme` read `brightnessComponent` straight off the background, which throws for a
    /// gray-colourspace colour such as `NSColor.clear` (a transparent editor over a glass window).
    @MainActor
    func test_clearThemeBackgroundDoesNotThrow() {
        var theme = Mock.theme()
        theme.background = .clear
        let minimap = MinimapView(textView: Mock.textView(), theme: theme)
        minimap.setTheme(theme)
    }

    /// A ⌘-click with no ⌘-hover before it (the editor had no focus) jumped nowhere: only a hovered range was
    /// ever jumped from (Forge FD24). The click itself now resolves the identifier under it.
    @MainActor
    func test_commandClickWithoutHoverJumpsFromTheIdentifierUnderTheClick() async throws {
        let controller = TextViewController(
            string: "func greet() {}\ngreet()\n", language: .swift, configuration: Mock.config(),
            cursorPositions: [], highlightProviders: [TreeSitterClient()])
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), styleMask: .borderless, backing: .buffered,
            defer: false)
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        controller.textView.layoutManager.layoutLines()
        let links = LinkRecorder()
        controller.jumpToDefinitionDelegate = links
        let client = try XCTUnwrap(controller.treeSitterClient)
        while client.state == nil { try await Task.sleep(for: .milliseconds(50)) }

        let call = NSRange(location: 16, length: 5)  // `greet` on line 2
        let textView = try XCTUnwrap(controller.textView)
        let rect = try XCTUnwrap(textView.layoutManager.rectsFor(range: call).first)
        XCTAssertNotNil(controller.jumpToDefinitionModel.treeSitterClient, "the model must get the controller's client")
        controller.jumpToDefinitionModel.jump(atWindowPoint: textView.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil))

        for _ in 0..<100 where links.queried.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(links.queried, [call])
    }

    /// The completion panel painted the window background with a divider above its footer, and selected rows in
    /// the editor background — invisible over a transparent editor (Forge FD5). A `SuggestionPanelStyle` now
    /// paints it; without one it keeps the default look.
    @MainActor
    func test_suggestionPanelFollowsItsStyle() throws {
        let panel = SuggestionViewController()
        _ = panel.view
        XCTAssertEqual(panel.view.layer?.backgroundColor, NSColor.windowBackgroundColor.cgColor)
        XCTAssertFalse(panel.previewView.dividerView.isHidden)

        let style = SuggestionPanelStyle(
            background: NSColor(srgbRed: 0.1, green: 0.1, blue: 0.2, alpha: 0.9),
            selectedRowBackground: NSColor(srgbRed: 0.9, green: 0.2, blue: 0.6, alpha: 0.2), cornerRadius: 12)
        var config = Mock.config()
        config.appearance.suggestionPanelStyle = style
        let controller = TextViewController(
            string: "", language: .swift, configuration: config, cursorPositions: [], highlightProviders: [])
        let model = SuggestionViewModel()
        model.activeTextView = controller
        panel.model = model
        panel.styleView(using: controller)

        XCTAssertEqual(panel.view.layer?.backgroundColor, style.background.cgColor)
        XCTAssertEqual(panel.view.layer?.cornerRadius, 12)
        XCTAssertEqual(panel.tintView.layer?.backgroundColor, .clear)
        XCTAssertTrue(panel.previewView.dividerView.isHidden)
        XCTAssertTrue(panel.previewView.materialView.isHidden)
        let row = try XCTUnwrap(panel.tableView(panel.tableView, rowViewForRow: 0) as? CodeSuggestionRowView)
        XCTAssertEqual(row.getSelectionColor?(), style.selectedRowBackground)
    }

    /// The minimap measured a wrapped row's offsets from its CTLine's location (the row's start in the line), not
    /// from the row itself, so a selection on any row after the first drew left of the minimap (Forge FD64).
    @MainActor
    func test_minimapXPositionOnAWrappedRowCountsFromTheRow() throws {
        let line = TextLine()
        let text = NSTextStorage(string: String(repeating: "let value = 1; ", count: 20))
        line.prepareForDisplay(
            displayData: TextLine.DisplayData(maxWidth: 200, lineHeightMultiplier: 1, estimatedLineHeight: 15),
            range: NSRange(location: 0, length: text.length),
            stringRef: text,
            markedRanges: nil,
            attachments: []
        )
        let rows = Array(line.lineFragments)
        XCTAssertGreaterThan(rows.count, 2)
        let renderer = MinimapLineRenderer(textView: Mock.textView())
        XCTAssertEqual(renderer.characterXPosition(in: rows[2].data, for: 0), 8)
        XCTAssertEqual(renderer.characterXPosition(in: rows[2].data, for: 4), 8 + 4 * 1.5)
    }
}

private final class LinkRecorder: JumpToDefinitionDelegate {
    var queried: [NSRange] = []
    func queryLinks(forRange range: NSRange, textView: TextViewController) async -> [JumpToDefinitionLink]? {
        queried.append(range)
        return nil
    }
    func openLink(link: JumpToDefinitionLink) {}
}
