'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { HotGarbageServer } = require('../../server/engine_split');

const DATA_PATH = path.join(__dirname, '../../data/artifacts.json');

function makeGame(players = ['Alice', 'Bob', 'Carol']) {
  return new HotGarbageServer({ seed: 42, playerIds: players, dataPath: DATA_PATH });
}

test('startAuction returns public artifact without value', () => {
  const g = makeGame();
  const pub = g.startAuction('Alice');
  assert.ok(pub.id);
  assert.ok(pub.name);
  assert.ok(pub.category);
  assert.ok(pub.flavor);
  assert.equal(pub.value, undefined);
});

test('getAuctioneerArtifact returns artifact with value', () => {
  const g = makeGame();
  g.startAuction('Alice');
  const full = g.getAuctioneerArtifact();
  assert.ok(typeof full.value === 'number');
});

test('submitBid records bid; auctioneer bid ignored', () => {
  const g = makeGame();
  g.startAuction('Alice');
  g.submitBid('Alice', 999); // auctioneer — should be ignored
  g.submitBid('Bob', 100);
  assert.equal(g.allBidsReceived(), false); // Carol hasn't bid
  g.submitBid('Carol', 200);
  assert.equal(g.allBidsReceived(), true);
});

test('submitBid clamps to player cash', () => {
  const g = makeGame();
  g.startAuction('Alice');
  g.submitBid('Bob', 999999);
  g.submitBid('Carol', 0);
  const result = g.resolveAuction();
  assert.equal(result.winner, 'Bob');
  assert.ok(result.price <= 1000); // clamped to starting cash
});

test('resolveAuction: highest bid wins', () => {
  const g = makeGame();
  g.startAuction('Alice');
  g.submitBid('Bob', 300);
  g.submitBid('Carol', 500);
  const result = g.resolveAuction();
  assert.equal(result.winner, 'Carol');
  assert.equal(result.price, 500);
});

test('resolveAuction: no bids → BANK wins at bankFloor', () => {
  const g = makeGame();
  g.startAuction('Alice');
  g.submitBid('Bob', 0);
  g.submitBid('Carol', 0);
  const result = g.resolveAuction();
  assert.equal(result.winner, 'BANK');
  assert.equal(result.price, 25);
});

test('maybeChaos returns object (may be empty)', () => {
  const g = makeGame();
  g.startAuction('Alice');
  g.submitBid('Bob', 100);
  g.submitBid('Carol', 0);
  const result = g.resolveAuction();
  const chaos = g.maybeChaos(result);
  assert.equal(typeof chaos, 'object');
});

test('getFinalScores returns ranked array', () => {
  const g = makeGame();
  g.startAuction('Alice');
  g.submitBid('Bob', 100);
  g.submitBid('Carol', 0);
  g.resolveAuction();
  const ranking = g.getFinalScores();
  assert.equal(ranking.length, 3);
  assert.ok(ranking[0].total >= ranking[1].total);
});

test('getRounds and getOrder', () => {
  const g = makeGame(['Alice', 'Bob', 'Carol']);
  assert.equal(g.getRounds(), 3);
  assert.deepEqual(g.getOrder(), ['Alice', 'Bob', 'Carol']);
});

test('initRoles: assigns a role to every player', () => {
  const g = makeGame();
  g.initRoles();
  for (const id of ['Alice', 'Bob', 'Carol']) {
    const state = g.getPlayerRole(id);
    assert.ok(state, `expected role for ${id}`);
    assert.ok(state.role.id);
  }
});

test('initRoles: getPlayerRole returns null for unknown player', () => {
  const g = makeGame();
  g.initRoles();
  assert.equal(g.getPlayerRole('nobody'), null);
});

test('precision: >=125% bid → 1.25x', () => {
  const g = makeGame();
  assert.equal(g._precisionMultiplier(100, 125), 1.25);
  assert.equal(g._precisionMultiplier(100, 300), 1.25);
});

test('precision: 90-125% bid → 1.15x', () => {
  const g = makeGame();
  assert.equal(g._precisionMultiplier(100, 100), 1.15);
  assert.equal(g._precisionMultiplier(100, 90), 1.15);
});

test('precision: 60-90% bid → 1.0x', () => {
  const g = makeGame();
  assert.equal(g._precisionMultiplier(100, 80), 1.0);
  assert.equal(g._precisionMultiplier(100, 60), 1.0);
});

test('precision: <60% bid → 0.8x', () => {
  const g = makeGame();
  assert.equal(g._precisionMultiplier(100, 59), 0.8);
  assert.equal(g._precisionMultiplier(100, 0), 0.8);
});

test('resolveAuction includes precisionMult in result', () => {
  const g = makeGame();
  g.startAuction('Alice');
  g.submitBid('Bob', 500);
  g.submitBid('Carol', 200);
  const result = g.resolveAuction();
  assert.ok(typeof result.precisionMult === 'number');
});
