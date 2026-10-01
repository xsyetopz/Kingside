import ChessContent
import ChessCore
import ChessPlay
import SwiftUI

extension MoveClassification {
  /// The mark shown beside a move; the grade's name is its accessibility text.
  var symbol: String {
    switch self {
    case .brilliant: "sparkles"
    case .great: "exclamationmark"
    case .best: "star.fill"
    case .excellent: "hand.thumbsup.fill"
    case .good: "checkmark"
    case .book: "book.fill"
    case .inaccuracy: "questionmark"
    case .mistake: "exclamationmark.triangle.fill"
    case .miss: "xmark"
    case .blunder: "exclamationmark.2"
    }
  }

  /// System colors: cool for strong moves, warm for errors.
  var color: Color {
    switch self {
    case .brilliant: .teal
    case .great: .blue
    case .best, .excellent: .green
    case .good: .mint
    case .book: .brown
    case .inaccuracy: .yellow
    case .mistake, .miss: .orange
    case .blunder: .red
    }
  }
}

/// Progress of the analysis while it runs, then each side's accuracy.
struct ReviewSummary: View {
  let review: GameReviewModel
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization

  var body: some View {
    let style = model.catalog.interface
    VStack(alignment: .leading, spacing: style.gap) {
      if review.isComplete {
        ForEach(PieceColor.allCases, id: \.self) { color in
          HStack {
            Text(review.game.player(color).name).font(.headline)
            Spacer(minLength: 0)
            if let accuracy = review.accuracy(for: color) {
              Text(localization.string("review.accuracy", Int(accuracy.rounded())))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
          }
        }
      } else {
        ProgressView(value: Double(review.analyses.count), total: Double(review.positions.count)) {
          Text(
            localization.string("review.progress", review.analyses.count, review.positions.count)
          )
          .font(.subheadline)
        }
        if !review.isAnalyzing {
          Button(localization("common.retry")) { review.start() }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(style.gap)
    .contentPanel(style)
  }
}

/// The coach line for the shown move and the evaluation after it.
struct ReviewCoach: View {
  let review: GameReviewModel
  let ply: Int
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization

  var body: some View {
    let style = model.catalog.interface
    let move = review.moves.first { $0.ply == ply - 1 }
    VStack(alignment: .leading, spacing: style.gap / 2) {
      if let move {
        HStack {
          Label(localization(move.classification.titleKey), systemImage: move.classification.symbol)
            .font(.headline)
            .foregroundStyle(move.classification.color)
          Spacer(minLength: 0)
          Text(EvaluationLabel.text(move.evaluationAfter))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .accessibilityLabel(
              localization.string("review.evaluation", EvaluationLabel.text(move.evaluationAfter))
            )
        }
        Text(move.coachText(localization: localization)).foregroundStyle(.secondary)
      } else if ply == 0 {
        Text(localization("review.position.start")).font(.headline)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(style.gap)
    .contentPanel(style)
  }
}

/// First, previous, next, and last. The arrow keys work on iOS and macOS wherever the focus is.
struct ReviewControls: View {
  let ply: Int
  let moveCount: Int
  let go: (ReviewLayout.Step) -> Void
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization

  var body: some View {
    HStack(spacing: model.catalog.interface.gap) {
      control("review.nav.first", "backward.end.fill", .first, key: .home)
      control("review.nav.previous", "chevron.left", .previous, key: .leftArrow)
      control("review.nav.next", "chevron.right", .next, key: .rightArrow)
      control("review.nav.last", "forward.end.fill", .last, key: .end)
    }
    .buttonStyle(.bordered)
    .controlSize(.large)
    .frame(maxWidth: .infinity)
  }

  private func control(
    _ title: String,
    _ symbol: String,
    _ step: ReviewLayout.Step,
    key: KeyEquivalent
  ) -> some View {
    Button {
      go(step)
    } label: {
      Label(localization(title), systemImage: symbol)
        .labelStyle(.iconOnly)
        .frame(maxWidth: .infinity)
    }
    .disabled(ReviewLayout.ply(ply, step: step, moveCount: moveCount) == ply)
    #if !os(tvOS)
      .keyboardShortcut(key, modifiers: [])
    #endif
  }
}

/// The moves as numbered rows, each move with its grade; the shown move is highlighted.
struct ReviewMoveList: View {
  let review: GameReviewModel
  @Binding
  var ply: Int
  let axis: Axis.Set
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization

  var body: some View {
    let style = model.catalog.interface
    let rows = ReviewLayout.rows(moveCount: review.moveCount)
    ScrollViewReader { proxy in
      ScrollView(axis) {
        if rows.isEmpty {
          Text(localization("game.moves.empty")).foregroundStyle(.secondary)
        } else if axis == .horizontal {
          LazyHStack(spacing: style.gap) { rowViews(rows, style) }
        } else {
          LazyVStack(alignment: .leading, spacing: style.gap / 2) { rowViews(rows, style) }
            .padding(style.gap)
        }
      }
      // One line is only as tall as its moves; a horizontal scroll view would otherwise take
      // all free height and shrink the board above it.
      .fixedSize(horizontal: false, vertical: axis == .horizontal)
      .onChange(of: ply) { _, new in
        withAnimation { proxy.scrollTo((new + 1) / 2) }
      }
    }
  }

  private func rowViews(_ rows: [ReviewLayout.Row], _ style: InterfaceStyle) -> some View {
    ForEach(rows) { row in
      HStack(spacing: style.gap / 2) {
        // The widest number sets the column, so the moves line up as on the game screen.
        ZStack(alignment: .leading) {
          if axis == .vertical {
            Text(localization.string("review.moves.number", rows.count)).hidden()
          }
          Text(localization.string("review.moves.number", row.number))
        }
        .monospacedDigit()
        .foregroundStyle(.secondary)
        moveButton(row.whitePly, style)
        if let black = row.blackPly {
          moveButton(black, style)
        } else if axis == .vertical {
          Spacer().frame(maxWidth: .infinity)
        }
      }
      .id(row.id)
    }
  }

  private func moveButton(_ target: Int, _ style: InterfaceStyle) -> some View {
    let played = review.game.game.moves[target - 1]
    let grade = review.moves.first { $0.ply == target - 1 }?.classification
    return Button {
      ply = target
    } label: {
      HStack(spacing: style.gap / 4) {
        Text(played.san).monospacedDigit()
        if let grade { Image(systemName: grade.symbol).foregroundStyle(grade.color) }
      }
      .padding(.horizontal, style.gap / 2)
      .padding(.vertical, style.gap / 4)
      .background(
        ply == target ? Color.accentColor.opacity(0.25) : Color.clear,
        in: RoundedRectangle(cornerRadius: style.cornerRadius / 2, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .frame(maxWidth: axis == .vertical ? .infinity : nil, alignment: .leading)
    .accessibilityValue(grade.map { localization($0.titleKey) } ?? "")
  }
}
