import ChessCore
import Testing

func move(_ uci: String) throws -> ChessMove { try #require(ChessMove(uci: uci)) }
