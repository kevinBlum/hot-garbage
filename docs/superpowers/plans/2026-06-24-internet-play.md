# Hot Garbage Internet Play — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace LAN-only ENet transport with a hosted Node.js WebSocket server enabling internet play through named password-protected rooms backed by DynamoDB.

**Architecture:** A new `hot-garbage-server/` Node.js package wraps `server/engine.js` in a subclass that adds an async split API, adds a WebSocket layer with room/session management, and persists room metadata to DynamoDB. Godot clients rewrite `NetworkManager.gd` from ENet to `WebSocketPeer`; all game scenes are untouched except two mechanical line changes per file.

**Tech Stack:** Node.js 18+ (`node:test` built-in runner), `ws`, `@aws-sdk/client-dynamodb`, `@aws-sdk/util-dynamodb`, `bcrypt`, Godot 4.3+ GDScript, DynamoDB on-demand, AWS App Runner + ECR, `amazon/dynamodb-local` (dev)

## Global Constraints

- `server/engine.js` and `server/scoring.js`: zero modifications — extend via subclass only
- Privacy invariant: `auctioneer_reveal` sent only to one WebSocket connection; `start_pitch` broadcast never includes `value`
- All JSON messages: `{ "type": "...", ...payload }` envelope
- Player name is the stable identity key — unique per room, case-sensitive
- `SERVER_URL` constant in `NetworkManager.gd` is the only toggle between local dev and prod
- Godot 4.3+; Node.js 18+

---

## File Map

**New — server:**
- `hot-garbage-server/package.json`
- `hot-garbage-server/Dockerfile`
- `docker-compose.yml` (repo root)
- `server/engine_split.js` — `HotGarbageServer` subclass with split async API
- `hot-garbage-server/room_store.js` — DynamoDB CRUD wrapper
- `hot-garbage-server/game_session.js` — per-room turn loop
- `hot-garbage-server/server.js` — WebSocket server, room routing
- `hot-garbage-server/test/engine_split.test.js`
- `hot-garbage-server/test/room_store.test.js`
- `hot-garbage-server/test/integration.test.js`

**Modified — Godot:**
- `hot-garbage-godot/src/network/network_manager.gd` — full rewrite
- `hot-garbage-godot/src/server/game_server.gd` — stripped to display state
- `hot-garbage-godot/src/scenes/main_menu.gd` — room name + password UI
- `hot-garbage-godot/src/scenes/lobby.gd` — array iteration, start_game, server_restarted banner
- `hot-garbage-godot/src/scenes/hud.gd` — local_name identity fix
- `hot-garbage-godot/src/scenes/auctioneer_view.gd` — bid_count_updated signal, local_name
- `hot-garbage-godot/src/scenes/bidder_view.gd` — local_name
- `hot-garbage-godot/src/scenes/bid_reveal.gd` — remove peer_id lookup

---

### Task 1: Server scaffold + local dev environment

**Files:**
- Create: `hot-garbage-server/package.json`
- Create: `hot-garbage-server/server.js` (skeleton)
- Create: `hot-garbage-server/Dockerfile`
- Create: `docker-compose.yml`

**Interfaces:**
- Produces: `ws://localhost:3000` WebSocket endpoint, DynamoDB local at `http://localhost:8000`

- [ ] **Step 1: Create package.json**

```json
{
  "name": "hot-garbage-server",
  "version": "1.0.0",
  "type": "commonjs",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "test": "node --test test/*.test.js"
  },
  "dependencies": {
    "@aws-sdk/client-dynamodb": "^3.0.0",
    "@aws-sdk/util-dynamodb": "^3.0.0",
    "bcrypt": "^5.1.0",
    "ws": "^8.0.0"
  }
}
```

Run: `cd hot-garbage-server && npm install`

- [ ] **Step 2: Create Dockerfile**

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY hot-garbage-server/package*.json ./hot-garbage-server/
COPY server/ ./server/
COPY data/ ./data/
WORKDIR /app/hot-garbage-server
RUN npm ci --omit=dev
COPY hot-garbage-server/ .
EXPOSE 3000
CMD ["node", "server.js"]
```

- [ ] **Step 3: Create docker-compose.yml at repo root**

```yaml
services:
  dynamodb-local:
    image: amazon/dynamodb-local:latest
    ports:
      - "8000:8000"
    command: "-jar DynamoDBLocal.jar -sharedDb -inMemory"

  server:
    build:
      context: .
      dockerfile: hot-garbage-server/Dockerfile
    ports:
      - "3000:3000"
    environment:
      DYNAMODB_TABLE: hot-garbage-rooms
      DYNAMODB_REGION: us-east-1
      DYNAMODB_ENDPOINT: http://dynamodb-local:8000
      PORT: 3000
    depends_on:
      - dynamodb-local
```

- [ ] **Step 4: Create skeleton server.js**

```javascript
'use strict';
const { WebSocketServer } = require('ws');

const PORT = parseInt(process.env.PORT || '3000', 10);
const wss = new WebSocketServer({ port: PORT });

wss.on('connection', (ws) => {
  console.log('client connected');
  ws.on('close', () => console.log('client disconnected'));
});

console.log(`Hot Garbage server listening on :${PORT}`);
```

- [ ] **Step 5: Verify scaffold**

```bash
docker compose up dynamodb-local server
```

Expected: `Hot Garbage server listening on :3000` in server logs.

In a second terminal:
```bash
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  -H "Sec-WebSocket-Version: 13" http://localhost:3000
```
Expected: `HTTP/1.1 101 Switching Protocols`

- [ ] **Step 6: Create DynamoDB table in local instance**

```bash
aws dynamodb create-table \
  --table-name hot-garbage-rooms \
  --attribute-definitions AttributeName=roomName,AttributeType=S \
  --key-schema AttributeName=roomName,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --endpoint-url http://localhost:8000 \
  --region us-east-1
```
Expected: JSON response with `TableDescription.TableStatus: "ACTIVE"`

- [ ] **Step 7: Commit**

```bash
git add hot-garbage-server/package.json hot-garbage-server/package-lock.json \
  hot-garbage-server/Dockerfile docker-compose.yml hot-garbage-server/server.js
git commit -m "feat: hot-garbage-server scaffold — ws skeleton, Dockerfile, docker-compose"
```

---

### Task 2: engine_split.js — HotGarbageServer with async split API

**Files:**
- Create: `server/engine_split.js`
- Create: `hot-garbage-server/test/engine_split.test.js`

**Interfaces:**
- Consumes: `server/engine.js` → `{ HotGarbage }`
- Produces: `HotGarbageServer` — same constructor opts as `HotGarbage` plus `dataPath` option; methods: `startAuction(id)`, `getAuctioneerArtifact()`, `submitBid(id, amount)`, `allBidsReceived()`, `resolveAuction()`, `maybeChaos(result)`, `getFinalScores()`, `getRounds()`, `getOrder()`

- [ ] **Step 1: Write failing tests**

`hot-garbage-server/test/engine_split.test.js`:
```javascript
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
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd hot-garbage-server && node --test test/engine_split.test.js 2>&1 | head -20
```
Expected: `Error: Cannot find module '../../server/engine_split'`

- [ ] **Step 3: Implement engine_split.js**

`server/engine_split.js`:
```javascript
'use strict';
const { HotGarbage } = require('./engine');
const { rankPlayers } = require('./scoring');

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
    const { pick } = require('./engine');  // pick is not exported — inline it
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

