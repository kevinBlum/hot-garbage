'use strict';
const path = require('path');
const { HotGarbageServer } = require('../server/engine_split');

const DATA_PATH = path.join(__dirname, '../data/artifacts.json');

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

class GameSession {
  constructor(playerNames, config, send) {
    this._playerNames = playerNames;
    this._config = config;
    this._engineFactory = config._engineFactory || null;
    this._pitchDuration = (config.pitchDuration ?? 45) * 1000;
    this._chaosChance = config.chaosChance ?? 0.25;
    this._send = send; // fn(playerName|null, msg)
    this._engine = null;
    this._order = [];
    this._round = 1;
    this._turnIdx = 0;
    this._biddingOpen = false;
    this._pendingResolve = false;
    this._turnGen = 0;
    this._currentAuctioneer = null;
    this._receivedBidCount = 0;
    this.isActive = false;
  }

  start() {
    this.isActive = true;
    this._engine = this._engineFactory
      ? this._engineFactory()
      : new HotGarbageServer({
          seed: (Math.random() * 0x100000000) >>> 0,
          playerIds: this._playerNames,
          chaosChance: this._chaosChance,
          dataPath: DATA_PATH,
        });
    this._order = this._engine.getOrder();
    this._engine.initRoles();
    this._notifiedBroke = new Set();
    for (const name of this._playerNames) {
      const rs = this._engine.getPlayerRole(name);
      if (rs) {
        this._send(name, {
          type: 'role_assigned',
          role: rs.role,
          objectiveItemId: rs.objectiveItemId,
          objectiveItemName: rs.objectiveItemName,
          objectiveBonus: rs.objectiveBonus,
        });
      }
    }
    this._send(null, { type: 'advance_scene', scene: 'auction_house' });
    this._beginTurn();
  }

  async _beginTurn() {
    if (this._round > this._engine.getRounds()) {
      this._endGame();
      return;
    }

    this._turnGen++;
    const myGen = this._turnGen;
    this._biddingOpen = false;
    this._pendingResolve = false;
    this._receivedBidCount = 0;

    this._currentAuctioneer = this._order[this._turnIdx];
    const bidderCount = this._playerNames.length - 1;

    const publicArtifact = this._engine.startAuction(this._currentAuctioneer);
    const fullArtifact = this._engine.getAuctioneerArtifact();

    // Mask junk category so bidders can't identify it from category alone
    if (publicArtifact.category === 'junk') publicArtifact.category = 'unknown';

    this._send(this._currentAuctioneer, {
      type: 'auctioneer_reveal',
      artifact: fullArtifact,
      pitchDuration: this._pitchDuration / 1000,
    });

    this._send(null, {
      type: 'start_pitch',
      artifact: publicArtifact,
      pitchDuration: this._pitchDuration / 1000,
      auctioneerName: this._currentAuctioneer,
      round: this._round,
      totalRounds: this._engine.getRounds(),
    });

    await sleep(this._pitchDuration);
    if (myGen === this._turnGen && !this._biddingOpen) {
      this._openBidding();
    }
  }

  _openBidding() {
    if (this._biddingOpen) return;
    this._biddingOpen = true;
    const timeout = this._config.bidTimeout ?? 30;
    this._send(null, { type: 'open_bidding', bidTimeout: timeout });
    if (timeout > 0) {
      setTimeout(() => {
        if (this._biddingOpen && !this._pendingResolve) this._resolveAuction();
      }, timeout * 1000);
    }
  }

  openEarly(playerName) {
    if (playerName !== this._currentAuctioneer) return;
    this._openBidding();
  }

  submitBid(playerName, amount) {
    if (!this._biddingOpen || this._pendingResolve) return;
    if (playerName === this._currentAuctioneer) return;
    this._engine.submitBid(playerName, amount);
    this._receivedBidCount++;
    const bidderCount = this._playerNames.length - 1;
    this._send(this._currentAuctioneer, {
      type: 'bid_count',
      received: this._receivedBidCount,
      total: bidderCount,
    });
    if (this._engine.allBidsReceived()) {
      this._resolveAuction();
    }
  }

  forceResolve(playerName) {
    if (!this._biddingOpen || this._pendingResolve) return;
    // Only host (first player) can force resolve
    if (playerName !== this._playerNames[0]) return;
    this._resolveAuction();
  }

  async _resolveAuction() {
    if (this._pendingResolve) return;
    this._pendingResolve = true;

    const result = this._engine.resolveAuction();
    const chaos = this._engine.maybeChaos(result);

    // Sync all players after auction resolves
    for (const name of this._playerNames) {
      this._syncPlayer(name);
    }

    const publicArtifact = { ...result.artifact };
    delete publicArtifact.value;

    // Send bid result before checking set rush so players see the outcome
    this._send(null, {
      type: 'bid_result',
      winner: result.winner,
      price: result.price,
      artifact: publicArtifact,
    });

    const rush = this._engine.checkSetRush();
    if (rush?.triggered) {
      this._send(null, { type: 'set_rush_win', winner: rush.winner, category: rush.category });
      this._endGame();
      return;
    }
    if (rush?.oneAway) {
      this._send(null, { type: 'one_away', player: rush.player, category: rush.category });
    }

    for (const name of this._engine.getBrokeMode()) {
      if (!this._notifiedBroke.has(name)) {
        this._notifiedBroke.add(name);
        this._send(null, { type: 'broke_mode', player: name });
      }
    }

    if (chaos && chaos.type) {
      this._send(null, { type: 'chaos', ...chaos });
    }

    this._turnIdx++;
    if (this._turnIdx >= this._order.length) {
      this._turnIdx = 0;
      this._round++;
    }

    this._pendingResolve = false;
    this._receivedBidCount = 0;
    this._beginTurn();
  }

  _syncPlayer(playerName) {
    if (playerName === 'BANK') return;
    const p = this._engine.players[playerName];
    if (!p) return;
    const safeArtifacts = p.artifacts.map(({ value, ...rest }) => rest);
    this._send(playerName, { type: 'sync_player_state', cash: p.cash, artifacts: safeArtifacts });
  }

  activateAbility(playerName, abilityType, targetName) {
    if (!this.isActive) return;
    const result = this._engine.activateAbility(playerName, abilityType, { targetId: targetName || null });
    if (result.success) {
      this._send(null, {
        type: 'ability_result',
        actorName: playerName,
        abilityType,
        effect: result.effect,
        payload: result.payload,
      });
      const toSync = new Set([playerName]);
      if (targetName) toSync.add(targetName);
      for (const name of toSync) this._syncPlayer(name);
    }
  }

  async _endGame() {
    this.isActive = false;
    this._send(null, { type: 'final_scores', ranking: this._engine.getFullFinalScores() });
  }
}

module.exports = GameSession;
