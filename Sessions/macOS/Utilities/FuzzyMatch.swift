//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// Shared subsequence fuzzy matcher used by the command palette and the
/// sidebar workspace filter.
enum FuzzyMatch {

    /// Subsequence fuzzy match score; nil when the query does not match.
    /// Bonuses for prefix, word-boundary, and consecutive matches keep
    /// "nt" ranking "New Tab" above "Find in Terminal".
    static func score(query: String, in candidate: String) -> Int? {
        if query.isEmpty { return 0 }
        let query = Array(query.lowercased())
        let candidate = Array(candidate.lowercased())
        var score = 0
        var queryIndex = 0
        var previousMatchIndex: Int?
        for (index, character) in candidate.enumerated() where queryIndex < query.count {
            guard character == query[queryIndex] else { continue }
            var characterScore = 1
            if index == 0 {
                characterScore += 3
            } else if !candidate[index - 1].isLetter && !candidate[index - 1].isNumber {
                characterScore += 2
            }
            if let previous = previousMatchIndex, index == previous + 1 {
                characterScore += 2
            }
            score += characterScore
            previousMatchIndex = index
            queryIndex += 1
        }
        return queryIndex == query.count ? score : nil
    }

    /// Whether the query fuzzy-matches the candidate at all.
    static func matches(query: String, in candidate: String) -> Bool {
        score(query: query, in: candidate) != nil
    }
}
