'use strict';
const http = require('http');
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

  const room = { config, passwordHash, createdBy: playerName, players: new Map(), session: null, wasRestored: false };
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
    rooms.set(roomName, { config: dbRoom.config, passwordHash: dbRoom.passwordHash, createdBy: dbRoom.createdBy, players: new Map(), session: null, wasRestored: true });
  }
  const room = rooms.get(roomName);

  if (room.players.has(playerName) && room.players.get(playerName) !== ws) {
    return send(ws, { type: 'error', code: 'NAME_IN_USE', message: 'Name already in use.' });
  }

  if (room.players.size >= (room.config.maxPlayers || 8) && !room.players.has(playerName)) {
    return send(ws, { type: 'error', code: 'ROOM_FULL', message: 'Room is full.' });
  }

  const inActiveGame = room.session && room.session.isActive && !room.session._playerNames.includes(playerName);
  if (inActiveGame) return send(ws, { type: 'error', code: 'GAME_IN_PROGRESS', message: 'Game in progress.' });

  room.players.set(playerName, ws);
  ctx.playerName = playerName;
  ctx.roomName = roomName;

  const players = [...room.players.keys()];
  const isHost = playerName === room.createdBy;
  const serverRestarted = !!room.wasRestored;

  send(ws, { type: 'room_joined', roomName, isHost, config: room.config, players, serverRestarted });
  broadcastRoom(roomName, { type: 'player_joined', playerName, players }, playerName);
}

function handleStartGame(ws, msg, ctx) {
  const { roomName, playerName } = ctx;
  const room = rooms.get(roomName);
  if (!room || room.createdBy !== playerName) return;
  if (room.session && room.session.isActive) return;
  if (room.players.size < 2) return send(ws, { type: 'error', code: 'NOT_ENOUGH_PLAYERS', message: 'Need at least 2 players.' });

  const playerNames = [...room.players.keys()];
  room.wasRestored = false;
  const sessionConfig = { ...room.config, pitchDuration: msg.pitchDuration || room.config.pitchDuration };
  room.session = new GameSession(playerNames, sessionConfig, makeSend(roomName));
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

function handleAbilityActivate(ws, msg, ctx) {
  const room = rooms.get(ctx.roomName);
  if (!room?.session?.isActive) return;
  room.session.activateAbility(ctx.playerName, msg.abilityType ?? '', msg.targetName ?? null);
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
  // If room is empty, remove from memory (but NOT from Dynamo — room persists for rejoin)
  if (room.players.size === 0) {
    rooms.delete(roomName);
  }
}

// --- main ---

const httpServer = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', rooms: rooms.size }));
    return;
  }
  res.writeHead(426, { 'Upgrade': 'Required' });
  res.end('WebSocket upgrade required');
});

const wss = new WebSocketServer({ server: httpServer });
httpServer.listen(PORT);

// Ping every 30s to keep ALB connections alive and evict dead sockets.
const keepAlive = setInterval(() => {
  for (const client of wss.clients) {
    if (!client.isAlive) { client.terminate(); continue; }
    client.isAlive = false;
    client.ping();
  }
}, 30_000);
wss.on('close', () => clearInterval(keepAlive));

wss.on('connection', (ws) => {
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
  const ctx = { playerName: null, roomName: null };

  ws.on('message', async (data) => {
    let msg;
    try { msg = JSON.parse(data); } catch { return; }
    switch (msg.type) {
      case 'create_room':   return handleCreateRoom(ws, msg, ctx);
      case 'join_room':     return handleJoinRoom(ws, msg, ctx);
      case 'start_game':    return handleStartGame(ws, msg, ctx);
      case 'open_early':    return handleOpenEarly(ws, ctx);
      case 'submit_bid':    return handleSubmitBid(ws, msg, ctx);
      case 'force_resolve': return handleForceResolve(ws, ctx);
      case 'ability_activate': return handleAbilityActivate(ws, msg, ctx);
      case 'delete_room':   return handleDeleteRoom(ws, ctx);
      case 'player_move':
        if (ctx.roomName) {
          broadcastRoom(ctx.roomName, {
            type: 'player_move',
            playerName: ctx.playerName,
            x: msg.x ?? 0, y: msg.y ?? 0, z: msg.z ?? 0,
            ry: msg.ry ?? 0,
            anim: msg.anim ?? 'idle',
          }, ctx.playerName); // exclude sender
        }
        return;
    }
  });

  ws.on('close', () => {
    if (ctx.roomName && ctx.playerName) handleDisconnect(ctx.roomName, ctx.playerName);
  });
});

startup()
  .then(() => console.log(`Hot Garbage server listening on :${PORT}`))
  .catch(err => console.warn('Startup warning (DynamoDB may not be ready):', err.message));

function close() { wss.close(); httpServer.close(); }

module.exports = { wss, rooms, close };
