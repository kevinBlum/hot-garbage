# Hot Garbage: Core Mechanics Implementation Plan (1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add secret roles + objectives, auctioneer precision multiplier, set-rush win condition, and broke mode to the live networked game.

**Architecture:** All game-state changes are authoritative in `server/engine_split.js` (`HotGarbageServer`) and orchestrated through `hot-garbage-server/game_session.js`. New features add a `server/roles.js` module, extend the engine with role/precision/set-rush state, add new WebSocket message types, and wire Godot client overlays and E-key proximity activation.

**Tech Stack:** Node.js 18+ CommonJS, Node built-in test runner (`node:test`), GDScript 4, WebSocket

## Global Constraints

- `server/engine.js` and `server/scoring.js` must stay I/O-free — no fs, fetch, or console
- `artifact.value` must never be sent to non-owner clients (existing invariant)
- Roles are private — `role_assigned` is sent only to the assigned player, never broadcast
- Role abilities require physical 3D E-key activation — no HUD-only activation paths
- Follow GDScript 4 patterns: typed vars, `_UITheme` for all styling, `add_center_container` for centering
- Tests use Node built-in `test()` and `assert/strict` — no external test frameworks

---

### Task 1: Role pool definitions (`server/roles.js`)

**Files:**
- Create: `server/roles.js`
- Create: `hot-garbage-server/test/roles.test.js`

**Interfaces:**
- Produces:
  - `ROLE_POOL: Array<{ id, name, description, activationPhase, requiresTarget }>`
  - `assignRoles(playerIds: string[], deck: Object[], rng: () => number): { [playerId]: RoleState }`
  - `RoleState: { role, objectiveItemId, objectiveItemName, objectiveBonus, objectiveComplete, abilityUsed, vaultedItemId }`

- [ ] **Step 1: Create `server/roles.js`**

```js
'use strict';

const ROLE_POOL = [
  { id: 'thief',         name: 'THIEF',         description: 'Steal the just-auctioned item from the winner.',        activationPhase: 'bid_result', requiresTarget: true  },
  { id: 'smasher',       name: 'SMASHER',       description: 'Destroy the item on the pedestal during pitch.',        activationPhase: 'pitch',      requiresTarget: false },
  { id: 'saboteur',      name: 'SABOTEUR',      description: 'Swap the pedestal item for a random deck card.',        activationPhase: 'pitch',      requiresTarget: false },
  { id: 'insider',       name: 'INSIDER',       description: 'Peek at the current item\'s true value privately.',     activationPhase: 'pitch',      requiresTarget: false },
  { id: 'fence',         name: 'FENCE',         description: 'Sell one artifact you own back to bank at true value.', activationPhase: 'any',        requiresTarget: false },
  { id: 'secret_buyer',  name: 'SECRET BUYER',  description: 'As auctioneer, buy the item yourself.',                activationPhase: 'bid_result', requiresTarget: false },
  { id: 'appraiser',     name: 'APPRAISER',     description: 'Publicly broadcast the true value to all players.',    activationPhase: 'auction',    requiresTarget: false },
  { id: 'mole',          name: 'MOLE',          description: 'Peek at the next item in the deck.',                   activationPhase: 'any',        requiresTarget: false },
  { id: 'vandal',        name: 'VANDAL',        description: 'Secretly reduce the item\'s true value by 30%.',       activationPhase: 'pitch',      requiresTarget: false },
  { id: 'speculator',    name: 'SPECULATOR',    description: 'Predict HIGH or LOW vs true value for a cash bonus.',  activationPhase: 'bidding',    requiresTarget: false },
  { id: 'ghost',         name: 'GHOST',         description: 'Make your winning bid anonymous for one auction.',      activationPhase: 'bidding',    requiresTarget: false },
  { id: 'emcee',         name: 'EMCEE',         description: 'Hijack the auctioneer role for this round.',           activationPhase: 'pitch',      requiresTarget: false },
  { id: 'extortionist',  name: 'EXTORTIONIST',  description: 'Lock a player out of bidding in this auction.',        activationPhase: 'bidding',    requiresTarget: true  },
  { id: 'shill',         name: 'SHILL',         description: 'Submit a fake bid; if highest, auction fails to bank.',activationPhase: 'bidding',    requiresTarget: false },
  { id: 'smuggler',      name: 'SMUGGLER',      description: 'Steal any artifact from any player\'s collection.',    activationPhase: 'any',        requiresTarget: true  },
  { id: 'hoarder',       name: 'HOARDER',       description: 'Vault one artifact so it cannot be stolen.',           activationPhase: 'any',        requiresTarget: false },
  { id: 'price_fixer',   name: 'PRICE FIXER',   description: 'Set a mandatory minimum bid before an auction.',       activationPhase: 'pre_pitch',  requiresTarget: false },
  { id: 'swapper',       name: 'SWAPPER',       description: 'Force a trade: your worst artifact for theirs.',       activationPhase: 'any',        requiresTarget: true  },
  { id: 'philanthropist',name: 'PHILANTHROPIST', description: 'Give 150 cash to a player; own your target to win.',  activationPhase: 'any',        requiresTarget: true  },
  { id: 'arsonist',      name: 'ARSONIST',      description: 'Destroy one random artifact from any player.',         activationPhase: 'any',        requiresTarget: false },
];

const OBJECTIVE_BONUSES = {
  thief: 750, smasher: 600, saboteur: 500, insider: 400, fence: 450,
  secret_buyer: 700, appraiser: 400, mole: 350, vandal: 500, speculator: 400,
  ghost: 650, emcee: 600, extortionist: 500, shill: 400, smuggler: 700,
  hoarder: 550, price_fixer: 400, swapper: 450, philanthropist: 1000, arsonist: 500,
};

function assignRoles(playerIds, deck, rng) {
  if (playerIds.length > ROLE_POOL.length) {
    throw new Error(`Too many players (${playerIds.length}) for role pool (${ROLE_POOL.length})`);
  }
  const shuffled = ROLE_POOL.slice().sort(() => rng() - 0.5);
  const assigned = {};
  for (let i = 0; i < playerIds.length; i++) {
    const role = shuffled[i];
    const targetIdx = Math.floor(rng() * deck.length);
    assigned[playerIds[i]] = {
      role,
      objectiveItemId: deck[targetIdx].id,
      objectiveItemName: deck[targetIdx].name,
      objectiveBonus: OBJECTIVE_BONUSES[role.id] ?? 500,
      objectiveComplete: false,
      abilityUsed: false,
      vaultedItemId: null,
    };
  }
  return assigned;
}

module.exports = { ROLE_POOL, assignRoles, OBJECTIVE_BONUSES };
```

