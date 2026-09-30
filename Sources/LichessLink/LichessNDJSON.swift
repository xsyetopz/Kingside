import Foundation

/// Line-level parsing for Lichess NDJSON streams. Pure, so it needs no network.
enum LichessNDJSON {
    private struct Envelope: Decodable {
        var type: String?
    }

    /// Returns `nil` for a keep-alive (blank) line and for a line whose `type` is missing or unknown.
    /// `decode` maps a known type to its event, and returns `nil` for an unknown type.
    static func parse<Event>(line: String, decode: (String, Data, JSONDecoder) throws -> Event?) throws -> Event? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let data = Data(trimmed.utf8)
        let decoder = JSONDecoder()
        do {
            guard let type = try decoder.decode(Envelope.self, from: data).type else { return nil }
            return try decode(type, data, decoder)
        } catch {
            throw LichessError.decoding(String(describing: error))
        }
    }
}
