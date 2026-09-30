import Foundation

/// `chat-filter.json`: the words that the online chat hides in incoming lines.
public struct ChatFilter: Codable, Hashable, Sendable {
    /// Says what the list is, for whoever edits the file.
    public let note: String
    /// Lowercase words; a line's whole word that matches one is masked.
    public let words: [String]

    public init(note: String, words: [String]) {
        self.note = note
        self.words = words
    }

    /// The character that replaces each letter of a masked word.
    public static let maskCharacter: Character = "•"

    /// `text` with every whole word that is in `words` masked, ignoring case. A word is a run of
    /// letters and digits, so "class" and "assistant" stay whole and "damn!" loses only "damn".
    /// Lichess moderates chat on its side; this only adds a second, local layer.
    public func masked(_ text: String) -> String {
        let blocked = Set(words.map { $0.lowercased() })
        var result = ""
        var word = ""
        func flush() {
            let isBlocked = blocked.contains(word.lowercased())
            result.append(isBlocked ? String(repeating: Self.maskCharacter, count: word.count) : word)
            word = ""
        }
        for character in text {
            if character.isLetter || character.isNumber {
                word.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }

    /// Why the list is unusable, or nil: words must be non-empty, lowercase, and one word each.
    public var problem: String? {
        if note.isEmpty { return "The note is empty." }
        if words.isEmpty { return "The list has no words." }
        for word in words where word.isEmpty || word != word.lowercased() || !word.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return "\"\(word)\" is not a single lowercase word."
        }
        if Set(words).count != words.count { return "The list has a duplicate word." }
        return nil
    }
}