- [ ] **Step 2: Create `hot-garbage-server/test/roles.test.js`**

```js
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
```

- [ ] **Step 3: Run tests**

```bash
cd hot-garbage-server && node --test test/roles.test.js
```

Expected: `6 pass, 0 fail`

- [ ] **Step 4: Commit**

```bash
git add server/roles.js hot-garbage-server/test/roles.test.js
git commit -m "feat: role pool (20 roles) + assignRoles"
```

---

### Task 2: Role state + precision multiplier in `HotGarbageServer`

**Files:**
- Modify: `server/engine_split.js`
- Modify: `hot-garbage-server/test/engine_split.test.js`

**Interfaces:**
- Consumes: `assignRoles` from `server/roles.js`
- Produces:
  - `engine.initRoles(): void` — call after construction, before `start()`
  - `engine.getPlayerRole(playerId: string): RoleState | null`
  - `engine._precisionMultiplier(trueValue: number, bid: number): number`
  - `engine.resolveAuction()` — now returns `precisionMult` field; seller payout is multiplied

- [ ] **Step 1: Add failing tests to `hot-garbage-server/test/engine_split.test.js`**

Append to the existing file:

```js
const { assignRoles } = require('../../server/roles');

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
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd hot-garbage-server && node --test test/engine_split.test.js 2>&1 | tail -8
```

Expected: failures on `initRoles`, `getPlayerRole`, `_precisionMultiplier`

- [ ] **Step 3: Add `require` and new state to `server/engine_split.js`**

At the top of `server/engine_split.js`, after `const { rankPlayers }` line, add:
```js
const { assignRoles } = require('./roles');
```

In the `HotGarbageServer` constructor, after `this._submittedBids = {}`, add:
```js
this._roleState = {};
this._precisionHistory = {};
this._smashedCurrentItem = false;
this._lastAuctionWinner = null;
this._lastAuctionArtifact = null;
```

- [ ] **Step 4: Add `initRoles`, `getPlayerRole`, `_precisionMultiplier` methods**

Add before `module.exports`:
```js
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
```

- [ ] **Step 5: Update `resolveAuction()` to apply precision and track history**

In `resolveAuction()`, find the winning-bid branch where `seller.cash += top.bid`. Replace with:
```js
const mult = this._precisionMultiplier(artifact.value, top.bid);
const payout = Math.round(top.bid * mult);
seller.cash += payout;
(this._precisionHistory[this._currentAuctioneer] ||= []).push(mult);
result = { artifact, winner: top.id, price: top.bid, sellerGain: payout, precisionMult: mult };
```

In the bank-floor branch where `seller.cash += this.bankFloor`, add after it:
```js
(this._precisionHistory[this._currentAuctioneer] ||= []).push(1.0);
```
And update that branch's result to include `precisionMult: 1.0`.

