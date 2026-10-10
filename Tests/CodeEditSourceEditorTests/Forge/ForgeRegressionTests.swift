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
