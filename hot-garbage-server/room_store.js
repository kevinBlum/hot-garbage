'use strict';
const { DynamoDBClient, GetItemCommand, PutItemCommand, DeleteItemCommand, ScanCommand } = require('@aws-sdk/client-dynamodb');
const { marshall, unmarshall } = require('@aws-sdk/util-dynamodb');

// Read config dynamically so test files can set env vars before requiring.
function makeClient() {
  const opts = { region: process.env.DYNAMODB_REGION || 'us-east-1' };
  if (process.env.DYNAMODB_ENDPOINT) {
    opts.endpoint = process.env.DYNAMODB_ENDPOINT;
    // Provide dummy credentials for local DynamoDB (dynalite / DynamoDB Local).
    opts.credentials = { accessKeyId: 'local', secretAccessKey: 'local' };
  }
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