const EVENTS = [
  { id: 'market_crash',      text: 'MARKET CRASH — Forgeries score double this game.' },
  { id: 'museum_heist',      text: 'MUSEUM HEIST — a random player loses their priciest artifact to the Bank.' },
  { id: 'bidding_frenzy',    text: 'BIDDING FRENZY — next auction, everyone must bid at least 50.' },
  { id: 'insider_tip',       text: 'INSIDER TIP — a random bidder secretly learns the next true band.' },
  { id: 'counterfeit_scare', text: 'COUNTERFEIT SCARE — next Forgery is halved at reveal.' },
];

module.exports = { HotGarbageServer };
```

Note: `pick` is not exported from `engine.js` — we re-implement `_pick` on the subclass using `this.rng`.

- [ ] **Step 4: Run tests — verify they pass**

```bash
cd hot-garbage-server && node --test test/engine_split.test.js
```
Expected: all 9 tests pass, no failures.

- [ ] **Step 5: Commit**

```bash
git add server/engine_split.js hot-garbage-server/test/engine_split.test.js
git commit -m "feat: HotGarbageServer — split async API for networked bid collection"
```

---

### Task 3: room_store.js — DynamoDB CRUD wrapper

**Files:**
- Create: `hot-garbage-server/room_store.js`
- Create: `hot-garbage-server/test/room_store.test.js`

**Interfaces:**
- Produces: `roomStore.createRoom(roomName, passwordHash, createdBy, config)`, `getRoom(roomName)`, `deleteRoom(roomName)`, `scanAllRooms()`

- [ ] **Step 1: Write failing tests**

`hot-garbage-server/test/room_store.test.js`:
```javascript
'use strict';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { DynamoDBClient, CreateTableCommand, DeleteTableCommand } = require('@aws-sdk/client-dynamodb');

process.env.DYNAMODB_TABLE = 'hg-test-rooms';
process.env.DYNAMODB_REGION = 'us-east-1';
process.env.DYNAMODB_ENDPOINT = 'http://localhost:8000';

const roomStore = require('../room_store');

const client = new DynamoDBClient({
  region: 'us-east-1',
  endpoint: 'http://localhost:8000',
});

before(async () => {
  await client.send(new CreateTableCommand({
    TableName: 'hg-test-rooms',
    AttributeDefinitions: [{ AttributeName: 'roomName', AttributeType: 'S' }],
    KeySchema: [{ AttributeName: 'roomName', KeyType: 'HASH' }],
    BillingMode: 'PAY_PER_REQUEST',
  }));
});

after(async () => {
  await client.send(new DeleteTableCommand({ TableName: 'hg-test-rooms' }));
});

test('createRoom then getRoom returns the record', async () => {
  await roomStore.createRoom('myroom', 'hash123', 'Alice', { pitchDuration: 45 });
  const r = await roomStore.getRoom('myroom');
  assert.equal(r.roomName, 'myroom');
  assert.equal(r.passwordHash, 'hash123');
  assert.equal(r.createdBy, 'Alice');
  assert.deepEqual(r.config, { pitchDuration: 45 });
  assert.ok(r.createdAt > 0);
});

test('createRoom throws if room already exists', async () => {
  await assert.rejects(
    () => roomStore.createRoom('myroom', 'hash456', 'Bob', {}),
    /ConditionalCheckFailedException/
  );
});

test('getRoom returns null for missing room', async () => {
  const r = await roomStore.getRoom('nonexistent');
  assert.equal(r, null);
});

test('deleteRoom removes the record', async () => {
  await roomStore.deleteRoom('myroom');
  const r = await roomStore.getRoom('myroom');
  assert.equal(r, null);
});

test('scanAllRooms returns all records', async () => {
  await roomStore.createRoom('room-a', 'h1', 'Alice', {});
  await roomStore.createRoom('room-b', 'h2', 'Bob', {});
  const all = await roomStore.scanAllRooms();
  const names = all.map(r => r.roomName);
  assert.ok(names.includes('room-a'));
  assert.ok(names.includes('room-b'));
  await roomStore.deleteRoom('room-a');
  await roomStore.deleteRoom('room-b');
});
```

- [ ] **Step 2: Run tests — verify they fail**

Ensure DynamoDB local is running: `docker compose up dynamodb-local -d`

```bash
cd hot-garbage-server && node --test test/room_store.test.js 2>&1 | head -10
```
Expected: `Error: Cannot find module '../room_store'`

- [ ] **Step 3: Implement room_store.js**

`hot-garbage-server/room_store.js`:
```javascript
'use strict';
const { DynamoDBClient, GetItemCommand, PutItemCommand, DeleteItemCommand, ScanCommand } = require('@aws-sdk/client-dynamodb');
const { marshall, unmarshall } = require('@aws-sdk/util-dynamodb');

// Read config dynamically so test files can set env vars before requiring.
function makeClient() {
  const opts = { region: process.env.DYNAMODB_REGION || 'us-east-1' };
  if (process.env.DYNAMODB_ENDPOINT) opts.endpoint = process.env.DYNAMODB_ENDPOINT;
  return new DynamoDBClient(opts);
}
function table() { return process.env.DYNAMODB_TABLE || 'hot-garbage-rooms'; }

async function createRoom(roomName, passwordHash, createdBy, config) {
  await makeClient().send(new PutItemCommand({
    TableName: table(),
    ConditionExpression: 'attribute_not_exists(roomName)',
    Item: marshall({ roomName, passwordHash, createdBy, config, createdAt: Date.now() }),
  }));
}

async function getRoom(roomName) {
  const res = await makeClient().send(new GetItemCommand({
    TableName: table(),
    Key: marshall({ roomName }),
  }));
  return res.Item ? unmarshall(res.Item) : null;
}

async function deleteRoom(roomName) {
  await makeClient().send(new DeleteItemCommand({
    TableName: table(),
    Key: marshall({ roomName }),
  }));
}

async function scanAllRooms() {
  const res = await makeClient().send(new ScanCommand({ TableName: table() }));
  return (res.Items || []).map(unmarshall);
}

module.exports = { createRoom, getRoom, deleteRoom, scanAllRooms };
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
cd hot-garbage-server && node --test test/room_store.test.js
```
Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add hot-garbage-server/room_store.js hot-garbage-server/test/room_store.test.js
git commit -m "feat: room_store — DynamoDB CRUD for named rooms"
```

---

### Task 4: game_session.js — per-room turn loop

**Files:**
- Create: `hot-garbage-server/game_session.js`
- Create: `hot-garbage-server/test/game_session.test.js`

