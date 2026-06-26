'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { ROLE_POOL, assignRoles } = require('../../server/roles');

const rng = () => Math.random();
const fakeDeck = Array.from({ length: 20 }, (_, i) => ({ id: `item_${i}`, name: `Item ${i}` }));

test('assigns one role per player', () => {
  const ids = ['alice', 'bob', 'carol'];
  const result = assignRoles(ids, fakeDeck, rng);
  assert.equal(Object.keys(result).length, 3);
  for (const id of ids) assert.ok(result[id].role.id);
});

test('assigns unique roles', () => {
  const ids = ['a', 'b', 'c', 'd', 'e', 'f'];
  const result = assignRoles(ids, fakeDeck, rng);
  const roleIds = Object.values(result).map(r => r.role.id);
  assert.equal(new Set(roleIds).size, roleIds.length);
});

test('objective points to a real deck item', () => {
  const result = assignRoles(['alice'], fakeDeck, rng);
  assert.ok(fakeDeck.find(d => d.id === result['alice'].objectiveItemId));
});

test('initial abilityUsed is false', () => {
  const result = assignRoles(['alice'], fakeDeck, rng);
  assert.equal(result['alice'].abilityUsed, false);
});

test('throws when player count exceeds pool', () => {
  const ids = Array.from({ length: 21 }, (_, i) => `p${i}`);
  assert.throws(() => assignRoles(ids, fakeDeck, rng), /Too many players/);
});

test('ROLE_POOL has exactly 20 entries with unique ids', () => {
  assert.equal(ROLE_POOL.length, 20);
  const ids = ROLE_POOL.map(r => r.id);
  assert.equal(new Set(ids).size, 20);
});
