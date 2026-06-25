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

test('start sends advance_scene to each player', async () => {
  const { session, log } = makeSession();
  session.start();
  await new Promise(r => setTimeout(r, 100));
  const scenes = msgsOf(log, 'advance_scene');
  assert.ok(scenes.length >= 3);
  const auctioneer = scenes.find(e => e.msg.scene === 'auctioneer_view');
  assert.ok(auctioneer, 'auctioneer should receive auctioneer_view');
  const bidders = scenes.filter(e => e.msg.scene === 'bidder_view');
  assert.equal(bidders.length, 2);
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