Also track the last auction winner at the end of `resolveAuction()`, before the return:
```js
if (result.winner !== 'BANK') {
  this._lastAuctionWinner = result.winner;
  this._lastAuctionArtifact = result.artifact;
}
return result;
```

- [ ] **Step 6: Run tests**

```bash
cd hot-garbage-server && node --test test/engine_split.test.js
```

Expected: all tests pass

- [ ] **Step 7: Commit**

```bash
git add server/engine_split.js hot-garbage-server/test/engine_split.test.js
git commit -m "feat: role state + precision multiplier in HotGarbageServer"
```

---

### Task 3: Set-rush detection + broke mode

**Files:**
- Modify: `server/engine_split.js`
- Modify: `hot-garbage-server/test/engine_split.test.js`

**Interfaces:**
- Produces:
  - `engine.checkSetRush(): { triggered: true, winner, category } | { oneAway: true, player, category } | null`
  - `engine._checkBroke(): void` — marks newly bankrupt players
  - `engine.getBrokeMode(): Set<string>`

- [ ] **Step 1: Add failing tests**

Append to `hot-garbage-server/test/engine_split.test.js`:

```js
test('checkSetRush: null when no player near a set', () => {
  const g = makeGame();
  assert.equal(g.checkSetRush(), null);
});

test('checkSetRush: oneAway when player has 2 of same category', () => {
  const g = makeGame();
  g.players['Alice'].artifacts = [
    { id: '1', category: 'relics', value: 100 },
    { id: '2', category: 'relics', value: 100 },
  ];
  const r = g.checkSetRush();
  assert.ok(r?.oneAway);
  assert.equal(r.player, 'Alice');
  assert.equal(r.category, 'relics');
});

test('checkSetRush: triggered when player has 3 of same category', () => {
  const g = makeGame();
  g.players['Alice'].artifacts = [
    { id: '1', category: 'relics', value: 100 },
    { id: '2', category: 'relics', value: 100 },
    { id: '3', category: 'relics', value: 100 },
  ];
  const r = g.checkSetRush();
  assert.ok(r?.triggered);
  assert.equal(r.winner, 'Alice');
});

test('_checkBroke: marks player at 0 cash', () => {
  const g = makeGame();
  g.players['Bob'].cash = 0;
  g._checkBroke();
  assert.ok(g.getBrokeMode().has('Bob'));
  assert.ok(!g.getBrokeMode().has('Alice'));
});

test('_checkBroke: does not double-add already-broke player', () => {
  const g = makeGame();
  g.players['Bob'].cash = 0;
  g._checkBroke();
  g._checkBroke();
  assert.equal(g.getBrokeMode().size, 1);
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd hot-garbage-server && node --test test/engine_split.test.js 2>&1 | grep 'fail\|checkSetRush\|checkBroke' | head -10
```

Expected: failures on `checkSetRush`, `_checkBroke`, `getBrokeMode`

- [ ] **Step 3: Add methods to `server/engine_split.js`**

In the constructor, after `this._lastAuctionArtifact = null`, add:
```js
this._brokeMode = new Set();
```

Add methods before `module.exports`:
```js
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
```

In `resolveAuction()`, after the `this._lastAuctionWinner` tracking block, add:
```js
this._checkBroke();
```

- [ ] **Step 4: Run tests**

```bash
cd hot-garbage-server && node --test test/engine_split.test.js
```

Expected: all tests pass

- [ ] **Step 5: Commit**

```bash
git add server/engine_split.js hot-garbage-server/test/engine_split.test.js
git commit -m "feat: set-rush detection + broke mode tracking"
```

---

### Task 4: Ability activation — Thief, Smasher, Appraiser, Philanthropist

**Files:**
- Modify: `server/engine_split.js`
- Create: `hot-garbage-server/test/abilities.test.js`

**Interfaces:**
- Produces:
  - `engine.activateAbility(actorId: string, abilityType: string, opts: { targetId?: string }): { success: bool, effect: string, payload: Object }`
  - `resolveAuction()` — respects `_smashedCurrentItem` flag (returns BANK result early)

- [ ] **Step 1: Create `hot-garbage-server/test/abilities.test.js`**

```js
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
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd hot-garbage-server && node --test test/abilities.test.js 2>&1 | tail -6
```

Expected: `activateAbility is not a function`

- [ ] **Step 3: Add `activateAbility` to `server/engine_split.js`**

Add before `module.exports`:

