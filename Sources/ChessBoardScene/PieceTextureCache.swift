import ChessContent
import ChessCore
import Foundation
import SpriteKit

/// Piece textures rasterized from the set's vector PDFs, one per (set, piece, pixel size).
@MainActor
final class PieceTextureCache {
    private struct Key: Hashable {
        let setID: String
        let piece: Piece
        let pixelSize: Int
    }

    private let bundle: Bundle
    private var textures: [Key: SKTexture] = [:]

    init(bundle: Bundle) {
        self.bundle = bundle
    }

    var count: Int { textures.count }

    /// Nil when the set has no file for the piece or the file is not a readable PDF.
    func texture(for piece: Piece, in set: PieceSet, pixelSize: Int) -> SKTexture? {
        let key = Key(setID: set.id, piece: piece, pixelSize: pixelSize)
        if let texture = textures[key] { return texture }
        guard let url = set.url(for: piece, in: bundle),
              let image = Self.rasterize(pdfAt: url, pixelSize: pixelSize)
        else { return nil }
        let texture = SKTexture(cgImage: image)
        textures[key] = texture
        return texture
    }

    /// Draws the first page of a PDF, scaled to fit and centered, into a square
    /// `pixelSize` × `pixelSize` sRGB bitmap.
    nonisolated static func rasterize(pdfAt url: URL, pixelSize: Int) -> CGImage? {
        guard pixelSize > 0, let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let side = CGFloat(pixelSize)
        let scale = min(side / box.width, side / box.height)
        context.interpolationQuality = .high
        context.translateBy(x: (side - box.width * scale) / 2, y: (side - box.height * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        return context.makeImage()
    }
}

/// A piece image for screens that show one outside the board, such as the piece set picker.
public enum PieceImage {
    /// The piece rasterized square, `pixelSize` on a side; nil when the set has no readable file for it.
    public static func cgImage(
        for piece: Piece, in set: PieceSet, pixelSize: Int, bundle: Bundle = Localization.moduleBundle
    ) -> CGImage? {
        set.url(for: piece, in: bundle).flatMap { PieceTextureCache.rasterize(pdfAt: $0, pixelSize: pixelSize) }
    }
}
