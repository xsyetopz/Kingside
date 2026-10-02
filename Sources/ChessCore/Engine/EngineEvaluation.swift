/// Static evaluation: material and piece placement (kept incrementally by the board and
/// tapered between middlegame and endgame), plus pawn structure, rook files, bishop pair,
/// king shelter and a mop-up term for won endgames.
enum EngineEvaluation {
  static let middlegameValue = [0, 100, 320, 330, 480, 950, 0]
  static let endgameValue = [0, 120, 300, 320, 530, 980, 0]
  static let maxPhase = 24

  @inline(__always)
  static func phaseWeight(_ kind: Int) -> Int {
    switch kind {
    case EngineKind.knight, EngineKind.bishop: 1
    case EngineKind.rook: 2
    case EngineKind.queen: 4
    default: 0
    }
  }

  /// Placement bonus for a white piece on (file, rank); black values are mirrored.
  static func placement(kind: Int, file: Int, rank: Int) -> (middlegame: Int, endgame: Int) {
    switch kind {
    case EngineKind.pawn: pawnPlacement(file: file, rank: rank)
    case EngineKind.knight: knightPlacement(file: file, rank: rank)
    case EngineKind.bishop: bishopPlacement(file: file, rank: rank)
    case EngineKind.rook: rookPlacement(file: file, rank: rank)
    case EngineKind.queen: queenPlacement(file: file, rank: rank)
    case EngineKind.king: kingPlacement(file: file, rank: rank)
    default: (0, 0)
    }
  }

  /// Manhattan distance to the four central squares: 0 in the centre, 6 in a corner.
  private static func centreDistance(file: Int, rank: Int) -> Int {
    (abs(2 * file - 7) + abs(2 * rank - 7)) / 2 - 1
  }

  /// 0 for the d and e files, 3 for the a and h files.
  private static func fileCentreDistance(_ file: Int) -> Int { abs(2 * file - 7) / 2 }

  /// Pawn advance bonus by rank.
  private static let pawnAdvanceMiddlegame = [0, 0, 4, 10, 20, 34, 55, 0]
  private static let pawnAdvanceEndgame = [0, 0, 6, 14, 28, 50, 85, 0]
  /// Middlegame bonus for a pawn on the fourth or fifth rank, indexed by 2 minus its file's
  /// distance from the centre files (clamped at 0).
  private static let centralPawnBonus = [0, 6, 12]
  /// A d or e pawn still on its second rank blocks the bishops.
  private static let unmovedCentrePawnPenalty = 8

  private static func pawnPlacement(file: Int, rank: Int) -> (middlegame: Int, endgame: Int) {
    let fileCentre = fileCentreDistance(file)
    var middle = pawnAdvanceMiddlegame[rank]
    if rank == 3 || rank == 4 { middle += centralPawnBonus[max(0, 2 - fileCentre)] }
    if rank == 1 && fileCentre == 0 { middle -= unmovedCentrePawnPenalty }
    return (middle, pawnAdvanceEndgame[rank])
  }

  /// Penalty for a minor piece left on its first rank, which delays development.
  private static let knightBackRankPenalty = 8
  private static let bishopBackRankPenalty = 6
  private static let bishopLongDiagonalBonus = 6

  /// Knights lose value quickly away from the centre.
  private static func knightPlacement(file: Int, rank: Int) -> (middlegame: Int, endgame: Int) {
    let centre = centreDistance(file: file, rank: rank)
    let backRank = rank == 0 ? knightBackRankPenalty : 0
    return (12 - 8 * centre - backRank, 10 - 6 * centre)
  }

  private static func bishopPlacement(file: Int, rank: Int) -> (middlegame: Int, endgame: Int) {
    let centre = centreDistance(file: file, rank: rank)
    let longDiagonal = file == rank || file + rank == 7 ? bishopLongDiagonalBonus : 0
    let backRank = rank == 0 ? bishopBackRankPenalty : 0
    return (8 - 4 * centre + longDiagonal - backRank, 6 - 4 * centre)
  }

