import Foundation

/// Static evaluation: material and piece placement (kept incrementally by the board and
/// tapered between middlegame and endgame), plus pawn structure, rook files, bishop pair,
/// king shelter and a mop-up term for won endgames.
enum EngineEvaluation {
    static let middlegameValue = [0, 100, 320, 330, 480, 950, 0]
    static let endgameValue = [0, 120, 300, 320, 530, 980, 0]
    static let maxPhase = 24

    @inline(__always) static func phaseWeight(_ kind: Int) -> Int {
        switch kind {
        case EngineKind.knight, EngineKind.bishop: 1
        case EngineKind.rook: 2
        case EngineKind.queen: 4
        default: 0
        }
    }

    /// Placement bonus for a white piece on (file, rank); black values are mirrored.
    static func placement(kind: Int, file: Int, rank: Int) -> (middlegame: Int, endgame: Int) {
        // Manhattan distance to the four central squares: 0 in the centre, 6 in a corner.
        let centre = (abs(2 * file - 7) + abs(2 * rank - 7)) / 2 - 1
        let fileCentre = abs(2 * file - 7) / 2  // 0 for d/e files, 3 for a/h files
        switch kind {
        case EngineKind.pawn:
            let advance = [0, 0, 4, 10, 20, 34, 55, 0][rank]
            let endAdvance = [0, 0, 6, 14, 28, 50, 85, 0][rank]
            var middle = advance
            if rank == 3 || rank == 4 { middle += [0, 6, 12][max(0, 2 - fileCentre)] }
            if rank == 1 && fileCentre == 0 { middle -= 8 }
            return (middle, endAdvance)
        case EngineKind.knight:
            return (12 - 8 * centre - (rank == 0 ? 8 : 0), 10 - 6 * centre)
        case EngineKind.bishop:
            let long = file == rank || file + rank == 7 ? 6 : 0
            return (8 - 4 * centre + long - (rank == 0 ? 6 : 0), 6 - 4 * centre)
        case EngineKind.rook:
            let seventh = rank == 6 ? 18 : 0
            return (seventh + (fileCentre == 0 ? 6 : 0) - (fileCentre == 3 && rank > 0 ? 4 : 0), rank == 6 ? 12 : 0)
        case EngineKind.queen:
            return (4 - 2 * centre - (rank > 1 && rank < 6 ? 0 : 2), 8 - 4 * centre)
        case EngineKind.king:
            let rankPenalty = [0, -18, -36, -50, -60, -64, -64, -64][rank]
            let fileBonus = [12, 18, 6, -8, -8, 6, 18, 12][file]
            return (rankPenalty + fileBonus, 24 - 8 * centre)
        default:
            return (0, 0)
        }
    }

    static let passedMiddlegame = [0, 5, 10, 16, 26, 42, 64, 0]
    static let passedEndgame = [0, 10, 18, 32, 54, 86, 124, 0]
}

extension EngineBoard {
    /// Static score from the side to move's point of view, in centipawns.
    func evaluate() -> Int {
        var middle = middlegame
        var end = endgame

        withUnsafeTemporaryAllocation(of: Int.self, capacity: 80) { scratch in
            let s = scratch.baseAddress!
            // 0..<8 white pawns per file, 8..<16 black pawns per file,
            // 16..<24 lowest white pawn rank per file, 24..<32 highest black pawn rank per file,
            // 40..<80 squares of pawns and rooks for the second pass.
            for file in 0..<8 {
                s[file] = 0
                s[8 + file] = 0
                s[16 + file] = 8
                s[24 + file] = -1
            }
            var listed = 0
            var square = 0
            while square < 128 {
                if square & 0x88 != 0 { square += 8; continue }
                let piece = squares[square]
                let kind = piece & 7
                if kind == EngineKind.pawn {
                    let file = square & 7, rank = square >> 4
                    if piece & EngineKind.blackBit == 0 {
                        s[file] += 1
                        s[16 + file] = min(s[16 + file], rank)
                    } else {
                        s[8 + file] += 1
                        s[24 + file] = max(s[24 + file], rank)
                    }
                    if listed < 40 { s[40 + listed] = square; listed += 1 }
                } else if kind == EngineKind.rook, listed < 40 {
                    s[40 + listed] = square
                    listed += 1
                }
                square += 1
            }

            for index in 0..<listed {
                let square = s[40 + index]
                let piece = squares[square]
                let file = square & 7, rank = square >> 4
                let black = piece & EngineKind.blackBit != 0
                let sign = black ? -1 : 1
                let own = black ? 8 : 0
                if piece & 7 == EngineKind.rook {
                    if s[file] + s[8 + file] == 0 {
                        middle += sign * 22; end += sign * 10
                    } else if s[own + file] == 0 {
                        middle += sign * 10; end += sign * 6
                    }
                    continue
                }
                let left = file > 0 ? s[own + file - 1] : 0
                let right = file < 7 ? s[own + file + 1] : 0
                if left + right == 0 { middle -= sign * 12; end -= sign * 16 }
                if s[own + file] > 1 { middle -= sign * 6; end -= sign * 12 }
                var passed = true
                for adjacent in max(0, file - 1)...min(7, file + 1) {
                    if black ? s[16 + adjacent] < rank : s[24 + adjacent] > rank { passed = false; break }
                }
                if passed {
                    let relative = black ? 7 - rank : rank
                    middle += sign * EngineEvaluation.passedMiddlegame[relative]
                    end += sign * EngineEvaluation.passedEndgame[relative]
                }
            }
        }

        // Bishop pair.
        if counts[EngineKind.bishop] >= 2 { middle += 30; end += 50 }
        if counts[EngineKind.bishop | EngineKind.blackBit] >= 2 { middle -= 30; end -= 50 }

        // King shelter: pawns directly in front of a king still on its first two ranks.
        middle += kingShelter(color: 0) - kingShelter(color: 1)

        let phase = min(self.phase, EngineEvaluation.maxPhase)
        var score = (middle * phase + end * (EngineEvaluation.maxPhase - phase)) / EngineEvaluation.maxPhase
        score += mopUp(score)
        return (side == 0 ? score : -score) + 10
    }

    private func kingShelter(color: Int) -> Int {
        let king = kings[color]
        let relativeRank = color == 0 ? king >> 4 : 7 - (king >> 4)
        guard relativeRank <= 1 else { return -20 }
        let pawn = EngineKind.pawn | color << 3
        let forward = color == 0 ? 16 : -16
        var score = 0
        for fileStep in -1...1 {
            let base = king + fileStep
            guard base & 0x88 == 0 else { continue }
            let near = base + forward, far = base + 2 * forward
            if near & 0x88 == 0 && squares[near] == pawn { score += 14 }
            else if far & 0x88 == 0 && squares[far] == pawn { score += 7 }
            else { score -= 12 }
        }
        return score
    }

    /// Drives the losing king to the edge and brings the winning king closer when one side
    /// has no pawns left and is clearly behind, so won endgames get converted.
    private func mopUp(_ score: Int) -> Int {
        guard abs(score) > 350 else { return 0 }
        let loser = score > 0 ? 1 : 0
        guard counts[EngineKind.pawn | loser << 3] == 0 else { return 0 }
        let losingKing = kings[loser], winningKing = kings[loser ^ 1]
        let file = losingKing & 7, rank = losingKing >> 4
        let edge = (abs(2 * file - 7) + abs(2 * rank - 7)) / 2
        let distance = abs(file - (winningKing & 7)) + abs(rank - (winningKing >> 4))
        let bonus = 10 * edge + 4 * (14 - distance)
        return score > 0 ? bonus : -bonus
    }
}
