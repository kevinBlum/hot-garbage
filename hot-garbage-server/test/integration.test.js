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
