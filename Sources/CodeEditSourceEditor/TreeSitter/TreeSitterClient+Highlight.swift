//
//  TreeSitterClient+Highlight.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 3/10/23.
//

import Foundation
import SwiftTreeSitter
import CodeEditLanguages

extension TreeSitterClient {
    func queryHighlightsForRange(range: NSRange) -> [HighlightRange] {
        guard let state = self.state else { return [] }

        var highlights: [HighlightRange] = []
        var injectedSet = IndexSet(integersIn: range)

        for layer in state.layers where layer.id != state.primaryLayer.id {
            // Query injected only if a layer's ranges intersects with `range`
            for layerRange in layer.ranges {
                if let rangeIntersection = range.intersection(layerRange) {
                    let queryResult = queryLayerHighlights(
                        layer: layer,
                        range: rangeIntersection
                    )

                    highlights.append(contentsOf: queryResult)
                    injectedSet.remove(integersIn: rangeIntersection)
                }
            }
        }

        // Query primary for any ranges that weren't used in the injected layers.
        for range in injectedSet.rangeView {
            let queryResult = queryLayerHighlights(
                layer: state.layers[0],
                range: NSRange(range)
            )
            highlights.append(contentsOf: queryResult)
        }

        return highlights
    }

    /// Queries the given language layer for any highlights.
    /// - Parameters:
    ///   - layer: The layer to query.
    ///   - range: The range to query for.
    /// - Returns: Any ranges to highlight.
    internal func queryLayerHighlights(
        layer: LanguageLayer,
        range: NSRange
    ) -> [HighlightRange] {
        guard let tree = layer.tree,
              let rootNode = tree.rootNode else {
            return []
        }

        // This needs to be on the main thread since we're going to use the `textProvider` in
        // the `highlightsFromCursor` method, which uses the textView's text storage.
        guard let queryCursor = layer.languageQuery?.execute(node: rootNode, in: tree) else {
            return []
        }
        queryCursor.setRange(range)
        queryCursor.matchLimit =  Constants.matchLimit

        var highlights: [HighlightRange] = []

        // See https://github.com/CodeEditApp/CodeEditSourceEditor/pull/228
        if layer.id == .jsdoc {
            highlights.append(HighlightRange(range: range, capture: .comment))
        }

        highlights += highlightsFromCursor(cursor: queryCursor, includedRange: range)

        return highlights
    }

    /// Resolves a query cursor to the highlight ranges it contains.
    /// **Must be called on the main thread**
    /// - Parameters:
    ///     - cursor: The cursor to resolve.
    ///     - includedRange: The range to include highlights from.
    /// - Returns: Any highlight ranges contained in the cursor.
    internal func highlightsFromCursor(
        cursor: QueryCursor,
        includedRange: NSRange
    ) -> [HighlightRange] {
        guard let readCallback else { return [] }
        let captures = cursor
            .resolve(with: .init(textProvider: readCallback)) // Resolve our cursor against the query
            .flatMap { $0.captures }
        return Self.resolveHighlights(captures) { range, capture in
            readCallback(range, capture.node.pointRange)
        }.compactMap { highlight in
            let intersectionRange = highlight.range.intersection(includedRange) ?? .zero
            guard intersectionRange.length > 0 else { return nil }
            return HighlightRange(range: intersectionRange, capture: highlight.capture)
        }
    }

    /// Picks exactly one capture per range: the lowest capture index whose name maps to a highlight
    /// (``CaptureName/forHighlight(_:text:)``). Unmapped captures never win, so the next-best one does.
    ///
    /// Capture indices are the query's capture-name ids, in order of first appearance in `highlights.scm`.
    /// - Parameters:
    ///   - captures: The resolved captures, in the order SwiftTreeSitter returns them.
    ///   - read: Reads text for a range of a capture (only the first character is asked for).
    /// - Returns: One highlight per range, in reverse capture order (the order highlights were always applied in).
    static func resolveHighlights(
        _ captures: [QueryCapture],
        read: (NSRange, QueryCapture) -> String?
    ) -> [HighlightRange] {
        let captures = Array(captures.reversed())
        var winners: [NSRange: (index: Int, capture: CaptureName)] = [:]
        for capture in captures {
            let range = capture.range
            if let winner = winners[range], winner.index <= capture.index { continue }
            let name = CaptureName.forHighlight(capture.name) {
                read(NSRange(location: range.location, length: min(1, range.length)), capture)
            }
            if let name { winners[range] = (capture.index, name) }
        }
        return captures.compactMap { capture in
            guard let winner = winners[capture.range], winner.index == capture.index else { return nil }
            winners[capture.range] = nil // emit each range once
            return HighlightRange(range: capture.range, capture: winner.capture)
        }
    }
}