**Interfaces:**
- Consumes: `server/engine_split.js` → `HotGarbageServer`
- Produces: `new GameSession(playerNames, config, sendFn)` → `.start()`, `.openEarly(playerName)`, `.submitBid(playerName, amount)`, `.forceResolve(playerName)`, `.isActive` (bool)

The `sendFn` signature: `(playerName: string|null, msg: object) => void` — `null` means broadcast all players in the session.

- [ ] **Step 1: Write failing tests**

`hot-garbage-server/test/game_session.test.js`:
```javascript
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
```

- [ ] **Step 2: Run — verify fail**

```bash
cd hot-garbage-server && node --test test/game_session.test.js 2>&1 | head -5
```
Expected: `Error: Cannot find module '../game_session'`

- [ ] **Step 3: Implement game_session.js**

`hot-garbage-server/game_session.js`:
```javascript
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
    this.isActive = false;
  }

  start() {
    this.isActive = true;
    this._engine = new HotGarbageServer({
      seed: (Math.random() * 0x100000000) >>> 0,
      playerIds: this._playerNames,
      chaosChance: this._chaosChance,
      dataPath: DATA_PATH,
    });
    this._order = this._engine.getOrder();
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

    this._currentAuctioneer = this._order[this._turnIdx];
    const bidderCount = this._playerNames.length - 1;
    let receivedBids = 0;

    for (const name of this._playerNames) {
      this._send(name, {
        type: 'advance_scene',
        scene: name === this._currentAuctioneer ? 'auctioneer_view' : 'bidder_view',
      });
    }

    await sleep(500);

    const publicArtifact = this._engine.startAuction(this._currentAuctioneer);
    const fullArtifact = this._engine.getAuctioneerArtifact();

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
    });

    await sleep(this._pitchDuration);
    if (myGen === this._turnGen && !this._biddingOpen) {
      this._openBidding();
    }
  }

  _openBidding() {
    if (this._biddingOpen) return;
    this._biddingOpen = true;
    this._send(null, { type: 'open_bidding' });
  }

  openEarly(playerName) {
    if (playerName !== this._currentAuctioneer) return;
    this._openBidding();
  }

  submitBid(playerName, amount) {
    if (!this._biddingOpen || this._pendingResolve) return;
    if (playerName === this._currentAuctioneer) return;
    this._engine.submitBid(playerName, amount);
    const bidderCount = this._playerNames.length - 1;
    // Count how many bids we've received by checking allBidsReceived progress
    // We track it separately since engine doesn't expose count
    this._receivedBidCount = (this._receivedBidCount || 0) + 1;
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
    // Only host (first player) or auctioneer can force resolve
    if (playerName !== this._playerNames[0] && playerName !== this._currentAuctioneer) return;
    this._resolveAuction();
  }

  async _resolveAuction() {
    if (this._pendingResolve) return;
    this._pendingResolve = true;
    this._receivedBidCount = 0;
    this._send(null, { type: 'advance_scene', scene: 'bid_reveal' });
    await sleep(300);

    const result = this._engine.resolveAuction();
    const chaos = this._engine.maybeChaos(result);

    this._syncPlayer(result.winner);
    this._syncPlayer(this._currentAuctioneer);

    const publicArtifact = { ...result.artifact };
    delete publicArtifact.value;

    this._send(null, {
      type: 'bid_result',
      winner: result.winner,
      price: result.price,
      artifact: publicArtifact,
    });

    if (chaos && chaos.type) {
      this._send(null, { type: 'chaos', ...chaos });
    }

    this._turnIdx++;
    if (this._turnIdx >= this._order.length) {
      this._turnIdx = 0;
      this._round++;
    }

    await sleep(3000);
    this._pendingResolve = false;
    this._beginTurn();
  }

  _syncPlayer(playerName) {
    if (playerName === 'BANK') return;
    const p = this._engine.players[playerName];
    if (!p) return;
    const safeArtifacts = p.artifacts.map(({ value, ...rest }) => rest);
    this._send(playerName, { type: 'sync_player_state', cash: p.cash, artifacts: safeArtifacts });
  }

  async _endGame() {
    this.isActive = false;
    this._send(null, { type: 'advance_scene', scene: 'final_scores' });
    await sleep(500);
    this._send(null, { type: 'final_scores', ranking: this._engine.getFinalScores() });
  }
}

module.exports = GameSession;
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
cd hot-garbage-server && node --test test/game_session.test.js
```
Expected: all 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add hot-garbage-server/game_session.js hot-garbage-server/test/game_session.test.js
git commit -m "feat: game_session — per-room turn loop with async bid collection"
```

---

### Task 5: server.js — room management + full game wiring

**Files:**
- Modify: `hot-garbage-server/server.js` (replace skeleton)
- Create: `hot-garbage-server/test/integration.test.js`

**Interfaces:**
- Consumes: `room_store.js`, `game_session.js`
- Produces: WebSocket endpoint handling all protocol messages from spec §4

- [ ] **Step 1: Replace server.js skeleton with full implementation**

`hot-garbage-server/server.js`:
```javascript
'use strict';
const { WebSocketServer } = require('ws');
const bcrypt = require('bcrypt');
const roomStore = require('./room_store');
const GameSession = require('./game_session');

const PORT = parseInt(process.env.PORT || '3000', 10);
const BCRYPT_ROUNDS = 10;
const NAME_RE = /^[a-z0-9-]{1,20}$/;

// rooms: roomName → { config, passwordHash, createdBy, players: Map<playerName, ws>, session: GameSession|null }
const rooms = new Map();

function send(ws, msg) {
  if (ws.readyState === 1 /* OPEN */) ws.send(JSON.stringify(msg));
}

function broadcastRoom(roomName, msg, excludeName = null) {
  const room = rooms.get(roomName);
  if (!room) return;
  for (const [name, sock] of room.players) {
    if (name !== excludeName) send(sock, msg);
  }
}

function sendToPlayer(roomName, playerName, msg) {
  const room = rooms.get(roomName);
  if (!room) return;
  const sock = room.players.get(playerName);
  if (sock) send(sock, msg);
}

function makeSend(roomName) {
  return (playerName, msg) => {
    if (playerName === null) broadcastRoom(roomName, msg);
    else sendToPlayer(roomName, playerName, msg);
  };
}

async function startup() {
  const allRooms = await roomStore.scanAllRooms();
  for (const r of allRooms) {
    // wasRestored: true flags rooms loaded on cold start so the lobby can show a banner.
    rooms.set(r.roomName, { config: r.config, passwordHash: r.passwordHash, createdBy: r.createdBy, players: new Map(), session: null, wasRestored: true });
  }
  console.log(`Restored ${allRooms.length} room(s) from DynamoDB`);
}

// --- message handlers ---

