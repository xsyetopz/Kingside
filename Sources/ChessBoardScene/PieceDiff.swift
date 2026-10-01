import ChessCore

/// How the pieces change between two boards. A piece that leaves a square slides to a square
/// where the same piece appears: the last move first (which may promote), then the nearest
/// match, so castling moves both king and rook. Pieces left over fade out or appear in place.
struct PieceDiff: Equatable {
  /// A piece that slides from `from` to `to`, where it becomes `piece` (a promotion changes it).
  struct Move: Hashable {
    let from: Square
    let to: Square
    let piece: Piece
  }

  private(set) var moved: Set<Move> = []
  private(set) var added: [Square: Piece] = [:]
  private(set) var removed: Set<Square> = []

  init(old: [Square: Piece], new: [Square: Piece], lastMove: ChessMove?) {
    var vacated = old.filter { new[$0.key] != $0.value }
    var appeared = new.keys.filter { old[$0] != new[$0] }.sorted()
    if let move = lastMove, let index = appeared.firstIndex(of: move.to),
      let piece = vacated[move.from], let landed = new[move.to], piece.color == landed.color
    {
      vacated[move.from] = nil
      appeared.remove(at: index)
      moved.insert(Move(from: move.from, to: move.to, piece: landed))
    }
    for square in appeared {
      guard let piece = new[square] else { continue }
      let match = vacated.filter { $0.value == piece }.min { lhs, rhs in
        let (left, right) = (Self.distance(lhs.key, square), Self.distance(rhs.key, square))
        return left != right ? left < right : lhs.key < rhs.key
      }
      if let match {
        vacated[match.key] = nil
        moved.insert(Move(from: match.key, to: square, piece: piece))
      } else {
        added[square] = piece
      }
    }
    removed = Set(vacated.keys)
  }

  private static func distance(_ lhs: Square, _ rhs: Square) -> Int {
    max(abs(lhs.file - rhs.file), abs(lhs.rank - rhs.rank))
  }
}
