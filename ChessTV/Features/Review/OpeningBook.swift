import Foundation

/// A small built-in list of common opening lines, used to mark early moves as "Book".
/// `bookPlyCount(for:)` returns how many leading plies of a game follow one of the lines.
enum OpeningBook {
    /// Main lines in SAN, space separated, without check marks.
    static let lines: [String] = [
        "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O",
        "e4 e5 Nf3 Nc6 Bb5 Nf6 O-O Nxe4 d4 Nd6 Bxc6 dxc6 dxe5 Nf5",
        "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3 d6 O-O O-O",
        "e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Be7 O-O O-O Re1 d6",
        "e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5 d5 exd5 Na5",
        "e4 e5 Nf3 Nc6 d4 exd4 Nxd4 Nf6 Nxc6 bxc6 e5",
        "e4 e5 Nf3 Nc6 Nc3 Nf6 Bb5 Bb4 O-O O-O d3 d6",
        "e4 e5 Nf3 Nf6 Nxe5 d6 Nf3 Nxe4 d4 d5 Bd3",
        "e4 e5 Nf3 d6 d4 Nf6 Nc3 Nbd7 Bc4 Be7",
        "e4 e5 f4 exf4 Nf3 g5 h4 g4",
        "e4 e5 Nc3 Nf6 f4 d5 fxe5 Nxe4",
        "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6",
        "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6 Be3 Bg7 f3 O-O",
        "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 e5 Ndb5 d6",
        "e4 c5 Nf3 e6 d4 cxd4 Nxd4 a6 Bd3 Nf6 O-O",
        "e4 c5 Nc3 Nc6 g3 g6 Bg2 Bg7 d3 d6",
        "e4 c5 c3 Nf6 e5 Nd5 d4 cxd4 Nf3 Nc6",
        "e4 e6 d4 d5 Nc3 Nf6 Bg5 Be7 e5 Nfd7",
        "e4 e6 d4 d5 e5 c5 c3 Nc6 Nf3 Qb6",
        "e4 c6 d4 d5 Nc3 dxe4 Nxe4 Bf5 Ng3 Bg6 h4 h6",
        "e4 c6 d4 d5 e5 Bf5 Nf3 e6 Be2 c5",
        "e4 d5 exd5 Qxd5 Nc3 Qa5 d4 Nf6 Nf3 Bf5",
        "e4 d6 d4 Nf6 Nc3 g6 f4 Bg7 Nf3 O-O",
        "e4 Nf6 e5 Nd5 d4 d6 Nf3 Bg4 Be2 e6",
        "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3 Nbd7",
        "d4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4 Bf5",
        "d4 d5 c4 dxc4 Nf3 Nf6 e3 e6 Bxc4 c5 O-O a6",
        "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5",
        "d4 Nf6 c4 e6 Nc3 Bb4 Qc2 O-O a3 Bxc3 Qxc3",
        "d4 Nf6 c4 e6 Nf3 b6 g3 Ba6 b3 Bb4",
        "d4 Nf6 c4 c5 d5 e6 Nc3 exd5 cxd5 d6",
        "d4 d5 Bf4 Nf6 e3 c5 c3 Nc6 Nd2 e6 Ngf3",
        "d4 d5 Nf3 Nf6 e3 e6 Bd3 c5 c3 Nc6 Nbd2",
        "d4 f5 g3 Nf6 Bg2 g6 Nf3 Bg7 O-O O-O",
        "c4 e5 Nc3 Nf6 Nf3 Nc6 g3 d5 cxd5 Nxd5",
        "c4 Nf6 Nc3 e6 e4 d5 e5 d4",
        "Nf3 d5 g3 Nf6 Bg2 e6 O-O Be7 d3 O-O"
    ]

    private static let parsedLines: [[String]] = lines.map { $0.split(separator: " ").map(String.init) }

    /// Number of leading plies of `sans` that follow a book line. Check and mate marks are ignored.
    static func bookPlyCount(for sans: [String]) -> Int {
        let played = sans.map { $0.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "#", with: "") }
        var best = 0
        for line in parsedLines {
            var count = 0
            while count < min(line.count, played.count), line[count] == played[count] { count += 1 }
            best = max(best, count)
        }
        return best
    }
}
