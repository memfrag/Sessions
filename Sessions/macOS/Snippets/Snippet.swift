//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// A reusable text snippet the user can paste into a terminal. Content may
/// contain `{{name}}` placeholders that are filled in before pasting.
struct Snippet: Codable, Identifiable, Hashable {

    let id: String

    var title: String

    var content: String

    init(id: String = UUID().uuidString, title: String = "", content: String = "") {
        self.id = id
        self.title = title
        self.content = content
    }

    /// A placeholder token, e.g. `{{host}}` or `{{port:8080}}`.
    struct Placeholder: Hashable, Identifiable {
        let name: String
        let defaultValue: String?
        var id: String { name }
    }

    /// Unique placeholders in first-seen order. Content `{{host}}:{{port:8080}}`
    /// yields `host` (no default) and `port` (default "8080").
    var placeholders: [Placeholder] {
        var seen = Set<String>()
        var result: [Placeholder] = []
        for match in Self.placeholderPattern.matches(
            in: content,
            range: NSRange(content.startIndex..., in: content)
        ) {
            guard let nameRange = Range(match.range(at: 1), in: content) else { continue }
            let name = String(content[nameRange])
            guard seen.insert(name).inserted else { continue }
            result.append(Placeholder(name: name, defaultValue: Self.defaultValue(from: match, in: content)))
        }
        return result
    }

    /// Placeholder names, in first-seen order.
    var placeholderNames: [String] {
        placeholders.map(\.name)
    }

    /// The trimmed default value from a match's second capture group, or nil.
    private static func defaultValue(from match: NSTextCheckingResult, in content: String) -> String? {
        guard match.range(at: 2).location != NSNotFound,
              let range = Range(match.range(at: 2), in: content) else {
            return nil
        }
        return String(content[range]).trimmingCharacters(in: .whitespaces)
    }

    /// `NSRange`s of every `{{name}}` token (including the braces), for
    /// highlighting in an editor.
    static func placeholderRanges(in text: String) -> [NSRange] {
        placeholderPattern
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map(\.range)
    }

    /// Substitutes every `{{name}}` / `{{name:default}}` token with its
    /// value from `values`, falling back to the token's default, then the
    /// empty string.
    static func fill(_ content: String, with values: [String: String]) -> String {
        let fullRange = NSRange(content.startIndex..., in: content)
        let result = NSMutableString(string: content)
        // Replace back-to-front so earlier ranges stay valid.
        for match in placeholderPattern.matches(in: content, range: fullRange).reversed() {
            guard let nameRange = Range(match.range(at: 1), in: content) else { continue }
            let name = String(content[nameRange])
            let value = values[name] ?? defaultValue(from: match, in: content) ?? ""
            result.replaceCharacters(in: match.range, with: value)
        }
        return result as String
    }

    /// `{{ name }}` or `{{ name : default }}` — a name of letters, digits,
    /// and underscores, plus an optional default after a colon (anything
    /// up to the closing braces). Inner whitespace is allowed.
    private static let placeholderPattern = try! NSRegularExpression(
        pattern: #"\{\{\s*([A-Za-z0-9_]+)\s*(?::([^}]*))?\}\}"#
    )
}
