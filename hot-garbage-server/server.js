'use strict';
const { WebSocketServer } = require('ws');

const PORT = parseInt(process.env.PORT || '3000', 10);
const wss = new WebSocketServer({ port: PORT });

wss.on('connection', (ws) => {
  console.log('client connected');
  ws.on('close', () => console.log('client disconnected'));
});

console.log(`Hot Garbage server listening on :${PORT}`);
