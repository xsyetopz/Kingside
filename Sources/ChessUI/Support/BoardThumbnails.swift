import ChessBoardScene
import ChessContent
import ChessCore
import SwiftUI

/// A still board, for cards and previews: in the chosen theme and piece set unless others are
/// given.
struct BoardThumbnail: View {
  let position: ChessPosition
  /// Black at the bottom.
  var flipped = false
  let side: Double
  var theme: BoardTheme?
  var pieceSet: PieceSet?

  @Environment(AppModel.self)
  private var model
  @Environment(\.displayScale)
  private var displayScale

  var body: some View {
    let theme = theme ?? model.boardTheme
    let pixels = Int((side / 8 * displayScale).rounded())
    let images = PieceThumbnails.images(for: pieceSet ?? model.pieceSet, pixelSize: pixels)
    let scale = displayScale
    Canvas { context, size in
      let cell = size.width / 8
      for rank in 0..<8 {
        for file in 0..<8 {
          let rect = CGRect(
            x: Double(flipped ? 7 - file : file) * cell,
            y: Double(flipped ? rank : 7 - rank) * cell,
            width: cell,
            height: cell
          )
          let isDark = (file + rank).isMultiple(of: 2)
          context.fill(
            Path(rect),
            with: .color(Color(isDark ? theme.squares.dark : theme.squares.light))
          )
          if let piece = position[Square(file: file, rank: rank)], let image = images[piece] {
            context.draw(Image(decorative: image, scale: scale), in: rect)
          }
        }
      }
    }
    .frame(width: side, height: side)
    .clipShape(RoundedRectangle(cornerRadius: side / 24, style: .continuous))
    .accessibilityHidden(true)
  }
}

/// Rasterized pieces by set and size, so thumbnails do not read the PDFs on every redraw.
@MainActor
private enum PieceThumbnails {
  private struct Key: Hashable {
    let setID: String
    let pixelSize: Int
  }

  private static var cache: [Key: [Piece: CGImage]] = [:]

  static func images(for set: PieceSet, pixelSize: Int) -> [Piece: CGImage] {
    let key = Key(setID: set.id, pixelSize: pixelSize)
    if let images = cache[key] { return images }
    var images: [Piece: CGImage] = [:]
    for color in [PieceColor.white, .black] {
      for type in PieceType.allCases {
        let piece = Piece(type: type, color: color)
        images[piece] = PieceImage.cgImage(for: piece, in: set, pixelSize: pixelSize)
      }
    }
    cache[key] = images
    return images
  }
}

/// Four large pieces of a set on a two-by-two board in the chosen theme: a set's look shows at
/// a size where a whole-board thumbnail makes its pieces too small to tell apart.
struct PieceSetSample: View {
  let pieceSet: PieceSet
  let side: Double

  @Environment(AppModel.self)
  private var model
  @Environment(\.displayScale)
  private var displayScale

  private static let pieces: [Piece] = [
    Piece(type: .king, color: .white), Piece(type: .knight, color: .black),
    Piece(type: .queen, color: .black), Piece(type: .knight, color: .white),
  ]

  var body: some View {
    let theme = model.boardTheme
    let images = PieceThumbnails.images(
      for: pieceSet,
      pixelSize: Int((side / 2 * displayScale).rounded())
    )
    let scale = displayScale
    Canvas { context, size in
      let cell = size.width / 2
      for (index, piece) in Self.pieces.enumerated() {
        let rect = CGRect(
          x: Double(index % 2) * cell,
          y: Double(index / 2) * cell,
          width: cell,
          height: cell
        )
        // Dark at the bottom left, as on a real board.
        let isDark = index == 1 || index == 2
        context.fill(
          Path(rect),
          with: .color(Color(isDark ? theme.squares.dark : theme.squares.light))
        )
        if let image = images[piece] {
          context.draw(Image(decorative: image, scale: scale), in: rect)
        }
      }
    }
    .frame(width: side, height: side)
    .clipShape(RoundedRectangle(cornerRadius: side / 12, style: .continuous))
    .accessibilityHidden(true)
  }
}
