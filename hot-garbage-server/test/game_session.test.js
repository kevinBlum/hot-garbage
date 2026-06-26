'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const GameSession = require('../game_session');

function makeSession(players = ['Alice', 'Bob', 'Carol']) {
  const log = [];
  const send = (to, msg) => log.push({ to, msg });
  const session = new GameSession(players, { pitchDuration: 0, chaosChance: 0 }, send);
  return { session, log };
}

function msgsOf(log, type, to = undefined) {
  return log.filter(e => e.msg.type === type && (to === undefined || e.to === to));
}

test('start sends advance_scene auction_house to all players', async () => {
  const { session, log } = makeSession();
  session.start();
  await new Promise(r => setTimeout(r, 100));
  const scenes = msgsOf(log, 'advance_scene');
  assert.equal(scenes.length, 1, 'only one advance_scene should be sent');
  assert.equal(scenes[0].to, null, 'advance_scene should be broadcast');
  assert.equal(scenes[0].msg.scene, 'auction_house');
});

test('start sends auctioneer_reveal to auctioneer only', async () => {
  const { session, log } = makeSession();
  session.start();
  await new Promise(r => setTimeout(r, 100));
  const reveals = msgsOf(log, 'auctioneer_reveal');
  assert.equal(reveals.length, 1);
  assert.notEqual(reveals[0].to, null); // targeted, not broadcast
});

test('auctioneer_reveal artifact has value; start_pitch does not', async () => {
  const { session, log } = makeSession();
  session.start();
  await new Promise(r => setTimeout(r, 100));
  const reveal = msgsOf(log, 'auctioneer_reveal')[0];
  assert.ok(typeof reveal.msg.artifact.value === 'number');
  const pitch = msgsOf(log, 'start_pitch')[0];
  assert.equal(pitch.msg.artifact.value, undefined);
});

test('pitchDuration=0 opens bidding immediately', async () => {
  const { session, log } = makeSession();
  session.start();
  await new Promise(r => setTimeout(r, 100));
  assert.ok(msgsOf(log, 'open_bidding').length > 0);
});

test('submitBid sends bid_count to auctioneer', async () => {
  const { session, log } = makeSession(['Alice', 'Bob', 'Carol']);
  session.start();
  await new Promise(r => setTimeout(r, 100));
  log.length = 0; // clear startup messages
  session.submitBid('Bob', 100);
  const counts = msgsOf(log, 'bid_count');
  assert.equal(counts.length, 1);
  assert.equal(counts[0].msg.received, 1);
  assert.equal(counts[0].msg.total, 2);
});

test('all bids received triggers bid_result broadcast', async () => {
  const { session, log } = makeSession(['Alice', 'Bob', 'Carol']);
  session.start();
  await new Promise(r => setTimeout(r, 100));
  session.submitBid('Bob', 300);
  session.submitBid('Carol', 100);
  await new Promise(r => setTimeout(r, 100));
  assert.ok(msgsOf(log, 'bid_result').length > 0);
});

test('bid_result artifact has no value field', async () => {
  const { session, log } = makeSession(['Alice', 'Bob', 'Carol']);
  session.start();
  await new Promise(r => setTimeout(r, 100));
  session.submitBid('Bob', 100);
  session.submitBid('Carol', 0);
  await new Promise(r => setTimeout(r, 100));
  const results = msgsOf(log, 'bid_result');
  assert.ok(results.length > 0);
  assert.equal(results[0].msg.artifact.value, undefined);
});

test('auctioneer bid is ignored', async () => {
  const { session, log } = makeSession(['Alice', 'Bob', 'Carol']);
  session.start();
  await new Promise(r => setTimeout(r, 100));
  session.submitBid('Alice', 999); // Alice is auctioneer — should be ignored
  session.submitBid('Bob', 100);
  session.submitBid('Carol', 50);
  await new Promise(r => setTimeout(r, 100));
  // Should still resolve (Alice's bid didn't block allBidsReceived)
  assert.ok(msgsOf(log, 'bid_result').length > 0);
});

test('start_pitch includes round and totalRounds', async () => {
  const { session, log } = makeSession();
  session.start();
  await new Promise(r => setTimeout(r, 100));
  const pitch = msgsOf(log, 'start_pitch')[0];
  assert.ok(pitch, 'start_pitch should be sent');
  assert.equal(pitch.msg.round, 1, 'first turn is round 1');
  assert.equal(typeof pitch.msg.totalRounds, 'number');
  assert.ok(pitch.msg.totalRounds > 0);
});

test('junk category is masked as unknown in start_pitch', async () => {
  const log = [];
  const send = (to, msg) => log.push({ to, msg });
  const junkArtifact = { id: 99, name: 'Trash Bag', category: 'junk', flavor: 'Smells bad' };
  const mockEngine = {
    startAuction: () => ({ ...junkArtifact }),
    getAuctioneerArtifact: () => ({ ...junkArtifact, value: 50 }),
    submitBid: () => {},
    allBidsReceived: () => false,
    resolveAuction: () => ({ winner: 'BANK', price: 0, artifact: { id: 99 } }),
    maybeChaos: () => null,
    getFinalScores: () => [],
    getRounds: () => 5,
    getOrder: () => ['Alice', 'Bob', 'Carol'],
    players: {
      Alice: { cash: 1000, artifacts: [] },
      Bob:   { cash: 1000, artifacts: [] },
      Carol: { cash: 1000, artifacts: [] },
    },
  };
  const session = new GameSession(
    ['Alice', 'Bob', 'Carol'],
    { pitchDuration: 0, chaosChance: 0, _engineFactory: () => mockEngine },
    send
  );
  session.start();
  await new Promise(r => setTimeout(r, 100));
  const pitches = log.filter(e => e.msg.type === 'start_pitch');
  assert.ok(pitches.length > 0, 'start_pitch should be sent');
  for (const p of pitches) {
    assert.notEqual(p.msg.artifact.category, 'junk', 'junk must be masked in start_pitch');
    assert.equal(p.msg.artifact.category, 'unknown');
  }
  // Auctioneer reveal must still see real category
  const reveal = log.find(e => e.msg.type === 'auctioneer_reveal');
  assert.ok(reveal);
  assert.equal(reveal.msg.artifact.category, 'junk', 'auctioneer_reveal must preserve real category');
});

test('bid timer auto-resolves auction when no bids received', async () => {
  const { session, log } = makeSession(['Alice', 'Bob', 'Carol']);
  // Override bidTimeout in config — re-create with low timeout
  const log2 = [];
  const send2 = (to, msg) => log2.push({ to, msg });
  const session2 = new GameSession(
    ['Alice', 'Bob', 'Carol'],
    { pitchDuration: 0, chaosChance: 0, bidTimeout: 0.05 },
    send2
  );
  session2.start();
  await new Promise(r => setTimeout(r, 300));
  const results = log2.filter(e => e.msg.type === 'bid_result');
  assert.ok(results.length > 0, 'auction must auto-resolve via bid timer');
});

test('resolveAuction does not send advance_scene', async () => {
  const { session, log } = makeSession(['Alice', 'Bob', 'Carol']);
  session.start();
  await new Promise(r => setTimeout(r, 100));
  log.length = 0; // clear startup messages
  session.openEarly('Alice'); // trigger bidding
  await new Promise(r => setTimeout(r, 50));
  session.forceResolve('Alice');
  await new Promise(r => setTimeout(r, 100));
  const scenes = msgsOf(log, 'advance_scene');
  assert.equal(scenes.length, 0, 'no advance_scene during auction resolve');
});
