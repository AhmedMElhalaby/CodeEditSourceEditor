import XCTest
import CodeEditTextView
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
}
