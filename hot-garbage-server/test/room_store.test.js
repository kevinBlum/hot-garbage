'use strict';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { DynamoDBClient, CreateTableCommand, DeleteTableCommand } = require('@aws-sdk/client-dynamodb');
const dynalite = require('dynalite');

// Use dynalite (pure Node.js DynamoDB) so tests run without Docker or Java.
const DYNALITE_PORT = 18000;

process.env.DYNAMODB_TABLE = 'hg-test-rooms';
process.env.DYNAMODB_REGION = 'us-east-1';
process.env.DYNAMODB_ENDPOINT = `http://localhost:${DYNALITE_PORT}`;

const roomStore = require('../room_store');

let dynaliteServer;

const client = new DynamoDBClient({
  region: 'us-east-1',
  endpoint: `http://localhost:${DYNALITE_PORT}`,
  credentials: { accessKeyId: 'local', secretAccessKey: 'local' },
});

before(async () => {
  dynaliteServer = dynalite({ createTableMs: 0 });
  await new Promise((resolve, reject) => {
    dynaliteServer.listen(DYNALITE_PORT, err => err ? reject(err) : resolve());
  });

  await client.send(new CreateTableCommand({
    TableName: 'hg-test-rooms',
    AttributeDefinitions: [{ AttributeName: 'roomName', AttributeType: 'S' }],
    KeySchema: [{ AttributeName: 'roomName', KeyType: 'HASH' }],
    BillingMode: 'PAY_PER_REQUEST',
  }));
});

after(async () => {
  await client.send(new DeleteTableCommand({ TableName: 'hg-test-rooms' }));
  await new Promise((resolve, reject) => {
    dynaliteServer.close(err => err ? reject(err) : resolve());
  });
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
