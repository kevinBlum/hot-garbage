# Hot Garbage 🗑️✨

A friend-slop party game of bluffing, bidding, and bad provenance. 4–8 players, ~15–20 minutes, phones-as-controllers.

You're handed a hand of dubious artifacts. **Only you know what each is truly worth.** Take turns auctioning them off — hype, lie, do a bit — while everyone else tries to read whether you're sitting on a Holy Grail or a haunted music box. Spend your winnings building **themed collections**; complete a set and it multiplies. At the end, everything flips face-up and the cons are revealed.

## The one-paragraph pitch

Each round, players take turns as the auctioneer. The auctioneer sees the **true value** of their artifact; everyone else sees only its **category** (Antiquities, Curios, Relics, Forgeries, Junk) and the auctioneer's pitch. The table bids real money. Because the win condition rewards **completed collections**, players will overpay for the category they need — and the auctioneer knows it. Random "Appraiser" reveals and market-event cards inject chaos so getting conned is funny, not bitter.

## Repo layout

```
hot-garbage/
├── README.md              ← you are here
├── docs/
│   ├── DESIGN.md          ← full design spec & rules
│   ├── RULES.md           ← player-facing quick rules
│   └── ROADMAP.md         ← build phases & open questions
├── data/
│   └── artifacts.json     ← the 60-card starter deck
├── server/
│   ├── scoring.js         ← pure scoring + collection logic
│   ├── engine.js          ← game state machine (framework-free)
│   └── simulate.js        ← runs a full bot game in the terminal
└── client/                ← (stub) where the phone UI goes later
```

## Quick start

```bash
# requires Node 18+
cd hot-garbage
node server/simulate.js        # play a full 4-bot game in your terminal
node server/simulate.js --seed 42 --players 6   # reproducible, 6 players
```

The simulation exercises the real engine and scoring code, so once it feels right you build UI on top of `engine.js` without touching the rules.

## Design north star

This is a **social-chaos** game, not a math game. The single honest signal — an artifact's *category* never lies, only its *value* does — is the skill anchor that keeps players engaged. Protect it. Everything else can be loud, random, and ridiculous.

## License

Your call — MIT is a sane default for a hobby repo.
