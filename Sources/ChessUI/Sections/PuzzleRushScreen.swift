import ChessContent
import ChessPlay
import SwiftUI

/// Puzzle Rush: pick a mode, run it, and see the result. The run lives as long as the screen.
struct PuzzleRushScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.localization) private var localization
    @State private var mode = PuzzleRushMode.threeMinutes
    @State private var session: PuzzleRushSession?

    var body: some View {
        Group {
            if let session {
                PuzzleRushRunView(session: session) { self.session = nil }
            } else {
                picker
            }
        }
        .onDisappear { session?.stop() }
    }

    private var picker: some View {
        WidthAdaptive {
            List {
                ScreenHeading(title: localization("puzzleRush.title"))
                ForEach(PuzzleRushMode.allCases) { choice in
                    SetupRow(title: localization(choice.nameKey), detail: best(choice), isSelected: choice == mode) {
                        mode = choice
                    } leading: {
                        Image(systemName: PuzzleLayout.symbol(for: choice)).foregroundStyle(.tint)
                    }
                }
            }
            .startBar(title: localization("puzzleRush.start"), isEnabled: true, action: start)
        } wide: {
            SetupSplit {
                ScreenHeading(title: localization("puzzleRush.title"))
                Image(systemName: PuzzleLayout.symbol(for: mode))
                    .font(.system(size: model.catalog.interface.home.iconColumnWidth * 2 * model.catalog.interface.platformScale))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                Text(localization(mode.nameKey)).font(.title.bold())
                Text(localization("puzzleRush.detail")).foregroundStyle(.secondary)
                Text(best(mode)).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.tint)
                StartButton(title: localization("puzzleRush.start"), isEnabled: true, action: start)
            } options: {
                ForEach(PuzzleRushMode.allCases) { choice in
                    ChoiceTile(title: localization(choice.nameKey), detail: best(choice), isSelected: choice == mode) {
                        mode = choice
                    } artwork: {
                        // One height for all glyphs, so the tiles match.
                        Image(systemName: PuzzleLayout.symbol(for: choice)).font(.title2).foregroundStyle(.tint)
                            .frame(height: model.catalog.interface.home.iconColumnWidth * model.catalog.interface.platformScale)
                    }
                }
            }
        }
        // The run replaces the picker in place, so the picker already takes the run's full height.
        .screenTitle(localization("puzzleRush.title"), chrome: .board)
    }

    private func best(_ mode: PuzzleRushMode) -> String {
        localization.string("puzzleRush.best", model.puzzleProgress.rushBest(for: mode))
    }

    private func start() {
        let session = PuzzleRushSession(
            mode: mode, catalog: model.catalog, progress: model.puzzleProgress, board: model.makePuzzleBoard())
        session.start()
        self.session = session
    }
}

/// The run: the clock, the strikes, the score, and the board. The result comes up as a sheet.
private struct PuzzleRushRunView: View {
    let session: PuzzleRushSession
    /// Goes back to the mode picker.
    let changeMode: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.localization) private var localization

    var body: some View {
        let run = session.run
        PuzzleScreenLayout(
            title: localization(session.mode.nameKey), board: session.board,
            stats: [
                PuzzleStat(title: localization("puzzleRush.stat.score"), value: String(run.score)),
                PuzzleStat(
                    title: localization("puzzleRush.stat.best"),
                    value: String(model.puzzleProgress.rushBest(for: session.mode))),
            ],
            primary: PuzzleAction(
                title: localization("puzzleRush.action.end"), systemImage: "flag.checkered",
                isEnabled: session.isRunning
            ) { session.end() },
            offersRetry: false
        ) {
            header(run)
        }
        .sheet(isPresented: showsResult) {
            if let result = session.result {
                PuzzleRushResultSheet(result: result, playAgain: session.start, changeMode: changeMode)
            }
        }
    }

    /// The sheet shows while the run has a result; swiping it away is Change Mode.
    private var showsResult: Binding<Bool> {
        Binding(
            get: { session.result != nil },
            set: { if !$0 && session.result != nil { changeMode() } })
    }

    private func header(_ run: PuzzleRushRun) -> some View {
        let style = model.catalog.interface
        let size = style.puzzles.strikeSize * style.platformScale
        return HStack(spacing: style.gap) {
            if let remaining = run.remaining {
                Text(GameLayout.clockText(remaining))
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(
                        remaining <= model.catalog.tuning.clock.lowTimeSeconds
                            ? AnyShapeStyle(.red) : AnyShapeStyle(.primary)
                    )
                    .accessibilityLabel(localization("puzzleRush.clock.label"))
                    .accessibilityValue(GameLayout.clockText(remaining))
            }
            Spacer(minLength: 0)
            HStack(spacing: style.gap / 2) {
                ForEach(0..<run.maxStrikes, id: \.self) { index in
                    Image(systemName: index < run.strikes ? "xmark.circle.fill" : "circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .foregroundStyle(index < run.strikes ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localization.plural("puzzleRush.strikes", count: run.strikes))
        }
        .frame(maxWidth: .infinity)
        .padding(style.gap)
        .surface(style)
    }
}

/// Shown when the run ends: the score, and what to do next.
private struct PuzzleRushResultSheet: View {
    let result: PuzzleRushSession.Result
    let playAgain: () -> Void
    let changeMode: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.localization) private var localization

    var body: some View {
        let style = model.catalog.interface
        VStack(spacing: style.sectionGap) {
            VStack(spacing: style.gap / 2) {
                Text(localization(result.isNewBest ? "puzzleRush.result.newBest" : "puzzleRush.result.title"))
                    .font(.largeTitle.bold())
                Text(localization.plural("puzzleRush.result.score", count: result.score)).font(.title3)
                Text(localization.string("puzzleRush.best", result.best)).foregroundStyle(.secondary)
            }
            VStack(spacing: style.gap) {
                Button(localization("puzzleRush.action.playAgain"), action: playAgain)
                    .buttonStyle(.borderedProminent)
                Button(localization("puzzleRush.action.changeMode"), action: changeMode)
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding(style.sectionGap)
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }
}