async function handleCreateRoom(ws, msg, ctx) {
  const roomName = (msg.roomName || '').toLowerCase().trim();
  const playerName = (msg.playerName || '').trim();
  const password = msg.password || '';

  if (!NAME_RE.test(roomName)) return send(ws, { type: 'error', code: 'INVALID_NAME', message: 'Room name must be 1–20 alphanumeric/hyphen characters.' });
  if (!playerName) return send(ws, { type: 'error', code: 'INVALID_NAME', message: 'Player name required.' });
  if (rooms.has(roomName)) return send(ws, { type: 'error', code: 'NAME_TAKEN', message: 'Room already exists.' });

  const config = { pitchDuration: 45, chaosChance: 0.25, maxPlayers: 8, ...msg.config };
  const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);

  try {
    await roomStore.createRoom(roomName, passwordHash, playerName, config);
  } catch (e) {
    return send(ws, { type: 'error', code: 'NAME_TAKEN', message: 'Room already exists.' });
  }

  const room = { config, passwordHash, createdBy: playerName, players: new Map(), session: null };
  rooms.set(roomName, room);
  room.players.set(playerName, ws);
  ctx.playerName = playerName;
  ctx.roomName = roomName;

  send(ws, { type: 'room_joined', roomName, isHost: true, config, players: [playerName], serverRestarted: false });
}

async function handleJoinRoom(ws, msg, ctx) {
  const roomName = (msg.roomName || '').toLowerCase().trim();
  const playerName = (msg.playerName || '').trim();
  const password = msg.password || '';

  const dbRoom = await roomStore.getRoom(roomName);
  if (!dbRoom) return send(ws, { type: 'error', code: 'ROOM_NOT_FOUND', message: 'Room not found.' });

  const ok = await bcrypt.compare(password, dbRoom.passwordHash);
  if (!ok) return send(ws, { type: 'error', code: 'WRONG_PASSWORD', message: 'Wrong password.' });

  if (!rooms.has(roomName)) {
    rooms.set(roomName, { config: dbRoom.config, passwordHash: dbRoom.passwordHash, createdBy: dbRoom.createdBy, players: new Map(), session: null });
  }
  const room = rooms.get(roomName);

  if (room.players.size >= (room.config.maxPlayers || 8) && !room.players.has(playerName)) {
    return send(ws, { type: 'error', code: 'ROOM_FULL', message: 'Room is full.' });
  }

  const inActiveGame = room.session && room.session.isActive && !room.session._playerNames.includes(playerName);
  if (inActiveGame) return send(ws, { type: 'error', code: 'GAME_IN_PROGRESS', message: 'Game in progress.' });

  if (room.players.has(playerName) && room.players.get(playerName) !== ws) {
    return send(ws, { type: 'error', code: 'NAME_IN_USE', message: 'Name already in use.' });
  }

  room.players.set(playerName, ws);
  ctx.playerName = playerName;
  ctx.roomName = roomName;

  const players = [...room.players.keys()];
  const isHost = playerName === room.createdBy;
  const serverRestarted = !!room.wasRestored;

  send(ws, { type: 'room_joined', roomName, isHost, config: room.config, players, serverRestarted });
  broadcastRoom(roomName, { type: 'player_joined', playerName, players }, playerName);
}

function handleStartGame(ws, ctx) {
  const { roomName, playerName } = ctx;
  const room = rooms.get(roomName);
  if (!room || room.createdBy !== playerName) return;
  if (room.session && room.session.isActive) return;
  if (room.players.size < 2) return send(ws, { type: 'error', code: 'NOT_ENOUGH_PLAYERS', message: 'Need at least 2 players.' });

  const playerNames = [...room.players.keys()];
  room.wasRestored = false;
  room.session = new GameSession(playerNames, room.config, makeSend(roomName));
  room.session.start();
}

function handleOpenEarly(ws, ctx) {
  const room = rooms.get(ctx.roomName);
  if (!room || !room.session) return;
  room.session.openEarly(ctx.playerName);
}

function handleSubmitBid(ws, msg, ctx) {
  const room = rooms.get(ctx.roomName);
  if (!room || !room.session) return;
  room.session.submitBid(ctx.playerName, parseInt(msg.amount, 10) || 0);
}

function handleForceResolve(ws, ctx) {
  const room = rooms.get(ctx.roomName);
  if (!room || !room.session) return;
  room.session.forceResolve(ctx.playerName);
}

async function handleDeleteRoom(ws, ctx) {
  const { roomName, playerName } = ctx;
  const room = rooms.get(roomName);
  if (!room || room.createdBy !== playerName) return;
  broadcastRoom(roomName, { type: 'server_disconnected' });
  rooms.delete(roomName);
  await roomStore.deleteRoom(roomName);
}

function handleDisconnect(roomName, playerName) {
  const room = rooms.get(roomName);
  if (!room) return;
  room.players.delete(playerName);
  const players = [...room.players.keys()];
  broadcastRoom(roomName, { type: 'player_left', playerName, players });
}

// --- main ---

const wss = new WebSocketServer({ port: PORT });

wss.on('connection', (ws) => {
  const ctx = { playerName: null, roomName: null };

  ws.on('message', async (data) => {
    let msg;
    try { msg = JSON.parse(data); } catch { return; }
    switch (msg.type) {
      case 'create_room':   return handleCreateRoom(ws, msg, ctx);
      case 'join_room':     return handleJoinRoom(ws, msg, ctx);
      case 'start_game':    return handleStartGame(ws, ctx);
      case 'open_early':    return handleOpenEarly(ws, ctx);
      case 'submit_bid':    return handleSubmitBid(ws, msg, ctx);
      case 'force_resolve': return handleForceResolve(ws, ctx);
      case 'delete_room':   return handleDeleteRoom(ws, ctx);
    }
  });

  ws.on('close', () => {
    if (ctx.roomName && ctx.playerName) handleDisconnect(ctx.roomName, ctx.playerName);
  });
});

startup().then(() => console.log(`Hot Garbage server listening on :${PORT}`));
```

- [ ] **Step 2: Write integration tests**

`hot-garbage-server/test/integration.test.js`:
```javascript
'use strict';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { WebSocket } = require('ws');
const { DynamoDBClient, CreateTableCommand, DeleteTableCommand } = require('@aws-sdk/client-dynamodb');

process.env.DYNAMODB_TABLE = 'hg-integration-rooms';
process.env.DYNAMODB_REGION = 'us-east-1';
process.env.DYNAMODB_ENDPOINT = 'http://localhost:8000';
process.env.PORT = '3099';

// Start server in-process after env is set
const serverModule = require('../server');

const dbClient = new DynamoDBClient({ region: 'us-east-1', endpoint: 'http://localhost:8000' });

function connect() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket('ws://localhost:3099');
    ws.once('open', () => resolve(ws));
    ws.once('error', reject);
  });
}

function nextMsg(ws) {
  return new Promise((resolve) => ws.once('message', (d) => resolve(JSON.parse(d))));
}

function sendMsg(ws, msg) { ws.send(JSON.stringify(msg)); }

before(async () => {
  await new Promise(r => setTimeout(r, 200)); // wait for server startup
  await dbClient.send(new CreateTableCommand({
    TableName: 'hg-integration-rooms',
    AttributeDefinitions: [{ AttributeName: 'roomName', AttributeType: 'S' }],
    KeySchema: [{ AttributeName: 'roomName', KeyType: 'HASH' }],
    BillingMode: 'PAY_PER_REQUEST',
  }));
});

