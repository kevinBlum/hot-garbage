# Hot Garbage — Build Roadmap

## Phase 0 — Validate the loop (you are here)
- [x] Artifact deck (`data/artifacts.json`)
- [x] Scoring module (`server/scoring.js`)
- [x] Headless engine (`server/engine.js`)
- [x] Terminal bot simulation (`server/simulate.js`)
- [ ] Playtest the sim, tune bands/bonuses/bankroll until win conditions feel right

## Phase 1 — Local hot-seat prototype
- [ ] Minimal CLI or single-screen web page that passes one device around
- [ ] Real pitches spoken aloud; device only handles values, bids, scoring
- [ ] This is the cheapest way to test if the *social* part is fun (it's the whole game)

## Phase 2 — Networked phones-as-controllers
- [ ] Pick stack. Lightweight option: a Node + WebSocket (`ws`) host + static client; one shared "TV" screen + phone controllers (the Jackbox model)
- [ ] Room codes, lobby, reconnect handling
- [ ] Server is authoritative; reuse `engine.js` verbatim as the rules core
- [ ] Private value reveal must be server-side only (never ship true values to non-owner clients)

## Phase 3 — Content & feel
- [ ] Artifact art (even simple icon + color per category goes a long way)
- [ ] Sound: gavel, crowd "ooh," appraiser sting
- [ ] More artifacts; curse cards; more event cards
- [ ] Spoken-pitch timer + "going once / twice / sold" cadence

## Tech notes (for your homelab/AWS instincts)
- The authoritative-server + dumb-clients split maps cleanly onto a small container you could run in your homelab for LAN games, or a single Lambda-backed WebSocket API (API Gateway WebSocket + Lambda) for cheap hosted play. The engine is pure JS with no I/O, so it drops into either.
- Keep `engine.js` and `scoring.js` free of network/UI code (they already are) so the same logic runs in the terminal sim, the hot-seat prototype, and the hosted version.

## Open questions
1. **Pitches: spoken or typed?** Spoken = funnier, zero dev cost, needs people in a call/room. Typed = works fully async/remote but loses energy. Recommend spoken default, typed fallback.
2. **Economy balance:** starting bankroll vs. average artifact value. Too much cash = no tension; too little = nobody can complete sets. Sim is the place to tune this.
3. **Bank floor purchase:** does it pay the auctioneer a pittance, or just vanish the item? Affects how punishing a flopped con is.
4. **Round count vs. time:** N = player count is elegant but 8 players × 8 rounds is too long. Cap rounds (~6) and rotate who starts.
5. **Information leak risk:** if you let players see their own *future* hand, smart players plan around it and chaos drops. Draw-per-turn keeps it loose.
