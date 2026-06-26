'use strict';
const { HotGarbage } = require('./engine');
const { rankPlayers } = require('./scoring');
const { assignRoles } = require('./roles');

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
    this._roleState = {};
    this._precisionHistory = {};
    this._smashedCurrentItem = false;
    this._lastAuctionWinner = null;
    this._lastAuctionArtifact = null;
    this._brokeMode = new Set();
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

    let result;
    if (!bids.length || bids[0].bid <= 0) {
      seller.cash += this.bankFloor;
      (this._precisionHistory[this._currentAuctioneer] ||= []).push(1.0);
      result = { artifact, winner: 'BANK', price: this.bankFloor, sellerGain: this.bankFloor, precisionMult: 1.0 };
    } else {
      const top = bids[0];
      const winner = this.players[top.id];
      const mult = this._precisionMultiplier(artifact.value, top.bid);
      const payout = Math.round(top.bid * mult);
      winner.cash -= top.bid;
      winner.artifacts.push({ ...artifact });
      seller.cash += payout;
      (this._precisionHistory[this._currentAuctioneer] ||= []).push(mult);
      result = { artifact, winner: top.id, price: top.bid, sellerGain: payout, precisionMult: mult };
    }
    if (result.winner !== 'BANK') {
      this._lastAuctionWinner = result.winner;
      this._lastAuctionArtifact = result.artifact;
    }
    this._checkBroke();
    return result;
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

  initRoles() {
    this._roleState = assignRoles(this.order, this.deck, this.rng);
    for (const id of this.order) this._precisionHistory[id] = [];
  }

  getPlayerRole(playerId) {
    return this._roleState[playerId] ?? null;
  }

  _precisionMultiplier(trueValue, bid) {
    if (trueValue <= 0) return 1.0;
    const ratio = bid / trueValue;
    if (ratio >= 1.25) return 1.25;
    if (ratio >= 0.90) return 1.15;
    if (ratio >= 0.60) return 1.0;
    return 0.8;
  }

  checkSetRush() {
    let oneAway = null;
    for (const id of this.order) {
      const byCat = {};
      for (const a of this.players[id].artifacts) {
        byCat[a.category] = (byCat[a.category] || 0) + 1;
      }
      for (const [cat, count] of Object.entries(byCat)) {
        if (count >= 3) return { triggered: true, winner: id, category: cat };
        if (count === 2 && !oneAway) oneAway = { oneAway: true, player: id, category: cat };
      }
    }
    return oneAway;
  }

  _checkBroke() {
    for (const id of this.order) {
      if (this.players[id].cash <= 0) this._brokeMode.add(id);
    }
  }

  getBrokeMode() {
    return this._brokeMode;
  }
}

module.exports = { HotGarbageServer };