after(async () => {
  await dbClient.send(new DeleteTableCommand({ TableName: 'hg-integration-rooms' }));
});

test('create room → room_joined with isHost:true', async () => {
  const ws = await connect();
  sendMsg(ws, { type: 'create_room', roomName: 'int-test-1', password: 'pw', playerName: 'Alice' });
  const msg = await nextMsg(ws);
  assert.equal(msg.type, 'room_joined');
  assert.equal(msg.isHost, true);
  assert.equal(msg.roomName, 'int-test-1');
  ws.close();
});

test('join with wrong password → WRONG_PASSWORD error', async () => {
  const ws1 = await connect();
  sendMsg(ws1, { type: 'create_room', roomName: 'int-test-2', password: 'secret', playerName: 'Alice' });
  await nextMsg(ws1);
  const ws2 = await connect();
  sendMsg(ws2, { type: 'join_room', roomName: 'int-test-2', password: 'wrong', playerName: 'Bob' });
  const msg = await nextMsg(ws2);
  assert.equal(msg.type, 'error');
  assert.equal(msg.code, 'WRONG_PASSWORD');
  ws1.close(); ws2.close();
});

test('two players: start_game triggers advance_scene for each', async () => {
  const ws1 = await connect();
  const ws2 = await connect();

  sendMsg(ws1, { type: 'create_room', roomName: 'int-test-3', password: 'pw', playerName: 'Alice' });
  await nextMsg(ws1);

  sendMsg(ws2, { type: 'join_room', roomName: 'int-test-3', password: 'pw', playerName: 'Bob' });
  const joinMsg = await nextMsg(ws2); // room_joined
  assert.equal(joinMsg.type, 'room_joined');
  await nextMsg(ws1); // player_joined broadcast

  sendMsg(ws1, { type: 'start_game' });

  // Both should receive advance_scene
  const [s1, s2] = await Promise.all([nextMsg(ws1), nextMsg(ws2)]);
  assert.equal(s1.type, 'advance_scene');
  assert.equal(s2.type, 'advance_scene');

  ws1.close(); ws2.close();
});
```

- [ ] **Step 3: Run integration tests**

Ensure DynamoDB local is running. Run server tests (server starts in-process):
```bash
cd hot-garbage-server && node --test test/integration.test.js
```
Expected: all 3 tests pass.

- [ ] **Step 4: Verify with docker compose**

```bash
docker compose up --build
```
Expected: `Restored 0 room(s) from DynamoDB` then `Hot Garbage server listening on :3000`

- [ ] **Step 5: Commit**

```bash
git add hot-garbage-server/server.js hot-garbage-server/test/integration.test.js
git commit -m "feat: WebSocket server — room create/join/delete, full game session wiring"
```

---

### Task 6: Rewrite NetworkManager.gd

**Files:**
- Modify: `hot-garbage-godot/src/network/network_manager.gd` (full rewrite)

**Interfaces:**
- Produces (same public API as before, adapted):
  - `func create_room(room_name, password, player_name)`
  - `func join_room(room_name, password, player_name)`
  - `func disconnect_from_game()`
  - `func is_host() -> bool`
  - `func send_open_early()`
  - `func submit_bid(amount: int)`
  - `func start_game(pitch_duration: int)`
  - `var player_names: Array[String]`
  - `var local_name: String`
  - `var room_name: String`
  - `var server_restarted: bool`
  - Signals: `room_joined(room_name, is_host)`, `player_registered(player_name)`, `player_disconnected(player_name)`, `connection_failed()`, `server_disconnected()`, `error_received(code, message)`, `bid_count_updated(received, total)`

- [ ] **Step 1: Replace network_manager.gd**

`hot-garbage-godot/src/network/network_manager.gd`:
```gdscript
extends Node

signal room_joined(room_name: String, is_host: bool)
signal player_registered(player_name: String)
signal player_disconnected(player_name: String)
signal connection_failed()
signal server_disconnected()
signal error_received(code: String, message: String)
signal bid_count_updated(received: int, total: int)

const SERVER_URL := "ws://localhost:3000"
# const SERVER_URL := "wss://your-domain.awsapprunner.com"

const SCENE_PATHS := {
	"lobby":           "res://src/scenes/lobby.tscn",
	"auctioneer_view": "res://src/scenes/auctioneer_view.tscn",
	"bidder_view":     "res://src/scenes/bidder_view.tscn",
	"bid_reveal":      "res://src/scenes/bid_reveal.tscn",
	"final_scores":    "res://src/scenes/final_scores.tscn",
}

var player_names: Array[String] = []
var local_name: String = ""
var room_name: String = ""
var server_restarted: bool = false
var _is_host: bool = false
var _ws: WebSocketPeer = null

func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while _ws.get_available_packet_count() > 0:
			var raw := _ws.get_packet().get_string_from_utf8()
			var msg = JSON.parse_string(raw)
			if msg is Dictionary:
				_dispatch(msg)
	elif state == WebSocketPeer.STATE_CLOSED:
		var code := _ws.get_close_code()
		_ws = null
		if code == -1:
			connection_failed.emit()
		else:
			server_disconnected.emit()

func create_room(p_room_name: String, password: String, player_name: String) -> void:
	local_name = player_name
	_connect_and_send({
		"type": "create_room",
		"roomName": p_room_name.to_lower(),
		"password": password,
		"playerName": player_name,
	})

func join_room(p_room_name: String, password: String, player_name: String) -> void:
	local_name = player_name
	_connect_and_send({
		"type": "join_room",
		"roomName": p_room_name.to_lower(),
		"password": password,
		"playerName": player_name,
	})

func start_game(pitch_duration: int) -> void:
	_send({ "type": "start_game", "pitchDuration": pitch_duration })

func send_open_early() -> void:
	_send({ "type": "open_early" })

func submit_bid(amount: int) -> void:
	_send({ "type": "submit_bid", "amount": amount })

func disconnect_from_game() -> void:
	if _ws != null:
		_ws.close()
		_ws = null
	player_names.clear()
	local_name = ""
	room_name = ""
	_is_host = false

func is_host() -> bool:
	return _is_host

func _connect_and_send(msg: Dictionary) -> void:
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(SERVER_URL)
	if err != OK:
		_ws = null
		connection_failed.emit()
		return
	# Queue message to send once open — poll until open
	_pending_send = msg

var _pending_send: Dictionary = {}

func _send(msg: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ws.send_text(JSON.stringify(msg))

func _process_pending() -> void:
	if _pending_send.is_empty():
		return
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(_pending_send))
		_pending_send = {}

