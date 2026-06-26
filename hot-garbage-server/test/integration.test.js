'use strict';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { WebSocket } = require('ws');
const { DynamoDBClient, CreateTableCommand, DeleteTableCommand } = require('@aws-sdk/client-dynamodb');
const dynalite = require('dynalite');

const DYNALITE_PORT = 18099;
const SERVER_PORT = 3099;

process.env.DYNAMODB_TABLE = 'hg-integration-rooms';
process.env.DYNAMODB_REGION = 'us-east-1';
process.env.DYNAMODB_ENDPOINT = `http://localhost:${DYNALITE_PORT}`;
process.env.PORT = String(SERVER_PORT);

// Start server in-process after env is set
const { close: closeServer } = require('../server');

const dbClient = new DynamoDBClient({
  region: 'us-east-1',
  endpoint: `http://localhost:${DYNALITE_PORT}`,
  credentials: { accessKeyId: 'local', secretAccessKey: 'local' },
});

let dynaliteServer;

function connect() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${SERVER_PORT}`);
    ws.once('open', () => resolve(ws));
    ws.once('error', reject);
  });
}

// Buffering queue so rapid-fire messages aren't dropped between `once` calls
function makeQueue(ws) {
  const buf = [];
  const waiters = [];
  ws.on('message', (d) => {
    const msg = JSON.parse(d);
    if (waiters.length) waiters.shift()(msg);
    else buf.push(msg);
  });
  return {
    next() {
      return new Promise(resolve => {
        if (buf.length) resolve(buf.shift());
        else waiters.push(resolve);
      });
    },
    async nextOfType(type) {
      while (true) {
        const msg = await this.next();
        if (msg.type === type) return msg;
      }
    },
  };
}

function nextMsg(ws) {
  return new Promise((resolve) => ws.once('message', (d) => resolve(JSON.parse(d))));
}

function sendMsg(ws, msg) { ws.send(JSON.stringify(msg)); }

before(async () => {
  // Start dynalite
  dynaliteServer = dynalite({ createTableMs: 0 });
  await new Promise((resolve, reject) => {
    dynaliteServer.listen(DYNALITE_PORT, err => err ? reject(err) : resolve());
  });

  // Wait for server startup (startup() scans DynamoDB)
  await new Promise(r => setTimeout(r, 300));

  await dbClient.send(new CreateTableCommand({
    TableName: 'hg-integration-rooms',
    AttributeDefinitions: [{ AttributeName: 'roomName', AttributeType: 'S' }],
    KeySchema: [{ AttributeName: 'roomName', KeyType: 'HASH' }],
    BillingMode: 'PAY_PER_REQUEST',
  }));
});

after(async () => {
  closeServer();
  try {
    await dbClient.send(new DeleteTableCommand({ TableName: 'hg-integration-rooms' }));
  } catch (_) {}
  await new Promise((resolve, reject) => {
    dynaliteServer.close(err => err ? reject(err) : resolve());
  });
});

test('create room → room_joined with isHost:true', async () => {
  const ws = await connect();
  try {
    sendMsg(ws, { type: 'create_room', roomName: 'int-test-1', password: 'pw', playerName: 'Alice' });
    const msg = await nextMsg(ws);
    assert.equal(msg.type, 'room_joined');
    assert.equal(msg.isHost, true);
    assert.equal(msg.roomName, 'int-test-1');
  } finally {
    ws.close();
  }
});

test('join with wrong password → WRONG_PASSWORD error', async () => {
  const ws1 = await connect();
  const ws2 = await connect();
  try {
    sendMsg(ws1, { type: 'create_room', roomName: 'int-test-2', password: 'secret', playerName: 'Alice' });
    await nextMsg(ws1);
    sendMsg(ws2, { type: 'join_room', roomName: 'int-test-2', password: 'wrong', playerName: 'Bob' });
    const msg = await nextMsg(ws2);
    assert.equal(msg.type, 'error');
    assert.equal(msg.code, 'WRONG_PASSWORD');
  } finally {
    ws1.close(); ws2.close();
  }
});

test('two players: start_game triggers advance_scene for each', async () => {
  const ws1 = await connect();
  const ws2 = await connect();
  const q1 = makeQueue(ws1);
  const q2 = makeQueue(ws2);
  try {
    sendMsg(ws1, { type: 'create_room', roomName: 'int-test-3', password: 'pw', playerName: 'Alice' });
    await q1.next(); // room_joined

    sendMsg(ws2, { type: 'join_room', roomName: 'int-test-3', password: 'pw', playerName: 'Bob' });
    const joinMsg = await q2.next(); // room_joined
    assert.equal(joinMsg.type, 'room_joined');
    await q1.next(); // player_joined broadcast

    sendMsg(ws1, { type: 'start_game' });

    // start_game sends role_assigned (private) per player then advance_scene (broadcast)
    const [s1, s2] = await Promise.all([
      q1.nextOfType('advance_scene'),
      q2.nextOfType('advance_scene'),
    ]);
    assert.equal(s1.type, 'advance_scene');
    assert.equal(s2.type, 'advance_scene');
  } finally {
    ws1.close(); ws2.close();
  }
});