  private static let rookSeventhRankMiddlegame = 18
  private static let rookSeventhRankEndgame = 12
  private static let rookCentreFileBonus = 6
  /// Rook on an a or h file off its first rank.
  private static let rookEdgeFilePenalty = 4

  private static func rookPlacement(file: Int, rank: Int) -> (middlegame: Int, endgame: Int) {
    let fileCentre = fileCentreDistance(file)
    var middle = rank == 6 ? rookSeventhRankMiddlegame : 0
    if fileCentre == 0 { middle += rookCentreFileBonus }
    if fileCentre == 3 && rank > 0 { middle -= rookEdgeFilePenalty }
    return (middle, rank == 6 ? rookSeventhRankEndgame : 0)
  }

  /// Penalty for a queen on one of the two outer ranks at either end of the board.
  private static let queenOuterRankPenalty = 2

  private static func queenPlacement(file: Int, rank: Int) -> (middlegame: Int, endgame: Int) {
    let centre = centreDistance(file: file, rank: rank)
    let outerRank = rank > 1 && rank < 6 ? 0 : queenOuterRankPenalty
    return (4 - 2 * centre - outerRank, 8 - 4 * centre)
  }

  /// Middlegame king safety: stay on the first rank, preferably on a castled wing.
  private static let kingRankMiddlegame = [0, -18, -36, -50, -60, -64, -64, -64]
  private static let kingFileMiddlegame = [12, 18, 6, -8, -8, 6, 18, 12]

  /// In the endgame the king belongs in the centre.
  private static func kingPlacement(file: Int, rank: Int) -> (middlegame: Int, endgame: Int) {
    let centre = centreDistance(file: file, rank: rank)
    return (kingRankMiddlegame[rank] + kingFileMiddlegame[file], 24 - 8 * centre)
  }

  /// Passed pawn bonus by rank, counted from the pawn owner's side.
  static let passedMiddlegame = [0, 5, 10, 16, 26, 42, 64, 0]
  static let passedEndgame = [0, 10, 18, 32, 54, 86, 124, 0]
  /// No friendly pawn on either neighbouring file.
  static let isolatedPawnPenalty = (middlegame: 12, endgame: 16)
  /// Charged once per pawn on a file that holds more than one friendly pawn.
  static let doubledPawnPenalty = (middlegame: 6, endgame: 12)
  /// Rook on a file with no pawns at all.
  static let rookOpenFileBonus = (middlegame: 22, endgame: 10)
  /// Rook on a file with opponent pawns only.
  static let rookHalfOpenFileBonus = (middlegame: 10, endgame: 6)
  static let bishopPairBonus = (middlegame: 30, endgame: 50)
  /// Bonus for having the move.
  static let tempoBonus = 10

  /// Shelter pawn directly in front of the king or of a square beside it.
  static let shelterPawnNearBonus = 14
  /// Shelter pawn two squares in front instead.
  static let shelterPawnFarBonus = 7
  static let shelterPawnMissingPenalty = 12
  /// King off its first two ranks has no pawn shelter.
  static let exposedKingPenalty = 20

  /// Mop-up applies only beyond this score, in centipawns.
  static let mopUpThreshold = 350
  static let mopUpEdgeWeight = 10
  static let mopUpProximityWeight = 4
  /// Largest Manhattan distance between two squares.
  static let maxKingDistance = 14
}

/// Layout of the scratch buffer that `evaluate` fills in its first pass over the board.
private enum PawnScratch {
  /// Pawns per file, 8 entries for each color.
  static let whitePawns = 0
  static let blackPawns = 8
  /// Rank of the lowest white pawn per file, 8 when none.
  static let lowestWhitePawnRank = 16
  /// Rank of the highest black pawn per file, -1 when none.
  static let highestBlackPawnRank = 24
  /// Squares of pawns and rooks scored in the second pass.
  static let listed = 40
  static let maxListed = 40
  static let capacity = listed + maxListed
}

