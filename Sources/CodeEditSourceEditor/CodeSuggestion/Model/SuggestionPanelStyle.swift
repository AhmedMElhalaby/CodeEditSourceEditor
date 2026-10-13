//
//  SuggestionPanelStyle.swift
//  CodeEditSourceEditor
//

import AppKit

/// How the completion panel draws, independent of the editor's background (which may be transparent).
/// Set it on ``SourceEditorConfiguration/Appearance/suggestionPanelStyle``; when nil the panel keeps its default
/// look (window background, a divider above the preview, selection in the theme background).
public struct SuggestionPanelStyle: Equatable, Sendable {
    /// The panel's fill, the preview footer included. No divider is drawn.
    public var background: NSColor
    /// The fill behind the selected row.
    public var selectedRowBackground: NSColor
    /// The panel's corner radius.
    public var cornerRadius: CGFloat

    public init(background: NSColor, selectedRowBackground: NSColor, cornerRadius: CGFloat) {
        self.background = background
        self.selectedRowBackground = selectedRowBackground
        self.cornerRadius = cornerRadius
    }
}