func _dispatch(msg: Dictionary) -> void:
	_process_pending()
	match msg.get("type", ""):
		"room_joined":
			room_name = msg.get("roomName", "")
			_is_host = msg.get("isHost", false)
			server_restarted = msg.get("serverRestarted", false)
			player_names = Array(msg.get("players", []), TYPE_STRING, "", null)
			room_joined.emit(room_name, _is_host)
		"player_joined":
			player_names = Array(msg.get("players", []), TYPE_STRING, "", null)
			var name: String = msg.get("playerName", "")
			player_registered.emit(name)
		"player_left":
			player_names = Array(msg.get("players", []), TYPE_STRING, "", null)
			var name: String = msg.get("playerName", "")
			player_disconnected.emit(name)
		"error":
			error_received.emit(msg.get("code", ""), msg.get("message", ""))
		"advance_scene":
			var scene_key: String = msg.get("scene", "")
			if SCENE_PATHS.has(scene_key):
				get_tree().change_scene_to_file(SCENE_PATHS[scene_key])
		"auctioneer_reveal":
			get_tree().get_root().propagate_call("on_auctioneer_reveal",
				[msg.get("artifact", {}), msg.get("pitchDuration", 45)], true)
		"start_pitch":
			get_tree().get_root().propagate_call("on_start_pitch",
				[msg.get("artifact", {}), msg.get("pitchDuration", 45)], true)
		"open_bidding":
			get_tree().get_root().propagate_call("on_open_bidding", [], true)
		"bid_count":
			bid_count_updated.emit(msg.get("received", 0), msg.get("total", 0))
		"bid_result":
			get_tree().get_root().propagate_call("on_show_bid_result", [msg], true)
		"chaos":
			get_tree().get_root().propagate_call("on_show_chaos", [msg], true)
		"sync_player_state":
			GameServer.receive_player_state(msg.get("cash", 0), msg.get("artifacts", []))
		"final_scores":
			get_tree().get_root().propagate_call("on_show_final_scores",
				[msg.get("ranking", [])], true)
		"server_disconnected":
			server_disconnected.emit()
```

Note: `_process_pending` is called inside `_dispatch` so the first message back from the server flushes the pending send. Also update `_process` to call `_process_pending` while polling:

Add to `_process`, after polling:
```gdscript
	if state == WebSocketPeer.STATE_OPEN:
		_process_pending()
		while _ws.get_available_packet_count() > 0:
```

- [ ] **Step 2: Verify in Godot**

Open Godot editor → Project → Run. With `docker compose up` running:
- Enter a name, click CREATE ROOM → expect scene change to lobby (will fail until lobby is updated in Task 8, but no crash from NetworkManager is the goal here)

- [ ] **Step 3: Commit**

```bash
git add hot-garbage-godot/src/network/network_manager.gd
git commit -m "feat: NetworkManager — rewrite ENet transport to WebSocketPeer"
```

---

### Task 7: Strip GameServer.gd to display state only

**Files:**
- Modify: `hot-garbage-godot/src/server/game_server.gd`

- [ ] **Step 1: Replace game_server.gd**

`hot-garbage-godot/src/server/game_server.gd`:
```gdscript
extends Node

# Client-side display state only.
# All game logic runs on the Node.js server.
# Populated by NetworkManager when sync_player_state messages arrive.

var player_cash: Dictionary = {}
var player_artifacts: Dictionary = {}

func receive_player_state(cash: int, artifacts: Array) -> void:
	var own_id: String = NetworkManager.local_name
	if own_id.is_empty():
		return
	player_cash[own_id] = cash
	player_artifacts[own_id] = artifacts
	get_tree().call_group("hud_nodes", "refresh")
```

- [ ] **Step 2: Commit**

```bash
git add hot-garbage-godot/src/server/game_server.gd
git commit -m "refactor: GameServer — strip host logic, keep display state store only"
```

---

### Task 8: Update MainMenu UI

**Files:**
- Modify: `hot-garbage-godot/src/scenes/main_menu.gd`

- [ ] **Step 1: Replace main_menu.gd**

`hot-garbage-godot/src/scenes/main_menu.gd`:
```gdscript
extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _name_field: LineEdit
var _room_field: LineEdit
var _password_field: LineEdit
var _status_label: Label
var _dialog_open: bool = false

func _ready() -> void:
	_build_ui()
	NetworkManager.room_joined.connect(_on_room_joined)
	NetworkManager.error_received.connect(_on_error)
	NetworkManager.connection_failed.connect(_on_connection_failed)

func _build_ui() -> void:
	_UITheme.add_bg(self)

	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(960, 520)
	hbox.add_theme_constant_override("separation", 0)
	_UITheme.add_center_container(self).add_child(hbox)

	# --- Left: branding ---
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", _UITheme.GAP * 2)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(left)

	var title := Label.new()
	title.text = "HOT GARBAGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(title, _UITheme.FS_ARTIFACT, _UITheme.GOLD)
	left.add_child(title)

	var tagline := Label.new()
	tagline.text = "a game of bluffing, bidding,\nand bad provenance"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(tagline, _UITheme.FS_LABEL, _UITheme.DIM)
	left.add_child(tagline)

	var meta := Label.new()
	meta.text = "2–8 players · ~45 min"
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(meta, _UITheme.FS_LABEL, _UITheme.DIM)
	left.add_child(meta)

	# --- Separator ---
	var sep := VSeparator.new()
	_UITheme.style_vseparator(sep)
	hbox.add_child(sep)

	# --- Right: form ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", _UITheme.GAP)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(right)

	var name_lbl := Label.new()
	name_lbl.text = "PLAYER NAME"
	_UITheme.style_section_label(name_lbl)
	right.add_child(name_lbl)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Your name"
	_UITheme.style_line_edit(_name_field)
	right.add_child(_name_field)

	var room_lbl := Label.new()
	room_lbl.text = "ROOM NAME"
	_UITheme.style_section_label(room_lbl)
	right.add_child(room_lbl)

	_room_field = LineEdit.new()
	_room_field.placeholder_text = "e.g. kevins-garbage"
	_UITheme.style_line_edit(_room_field)
	right.add_child(_room_field)

	var pw_lbl := Label.new()
	pw_lbl.text = "PASSWORD"
	_UITheme.style_section_label(pw_lbl)
	right.add_child(pw_lbl)

	_password_field = LineEdit.new()
	_password_field.placeholder_text = "Room password"
	_password_field.secret = true
	_UITheme.style_line_edit(_password_field)
	right.add_child(_password_field)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, _UITheme.GAP)
	right.add_child(spacer)

	var create_btn := Button.new()
	create_btn.text = "CREATE ROOM"
	create_btn.pressed.connect(_on_create_pressed)
	_UITheme.style_button(create_btn)
	right.add_child(create_btn)

	var join_btn := Button.new()
	join_btn.text = "JOIN ROOM"
	join_btn.pressed.connect(_on_join_pressed)
	_UITheme.style_ghost_button(join_btn)
	right.add_child(join_btn)

	var settings_btn := Button.new()
	settings_btn.text = "SETTINGS"
	settings_btn.pressed.connect(_on_settings_pressed)
	_UITheme.style_ghost_button(settings_btn)
	right.add_child(settings_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_status_label, _UITheme.FS_BODY, _UITheme.DIM)
	right.add_child(_status_label)

func _validate() -> bool:
	if _name_field.text.strip_edges().is_empty():
		_status_label.text = "Enter your name."
		return false
	if _room_field.text.strip_edges().is_empty():
		_status_label.text = "Enter a room name."
		return false
	return true