```js
activateAbility(actorId, abilityType, { targetId = null } = {}) {
  const state = this._roleState[actorId];
  if (!state) return { success: false, effect: 'Unknown player.' };
  if (state.abilityUsed) return { success: false, effect: 'Ability already used.' };
  if (state.role.id !== abilityType) return { success: false, effect: 'Not your role.' };

  let payload = {};
  switch (abilityType) {
    case 'thief': {
      if (!targetId || !this.players[targetId])
        return { success: false, effect: 'Invalid target.' };
      if (this._lastAuctionWinner !== targetId)
        return { success: false, effect: 'Target did not win the last auction.' };
      const artifact = this._lastAuctionArtifact;
      const arts = this.players[targetId].artifacts;
      const idx = arts.findIndex(a => a.id === artifact.id);
      if (idx === -1) return { success: false, effect: 'Item no longer with target.' };
      arts.splice(idx, 1);
      this.players[actorId].artifacts.push(artifact);
      payload = { stolenItemName: artifact.name, fromPlayer: targetId };
      break;
    }
    case 'smasher': {
      if (!this._currentArtifact) return { success: false, effect: 'No item on pedestal.' };
      payload = { smashedItemName: this._currentArtifact.name };
      this._smashedCurrentItem = true;
      break;
    }
    case 'appraiser': {
      if (!this._currentArtifact) return { success: false, effect: 'No current item.' };
      payload = { trueValue: this._currentArtifact.value, itemName: this._currentArtifact.name };
      break;
    }
    case 'philanthropist': {
      if (!targetId || !this.players[targetId]) return { success: false, effect: 'Invalid target.' };
      if (this.players[actorId].cash < 150) return { success: false, effect: 'Insufficient funds.' };
      this.players[actorId].cash -= 150;
      this.players[targetId].cash += 150;
      payload = { toPlayer: targetId, amount: 150 };
      break;
    }
    default:
      return { success: false, effect: `Ability '${abilityType}' not yet implemented.` };
  }

  state.abilityUsed = true;
  return { success: true, effect: abilityType, payload };
}
```

- [ ] **Step 4: Guard smash in `resolveAuction()`**

At the very start of `resolveAuction()`, before any bid logic, add:
```js
this._smashedCurrentItem = false; // reset each auction
```

After the bid sort but before the result assignment block, add:
```js
if (this._smashedCurrentItem) {
  seller.cash += this.bankFloor;
  (this._precisionHistory[this._currentAuctioneer] ||= []).push(1.0);
  this._checkBroke();
  return { artifact, winner: 'BANK', price: this.bankFloor, sellerGain: this.bankFloor, precisionMult: 1.0 };
}
```

- [ ] **Step 5: Run tests**