extension EngineBoard {
  /// Static score from the side to move's point of view, in centipawns.
  func evaluate() -> Int {
    var middle = middlegame
    var end = endgame

    withUnsafeTemporaryAllocation(of: Int.self, capacity: PawnScratch.capacity) { buffer in
      let scratch = buffer.baseAddress!
      let listed = tallyPawnsAndRooks(into: scratch)
      for index in 0..<listed {
        let square = scratch[PawnScratch.listed + index]
        if squares[square] & EngineKind.mask == EngineKind.rook {
          addRookFile(square, scratch: scratch, middle: &middle, end: &end)
        } else {
          addPawnStructure(square, scratch: scratch, middle: &middle, end: &end)
        }
      }
    }

    addBishopPair(middle: &middle, end: &end)
    // King shelter: pawns directly in front of a king still on its first two ranks.
    middle += kingShelter(color: 0) - kingShelter(color: 1)

    var score = tapered(middle: middle, end: end)
    score += mopUp(score)
    return (side == 0 ? score : -score) + EngineEvaluation.tempoBonus
  }

  /// Fills the pawn counts and extreme pawn ranks per file in `scratch` and lists the squares of
  /// pawns and rooks after them (see `PawnScratch`). Returns how many squares it listed.
  @inline(__always)
  private func tallyPawnsAndRooks(into scratch: UnsafeMutablePointer<Int>) -> Int {
    for file in 0..<8 {
      scratch[PawnScratch.whitePawns + file] = 0
      scratch[PawnScratch.blackPawns + file] = 0
      scratch[PawnScratch.lowestWhitePawnRank + file] = 8
      scratch[PawnScratch.highestBlackPawnRank + file] = -1
    }
    var listed = 0
    var square = 0
    while square < 128 {
      if square & 0x88 != 0 { square += 8; continue }
      let piece = squares[square]
      let kind = piece & EngineKind.mask
      if kind == EngineKind.pawn { tallyPawn(piece, at: square, scratch: scratch) }
      if kind == EngineKind.pawn || kind == EngineKind.rook, listed < PawnScratch.maxListed {
        scratch[PawnScratch.listed + listed] = square
        listed += 1
      }
      square += 1
    }
    return listed
  }

  @inline(__always)
  private func tallyPawn(_ piece: Int, at square: Int, scratch: UnsafeMutablePointer<Int>) {
    let file = square & 7, rank = square >> 4
    if piece & EngineKind.blackBit == 0 {
      scratch[PawnScratch.whitePawns + file] += 1
      let lowest = PawnScratch.lowestWhitePawnRank + file
      scratch[lowest] = min(scratch[lowest], rank)
    } else {
      scratch[PawnScratch.blackPawns + file] += 1
      let highest = PawnScratch.highestBlackPawnRank + file
      scratch[highest] = max(scratch[highest], rank)
    }
  }

  /// Isolated, doubled and passed pawn terms for the pawn on `square`.
  @inline(__always)
  private func addPawnStructure(
    _ square: Int,
    scratch: UnsafeMutablePointer<Int>,
    middle: inout Int,
    end: inout Int
  ) {
    let file = square & 7, rank = square >> 4
    let black = squares[square] & EngineKind.blackBit != 0
    let sign = black ? -1 : 1
    let own = black ? PawnScratch.blackPawns : PawnScratch.whitePawns
    let left = file > 0 ? scratch[own + file - 1] : 0
    let right = file < 7 ? scratch[own + file + 1] : 0
    if left + right == 0 {
      middle -= sign * EngineEvaluation.isolatedPawnPenalty.middlegame
      end -= sign * EngineEvaluation.isolatedPawnPenalty.endgame
    }
    if scratch[own + file] > 1 {
      middle -= sign * EngineEvaluation.doubledPawnPenalty.middlegame
      end -= sign * EngineEvaluation.doubledPawnPenalty.endgame
    }
    if isPassedPawn(file: file, rank: rank, black: black, scratch: scratch) {
      let relative = black ? 7 - rank : rank
      middle += sign * EngineEvaluation.passedMiddlegame[relative]
      end += sign * EngineEvaluation.passedEndgame[relative]
    }
  }