func _on_create_pressed() -> void:
	AudioManager.play_ui()
	if not _validate():
		return
	_status_label.text = "Creating room..."
	NetworkManager.create_room(
		_room_field.text.strip_edges(),
		_password_field.text,
		_name_field.text.strip_edges()
	)

func _on_join_pressed() -> void:
	AudioManager.play_ui()
	if not _validate():
		return
	_status_label.text = "Joining room..."
	NetworkManager.join_room(
		_room_field.text.strip_edges(),
		_password_field.text,
		_name_field.text.strip_edges()
	)

func _on_room_joined(_room_name: String, _is_host: bool) -> void:
	get_tree().change_scene_to_file("res://src/scenes/lobby.tscn")

func _on_error(code: String, _message: String) -> void:
	var friendly := {
		"NAME_TAKEN": "That room name is taken. Try another.",
		"ROOM_NOT_FOUND": "Room not found. Check the name.",
		"WRONG_PASSWORD": "Wrong password.",
		"NAME_IN_USE": "That player name is already in use in this room.",
		"ROOM_FULL": "Room is full.",
		"GAME_IN_PROGRESS": "A game is in progress in that room.",
	}
	_status_label.text = friendly.get(code, "Error: %s" % code)

func _on_connection_failed() -> void:
	_status_label.text = "Could not connect to server."

func _on_settings_pressed() -> void:
	AudioManager.play_ui()
	get_tree().change_scene_to_file("res://src/scenes/settings.tscn")

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_show_quit_dialog()

