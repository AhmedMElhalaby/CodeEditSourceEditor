//
//  TreeSitterClient+Temporary.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 7/24/25.
//

import AppKit
import SwiftTreeSitter
import CodeEditLanguages

extension TreeSitterClient {
    static func quickHighlight(
        string: String,
        theme: EditorTheme,
        font: NSFont,
        language: CodeLanguage
    ) -> NSAttributedString? {
        guard let parserLanguage = language.language, let query = TreeSitterModel.shared.query(for: language.id) else {
            return nil
        }

        do {
            let parser = Parser()
            try parser.setLanguage(parserLanguage)
            guard let syntaxTree = parser.parse(string) else {
                return nil
            }
            let queryCursor = query.execute(in: syntaxTree)
            let captures = queryCursor
                .resolve(with: .init(string: string))
                .flatMap { $0.captures }
            let highlights = resolveHighlights(captures) { range, _ in
                (string as NSString).substring(with: range)
            }

            let string = NSMutableAttributedString(string: string)

            for highlight in highlights {
                string.setAttributes(
                    [
                        .font: theme.fontFor(for: highlight.capture, from: font),
                        .foregroundColor: theme.colorFor(highlight.capture)
                    ],
                    range: highlight.range
                )
            }

            return string
        } catch {
            return nil
        }
    }
}
