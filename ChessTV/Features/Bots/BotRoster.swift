import SwiftUI

/// The built-in bot characters, weakest first. All names and lines are original.
enum BotRoster {
    static let all: [Bot] = [
        Bot(
            id: "pip", name: "Pip", rating: 250, group: .beginner,
            symbol: "tortoise.fill", color: Color(hex: 0x6FA35A),
            bio: "A cheerful tortoise who just learned how the knight hops.",
            lines: [
                .greeting: ["Hi! I'm Pip. Let's take it slow and have fun!", "Oh, a game? Yay! Be gentle."],
                .playerCaptures: ["Hey, I was using that!", "Oopsie. Where did my piece go?"],
                .botCaptures: ["Ooh, I got one!", "Munch munch!"],
                .playerBlunder: ["Um, I think you dropped something!", "Is that a present for me?"],
                .check: ["Check! Did I say that right?", "Your king looks nervous!"],
                .botWins: ["I won?! Wow, I need a nap now.", "Slow and steady!"],
                .botLoses: ["Good game! You were super speedy.", "Aw, you got me. Again sometime?"],
                .draw: ["A tie! Everybody wins!", "Nobody lost. I like that."],
                .drawDeclined: ["No thanks, I'm having too much fun!"],
                .takeback: ["Sure, take it back. I make oopsies too!"]
            ]
        ),
        Bot(
            id: "maisie", name: "Maisie", rating: 450, group: .beginner,
            symbol: nil, color: Color(hex: 0xC7773A),
            bio: "Plays chess between bakery shifts and brings cookies to every game.",
            lines: [
                .greeting: ["Fresh cookies and a fresh board. Let's play!", "Hello, dear! Ready for a friendly game?"],
                .playerCaptures: ["Well, that one was half-baked anyway.", "Ooh, you snatched that like the last cookie!"],
                .botCaptures: ["I'll just take that, thank you!", "Into the oven it goes!"],
                .playerBlunder: ["Oh dear, I think you left that out to cool.", "Are you sure about that one, sweetie?"],
                .check: ["Check! Mind the hot tray!", "Your king is in a bit of a jam!"],
                .botWins: ["Well, that rose nicely! Good game.", "A win! I'll celebrate with a muffin."],
                .botLoses: ["You beat me fair and square. Cookie?", "Lovely game, you earned the biggest slice."],
                .draw: ["Split it down the middle, like a good pie.", "A draw! Shall we share the cookies?"],
                .drawDeclined: ["Not yet, dear, it's still in the oven."],
                .takeback: ["Of course! Everyone deserves a second batch."]
            ]
        ),
        Bot(
            id: "bramble", name: "Bramble", rating: 650, group: .beginner,
            symbol: "leaf.fill", color: Color(hex: 0x4E8C87),
            bio: "A gardener who thinks pawns are seedlings that grow into queens.",
            lines: [
                .greeting: ["Let's see what grows on this board today.", "Pull up a chair, the garden is lovely."],
                .playerCaptures: ["You pruned my piece. Rude, but tidy.", "Snip! There goes one of my sprouts."],
                .botCaptures: ["Weeded that one right out.", "A little pruning never hurt."],
                .playerBlunder: ["Hmm, that square looks a bit overwatered.", "I spy an unguarded flowerbed."],
                .check: ["Check! Watch out for thorns.", "Your king is in the brambles now!"],
                .botWins: ["The garden grew my way today.", "What a harvest! Thanks for the game."],
                .botLoses: ["You've got a green thumb for chess.", "Well played. My plans wilted."],
                .draw: ["Even soil on both sides. A draw!", "We'll call this one a tidy hedge."],
                .drawDeclined: ["No, no, my pawns are still sprouting."],
                .takeback: ["Replant it, I don't mind."]
            ]
        ),
        Bot(
            id: "rosa", name: "Rosa", rating: 850, group: .intermediate,
            symbol: "bicycle", color: Color(hex: 0xB5485A),
            bio: "Bike courier who plays fast, turns hard and never brakes for pawns.",
            lines: [
                .greeting: ["Helmet on. Let's ride!", "Ready? I don't do slow."],
                .playerCaptures: ["Flat tire! You got me.", "Okay, that one stung."],
                .botCaptures: ["Delivered!", "Special delivery: your piece is mine."],
                .playerBlunder: ["You just ran a red light.", "Whoa, big pothole there!"],
                .check: ["Check! Coming through!", "Ding ding! Check!"],
                .botWins: ["First across the line!", "That was a fun sprint. Rematch?"],
                .botLoses: ["You out-pedaled me. Nice!", "I'll get you on the next lap."],
                .draw: ["Photo finish! Draw.", "Neck and neck. Fair enough."],
                .drawDeclined: ["Nope, still pedaling!"],
                .takeback: ["Fine, back it up. Once!"]
            ]
        ),
        Bot(
            id: "gus", name: "Gus", rating: 1050, group: .intermediate,
            symbol: "cup.and.saucer.fill", color: Color(hex: 0x7A6A55),
            bio: "Retired ferry captain who plays over a very large mug of tea.",
            lines: [
                .greeting: ["Ahoy! Kettle's on. Your move, sailor.", "Calm seas today. Let's play."],
                .playerCaptures: ["Man overboard!", "Blast, I needed that one."],
                .botCaptures: ["Hauled aboard!", "That one's going in the cargo hold."],
                .playerBlunder: ["You've sprung a leak, friend.", "Rough waters ahead for you."],
                .check: ["Check! Iceberg dead ahead!", "All hands, your king's in trouble!"],
                .botWins: ["Safe in harbor. Good game!", "The old captain still has it."],
                .botLoses: ["You sank my ship. Well steered!", "I'll drink my tea in defeat."],
                .draw: ["We'll share the dock tonight.", "A draw. The sea is kind today."],
                .drawDeclined: ["Not yet! The voyage isn't over."],
                .takeback: ["Turn her around, then. One time."]
            ]
        ),
        Bot(
            id: "nadia", name: "Nadia", rating: 1250, group: .intermediate,
            symbol: "book.fill", color: Color(hex: 0x3D7EA6),
            bio: "Librarian who has read every opening book and remembers half of them.",
            lines: [
                .greeting: ["Shh... it's game time. Good luck!", "I checked out a new opening for you."],
                .playerCaptures: ["That piece was overdue anyway.", "Hm. Didn't see that chapter coming."],
                .botCaptures: ["Returned to the shelf.", "Page 42 said I could take that."],
                .playerBlunder: ["That move isn't in any book I know.", "You may want to re-read that line."],
                .check: ["Check. Please keep your voice down.", "Check, as the book suggests."],
                .botWins: ["The end. Thanks for a lovely read.", "A tidy conclusion, I think."],
                .botLoses: ["What a plot twist! Well played.", "You wrote a better ending than I did."],
                .draw: ["An open ending. A draw it is.", "Some stories end in a tie."],
                .drawDeclined: ["I'd like to read a few more pages first."],
                .takeback: ["Let's turn back a page, then."]
            ]
        ),
        Bot(
            id: "quill", name: "Quill", rating: 1450, group: .advanced,
            symbol: "graduationcap.fill", color: Color(hex: 0x9C5DB5),
            bio: "Grad student writing a thesis on knight outposts. Ask about it. Please.",
            lines: [
                .greeting: ["Excellent, a test subject! I mean, opponent.", "Let's gather some data."],
                .playerCaptures: ["Noted. Adjusting my hypothesis.", "Interesting. Very interesting."],
                .botCaptures: ["As my research predicted.", "Peer-reviewed capture."],
                .playerBlunder: ["That move would not survive peer review.", "Statistically, that was a mistake."],
                .check: ["Check. Please cite that in your notes.", "Check! Footnote one."],
                .botWins: ["Thesis confirmed! Thanks for your help.", "Great data. Good game!"],
                .botLoses: ["Back to the lab for me. Well played.", "My thesis needs a new chapter."],
                .draw: ["Inconclusive results. A draw.", "Further research is needed."],
                .drawDeclined: ["My sample size is too small to stop now."],
                .takeback: ["We'll exclude that from the dataset."]
            ]
        ),
        Bot(
            id: "priya", name: "Priya", rating: 1650, group: .advanced,
            symbol: "bolt.fill", color: Color(hex: 0xC99A2E),
            bio: "Club champion and speed puzzler. Loves sharp positions and loud tactics.",
            lines: [
                .greeting: ["Let's make this one sharp!", "Hope you like tactics."],
                .playerCaptures: ["Nice shot! I'll remember that.", "Okay, you're warming up."],
                .botCaptures: ["Zap! Mine now.", "Tactics flow like electricity."],
                .playerBlunder: ["Ooh, I think I felt a spark there.", "That one's going to cost you!"],
                .check: ["Check! Feel the voltage.", "Zap! Check."],
                .botWins: ["Charged up and done. Good game!", "Full power finish!"],
                .botLoses: ["You short-circuited me. Great game!", "Wow, you were electric."],
                .draw: ["Balanced current. A draw.", "No sparks left. Draw it is."],
                .drawDeclined: ["There's still plenty of charge in this position."],
                .takeback: ["Alright, rewind. I want a fair fight."]
            ]
        ),
        Bot(
            id: "viktor", name: "Viktor", rating: 1800, group: .advanced,
            symbol: nil, color: Color(hex: 0x5D6B8C),
            bio: "Stern chess coach with a soft spot for students who fight to the end.",
            lines: [
                .greeting: ["Sit up straight. Let's begin.", "Show me what you've learned."],
                .playerCaptures: ["Good. You saw that.", "Acceptable technique."],
                .botCaptures: ["You left that for me.", "Always check what's hanging."],
                .playerBlunder: ["We'll discuss that move in the lesson.", "Look at the whole board, please."],
                .check: ["Check. Calculate carefully.", "Check. Now think."],
                .botWins: ["Good effort. Review this game tonight.", "A lesson learned is a win too."],
                .botLoses: ["Excellent. I'm proud of you.", "Well played. That was real chess."],
                .draw: ["A fair result. Well defended.", "A draw. You held firm."],
                .drawDeclined: ["No. Play on and prove it."],
                .takeback: ["Once. Then think before you move."]
            ]
        ),
        Bot(
            id: "odette", name: "Odette", rating: 1950, group: .master,
            symbol: "moon.stars.fill", color: Color(hex: 0x3F4A8A),
            bio: "Night-shift astronomer who calculates variations like orbits.",
            lines: [
                .greeting: ["The stars are aligned for a good game.", "Good evening. Shall we begin?"],
                .playerCaptures: ["A comet I didn't chart.", "Hm. A small eclipse for me."],
                .botCaptures: ["Pulled into my orbit.", "Gravity always wins."],
                .playerBlunder: ["That piece has drifted out of orbit.", "A falling star, I'm afraid."],
                .check: ["Check. Your king is in my orbit.", "Check. The sky is closing in."],
                .botWins: ["The stars were on my side tonight.", "A clear night and a clean win."],
                .botLoses: ["A brilliant constellation of moves.", "You outshone me. Well played."],
                .draw: ["Two stars in balance. A draw.", "Perfect equilibrium."],
                .drawDeclined: ["The night is still young."],
                .takeback: ["Very well, let's rewind the sky."]
            ]
        ),
        Bot(
            id: "atlas", name: "Atlas", rating: 2100, group: .master,
            symbol: "cpu", color: Color(hex: 0x4B4845),
            bio: "A polite robot who carries the whole opening tree on its shoulders.",
            lines: [
                .greeting: ["Greetings. Initiating game protocol.", "Hello, human. Good luck."],
                .playerCaptures: ["Material loss logged.", "Unexpected. Recalculating."],
                .botCaptures: ["Piece acquired.", "Capture executed."],
                .playerBlunder: ["Evaluation shifted in my favor.", "Error detected in your last move."],
                .check: ["Check. Your move is required.", "Check detected."],
                .botWins: ["Game complete. Thank you for playing.", "Victory logged. Well fought."],
                .botLoses: ["Impressive. Updating my database.", "Defeat logged. You played well."],
                .draw: ["Result: balanced. Draw accepted.", "Equal outcome computed."],
                .drawDeclined: ["Negative. The position still has play."],
                .takeback: ["Reverting to previous state."]
            ]
        ),
        Bot(
            id: "orrin", name: "Archmage Orrin", rating: 2200, group: .master,
            symbol: "sparkles", color: Color(hex: 0x6B3FA0),
            bio: "An ancient wizard who swears he doesn't use magic. Mostly.",
            lines: [
                .greeting: ["Welcome, brave one. Let the duel begin!", "Ah, a challenger approaches."],
                .playerCaptures: ["A clever spell, young one.", "You dispelled my piece!"],
                .botCaptures: ["Poof! Vanished.", "A simple conjuring trick."],
                .playerBlunder: ["I sense a disturbance in your position.", "My crystal ball foresaw that."],
                .check: ["Check! Feel the arcane pressure.", "Check. The runes glow brightly."],
                .botWins: ["The ancient arts prevail. Good duel!", "Magic, or just good chess?"],
                .botLoses: ["Remarkable! You'd make a fine apprentice.", "Your magic is stronger today."],
                .draw: ["Our powers are evenly matched.", "A stalemate of sorcerers."],
                .drawDeclined: ["My spellbook still has pages left."],
                .takeback: ["I shall turn back time. Just this once."]
            ]
        )
    ]

    static func bot(id: String) -> Bot? { all.first { $0.id == id } }

    static func bots(in group: BotGroup) -> [Bot] { all.filter { $0.group == group } }

    static var defaultBot: Bot { all[2] }
}
