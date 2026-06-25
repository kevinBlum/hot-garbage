'use strict';
// Local dev runner: starts dynalite (in-process DynamoDB) + the game server.
// Usage: node hot-garbage-server/dev.js
// Then point Godot at ws://localhost:3000

const dynalite = require('dynalite');
const { DynamoDBClient, CreateTableCommand } = require('@aws-sdk/client-dynamodb');

const DYNALITE_PORT = 8000;
const TABLE = 'hot-garbage-rooms';

process.env.DYNAMODB_TABLE = TABLE;
process.env.DYNAMODB_REGION = 'us-east-1';
process.env.DYNAMODB_ENDPOINT = `http://localhost:${DYNALITE_PORT}`;
process.env.PORT = process.env.PORT || '3000';

const db = dynalite({ createTableMs: 0 });
db.listen(DYNALITE_PORT, async (err) => {
  if (err) { console.error('dynalite failed:', err); process.exit(1); }
  console.log(`DynamoDB local listening on :${DYNALITE_PORT}`);

  const client = new DynamoDBClient({
    region: 'us-east-1',
    endpoint: `http://localhost:${DYNALITE_PORT}`,
    credentials: { accessKeyId: 'local', secretAccessKey: 'local' },
  });

  try {
    await client.send(new CreateTableCommand({
      TableName: TABLE,
      AttributeDefinitions: [{ AttributeName: 'roomName', AttributeType: 'S' }],
      KeySchema: [{ AttributeName: 'roomName', KeyType: 'HASH' }],
      BillingMode: 'PAY_PER_REQUEST',
    }));
    console.log(`Table '${TABLE}' created`);
  } catch (e) {
    if (e.name === 'ResourceInUseException') {
      console.log(`Table '${TABLE}' already exists`);
    } else {
      console.error('Table creation failed:', e.message);
      process.exit(1);
    }
  }

  require('./server');
});
