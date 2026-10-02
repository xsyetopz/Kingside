import ChessContent
import ChessCore
import ChessPlay
import SwiftUI

extension MoveClassification {
  /// How a grade is drawn beside a move.
  enum Mark: Equatable {
    /// A chess annotation, such as "??" for a blunder.
    case annotation(String)
    /// An SF Symbol, for the grades that chess notation has no annotation for.
    case symbol(String)
  }

  /// The mark shown beside a move; the grade's name is its accessibility text.
  var mark: Mark {
    switch self {
    case .brilliant: .annotation("!!")
    case .great: .annotation("!")
    case .best: .symbol("star.fill")
    case .excellent: .symbol("hand.thumbsup.fill")
    case .good: .symbol("checkmark")
    case .book: .symbol("book.fill")
    case .inaccuracy: .annotation("?!")
    case .mistake: .annotation("?")
    case .miss: .symbol("xmark")
    case .blunder: .annotation("??")
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

private extension DynamicTypeSize {
  /// A title and its value side by side, or stacked at accessibility sizes, where side by side
  /// would cut both short.
  var lineLayout: AnyLayout {
    isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout())
  }
}

/// A grade's mark in its color. VoiceOver skips it: the grade's name stands beside it.
private struct ClassificationMark: View {
  let classification: MoveClassification

  var body: some View {
    Group {
      switch classification.mark {
      case .annotation(let text): Text(verbatim: text).fontWeight(.bold).fontDesign(.rounded)
      case .symbol(let name): Image(systemName: name)
      }
    }
    .foregroundStyle(classification.color)
    .accessibilityHidden(true)
  }
}

/// Progress of the analysis while it runs, then each side's accuracy.
struct ReviewSummary: View {
  let review: GameReviewModel
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization
  @Environment(\.dynamicTypeSize)
  private var dynamicTypeSize

  var body: some View {
    let style = model.catalog.interface
    VStack(alignment: .leading, spacing: style.gap) {
      if review.isComplete {
        ForEach(PieceColor.allCases, id: \.self) { color in
          dynamicTypeSize.lineLayout {
            Text(review.game.player(color).name).font(.headline)
              .frame(maxWidth: .infinity, alignment: .leading)
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
  @Environment(\.dynamicTypeSize)
  private var dynamicTypeSize

  var body: some View {
    let style = model.catalog.interface
    let move = review.moves.first { $0.ply == ply - 1 }
    VStack(alignment: .leading, spacing: style.gap / 2) {
      if let move {
        dynamicTypeSize.lineLayout {
          Label {
            Text(localization(move.classification.titleKey))
          } icon: {
            ClassificationMark(classification: move.classification)
          }
          .font(.headline)
          .foregroundStyle(move.classification.color)
          .frame(maxWidth: .infinity, alignment: .leading)
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
    let gap = model.catalog.interface.gap
    // At the largest text sizes four large buttons are wider than an iPhone, so they wrap
    // into two rows instead of pushing the screen past its edges.
    ViewThatFits(in: .horizontal) {
      HStack(spacing: gap) {
        backControls
        forwardControls
      }
      VStack(spacing: gap) {
        HStack(spacing: gap) { backControls }
        HStack(spacing: gap) { forwardControls }
      }
    }
    .buttonStyle(.bordered)
    .controlSize(.large)
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private var backControls: some View {
    control("review.nav.first", "backward.end.fill", .first, key: .home)
    control("review.nav.previous", "chevron.left", .previous, key: .leftArrow)
  }

  @ViewBuilder
  private var forwardControls: some View {
    control("review.nav.next", "chevron.right", .next, key: .rightArrow)
    control("review.nav.last", "forward.end.fill", .last, key: .end)
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
        if let grade { ClassificationMark(classification: grade) }
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
