# Hot Garbage — Design Specification

> Working title. Alt: *Provenance*, *Going Once*, *Caveat Emptor*.

## 1. Design pillars

1. **The category never lies, the value always might.** Players always see *what kind* of thing an artifact is; they never see what it's *worth* unless they own it or it gets appraised. This single honest signal is the skill floor that keeps a pure-bluff game from collapsing into a coin flip.
2. **The win condition forces buying.** Scoring rewards completed themed collections, so players must re-enter the shark tank every round instead of hoarding cash. Buying is not optional.
3. **Chaos makes losing funny.** Random reveals and market events mean a great con can evaporate and a worthless lot can spike. Getting fooled should produce a table laugh, not a grudge.
4. **Pace over depth.** 15–20 minutes total. Every system must justify itself against the clock.

## 2. Players & components

- **Players:** 4–8. Sweet spot 5–6.
- **Deck:** 60 artifacts (see `data/artifacts.json`), 12 per category × 5 categories.
- **Money:** everyone starts with a fixed bankroll (default §1000 — the § is a "simoleon" so no real-currency confusion).
- **Categories:** Antiquities, Curios, Relics, Forgeries, Junk.

## 3. Artifact anatomy

| Field | Visible to owner | Visible to table |
|-------|:---:|:---:|
| Name | ✅ | ✅ |
| Category | ✅ | ✅ |
| Flavor text | ✅ | ✅ |
| **True value** | ✅ | ❌ (until appraisal/endgame) |

True values are drawn from five bands (trash / modest / solid / treasure / grail) so the spread is wide enough that bluffing has real stakes.

## 4. Round structure

A game is **N rounds** (default = number of players, so everyone auctions an equal number of times; cap at ~6 for time).

Each round, every player takes one turn as **Auctioneer**:

1. **Draw & reveal.** Auctioneer privately sees their artifact's true value. Table sees name + category + flavor.
2. **The Pitch.** Auctioneer talks it up (spoken aloud is best; typed-and-read works remote). 20–30 sec soft timer.
3. **The Bidding.** Open ascending bids OR one-shot sealed bids (see §7 variant). Highest bid wins; winner pays, auctioneer collects.
4. **Resolution.** Artifact moves to winner's collection. Money transfers. If nobody bids above the reserve, **the Bank buys at a lowball floor** (default 10% of a fixed reference, or a flat §25) so artifacts always move and a failed con still stings the auctioneer.
5. **Chaos check.** After resolution, roll the chaos trigger (default 1-in-4): fire an Appraiser reveal or an Event card.

At end of final round: **the Grand Reveal** — all owned artifacts flip face-up, collections score, highest total wins.

## 5. Scoring & collections

Final score = Σ (value of each owned artifact) × (set multiplier for its category), plus leftover cash.

- **Set multiplier** kicks in when you own ≥3 artifacts of one category. Multiplier values per category live in `artifacts.json` (`setBonus`). Forgeries pay the most (2.5×) because they're the riskiest to collect blind; Junk pays least (1.5×).
- **Singletons & pairs** score at 1.0× (base value only).
- **Cash** counts 1:1, so a player who never buys *can* win on hoarded cash — but the multipliers make a completed set almost always beat a cash pile, which is the intended pressure.

> **Tuning lever:** if cash-hoarding wins too often in playtests, add a small per-round "storage tax" on cash, or cap counted cash. Don't nerf collections — that's the heart.

## 6. Chaos systems

**Appraiser reveals** (the table-laugh engine): a recently-sold artifact gets its true value announced. Instant payoff — did the buyer get robbed or score a steal?

**Event cards** (drawn on chaos trigger):
- *Market Crash* — all Forgeries score double this game. (Rewards the brave.)
- *Museum Heist* — a random player loses their single most valuable owned artifact to the Bank.
- *Bidding Frenzy* — next auction: no passing, everyone must bid at least §50.
- *Insider Tip* — one random non-owner secretly learns the next artifact's true band.
- *Counterfeit Scare* — next Forgery auctioned has its value halved at reveal.
- *Estate Sale* — auctioneer must sell TWO artifacts as a bundle.

**Mystery Lots:** occasionally the auctioneer also doesn't know the value (blind to everyone). Pure gamble; great for chaos dial.

## 7. Variants & tuning dials

- **Bidding style:** Open ascending (loud, social, slower) vs. Sealed simultaneous (faster, more bluff-pure). Default open.
- **Chaos dial:** trigger frequency 1-in-6 (tame) → 1-in-2 (mayhem). Default 1-in-4.
- **Hand size:** deal each player their full round's-worth up front (they choose pitch order) vs. draw one per turn. Default draw-per-turn (less to track on a phone).
- **Curse cards:** a few artifacts could carry hidden negative modifiers that tank a collection at reveal — flagged as a future addition, not in v1 data.

## 8. Why these three locked choices work together

The user's locked decisions — **pure bluff**, **collection win**, **high chaos** — interlock:

- Pure bluff alone risks noise; the collection win condition anchors bidding to honest *category* signals so there's always a reason to bid even when value is unknowable.
- Collection win alone risks slow optimization; high chaos keeps it loose and fast.
- High chaos alone risks feeling unfair; the honest category signal preserves enough skill that good players still edge out, and the public reveals make the randomness communal and funny.

## 9. Open design questions

See `ROADMAP.md` §Open Questions. Top three:
1. Spoken vs. typed pitches as the default for the digital build.
2. Exact starting bankroll vs. average artifact value (economy balance).
3. Whether the Bank-floor purchase should pay the auctioneer or just remove the item.
