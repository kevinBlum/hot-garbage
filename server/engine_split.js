'use strict';
const { HotGarbage } = require('./engine');
const { rankPlayers } = require('./scoring');

const EVENTS = [
  { id: 'market_crash',      text: 'MARKET CRASH — Forgeries score double this game.' },
  { id: 'museum_heist',      text: 'MUSEUM HEIST — a random player loses their priciest artifact to the Bank.' },
  { id: 'bidding_frenzy',    text: 'BIDDING FRENZY — next auction, everyone must bid at least 50.' },
  { id: 'insider_tip',       text: 'INSIDER TIP — a random bidder secretly learns the next true band.' },
  { id: 'counterfeit_scare', text: 'COUNTERFEIT SCARE — next Forgery is halved at reveal.' },
];

class HotGarbageServer extends HotGarbage {
  constructor(opts) {
    super(opts);
    this._currentAuctioneer = null;
    this._currentArtifact = null;
    this._submittedBids = {};
  }

  startAuction(auctioneerId) {
    this._currentAuctioneer = auctioneerId;
    this._currentArtifact = this._draw();
    this._submittedBids = {};
    const { id, name, category, flavor } = this._currentArtifact;
    return { id, name, category, flavor };
  }

  getAuctioneerArtifact() {
    return { ...this._currentArtifact };
  }

  submitBid(playerId, amount) {
    if (playerId === this._currentAuctioneer) return;
    if (!this.players[playerId]) return;
    if (this._submittedBids[playerId] !== undefined) return;
    const p = this.players[playerId];
    this._submittedBids[playerId] = Math.max(0, Math.min(Math.floor(amount || 0), p.cash));
  }

  allBidsReceived() {
    for (const id of this.order) {
      if (id !== this._currentAuctioneer && this._submittedBids[id] === undefined) return false;
    }
    return true;
  }

  resolveAuction() {
    const artifact = this._currentArtifact;
    const seller = this.players[this._currentAuctioneer];
    const bids = Object.entries(this._submittedBids)
      .map(([id, bid]) => ({ id, bid }))
      .sort((a, b) => b.bid - a.bid);

    if (!bids.length || bids[0].bid <= 0) {
      seller.cash += this.bankFloor;
      return { artifact, winner: 'BANK', price: this.bankFloor, sellerGain: this.bankFloor };
    }
    const top = bids[0];
    const winner = this.players[top.id];
    winner.cash -= top.bid;
    winner.artifacts.push({ ...artifact });
    seller.cash += top.bid;
    return { artifact, winner: top.id, price: top.bid, sellerGain: top.bid };
  }

  maybeChaos(lastResult) {
    if (this.rng() >= this.chaosChance) return {};
    if (this.rng() < 0.5) {
      if (lastResult.winner !== 'BANK') {
        const { artifact, winner, price } = lastResult;
        const verdict = artifact.value > price ? 'A STEAL' : 'ROBBED';
        return {
          type: 'appraiser',
          text: `"${artifact.name}" truly worth ${artifact.value} — ${winner} got ${verdict}.`,
          extra: {},
        };
      }
      return {};
    }
    const ev = this._pick(EVENTS);
    const extra = {};
    if (ev.id === 'market_crash') this.flags.forgeriesDouble = true;
    if (ev.id === 'museum_heist') {
      const victim = this._pick(this.order);
      const arts = this.players[victim].artifacts;
      if (arts.length) {
        let idx = 0;
        for (let i = 1; i < arts.length; i++) if (arts[i].value > arts[idx].value) idx = i;
        const lost = arts.splice(idx, 1)[0];
        extra.victim = victim;
        extra.lostName = lost.name;
      }
    }
    return { type: 'event', text: ev.text, extra };
  }

  _pick(arr) {
    return arr[Math.floor(this.rng() * arr.length)];
  }

  getFinalScores() {
    const cats = JSON.parse(JSON.stringify(this.categories));
    if (this.flags.forgeriesDouble && cats.forgeries) cats.forgeries.setBonus *= 2;
    return rankPlayers(this.players, cats);
  }

  getRounds() { return this.rounds; }
  getOrder() { return this.order.slice(); }
}

module.exports = { HotGarbageServer };
