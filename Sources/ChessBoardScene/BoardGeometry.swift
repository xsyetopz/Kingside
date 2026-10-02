import ChessContent
import ChessCore
import SpriteKit

/// Where the board sits in a scene: the largest centered square, 8 × 8 squares, with
/// `orientation`'s pieces at the bottom. Points are scene coordinates (origin bottom-left).
struct BoardGeometry: Equatable {
  let origin: CGPoint
  let squareSize: CGFloat
  let orientation: PieceColor

  init(sceneSize: CGSize, orientation: PieceColor) {
    let side = max(0, min(sceneSize.width, sceneSize.height))
    origin = CGPoint(x: (sceneSize.width - side) / 2, y: (sceneSize.height - side) / 2)
    squareSize = side / 8
    self.orientation = orientation
  }

  /// Screen column (0 = left) and row (0 = bottom) of a square.
  func cell(of square: Square) -> (column: Int, row: Int) {
    orientation == .white ? (square.file, square.rank) : (7 - square.file, 7 - square.rank)
  }

  func square(column: Int, row: Int) -> Square {
    orientation == .white
      ? Square(file: column, rank: row) : Square(file: 7 - column, rank: 7 - row)
  }

  func rect(of square: Square) -> CGRect {
    let cell = cell(of: square)
    return CGRect(
      x: origin.x + CGFloat(cell.column) * squareSize,
      y: origin.y + CGFloat(cell.row) * squareSize,
      width: squareSize,
      height: squareSize
    )
  }

  func center(of square: Square) -> CGPoint {
    let rect = rect(of: square)
    return CGPoint(x: rect.midX, y: rect.midY)
  }

  /// The square under a scene point; nil outside the board.
  func square(at point: CGPoint) -> Square? {
    guard squareSize > 0 else { return nil }
    let column = Int(((point.x - origin.x) / squareSize).rounded(.down))
    let row = Int(((point.y - origin.y) / squareSize).rounded(.down))
    guard (0..<8).contains(column), (0..<8).contains(row) else { return nil }
    return square(column: column, row: row)
  }
}

extension Square {
  /// a1 is dark.
  var isLight: Bool { (file + rank) % 2 == 1 }

  static let all: [Square] = (0..<8).flatMap { rank in (0..<8).map { Square(file: $0, rank: rank) }
  }
}

extension HexColor {
  var skColor: SKColor {
    SKColor(
      red: CGFloat(red) / 255,
      green: CGFloat(green) / 255,
      blue: CGFloat(blue) / 255,
      alpha: CGFloat(alpha) / 255
    )
  }
}
