# Acknowledgements

## Chess piece artwork ("cburnett" set)

The chess piece images (`Sources/ChessContent/Resources/Pieces/cburnett/`) are the
standard SVG pieces by Colin M.L. Burnett (Wikimedia Commons user
[Cburnett](https://commons.wikimedia.org/wiki/User:Cburnett)), converted to PDF without
changes to the artwork. The app shows the notice below under Settings > Licenses
(`Sources/ChessContent/Resources/Licenses/cburnett-notice.txt`).

License: used under the BSD 3-clause license. On Wikimedia Commons, all twelve files
are offered by their author under a choice of GFDL, BSD, or GPL
(`{{self|GFDL|migration=relicense|BSD|GPL}}`; the GFDL option also migrated to
CC BY-SA 3.0). This app takes the BSD option, whose `Template:BSD` defaults to the
3-clause version. Author attribution: Cburnett.

<!-- markdownlint-disable MD029 -- the license clauses keep their original numbering. -->

> Copyright (c) Colin M.L. Burnett (Cburnett). All rights reserved.
>
> Redistribution and use in source and binary forms, with or without modification,
> are permitted provided that the following conditions are met:
>
> 1. Redistributions of source code must retain the above copyright notice, this
>    list of conditions and the following disclaimer.
> 2. Redistributions in binary form must reproduce the above copyright notice, this
>    list of conditions and the following disclaimer in the documentation and/or
>    other materials provided with the distribution.
> 3. Neither the name of the copyright holder nor the names of its contributors may
>    be used to endorse or promote products derived from this software without
>    specific prior written permission.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
> ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
> WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
> IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
> INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
> NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
> PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
> WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
> ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
> POSSIBILITY OF SUCH DAMAGE.

<!-- markdownlint-enable MD029 -->

Sources (Wikimedia Commons):

| Piece | File page | Original file |
| --- | --- | --- |
| Chess_bdt45.svg | <https://commons.wikimedia.org/wiki/File:Chess_bdt45.svg> | <https://upload.wikimedia.org/wikipedia/commons/9/98/Chess_bdt45.svg> |
| Chess_blt45.svg | <https://commons.wikimedia.org/wiki/File:Chess_blt45.svg> | <https://upload.wikimedia.org/wikipedia/commons/b/b1/Chess_blt45.svg> |
| Chess_kdt45.svg | <https://commons.wikimedia.org/wiki/File:Chess_kdt45.svg> | <https://upload.wikimedia.org/wikipedia/commons/f/f0/Chess_kdt45.svg> |
| Chess_klt45.svg | <https://commons.wikimedia.org/wiki/File:Chess_klt45.svg> | <https://upload.wikimedia.org/wikipedia/commons/4/42/Chess_klt45.svg> |
| Chess_ndt45.svg | <https://commons.wikimedia.org/wiki/File:Chess_ndt45.svg> | <https://upload.wikimedia.org/wikipedia/commons/e/ef/Chess_ndt45.svg> |
| Chess_nlt45.svg | <https://commons.wikimedia.org/wiki/File:Chess_nlt45.svg> | <https://upload.wikimedia.org/wikipedia/commons/7/70/Chess_nlt45.svg> |
| Chess_pdt45.svg | <https://commons.wikimedia.org/wiki/File:Chess_pdt45.svg> | <https://upload.wikimedia.org/wikipedia/commons/c/c7/Chess_pdt45.svg> |
| Chess_plt45.svg | <https://commons.wikimedia.org/wiki/File:Chess_plt45.svg> | <https://upload.wikimedia.org/wikipedia/commons/4/45/Chess_plt45.svg> |
| Chess_qdt45.svg | <https://commons.wikimedia.org/wiki/File:Chess_qdt45.svg> | <https://upload.wikimedia.org/wikipedia/commons/4/47/Chess_qdt45.svg> |
| Chess_qlt45.svg | <https://commons.wikimedia.org/wiki/File:Chess_qlt45.svg> | <https://upload.wikimedia.org/wikipedia/commons/1/15/Chess_qlt45.svg> |
| Chess_rdt45.svg | <https://commons.wikimedia.org/wiki/File:Chess_rdt45.svg> | <https://upload.wikimedia.org/wikipedia/commons/f/ff/Chess_rdt45.svg> |
| Chess_rlt45.svg | <https://commons.wikimedia.org/wiki/File:Chess_rlt45.svg> | <https://upload.wikimedia.org/wikipedia/commons/7/72/Chess_rlt45.svg> |

## Sound effects

All sound effects are synthesized in code at launch from the `synth` pack in
`Sources/ChessContent/Resources/Catalogs/sound-packs.json`; no third-party audio is used.

## Puzzles (Lichess puzzle database)

`Sources/ChessContent/Resources/Catalogs/puzzles.json` contains puzzles selected from the Lichess
puzzle database (<https://database.lichess.org/#puzzles>, file
`lichess_db_puzzle.csv.zst`), keeping the puzzle id, FEN, UCI moves, rating and themes. Thanks to
lichess.org and its contributors.

License: Creative Commons CC0 1.0 Universal (public domain dedication,
<https://creativecommons.org/publicdomain/zero/1.0/>).

## Chat word filter (LDNOOBW)

`Sources/ChessContent/Resources/Catalogs/chat-filter.json` is derived from the English list of
"List of Dirty, Naughty, Obscene, and Otherwise Bad Words" by Shutterstock, Inc. and contributors
(<https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words>, commit
`5faf2ba42d7b1c0977169ec3611df25a3c08eb13`, file `en`). The entries were lowercased, and
multi-word and hyphenated entries were removed. The app shows the notice under Settings > Licenses
(`Sources/ChessContent/Resources/Licenses/ldnoobw-notice.txt`).

License: Creative Commons Attribution 4.0 International (CC BY 4.0,
<https://creativecommons.org/licenses/by/4.0/>).
