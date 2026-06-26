'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { HotGarbageServer } = require('../../server/engine_split');

const DATA_PATH = path.join(__dirname, '../../data/artifacts.json');

function makeGame(players = ['Alice', 'Bob', 'Carol']) {
  const g = new HotGarbageServer({ seed: 42, playerIds: players, dataPath: DATA_PATH });
  g.initRoles();
  // Force deterministic roles for testing
  g._roleState['Alice'].role = { id: 'thief',         name: 'THIEF',         activationPhase: 'bid_result', requiresTarget: true  };
  g._roleState['Bob'].role   = { id: 'smasher',       name: 'SMASHER',       activationPhase: 'pitch',      requiresTarget: false };
  g._roleState['Carol'].role = { id: 'appraiser',     name: 'APPRAISER',     activationPhase: 'auction',    requiresTarget: false };
  return g;
}

test('activateAbility: rejects if ability already used', () => {
  const g = makeGame();
  g._roleState['Alice'].abilityUsed = true;
  const r = g.activateAbility('Alice', 'thief', {});
  assert.equal(r.success, false);
  assert.match(r.effect, /already used/i);
});

test('activateAbility: rejects if role does not match ability', () => {
  const g = makeGame();
  const r = g.activateAbility('Alice', 'smasher', {});
  assert.equal(r.success, false);
  assert.match(r.effect, /not your role/i);
});

test('thief: transfers artifact from last winner to actor', () => {
  const g = makeGame();
  const artifact = { id: 'jade', name: 'Jade Elephant', category: 'relics', value: 300 };
  g.players['Bob'].artifacts = [artifact];
  g._lastAuctionWinner = 'Bob';
  g._lastAuctionArtifact = artifact;
  const r = g.activateAbility('Alice', 'thief', { targetId: 'Bob' });
  assert.equal(r.success, true);
  assert.equal(g.players['Bob'].artifacts.length, 0);
  assert.equal(g.players['Alice'].artifacts[0].id, 'jade');
  assert.equal(g._roleState['Alice'].abilityUsed, true);
});

test('thief: fails if target is not last auction winner', () => {
  const g = makeGame();
  g._lastAuctionWinner = 'Carol';
  const r = g.activateAbility('Alice', 'thief', { targetId: 'Bob' });
  assert.equal(r.success, false);
});

test('smasher: sets _smashedCurrentItem flag', () => {
  const g = makeGame();
  g._currentArtifact = { id: 'vase', name: 'Ming Vase', category: 'antiquities', value: 400 };
  const r = g.activateAbility('Bob', 'smasher', {});
  assert.equal(r.success, true);
  assert.equal(g._smashedCurrentItem, true);
  assert.equal(r.payload.smashedItemName, 'Ming Vase');
});

test('smasher: resolveAuction returns BANK when item smashed', () => {
  const g = makeGame();
  g.startAuction('Alice');
  g.activateAbility('Bob', 'smasher', {});
  g.submitBid('Bob', 500);
  g.submitBid('Carol', 200);
  const result = g.resolveAuction();
  assert.equal(result.winner, 'BANK');
});

test('appraiser: returns true value in payload', () => {
  const g = makeGame();
  g._currentArtifact = { id: 'vase', name: 'Ming Vase', category: 'antiquities', value: 450 };
  const r = g.activateAbility('Carol', 'appraiser', {});
  assert.equal(r.success, true);
  assert.equal(r.payload.trueValue, 450);
  assert.equal(r.payload.itemName, 'Ming Vase');
});

test('philanthropist: transfers 150 cash between players', () => {
  const g = new HotGarbageServer({ seed: 42, playerIds: ['Alice','Bob'], dataPath: DATA_PATH });
  g.initRoles();
  g._roleState['Alice'].role = { id: 'philanthropist', name: 'PHILANTHROPIST', activationPhase: 'any', requiresTarget: true };
  const aliceBefore = g.players['Alice'].cash;
  const bobBefore = g.players['Bob'].cash;
  const r = g.activateAbility('Alice', 'philanthropist', { targetId: 'Bob' });
  assert.equal(r.success, true);
  assert.equal(g.players['Alice'].cash, aliceBefore - 150);
  assert.equal(g.players['Bob'].cash, bobBefore + 150);
});
