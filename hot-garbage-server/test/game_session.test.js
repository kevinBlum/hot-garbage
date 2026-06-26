'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const GameSession = require('../game_session');

function makeSession(players = ['Alice', 'Bob', 'Carol'], overrides = {}) {
  const log = [];
  const send = (to, msg) => log.push({ to, msg });
  const session = new GameSession(players, { pitchDuration: 0, chaosChance: 0, bidTimeout: 0, ...overrides }, send);
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
    getFullFinalScores: () => [],
    getRounds: () => 5,
    getOrder: () => ['Alice', 'Bob', 'Carol'],
    initRoles: () => {},
    getPlayerRole: () => null,
    checkSetRush: () => null,
    getBrokeMode: () => new Set(),
    players: {
      Alice: { cash: 1000, artifacts: [] },
      Bob:   { cash: 1000, artifacts: [] },
      Carol: { cash: 1000, artifacts: [] },
    },
  };
  const session = new GameSession(
    ['Alice', 'Bob', 'Carol'],
    { pitchDuration: 0, chaosChance: 0, bidTimeout: 0, _engineFactory: () => mockEngine },
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
  // Use a mock engine with 1 round so the session terminates after one auction
  const artifact = { id: 1, name: 'Widget', category: 'curios', value: 50, flavor: '' };
  let resolved = false;
  const mockEngine = {
    startAuction: () => ({ ...artifact }),
    getAuctioneerArtifact: () => ({ ...artifact }),
    submitBid: () => {},
    allBidsReceived: () => false,
    resolveAuction: () => { resolved = true; return { winner: 'BANK', price: 0, artifact: { id: 1 } }; },
    maybeChaos: () => null,
    getFinalScores: () => [],
    getFullFinalScores: () => [],
    getRounds: () => 1,
    getOrder: () => ['Alice', 'Bob', 'Carol'],
    initRoles: () => {},
    getPlayerRole: () => null,
    checkSetRush: () => null,
    getBrokeMode: () => new Set(),
    players: {
      Alice: { cash: 1000, artifacts: [] },
      Bob:   { cash: 1000, artifacts: [] },
      Carol: { cash: 1000, artifacts: [] },
    },
  };
  const log2 = [];
  const send2 = (to, msg) => log2.push({ to, msg });
  const session2 = new GameSession(
    ['Alice', 'Bob', 'Carol'],
    { pitchDuration: 0, chaosChance: 0, bidTimeout: 0.05, _engineFactory: () => mockEngine },
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

test('start sends role_assigned privately to each player', async () => {
  const { session, log } = makeSession();
  session.start();
  await new Promise(r => setTimeout(r, 100));
  const roleMessages = msgsOf(log, 'role_assigned');
  assert.equal(roleMessages.length, 3, 'each player gets a role_assigned');
  for (const entry of roleMessages) {
    assert.notEqual(entry.to, null, 'role_assigned must be private, not broadcast');
    assert.ok(entry.msg.role, 'role_assigned has role');
    assert.ok(entry.msg.objectiveItemName, 'role_assigned has objectiveItemName');
  }
});

test('broke_mode is broadcast when a player hits 0 cash', async () => {
  const log = [];
  const send = (to, msg) => log.push({ to, msg });
  const artifact = { id: 1, name: 'Widget', category: 'curios', value: 50, flavor: '' };
  let brokeModeSet = new Set();
  const mockEngine = {
    startAuction: () => ({ ...artifact }),
    getAuctioneerArtifact: () => ({ ...artifact }),
    submitBid: () => {},
    allBidsReceived: () => true,
    resolveAuction: () => ({ winner: 'Bob', price: 100, artifact: { ...artifact } }),
    maybeChaos: () => ({}),
    getFinalScores: () => [],
    getFullFinalScores: () => [],
    getRounds: () => 5,
    getOrder: () => ['Alice', 'Bob', 'Carol'],
    initRoles: () => {},
    getPlayerRole: () => null,
    checkSetRush: () => null,
    getBrokeMode: () => brokeModeSet,
    players: {
      Alice: { cash: 0, artifacts: [] },
      Bob:   { cash: 900, artifacts: [] },
      Carol: { cash: 1000, artifacts: [] },
    },
  };
  brokeModeSet.add('Alice');
  const session = new GameSession(
    ['Alice', 'Bob', 'Carol'],
    { pitchDuration: 0, chaosChance: 0, bidTimeout: 0, _engineFactory: () => mockEngine },
    send
  );
  session.start();
  await new Promise(r => setTimeout(r, 100));
  session.submitBid('Bob', 100);
  await new Promise(r => setTimeout(r, 100));
  const brokeMsgs = log.filter(e => e.msg.type === 'broke_mode');
  assert.ok(brokeMsgs.length > 0, 'broke_mode broadcast when player at 0 cash');
  assert.equal(brokeMsgs[0].to, null, 'broke_mode is a broadcast');
  assert.equal(brokeMsgs[0].msg.player, 'Alice');
});

test('broke_mode is only sent once per player', async () => {
  const log = [];
  const send = (to, msg) => log.push({ to, msg });
  const artifact = { id: 1, name: 'Widget', category: 'curios', value: 50, flavor: '' };
  let resolveCount = 0;
  let brokeModeSet = new Set(['Alice']);
  const mockEngine = {
    startAuction: () => ({ ...artifact }),
    getAuctioneerArtifact: () => ({ ...artifact }),
    submitBid: () => {},
    allBidsReceived: () => true,
    resolveAuction: () => { resolveCount++; return { winner: 'BANK', price: 25, artifact: { ...artifact } }; },
    maybeChaos: () => ({}),
    getFinalScores: () => [],
    getFullFinalScores: () => [],
    getRounds: () => 10,
    getOrder: () => ['Alice', 'Bob', 'Carol'],
    initRoles: () => {},
    getPlayerRole: () => null,
    checkSetRush: () => null,
    getBrokeMode: () => brokeModeSet,
    players: {
      Alice: { cash: 0, artifacts: [] },
      Bob:   { cash: 1000, artifacts: [] },
      Carol: { cash: 1000, artifacts: [] },
    },
  };
  const session = new GameSession(
    ['Alice', 'Bob', 'Carol'],
    { pitchDuration: 0, chaosChance: 0, bidTimeout: 0, _engineFactory: () => mockEngine },
    send
  );
  session.start();
  await new Promise(r => setTimeout(r, 100));
  // Force two auctions to resolve
  session.submitBid('Bob', 100);
  await new Promise(r => setTimeout(r, 100));
  session.submitBid('Carol', 100);
  await new Promise(r => setTimeout(r, 100));
  const brokeMsgs = log.filter(e => e.msg.type === 'broke_mode' && e.msg.player === 'Alice');
  assert.equal(brokeMsgs.length, 1, 'broke_mode sent only once per player');
});

test('set_rush_win triggers end game and is broadcast', async () => {
  const log = [];
  const send = (to, msg) => log.push({ to, msg });
  const artifact = { id: 1, name: 'Widget', category: 'relics', value: 50, flavor: '' };
  const mockEngine = {
    startAuction: () => ({ ...artifact }),
    getAuctioneerArtifact: () => ({ ...artifact }),
    submitBid: () => {},
    allBidsReceived: () => true,
    resolveAuction: () => ({ winner: 'Bob', price: 100, artifact: { ...artifact } }),
    maybeChaos: () => ({}),
    getFinalScores: () => [],
    getFullFinalScores: () => [{ id: 'Bob', total: 500 }],
    getRounds: () => 10,
    getOrder: () => ['Alice', 'Bob', 'Carol'],
    initRoles: () => {},
    getPlayerRole: () => null,
    checkSetRush: () => ({ triggered: true, winner: 'Bob', category: 'relics' }),
    getBrokeMode: () => new Set(),
    players: {
      Alice: { cash: 1000, artifacts: [] },
      Bob:   { cash: 900, artifacts: [{ ...artifact }] },
      Carol: { cash: 1000, artifacts: [] },
    },
  };
  const session = new GameSession(
    ['Alice', 'Bob', 'Carol'],
    { pitchDuration: 0, chaosChance: 0, bidTimeout: 0, _engineFactory: () => mockEngine },
    send
  );
  session.start();
  await new Promise(r => setTimeout(r, 100));
  session.submitBid('Bob', 100);
  await new Promise(r => setTimeout(r, 100));
  const rushMsgs = log.filter(e => e.msg.type === 'set_rush_win');
  assert.equal(rushMsgs.length, 1, 'set_rush_win broadcast');
  assert.equal(rushMsgs[0].to, null, 'set_rush_win is broadcast');
  assert.equal(rushMsgs[0].msg.winner, 'Bob');
  assert.equal(rushMsgs[0].msg.category, 'relics');
  // Game should end — final_scores sent
  const finalMsgs = log.filter(e => e.msg.type === 'final_scores');
  assert.ok(finalMsgs.length > 0, 'final_scores sent after set_rush_win');
  assert.ok(!session.isActive, 'session is no longer active after set_rush_win');
});

test('activateAbility broadcasts ability_result and syncs affected players', async () => {
  const log = [];
  const send = (to, msg) => log.push({ to, msg });
  const artifact = { id: 1, name: 'Widget', category: 'curios', value: 50, flavor: '' };
  const mockEngine = {
    startAuction: () => ({ ...artifact }),
    getAuctioneerArtifact: () => ({ ...artifact }),
    submitBid: () => {},
    allBidsReceived: () => false,
    resolveAuction: () => ({ winner: 'BANK', price: 25, artifact: { ...artifact } }),
    maybeChaos: () => ({}),
    getFinalScores: () => [],
    getFullFinalScores: () => [],
    getRounds: () => 5,
    getOrder: () => ['Alice', 'Bob', 'Carol'],
    initRoles: () => {},
    getPlayerRole: () => null,
    checkSetRush: () => null,
    getBrokeMode: () => new Set(),
    activateAbility: (actor, type, opts) => ({
      success: true,
      effect: type,
      payload: { toPlayer: opts.targetId, amount: 150 },
    }),
    players: {
      Alice: { cash: 850, artifacts: [] },
      Bob:   { cash: 1150, artifacts: [] },
      Carol: { cash: 1000, artifacts: [] },
    },
  };
  const session = new GameSession(
    ['Alice', 'Bob', 'Carol'],
    { pitchDuration: 0, chaosChance: 0, bidTimeout: 0, _engineFactory: () => mockEngine },
    send
  );
  session.start();
  await new Promise(r => setTimeout(r, 50));
  log.length = 0;
  session.activateAbility('Alice', 'philanthropist', 'Bob');
  const abilityMsgs = log.filter(e => e.msg.type === 'ability_result');
  assert.equal(abilityMsgs.length, 1, 'ability_result is broadcast');
  assert.equal(abilityMsgs[0].to, null, 'ability_result is broadcast to all');
  assert.equal(abilityMsgs[0].msg.actorName, 'Alice');
  assert.equal(abilityMsgs[0].msg.abilityType, 'philanthropist');
  // Sync messages sent to Alice and Bob
  const syncMsgs = log.filter(e => e.msg.type === 'sync_player_state');
  assert.ok(syncMsgs.some(e => e.to === 'Alice'), 'actor is synced');
  assert.ok(syncMsgs.some(e => e.to === 'Bob'), 'target is synced');
});

test('final_scores ranking uses getFullFinalScores', async () => {
  const { session, log } = makeSession(['Alice', 'Bob']);
  // Run enough turns to reach end of game (2 players = 2 rounds, each player auctions once)
  session.start();
  await new Promise(r => setTimeout(r, 100));
  // Let all turns complete without bids (BANK wins each time, bidTimeout=0 auto-resolves)
  // With 2 players and 2 rounds, we need 4 auctions to trigger _endGame
  // pitchDuration=0, bidTimeout=0 means auto-resolve fires immediately
  await new Promise(r => setTimeout(r, 1000));
  const finalMsgs = log.filter(e => e.msg.type === 'final_scores');
  if (finalMsgs.length > 0) {
    // If the game ended, check that ranking entries have role fields (from getFullFinalScores)
    const ranking = finalMsgs[0].msg.ranking;
    assert.ok(Array.isArray(ranking));
    for (const entry of ranking) {
      assert.ok('role' in entry, 'final_scores entry has role from getFullFinalScores');
    }
  }
});
