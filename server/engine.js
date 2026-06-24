'use strict';
/**
 * Hot Garbage engine: a pure-ish state machine for the game rules.
 * No network, no UI. Randomness is injected via a seedable RNG so games
 * are reproducible. The same engine powers the terminal sim, a hot-seat
 * prototype, and (later) an authoritative server.
 */

const fs = require('fs');
const path = require('path');
const { rankPlayers } = require('./scoring');

// ---- seedable RNG (mulberry32) ----
function makeRng(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const pick = (rng, arr) => arr[Math.floor(rng() * arr.length)];
function shuffle(rng, arr) {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

const EVENTS = [
  { id: 'market_crash',     text: 'MARKET CRASH — Forgeries score double this game.' },
  { id: 'museum_heist',     text: 'MUSEUM HEIST — a random player loses their priciest artifact to the Bank.' },
  { id: 'bidding_frenzy',   text: 'BIDDING FRENZY — next auction, everyone must bid at least 50.' },
  { id: 'insider_tip',      text: 'INSIDER TIP — a random bidder secretly learns the next true band.' },
  { id: 'counterfeit_scare',text: 'COUNTERFEIT SCARE — next Forgery is halved at reveal.' },
];

class HotGarbage {
  /**
   * @param {Object} opts
   * @param {number} opts.seed
   * @param {string[]} opts.playerIds
   * @param {number} [opts.startingCash=1000]
   * @param {number} [opts.rounds]              defaults to playerIds.length, capped at 6
   * @param {number} [opts.chaosChance=0.25]
   * @param {number} [opts.bankFloor=25]
   * @param {string} [opts.dataPath]
   */
  constructor(opts) {
    this.rng = makeRng(opts.seed ?? 1);
    this.log = [];
    const dataPath = opts.dataPath || path.join(__dirname, '..', 'data', 'artifacts.json');
    const data = JSON.parse(fs.readFileSync(dataPath, 'utf8'));
    this.categories = data.categories;
    this.deck = shuffle(this.rng, data.artifacts);
    this.deckPtr = 0;

    this.startingCash = opts.startingCash ?? 1000;
    this.chaosChance = opts.chaosChance ?? 0.25;
    this.bankFloor = opts.bankFloor ?? 25;
    this.rounds = Math.min(opts.rounds ?? opts.playerIds.length, 6);

    this.players = {};
    for (const id of opts.playerIds) {
      this.players[id] = { id, cash: this.startingCash, artifacts: [] };
    }
    this.order = opts.playerIds.slice();
    this.flags = { forgeriesDouble: false };
  }

  _draw() {
    if (this.deckPtr >= this.deck.length) {
      this.deck = shuffle(this.rng, this.deck);
      this.deckPtr = 0;
    }
    return this.deck[this.deckPtr++];
  }

  _emit(msg) { this.log.push(msg); }

  /**
   * Run one auction. `bidStrategy(state, ctx) -> number` returns each
   * non-auctioneer's max willingness to pay. The engine resolves the winner.
   */
  runAuction(auctioneerId, bidStrategy) {
    const artifact = this._draw();
    const seller = this.players[auctioneerId];

    // Collect sealed max-bids from everyone except the auctioneer.
    const bids = [];
    for (const id of this.order) {
      if (id === auctioneerId) continue;
      const p = this.players[id];
      const ctx = { artifact, ownArtifacts: p.artifacts, cash: p.cash, categories: this.categories };
      let bid = Math.floor(bidStrategy(this, ctx) || 0);
      bid = Math.max(0, Math.min(bid, p.cash)); // can't bid more than you have
      bids.push({ id, bid });
    }
    bids.sort((a, b) => b.bid - a.bid);
    const top = bids[0];

    let result;
    if (!top || top.bid <= 0) {
      // Nobody wants it: Bank floor purchase.
      seller.cash += this.bankFloor;
      result = { artifact, winner: 'BANK', price: this.bankFloor, sellerGain: this.bankFloor };
      this._emit(`${auctioneerId} pitched "${artifact.name}" (${artifact.category}) — no takers. Bank pays ${this.bankFloor}.`);
    } else {
      const winner = this.players[top.id];
      winner.cash -= top.bid;
      winner.artifacts.push({ ...artifact });
      seller.cash += top.bid;
      result = { artifact, winner: top.id, price: top.bid, sellerGain: top.bid };
      this._emit(`${auctioneerId} sold "${artifact.name}" (${artifact.category}, true ${artifact.value}) to ${top.id} for ${top.bid}.`);
    }

    this._maybeChaos(result);
    return result;
  }

  _maybeChaos(lastResult) {
    if (this.rng() >= this.chaosChance) return;
    if (this.rng() < 0.5) {
      // Appraiser reveal
      const r = lastResult;
      if (r.winner !== 'BANK') {
        const verdict = r.artifact.value > r.price ? 'A STEAL' : 'ROBBED';
        this._emit(`  🔍 APPRAISER: "${r.artifact.name}" truly worth ${r.artifact.value} — ${r.winner} got ${verdict}.`);
      }
    } else {
      const ev = pick(this.rng, EVENTS);
      this._emit(`  🎲 EVENT: ${ev.text}`);
      if (ev.id === 'market_crash') this.flags.forgeriesDouble = true;
      if (ev.id === 'museum_heist') {
        const victim = pick(this.rng, this.order);
        const arts = this.players[victim].artifacts;
        if (arts.length) {
          let idx = 0;
          for (let i = 1; i < arts.length; i++) if (arts[i].value > arts[idx].value) idx = i;
          const lost = arts.splice(idx, 1)[0];
          this._emit(`     ${victim} loses "${lost.name}" to the heist.`);
        }
      }
    }
  }

  /** Run the whole game; returns final ranking. */
  run(bidStrategy) {
    for (let round = 1; round <= this.rounds; round++) {
      this._emit(`\n=== ROUND ${round} ===`);
      for (const auctioneerId of this.order) {
        this.runAuction(auctioneerId, bidStrategy);
      }
    }
    // Apply game-wide flags into scoring categories (clone so we don't mutate source).
    const cats = JSON.parse(JSON.stringify(this.categories));
    if (this.flags.forgeriesDouble && cats.forgeries) cats.forgeries.setBonus *= 2;
    return rankPlayers(this.players, cats);
  }
}

module.exports = { HotGarbage, makeRng, shuffle };
