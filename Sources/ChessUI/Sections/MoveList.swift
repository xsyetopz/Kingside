import ChessContent
import ChessPlay
import SwiftUI

/// The moves, scrolled to the latest: a score sheet of numbered rows with White's and Black's
/// moves in columns and the latest move marked, or one line on narrow screens.
struct MoveList: View {
  let rows: [MoveRow]
  let axis: Axis.Set
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization
  #if os(tvOS)
    @FocusState
    private var isFocused: Bool
  #endif

  var body: some View {
    let style = model.catalog.interface
    if rows.isEmpty {
      Text(localization("game.moves.empty"))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: axis == .vertical ? .infinity : nil)
        .padding(style.gap)
    } else {
      ScrollViewReader { proxy in
        ScrollView(axis) {
          if axis == .horizontal {
            LazyHStack(spacing: style.gap) {
              ForEach(rows) { row in
                Text(rowLabel(row)).monospacedDigit().id(row.id)
              }
            }
          } else {
            sheet(style)
          }
        }
        // One line is only as tall as its moves; a horizontal scroll view would otherwise take
        // all free height and shrink the board above it.
        .fixedSize(horizontal: false, vertical: axis == .horizontal)
        #if os(tvOS)
          // Focusable so the remote can scroll it; a scroll view draws no focus effect.
          .focusable()
          .focused($isFocused)
          .overlay {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .strokeBorder(.tint, lineWidth: 2 * style.platformScale)
            .opacity(isFocused ? 1 : 0)
          }
        #endif
        .onChange(of: rows.last?.id) { _, id in
          if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
        }
      }
    }
  }

  private func sheet(_ style: InterfaceStyle) -> some View {
    let latest = rows.last
    return LazyVStack(spacing: 0) {
      ForEach(rows) { row in
        HStack(spacing: style.gap) {
          // The widest number sets the column, so the moves line up.
          ZStack(alignment: .leading) {
            Text(localization.string("game.moves.number", String(rows.count))).hidden()
            Text(localization.string("game.moves.number", String(row.number)))
          }
          .foregroundStyle(.secondary)
          move(row.white, isLatest: row.id == latest?.id && row.black == nil, style: style)
          move(row.black ?? "", isLatest: row.id == latest?.id && row.black != nil, style: style)
        }
        .monospacedDigit()
        .padding(.horizontal, style.gap)
        .padding(.vertical, style.gap / 4)
        .background(
          row.number.isMultiple(of: 2) ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel(row))
        .id(row.id)
      }
    }
    .padding(.vertical, style.gap / 2)
  }

  private func move(_ san: String, isLatest: Bool, style: InterfaceStyle) -> some View {
    Text(san)
      .fontWeight(isLatest ? .semibold : .regular)
      .padding(.horizontal, style.gap / 2)
      .padding(.vertical, style.gap / 8)
      .background(
        isLatest ? AnyShapeStyle(.tint.opacity(0.3)) : AnyShapeStyle(.clear),
        in: RoundedRectangle(cornerRadius: style.cornerRadius / 3, style: .continuous)
      )
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func rowLabel(_ row: MoveRow) -> String {
    localization.string("game.moves.row", String(row.number), row.white, row.black ?? "")
  }
}
