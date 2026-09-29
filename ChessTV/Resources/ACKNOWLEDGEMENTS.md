# Acknowledgements

## Chess piece artwork ("cburnett" set)

The chess piece images (`cburnett-wK` ... `cburnett-bP` in `Assets.xcassets`) are the
standard SVG pieces by Colin M.L. Burnett (Wikimedia Commons user
[Cburnett](https://commons.wikimedia.org/wiki/User:Cburnett)), unmodified.

License: Creative Commons Attribution-Share Alike 3.0 Unported
(<https://creativecommons.org/licenses/by-sa/3.0/>). The Commons file pages
also list the files as triple-licensed under GFDL, BSD and GPL
(`{{self|GFDL|migration=relicense|BSD|GPL}}`); the Commons metadata API reports
"CC BY-SA 3.0" for all twelve files. Author attribution: Cburnett.

Sources (Wikimedia Commons):

| Piece | File page | Original file |
| --- | --- | --- |
| Chess_bdt45.svg | https://commons.wikimedia.org/wiki/File:Chess_bdt45.svg | https://upload.wikimedia.org/wikipedia/commons/9/98/Chess_bdt45.svg |
| Chess_blt45.svg | https://commons.wikimedia.org/wiki/File:Chess_blt45.svg | https://upload.wikimedia.org/wikipedia/commons/b/b1/Chess_blt45.svg |
| Chess_kdt45.svg | https://commons.wikimedia.org/wiki/File:Chess_kdt45.svg | https://upload.wikimedia.org/wikipedia/commons/f/f0/Chess_kdt45.svg |
| Chess_klt45.svg | https://commons.wikimedia.org/wiki/File:Chess_klt45.svg | https://upload.wikimedia.org/wikipedia/commons/4/42/Chess_klt45.svg |
| Chess_ndt45.svg | https://commons.wikimedia.org/wiki/File:Chess_ndt45.svg | https://upload.wikimedia.org/wikipedia/commons/e/ef/Chess_ndt45.svg |
| Chess_nlt45.svg | https://commons.wikimedia.org/wiki/File:Chess_nlt45.svg | https://upload.wikimedia.org/wikipedia/commons/7/70/Chess_nlt45.svg |
| Chess_pdt45.svg | https://commons.wikimedia.org/wiki/File:Chess_pdt45.svg | https://upload.wikimedia.org/wikipedia/commons/c/c7/Chess_pdt45.svg |
| Chess_plt45.svg | https://commons.wikimedia.org/wiki/File:Chess_plt45.svg | https://upload.wikimedia.org/wikipedia/commons/4/45/Chess_plt45.svg |
| Chess_qdt45.svg | https://commons.wikimedia.org/wiki/File:Chess_qdt45.svg | https://upload.wikimedia.org/wikipedia/commons/4/47/Chess_qdt45.svg |
| Chess_qlt45.svg | https://commons.wikimedia.org/wiki/File:Chess_qlt45.svg | https://upload.wikimedia.org/wikipedia/commons/1/15/Chess_qlt45.svg |
| Chess_rdt45.svg | https://commons.wikimedia.org/wiki/File:Chess_rdt45.svg | https://upload.wikimedia.org/wikipedia/commons/f/ff/Chess_rdt45.svg |
| Chess_rlt45.svg | https://commons.wikimedia.org/wiki/File:Chess_rlt45.svg | https://upload.wikimedia.org/wikipedia/commons/7/72/Chess_rlt45.svg |

## Sound effects

All sound effects are synthesized in code at launch (`Core/Audio/SoundEffects.swift`);
no third-party audio is used.

## Puzzles (Lichess puzzle database)

`Puzzles.json` contains 1,512 puzzles selected from the Lichess puzzle database
(<https://database.lichess.org/#puzzles>, file `lichess_db_puzzle.csv.zst`), keeping the
puzzle id, FEN, UCI moves, rating and themes. Thanks to lichess.org and its contributors.

License: Creative Commons CC0 1.0 Universal (public domain dedication,
<https://creativecommons.org/publicdomain/zero/1.0/>).