```bash
cd hot-garbage-server && node --test test/abilities.test.js
```

Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add server/engine_split.js hot-garbage-server/test/abilities.test.js
git commit -m "feat: ability activation — thief, smasher, appraiser, philanthropist"
```

---

### Task 5: Extended final scores + wire into `GameSession`

**Files:**
- Modify: `server/engine_split.js`
- Modify: `hot-garbage-server/game_session.js`
- Modify: `hot-garbage-server/server.js`
- Modify: `hot-garbage-server/test/engine_split.test.js`
- Modify: `hot-garbage-server/test/game_session.test.js`

**Interfaces:**
- Produces:
  - `engine.getFullFinalScores(): Array` — extends `getFinalScores()` with `role`, `objectiveItemName`, `objectiveComplete`, `objectiveBonus`, `precisionHistory`, `abilityUsed`
  - Session sends `role_assigned` privately on `start()`
  - Session sends `one_away`, `broke_mode`, `set_rush_win` after each `resolveAuction`
  - Session sends `ability_result` when ability succeeds
  - `_endGame` uses `getFullFinalScores`

- [ ] **Step 1: Add `getFullFinalScores` failing test**

Append to `hot-garbage-server/test/engine_split.test.js`:

```js
test('getFullFinalScores: includes role, objective, and precisionHistory per player', () => {
  const g = makeGame();
  g.initRoles();
  const scores = g.getFullFinalScores();
  assert.ok(Array.isArray(scores));
  for (const entry of scores) {
    assert.ok(entry.id, 'has id');
    assert.ok(entry.role, 'has role');
    assert.ok(entry.objectiveItemName, 'has objectiveItemName');
    assert.equal(typeof entry.objectiveComplete, 'boolean');
    assert.ok(Array.isArray(entry.precisionHistory));
  }
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd hot-garbage-server && node --test test/engine_split.test.js 2>&1 | grep -A3 'getFullFinalScores'
```

Expected: `getFullFinalScores is not a function`

- [ ] **Step 3: Add `getFullFinalScores` to `server/engine_split.js`**

Add before `module.exports`:

```js
getFullFinalScores() {
  const base = this.getFinalScores();
  return base.map(entry => {
    const roleState = this._roleState[entry.id];
    const playerArts = this.players[entry.id]?.artifacts ?? [];
    const objectiveComplete = roleState
      ? playerArts.some(a => a.id === roleState.objectiveItemId)
      : false;
    const objectiveBonus = objectiveComplete ? (roleState?.objectiveBonus ?? 0) : 0;
    return {
      ...entry,
      total: entry.total + objectiveBonus,
      role: roleState?.role ?? null,
      objectiveItemId: roleState?.objectiveItemId ?? null,
      objectiveItemName: roleState?.objectiveItemName ?? null,
      objectiveComplete,
      objectiveBonus,
      precisionHistory: this._precisionHistory[entry.id] ?? [],
      abilityUsed: roleState?.abilityUsed ?? false,
    };
  });
}
```

- [ ] **Step 4: Update `GameSession.start()` in `hot-garbage-server/game_session.js`**

After `this._order = this._engine.getOrder();`, add:

```js
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
```

- [ ] **Step 5: Update `_resolveAuction()` in `game_session.js` — set-rush + broke mode**

In `_resolveAuction()`, after the `this._syncPlayer` loop (where all players are synced), add:

```js
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
```

- [ ] **Step 6: Add `activateAbility` method to `GameSession`**

Add to `game_session.js`:

```js
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
```

- [ ] **Step 7: Update `_endGame` to use `getFullFinalScores`**

In `_endGame()`, replace `this._engine.getFinalScores()` with `this._engine.getFullFinalScores()`.

- [ ] **Step 8: Add `ability_activate` handler to `hot-garbage-server/server.js`**

After `case 'force_resolve': return handleForceResolve(ws, ctx);`, add:

```js
case 'ability_activate': return handleAbilityActivate(ws, msg, ctx);
```

Then add the handler function near the other handlers:

```js
function handleAbilityActivate(ws, msg, ctx) {
  const room = rooms.get(ctx.roomName);
  if (!room?.session?.isActive) return;
  room.session.activateAbility(ctx.playerName, msg.abilityType ?? '', msg.targetName ?? null);
}
```

- [ ] **Step 9: Run all server tests**

```bash
cd hot-garbage-server && node --test test/engine_split.test.js test/abilities.test.js test/roles.test.js test/game_session.test.js
```

Expected: all pass

- [ ] **Step 10: Commit**

```bash
git add server/engine_split.js hot-garbage-server/game_session.js hot-garbage-server/server.js \
        hot-garbage-server/test/engine_split.test.js hot-garbage-server/test/game_session.test.js
git commit -m "feat: getFullFinalScores, GameSession wires roles + set-rush + broke + ability_activate"
```

---

### Task 6: Godot network layer additions

**Files:**
- Modify: `hot-garbage-godot/src/network/network_transport.gd`
- Modify: `hot-garbage-godot/src/network/network_manager.gd`

**Interfaces:**
- Produces:
  - `NetworkTransport.send_ability_activate(ability_type: String, target_name: String)`
  - Signals on `NetworkManager`: `role_assigned(role: Dictionary, objective: Dictionary)`, `ability_result(data: Dictionary)`, `one_away(player: String, category: String)`, `broke_mode_started(player: String)`, `set_rush_win(winner: String, category: String)`

- [ ] **Step 1: Add `send_ability_activate` to `network_transport.gd`**

Append to `hot-garbage-godot/src/network/network_transport.gd`:

```gdscript
func send_ability_activate(ability_type: String, target_name: String = "") -> void:
	NetworkManager._send({ "type": "ability_activate", "abilityType": ability_type, "targetName": target_name })
```

- [ ] **Step 2: Add signals to `network_manager.gd`**

After the existing signal declarations (after `signal bid_count_updated`), add:

```gdscript
signal role_assigned(role: Dictionary, objective: Dictionary)
signal ability_result(data: Dictionary)
signal one_away(player: String, category: String)
signal broke_mode_started(player: String)
signal set_rush_win(winner: String, category: String)
```

- [ ] **Step 3: Add dispatch cases to `_dispatch()` in `network_manager.gd`**

In the `match msg.get("type", ""):` block, add:

```gdscript
"role_assigned":
    role_assigned.emit(
        msg.get("role", {}),
        {
            "itemId":   msg.get("objectiveItemId", ""),
            "itemName": msg.get("objectiveItemName", ""),
            "bonus":    msg.get("objectiveBonus", 0),
        }
    )
"ability_result":
    ability_result.emit(msg)
"one_away":
    one_away.emit(msg.get("player", ""), msg.get("category", ""))
"broke_mode":
    broke_mode_started.emit(msg.get("player", ""))
"set_rush_win":
    set_rush_win.emit(msg.get("winner", ""), msg.get("category", ""))
    get_tree().get_root().propagate_call("on_set_rush_win",
        [msg.get("winner", ""), msg.get("category", "")], true)
```

- [ ] **Step 4: Verify identifiers exist in both files**

```bash
grep -n "send_ability_activate\|role_assigned\|ability_result\|one_away\|broke_mode\|set_rush_win" \
  hot-garbage-godot/src/network/network_transport.gd \
  hot-garbage-godot/src/network/network_manager.gd
```

Expected: all identifiers found in both files.

- [ ] **Step 5: Commit**

```bash
git add hot-garbage-godot/src/network/network_transport.gd hot-garbage-godot/src/network/network_manager.gd
git commit -m "feat: Godot network layer — ability_activate send + role/ability/broke/rush signals"
```

---

### Task 7: Godot — role card overlay

**Files:**
- Create: `hot-garbage-godot/src/ui/role_card.gd`
- Modify: `hot-garbage-godot/src/scenes/auction_house.gd`

**Interfaces:**
- Consumes: `NetworkManager.role_assigned` signal
- Produces:
  - `RoleCard.show_assigned(role: Dictionary, objective: Dictionary)` — 5s display then fades
  - `RoleCard._start_fade()` — triggers fade-out

- [ ] **Step 1: Create `hot-garbage-godot/src/ui/role_card.gd`**

```gdscript
extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _fade_timer: float = 0.0
var _fading: bool = false

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_assigned(role: Dictionary, objective: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 220)
	_UITheme.add_center_container(self).add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   _UITheme.PAD * 2)
	margin.add_theme_constant_override("margin_right",  _UITheme.PAD * 2)
	margin.add_theme_constant_override("margin_top",    _UITheme.PAD * 2)
	margin.add_theme_constant_override("margin_bottom", _UITheme.PAD * 2)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _UITheme.GAP)
	margin.add_child(vbox)

	var role_lbl := Label.new()
	role_lbl.text = "YOUR ROLE: %s" % role.get("name", "UNKNOWN")
	_UITheme.style_label(role_lbl, _UITheme.FS_ARTIFACT, _UITheme.GOLD)
	role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(role_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = role.get("description", "")
	_UITheme.style_label(desc_lbl, _UITheme.FS_BODY, _UITheme.TEXT)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var obj_lbl := Label.new()
	obj_lbl.text = "OBJECTIVE: Acquire \"%s\" — §%d bonus" % [
		objective.get("itemName", "?"), objective.get("bonus", 0)]
	_UITheme.style_label(obj_lbl, _UITheme.FS_LABEL, _UITheme.DIM)
	obj_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	obj_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(obj_lbl)

	visible = true
	modulate.a = 1.0
	_fading = false
	_fade_timer = 0.0

func _start_fade() -> void:
	_fading = true
	_fade_timer = 1.5

func _process(delta: float) -> void:
	if not _fading:
		return
	_fade_timer -= delta
	if _fade_timer <= 0.0:
		visible = false
		_fading = false
		return
	modulate.a = clampf(_fade_timer / 1.5, 0.0, 1.0)
```

- [ ] **Step 2: Wire role card into `auction_house.gd`**

After `var _final_scores: Control = null`, add:

```gdscript
var _role_card: Control = null
var _my_role: Dictionary = {}
var _my_objective: Dictionary = {}
var _ability_used: bool = false
```

In `_setup_canvas()`, after `_canvas.add_child(_final_scores)`, add:

```gdscript
_role_card = load("res://src/ui/role_card.gd").new()
_canvas.add_child(_role_card)
```

Add new method to `auction_house.gd`:

```gdscript
func _on_role_assigned(role: Dictionary, objective: Dictionary) -> void:
	_my_role = role
	_my_objective = objective
	_ability_used = false
	if _role_card:
		_role_card.show_assigned(role, objective)
		get_tree().create_timer(5.0).timeout.connect(func(): _role_card._start_fade())
```

In `_connect_player_signals()`, add:

```gdscript
NetworkManager.role_assigned.connect(_on_role_assigned)
```

- [ ] **Step 3: Verify identifiers in place**

```bash
grep -n "_role_card\|_on_role_assigned\|_my_role\|_ability_used" \
  hot-garbage-godot/src/scenes/auction_house.gd \
  hot-garbage-godot/src/ui/role_card.gd
```

Expected: all identifiers found in their respective files.

- [ ] **Step 4: Commit**

```bash
git add hot-garbage-godot/src/ui/role_card.gd hot-garbage-godot/src/scenes/auction_house.gd
git commit -m "feat: role card overlay — private role + objective reveal at game start"
```

---

### Task 8: Godot — E-key proximity interaction + ability dispatch

**Files:**
- Modify: `hot-garbage-godot/src/scenes/auction_house.gd`

**Interfaces:**
- Consumes: `NetworkTransport.send_ability_activate`, `NetworkManager.ability_result` signal
- Produces: `_check_interact()` — proximity scan → sends `ability_activate` to server

- [ ] **Step 1: Add `_check_interact` and `INTERACT_RANGE` to `auction_house.gd`**

After the existing constants block, add:

```gdscript
const INTERACT_RANGE := 2.5
```

Add method:

```gdscript
func _check_interact() -> void:
	if _ability_used or _my_role.is_empty():
		return
	var role_id: String = _my_role.get("id", "")
	var requires_target: bool = _my_role.get("requiresTarget", false)

	if requires_target:
		var nearest_name: String = ""
		var nearest_dist: float = INTERACT_RANGE
		var my_pos: Vector3 = _local_player.position if _local_player else Vector3.ZERO
		for p_name: String in _remote_players:
			var dist: float = my_pos.distance_to((_remote_players[p_name] as Node3D).position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_name = p_name
		if nearest_name.is_empty():
			return
		NetworkTransport.send_ability_activate(role_id, nearest_name)
	else:
		NetworkTransport.send_ability_activate(role_id, "")
```

- [ ] **Step 2: Hook into `_unhandled_key_input`**

In the existing `_unhandled_key_input` method, at the very top (before the `ui_cancel` check), add:

```gdscript
if event.is_action_pressed("interact"):
	_check_interact()
	return
```

- [ ] **Step 3: Handle `ability_result` signal**

Add method to `auction_house.gd`:

```gdscript
func _on_ability_result(data: Dictionary) -> void:
	var actor: String = data.get("actorName", "")
	if actor == NetworkManager.local_name:
		_ability_used = true
	var target_node: Node3D = null
	if actor == NetworkManager.local_name:
		target_node = _local_player
	elif _remote_players.has(actor):
		target_node = _remote_players[actor]
	if target_node == null:
		return
	var lbl := Label3D.new()
	lbl.text = data.get("abilityType", "").to_upper().replace("_", " ")
	lbl.pixel_size = 0.05
	lbl.no_depth_test = true
	lbl.modulate = Color.html("C9A227")
	lbl.position = target_node.position + Vector3(0, 2.5, 0)
	add_child(lbl)
	get_tree().create_timer(2.5).timeout.connect(func(): lbl.queue_free())
```

In `_connect_player_signals()`, add:

```gdscript
NetworkManager.ability_result.connect(_on_ability_result)
```

- [ ] **Step 4: Verify**

```bash
grep -n "_check_interact\|INTERACT_RANGE\|_on_ability_result\|send_ability_activate" \
  hot-garbage-godot/src/scenes/auction_house.gd
```

Expected: all four identifiers present.

- [ ] **Step 5: Commit**

```bash
git add hot-garbage-godot/src/scenes/auction_house.gd
git commit -m "feat: E-key proximity interaction — dispatches role ability to nearest player"
```

---

### Task 9: Godot — ONE AWAY, broke mode, set-rush, extended final scores

**Files:**
- Modify: `hot-garbage-godot/src/scenes/auction_house.gd`
- Modify: `hot-garbage-godot/src/ui/final_scores_overlay.gd`

**Interfaces:**
- Consumes: `NetworkManager.one_away`, `NetworkManager.broke_mode_started`, `NetworkManager.set_rush_win`, extended `final_scores` ranking with `role`, `objectiveItemName`, `objectiveComplete`, `objectiveBonus`, `precisionHistory`, `abilityUsed`

- [ ] **Step 1: Add ONE AWAY + set-rush + broke mode handlers to `auction_house.gd`**

Add methods:

```gdscript
func on_one_away(player: String, category: String) -> void:
	_scoreboard_label.text = "ONE AWAY\n%s\n[%s]" % [player.to_upper(), category.to_upper()]
	_scoreboard_label.modulate = Color.html("C9A227")

func on_set_rush_win(winner: String, category: String) -> void:
	_scoreboard_label.text = "SET RUSH!\n%s WINS\n[%s]" % [winner.to_upper(), category.to_upper()]
	_scoreboard_label.modulate = Color.html("ff4444")

func _on_broke_mode_started(player: String) -> void:
	var target: Node3D = null
	if player == NetworkManager.local_name:
		target = _local_player
	elif _remote_players.has(player):
		target = _remote_players[player]
	if target:
		target.modulate = Color(0.45, 0.45, 0.45, 1.0)
	_scoreboard_label.text = "BROKE!\n%s\nno more bids" % player.to_upper()
	_scoreboard_label.modulate = Color.html("888888")
	get_tree().create_timer(3.0).timeout.connect(func():
		_scoreboard_label.text = "SCOREBOARD"
		_scoreboard_label.modulate = Color.WHITE)
```

In `_connect_player_signals()`, add:

```gdscript
NetworkManager.one_away.connect(on_one_away)
NetworkManager.set_rush_win.connect(on_set_rush_win)
NetworkManager.broke_mode_started.connect(_on_broke_mode_started)
```

- [ ] **Step 2: Extend final scores overlay in `final_scores_overlay.gd`**

In `show_scores()`, inside the `for i in range(ranking.size()):` loop, after the existing per-category breakdown block, add:

```gdscript
# Role + objective reveal
var role_data: Dictionary = p.get("role", {})
if not role_data.is_empty():
    var role_lbl := Label.new()
    var used_str: String = " (used)" if p.get("abilityUsed", false) else " (never used)"
    role_lbl.text = "  ROLE: %s%s" % [role_data.get("name", "?"), used_str]
    _UITheme.style_label(role_lbl, _UITheme.FS_LABEL, _UITheme.GOLD)
    _score_vbox.add_child(role_lbl)

    var obj_complete: bool = p.get("objectiveComplete", false)
    var obj_bonus: int = p.get("objectiveBonus", 0)
    var obj_result: String = ("COMPLETE +§%d" % obj_bonus) if obj_complete else "INCOMPLETE"
    var obj_lbl := Label.new()
    obj_lbl.text = "  OBJECTIVE: \"%s\" — %s" % [p.get("objectiveItemName", "?"), obj_result]
    _UITheme.style_label(obj_lbl, _UITheme.FS_LABEL,
        _UITheme.GOLD if obj_complete else _UITheme.DIM)
    _score_vbox.add_child(obj_lbl)

# Auctioneer precision breakdown
var precision: Array = p.get("precisionHistory", [])
if not precision.is_empty():
    var avg: float = 0.0
    for m: float in precision:
        avg += m
    avg /= float(precision.size())
    var prec_lbl := Label.new()
    prec_lbl.text = "  AUCTIONEER: avg %.2f× precision over %d round(s)" % [avg, precision.size()]
    _UITheme.style_label(prec_lbl, _UITheme.FS_LABEL, _UITheme.DIM)
    _score_vbox.add_child(prec_lbl)
```

- [ ] **Step 3: Verify identifiers present**

```bash
grep -n "on_one_away\|on_set_rush_win\|_on_broke_mode\|objectiveComplete\|precisionHistory" \
  hot-garbage-godot/src/scenes/auction_house.gd \
  hot-garbage-godot/src/ui/final_scores_overlay.gd
```

Expected: all identifiers found in their respective files.

- [ ] **Step 4: Commit**

```bash
git add hot-garbage-godot/src/scenes/auction_house.gd hot-garbage-godot/src/ui/final_scores_overlay.gd
git commit -m "feat: ONE AWAY scoreboard, broke mode dim, extended final scores with roles + objectives + precision"
```

---

## Self-Review

### Spec coverage

| Spec requirement | Task |
|---|---|
| Secret roles — pool of 20, one per player, one-shot | 1, 2 |
| Secret objectives — role-paired, target artifact, bonus | 1, 5 |
| Physical E-key activation, proximate to target | 8 |
| Ability use telegraphs actor visually | 8 (Label3D float) |
| Auctioneer precision multiplier (asymmetric) | 2 |
| Precision reveal only at final scores | 5, 9 |
| Set rush — 3 of same category = instant win | 3, 5, 9 |
| ONE AWAY announcement | 3, 5, 9 |
| Broke mode — 0 cash, stays in room, can't bid | 3, 5, 9 |
| Role + objective reveal at final scores | 5, 9 |
| Role card shown privately at game start | 7 |

**Deferred to Plan 2 (Black Market + Forgery):**
- Black market prop, stock, purchase flow, item effects
- Forgery table, mini-game, secret stash, forgery auction flow
- Remaining abilities: Saboteur, Insider, Fence, Secret Buyer, Mole, Vandal, Speculator, Ghost, Emcee, Extortionist, Shill, Smuggler, Hoarder, Price Fixer, Swapper, Arsonist

**Deferred to Plan 3 (Game Modes):**
- Lobby config sliders (pitch timer, bid timer, rounds, feature toggles)
- Standard / Party / Blitz presets

### Type consistency
- `role` dict keys used consistently: `id`, `name`, `description`, `activationPhase`, `requiresTarget`
- `RoleState` keys consistent across server and Godot: `role`, `objectiveItemId`, `objectiveItemName`, `objectiveBonus`, `objectiveComplete`, `abilityUsed`, `vaultedItemId`
- `ability_result` message keys: `actorName`, `abilityType`, `effect`, `payload` — consistent in Task 5 (session) and Task 8 (Godot)
- `one_away` message: `player`, `category` — consistent in Task 5 (session) and Task 6/9 (Godot)
