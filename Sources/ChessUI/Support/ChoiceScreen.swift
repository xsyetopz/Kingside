import SwiftUI

/// A pushed list of choices that goes back once one is picked, like a navigation-link
/// `Picker`, but with artwork per option: rows on narrow screens, cards on wide ones.
///
/// Settings uses it on iOS and tvOS instead of `Picker`: on tvOS a picker's pushed list
/// renders blank inside the path-based `SectionStack`.
struct ChoiceScreen<Option: Identifiable, Artwork: View>: View {
  let title: String
  let options: [Option]
  @Binding
  var selection: Option.ID
  let name: (Option) -> String
  /// Options without artwork get short cards.
  var isCompact = false
  @ViewBuilder
  let artwork: (Option) -> Artwork

  @Environment(AppModel.self)
  private var model
  @Environment(\.dismiss)
  private var dismiss

  var body: some View {
    WidthAdaptive {
      List(options) { option in
        Button {
          pick(option)
        } label: {
          HStack {
            artwork(option)
            Text(name(option)).foregroundStyle(Color.primary)
            Spacer(minLength: 0)
            if option.id == selection {
              Image(systemName: "checkmark").foregroundStyle(.tint)
            }
          }
        }
        .accessibilityAddTraits(option.id == selection ? .isSelected : [])
      }
    } wide: {
      CardGrid {
        ScreenHeading(title: title)
      } content: {
        ForEach(options) { option in
          Button {
            pick(option)
          } label: {
            CardLabel(
              title: name(option),
              isSelected: option.id == selection,
              isCompact: isCompact,
              style: model.catalog.interface
            ) {
              artwork(option)
            }
          }
          .cardButtonStyle(isSelected: option.id == selection)
          .accessibilityAddTraits(option.id == selection ? .isSelected : [])
        }
      }
    }
    .screenTitle(title, chrome: .pushed)
  }

  private func pick(_ option: Option) {
    selection = option.id
    dismiss()
  }
}