  /// Whether no opponent pawn on this or a neighbouring file stands ahead of the pawn.
  @inline(__always)
  private func isPassedPawn(
    file: Int,
    rank: Int,
    black: Bool,
    scratch: UnsafeMutablePointer<Int>
  ) -> Bool {
    for adjacent in max(0, file - 1)...min(7, file + 1)
    where black
      ? scratch[PawnScratch.lowestWhitePawnRank + adjacent] < rank
      : scratch[PawnScratch.highestBlackPawnRank + adjacent] > rank
    {
      return false
    }
    return true
  }

  /// Open and half-open file terms for the rook on `square`.
  @inline(__always)
  private func addRookFile(
    _ square: Int,
    scratch: UnsafeMutablePointer<Int>,
    middle: inout Int,
    end: inout Int
  ) {
    let file = square & 7
    let black = squares[square] & EngineKind.blackBit != 0
    let sign = black ? -1 : 1
    let own = black ? PawnScratch.blackPawns : PawnScratch.whitePawns
    let pawns = scratch[PawnScratch.whitePawns + file] + scratch[PawnScratch.blackPawns + file]
    if pawns == 0 {
      middle += sign * EngineEvaluation.rookOpenFileBonus.middlegame
      end += sign * EngineEvaluation.rookOpenFileBonus.endgame
    } else if scratch[own + file] == 0 {
      middle += sign * EngineEvaluation.rookHalfOpenFileBonus.middlegame
      end += sign * EngineEvaluation.rookHalfOpenFileBonus.endgame
    }
  }

  @inline(__always)
  private func addBishopPair(middle: inout Int, end: inout Int) {
    let bonus = EngineEvaluation.bishopPairBonus
    if counts[EngineKind.bishop] >= 2 {
      middle += bonus.middlegame
      end += bonus.endgame
    }
    if counts[EngineKind.bishop | EngineKind.blackBit] >= 2 {
      middle -= bonus.middlegame
      end -= bonus.endgame
    }
  }

  /// Blends the middlegame and endgame scores by the material left on the board (`phase`).
  @inline(__always)
  private func tapered(middle: Int, end: Int) -> Int {
    let maxPhase = EngineEvaluation.maxPhase
    let phase = min(self.phase, maxPhase)
    return (middle * phase + end * (maxPhase - phase)) / maxPhase
  }

  private func kingShelter(color: Int) -> Int {
    let king = kings[color]
    let relativeRank = color == 0 ? king >> 4 : 7 - (king >> 4)
    guard relativeRank <= 1 else { return -EngineEvaluation.exposedKingPenalty }
    let pawn = EngineKind.pawn | color << 3
    let forward = color == 0 ? 16 : -16
    var score = 0
    for fileStep in -1...1 {
      let base = king + fileStep
      guard base & 0x88 == 0 else { continue }
      let near = base + forward, far = base + 2 * forward
      if near & 0x88 == 0 && squares[near] == pawn {
        score += EngineEvaluation.shelterPawnNearBonus
      } else if far & 0x88 == 0 && squares[far] == pawn {
        score += EngineEvaluation.shelterPawnFarBonus
      } else {
        score -= EngineEvaluation.shelterPawnMissingPenalty
      }
    }
    return score
  }

  /// Drives the losing king to the edge and brings the winning king closer when one side
  /// has no pawns left and is clearly behind, so won endgames get converted.
  private func mopUp(_ score: Int) -> Int {
    guard abs(score) > EngineEvaluation.mopUpThreshold else { return 0 }
    let loser = score > 0 ? 1 : 0
    guard counts[EngineKind.pawn | loser << 3] == 0 else { return 0 }
    let losingKing = kings[loser], winningKing = kings[loser ^ 1]
    let file = losingKing & 7, rank = losingKing >> 4
    let edge = (abs(2 * file - 7) + abs(2 * rank - 7)) / 2
    let distance = abs(file - (winningKing & 7)) + abs(rank - (winningKing >> 4))
    let bonus =
      EngineEvaluation.mopUpEdgeWeight * edge
      + EngineEvaluation.mopUpProximityWeight * (EngineEvaluation.maxKingDistance - distance)
    return score > 0 ? bonus : -bonus
  }
}