func _show_quit_dialog() -> void:
	if _dialog_open:
		return
	_dialog_open = true
	var dlg := ConfirmationDialog.new()
	dlg.title = "Quit"
	dlg.dialog_text = "Quit Hot Garbage?"
	dlg.confirmed.connect(func(): get_tree().quit())
	dlg.canceled.connect(func():
		_dialog_open = false
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()
```

- [ ] **Step 2: Commit**

```bash
git add hot-garbage-godot/src/scenes/main_menu.gd
git commit -m "feat: main_menu — room name + password fields, CREATE ROOM / JOIN ROOM"
```

---

### Task 9: Scene touches — lobby, hud, auctioneer_view, bidder_view, bid_reveal

**Files:**
- Modify: `hot-garbage-godot/src/scenes/lobby.gd`
- Modify: `hot-garbage-godot/src/scenes/hud.gd`
- Modify: `hot-garbage-godot/src/scenes/auctioneer_view.gd`
- Modify: `hot-garbage-godot/src/scenes/bidder_view.gd`
- Modify: `hot-garbage-godot/src/scenes/bid_reveal.gd`

- [ ] **Step 1: Update lobby.gd**

Three changes: array iteration in `_refresh_player_list`, new `start_game` call, `server_restarted` banner.

In `_ready`, replace signal connections:
```gdscript
# old:
NetworkManager.player_registered.connect(_on_player_changed)
NetworkManager.player_disconnected.connect(_on_player_changed)

# new:
NetworkManager.player_registered.connect(func(_n): _refresh_player_list())
NetworkManager.player_disconnected.connect(func(_n): _refresh_player_list())
```

Replace `_refresh_player_list`:
```gdscript
func _refresh_player_list() -> void:
	for child in _player_list.get_children():
		child.queue_free()
	for name in NetworkManager.player_names:
		var lbl := Label.new()
		lbl.text = "• %s" % name
		_UITheme.style_label(lbl, _UITheme.FS_BODY, _UITheme.TEXT)
		_player_list.add_child(lbl)
	var count := NetworkManager.player_names.size()
	if NetworkManager.is_host():
		_status_label.text = "%d player(s) connected" % count
```

Replace `_on_start_pressed`:
```gdscript
func _on_start_pressed() -> void:
	AudioManager.play_ui()
	var duration: int = 45
	if _timer_spin != null:
		duration = int(_timer_spin.value)
	NetworkManager.start_game(duration)
```

Add server_restarted banner at the end of `_build_ui`, just before the start button block:
```gdscript
	if NetworkManager.server_restarted:
		var restart_lbl := Label.new()
		restart_lbl.text = "Server restarted — start a new game."
		_UITheme.style_label(restart_lbl, _UITheme.FS_BODY, Color(1, 0.6, 0.2))
		restart_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(restart_lbl)
```

- [ ] **Step 2: Update hud.gd**

In `refresh()`, replace the first line:
```gdscript
# old:
var own_id: String = NetworkManager.player_names.get(multiplayer.get_unique_id(), "")

# new:
var own_id: String = NetworkManager.local_name
```

- [ ] **Step 3: Update auctioneer_view.gd**

Replace `_on_bid_count_update` listener — connect to `bid_count_updated` signal instead of `bid_received`:

In `on_auctioneer_reveal`, replace:
```gdscript
# old:
if not NetworkManager.bid_received.is_connected(_on_bid_count_update):
    NetworkManager.bid_received.connect(_on_bid_count_update)

# new:
if not NetworkManager.bid_count_updated.is_connected(_on_bid_count_update):
    NetworkManager.bid_count_updated.connect(_on_bid_count_update)
```

Replace `_on_bid_count_update` signature:
```gdscript
# old:
func _on_bid_count_update(_peer_id: int, _amount: int) -> void:
    _received_bids += 1
    _bid_status_label.text = "Bids received: %d / %d" % [_received_bids, _expected_bids]

# new:
func _on_bid_count_update(received: int, total: int) -> void:
    _bid_status_label.text = "Bids received: %d / %d" % [received, total]
```

In `_refresh_players`, replace "is me" check:
```gdscript
# old:
var own_id: int = multiplayer.get_unique_id()
# ...
var is_me: bool = peer_id == own_id

# new — iterate Array[String] instead of dict:
func _refresh_players() -> void:
	for child in _player_vbox.get_children():
		child.queue_free()
	for name in NetworkManager.player_names:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", _UITheme.GAP)
		_player_vbox.add_child(row)
		var is_me: bool = name == NetworkManager.local_name
		var name_lbl := Label.new()
		name_lbl.text = name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_UITheme.style_label(name_lbl, _UITheme.FS_BODY,
			_UITheme.GOLD if is_me else _UITheme.TEXT)
		row.add_child(name_lbl)
		var cash: int = GameServer.player_cash.get(name, -1)
		var cash_lbl := Label.new()
		cash_lbl.text = "§%d" % cash if cash >= 0 else "—"
		_UITheme.style_label(cash_lbl, _UITheme.FS_BODY, _UITheme.DIM)
		row.add_child(cash_lbl)
```

Also remove `_expected_bids` initialization in `_ready` (no longer needed — total comes from server):
```gdscript
# remove this line from _ready:
_expected_bids = NetworkManager.get_peer_ids().size()
```
And remove `var _expected_bids: int = 0` from the top.

- [ ] **Step 4: Update bidder_view.gd**

Same `_refresh_players` fix as auctioneer_view (replace dict iteration with array + local_name check — identical code).

- [ ] **Step 5: Update bid_reveal.gd**

Remove `_peer_id_for_name` function entirely. In `on_show_bid_result`, use `result.winner` directly:

```gdscript
func on_show_bid_result(result: Dictionary) -> void:
	AudioManager.play_resolve()
	if result.winner == "BANK":
		_result_label.text = "No takers.\nBank paid §%d." % result.price
	else:
		_result_label.text = "%s\nwon for §%d!" % [result.winner, result.price]
	_hud.refresh()
```

- [ ] **Step 6: Commit**

```bash
git add hot-garbage-godot/src/scenes/lobby.gd \
  hot-garbage-godot/src/scenes/hud.gd \
  hot-garbage-godot/src/scenes/auctioneer_view.gd \
  hot-garbage-godot/src/scenes/bidder_view.gd \
  hot-garbage-godot/src/scenes/bid_reveal.gd
git commit -m "feat: update scenes for WebSocket transport — array iteration, local_name, bid_count signal"
```

---

### Task 10: AWS deployment

**Files:**
- Create: `hot-garbage-server/create-dynamo-table.sh`
- Create: `hot-garbage-server/deploy.sh`

**Prerequisites:** AWS CLI configured, account ID known, App Runner and ECR IAM permissions available (wire in from your existing bootstrapping repos).

- [ ] **Step 1: Create DynamoDB table in AWS**

```bash
aws dynamodb create-table \
  --table-name hot-garbage-rooms \
  --attribute-definitions AttributeName=roomName,AttributeType=S \
  --key-schema AttributeName=roomName,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```
Expected: `TableStatus: "ACTIVE"` within ~10 seconds.

- [ ] **Step 2: Create ECR repository**

```bash
aws ecr create-repository --repository-name hot-garbage-server --region us-east-1
```
Note the `repositoryUri` output: `[ACCOUNT].dkr.ecr.us-east-1.amazonaws.com/hot-garbage-server`

- [ ] **Step 3: Create deploy.sh**

`hot-garbage-server/deploy.sh`:
```bash
#!/bin/bash
set -e
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REPO=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/hot-garbage-server

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REPO
docker build -t hot-garbage-server -f hot-garbage-server/Dockerfile .
docker tag hot-garbage-server:latest $REPO:latest
docker push $REPO:latest
echo "Pushed to $REPO:latest"
```

```bash
chmod +x hot-garbage-server/deploy.sh && ./hot-garbage-server/deploy.sh
```

- [ ] **Step 4: Create App Runner service**

Create `hot-garbage-server/apprunner.json`:
```json
{
  "ServiceName": "hot-garbage",
  "SourceConfiguration": {
    "ImageRepository": {
      "ImageIdentifier": "[ACCOUNT].dkr.ecr.us-east-1.amazonaws.com/hot-garbage-server:latest",
      "ImageRepositoryType": "ECR",
      "ImageConfiguration": {
        "Port": "3000",
        "RuntimeEnvironmentVariables": {
          "DYNAMODB_TABLE": "hot-garbage-rooms",
          "DYNAMODB_REGION": "us-east-1",
          "PORT": "3000"
        }
      }
    },
    "AutoDeploymentsEnabled": false
  },
  "InstanceConfiguration": {
    "Cpu": "0.25 vCPU",
    "Memory": "0.5 GB"
  },
  "HealthCheckConfiguration": {
    "Protocol": "TCP",
    "Port": "3000"
  }
}
```

```bash
aws apprunner create-service --cli-input-json file://hot-garbage-server/apprunner.json --region us-east-1
```

Note the `ServiceUrl` from the output — this is your `wss://[id].us-east-1.awsapprunner.com` endpoint.

- [ ] **Step 5: Create IAM role for App Runner → DynamoDB**

```bash
# Trust policy
cat > /tmp/trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "tasks.apprunner.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role --role-name hot-garbage-apprunner \
  --assume-role-policy-document file:///tmp/trust.json

# Inline policy for DynamoDB access
aws iam put-role-policy --role-name hot-garbage-apprunner \
  --policy-name dynamo-rooms \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem","dynamodb:PutItem","dynamodb:DeleteItem","dynamodb:Scan"],
      "Resource": "arn:aws:dynamodb:us-east-1:[ACCOUNT]:table/hot-garbage-rooms"
    }]
  }'
```

Update the App Runner service to use the role (get service ARN from step 4 output):
```bash
aws apprunner update-service \
  --service-arn [SERVICE_ARN] \
  --instance-configuration '{"InstanceRoleArn":"arn:aws:iam::[ACCOUNT]:role/hot-garbage-apprunner"}' \
  --region us-east-1
```

- [ ] **Step 6: Update SERVER_URL in NetworkManager.gd**

In `hot-garbage-godot/src/network/network_manager.gd`:
```gdscript
# comment out local dev, uncomment prod:
# const SERVER_URL := "ws://localhost:3000"
const SERVER_URL := "wss://[id].us-east-1.awsapprunner.com"
```

- [ ] **Step 7: End-to-end smoke test**

Run the Godot game on two machines (or two instances on one machine). On machine 1:
- Enter name `Alice`, room `test-room`, password `test`
- Click CREATE ROOM → lands in lobby as host

On machine 2:
- Enter name `Bob`, room `test-room`, password `test`
- Click JOIN ROOM → lands in lobby, Alice's list shows both players

Host clicks START GAME → both machines advance to auctioneer/bidder views.

- [ ] **Step 8: Commit deploy scripts**

```bash
git add hot-garbage-server/deploy.sh hot-garbage-server/apprunner.json \
  hot-garbage-server/create-dynamo-table.sh
git commit -m "feat: AWS deployment — ECR push script, App Runner config, DynamoDB setup"
```

---

## Self-Review

**Spec coverage:**
- ✅ Named rooms with passwords (Task 5: handleCreateRoom/handleJoinRoom)
- ✅ DynamoDB persistence (Task 3: room_store.js)
- ✅ Room restore on cold start (Task 5: startup() scan)
- ✅ `server_restarted` flag in room_joined (Task 5, Task 9 lobby banner)
- ✅ Privacy invariant: auctioneer_reveal targeted send (Task 4: game_session._beginTurn)
- ✅ bid_count message to auctioneer (Task 4: game_session.submitBid)
- ✅ sync_player_state targeted (Task 4: game_session._syncPlayer)
- ✅ All error codes (Task 5: handlers)
- ✅ NetworkManager rewrite (Task 6)
- ✅ GameServer stripped (Task 7)
- ✅ MainMenu UI (Task 8)
- ✅ Scene touches: lobby, hud, auctioneer_view, bidder_view, bid_reveal (Task 9)
- ✅ App Runner + ECR + DynamoDB + IAM (Task 10)

**Type consistency check:**
- `NetworkManager.player_names`: `Array[String]` throughout (Tasks 6, 9)
- `NetworkManager.local_name`: `String` throughout (Tasks 6, 7, 9)
- `bid_count_updated(received: int, total: int)`: defined Task 6, consumed Task 9 auctioneer_view
- `send(playerName|null, msg)`: consistent in game_session and server.js
- `HotGarbageServer` constructor: `{ seed, playerIds, chaosChance, dataPath }` — matches engine.js opts pattern
