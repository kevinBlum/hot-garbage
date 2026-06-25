# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run a 4-player bot simulation (the main dev loop)
node server/simulate.js

# Common flags
node server/simulate.js --seed 42          # reproducible game
node server/simulate.js --players 6        # 6 players
node server/simulate.js --rounds 5         # override round count
node server/simulate.js --chaos 0.4        # higher chaos frequency

# npm shortcuts
npm run sim          # same as node server/simulate.js
npm run sim:6        # 6 players, chaos 0.4
```

No build step, no tests. Node 18+ required.

## Architecture

The codebase is at Phase 0 (simulation only). The three server modules are intentionally kept free of network/UI code so the same logic will power a hot-seat prototype and eventually a WebSocket server.

### `server/engine.js` — `HotGarbage` class

The game state machine. Constructed with `{ seed, playerIds, ...opts }` and driven by calling `game.run(bidStrategy)`. Key design choices:

- **Randomness is injected** via a seeded mulberry32 RNG (`makeRng(seed)`), making games fully reproducible.
- **`bidStrategy(game, ctx) → number`** is a callback passed to `run()` and `runAuction()`. The engine never decides bids itself — callers supply a function. This is the seam where human input (or bot logic) plugs in.
- **`ctx`** passed to `bidStrategy`: `{ artifact, ownArtifacts, cash, categories }`. Crucially, `ctx` does NOT include `artifact.value` — bidders never see true value, only category.
- **Chaos** fires after each auction at `chaosChance` probability: either an Appraiser reveal (announces the sold artifact's true value vs. price) or a random Event card.
- The `flags` object (e.g. `forgeriesDouble`) accumulates game-wide state effects from events.
- `run()` clones `this.categories` before passing to scoring so event-mutated multipliers don't persist.

### `server/scoring.js` — pure functions

`scorePlayer(artifacts, cash, categories)` and `rankPlayers(players, categories)`. No side effects, no randomness. A set bonus applies when a player owns `≥ SET_THRESHOLD` (3) artifacts of one category; otherwise multiplier is 1.0.

### `server/simulate.js` — bot harness

Wires a `botBid` strategy to `HotGarbage`. Bots bid by **category need** (how many of that category they already own), not by artifact value — deliberately mirroring how human players must reason. This is the reference example for implementing real player input.

### `data/artifacts.json`

60 artifacts across 5 categories (12 each): antiquities, curios, relics, forgeries, junk. Each artifact has `{ id, name, category, value, tag, flavor }`. The `categories` object at the top defines `setBonus` per category (forgeries: 2.5×, junk: 1.5×, others: 2.0×) and UI colors.

## Key invariants to preserve

- **True values must never reach non-owner clients.** When Phase 2 (networked) is built, `artifact.value` must only be sent to the auctioneer's client. The engine already enforces this via the `ctx` API.
- **`engine.js` and `scoring.js` must stay I/O-free.** No `fs`, no `fetch`, no `console` in these modules.
- **The category never lies.** Category is always public; value is always private until reveal. This is the core game mechanic — don't add anything that leaks value information outside of Appraiser reveals.

## Godot UI centering rule

**Never use `set_anchors_preset(Control.PRESET_CENTER)` with `custom_minimum_size`.** In Godot 4 this places the anchor at (0.5, 0.5) with zero offsets, giving the node a zero-size rect. When `custom_minimum_size` forces expansion the rect grows asymmetrically, landing the content off-center.

Always use `_UITheme.add_center_container(parent)` instead:

```gdscript
# correct
var vbox := VBoxContainer.new()
vbox.custom_minimum_size = Vector2(640, 520)
_UITheme.add_center_container(self).add_child(vbox)

# wrong — do not do this
var vbox := VBoxContainer.new()
vbox.set_anchors_preset(Control.PRESET_CENTER)   # BUG
vbox.custom_minimum_size = Vector2(640, 520)
add_child(vbox)
```

`add_center_container` wraps the boilerplate: creates a `CenterContainer` with `PRESET_FULL_RECT`, adds it to the parent, and returns it. Every full-screen scene that needs a centered content block must go through this helper.
