'use strict';
/**
 * Runs a full bot game of Hot Garbage in the terminal so you can sanity-check
 * the loop, economy, and scoring before building any UI.
 *
 *   node server/simulate.js
 *   node server/simulate.js --seed 42 --players 6 --rounds 5 --chaos 0.4
 */

const { HotGarbage } = require('./engine');
const { SET_THRESHOLD } = require('./scoring');

// ---- tiny arg parser ----
const args = {};
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a.startsWith('--')) args[a.slice(2)] = process.argv[++i];
}
const seed = parseInt(args.seed ?? '7', 10);
const numPlayers = parseInt(args.players ?? '4', 10);
const rounds = args.rounds ? parseInt(args.rounds, 10) : undefined;
const chaos = args.chaos ? parseFloat(args.chaos) : 0.25;

const NAMES = ['Ari', 'Bex', 'Cyd', 'Dov', 'Esme', 'Finn', 'Gwen', 'Hal'];
const playerIds = NAMES.slice(0, numPlayers);

/**
 * Bot bidding strategy. Bots can't see true value (pure bluff), so they
 * bid on CATEGORY NEED: how much closer does this artifact get them to a set?
 * Plus a little noise so games aren't deterministic in feel. This deliberately
 * mirrors how a human reads the table — by category, not by hidden value.
 */
function botBid(game, ctx) {
  const { artifact, ownArtifacts, cash } = ctx;
  const owned = ownArtifacts.filter(a => a.category === artifact.category).length;

  // Base appetite: a midpoint guess at value (bots assume "solid"-ish).
  let base = 150;

  // Set pressure: the closer to completing a set, the more they'll pay.
  if (owned === SET_THRESHOLD - 1) base *= 2.4;        // completes a set!
  else if (owned === SET_THRESHOLD - 2) base *= 1.6;   // one away from one-away
  else if (owned >= SET_THRESHOLD) base *= 1.3;        // extends a set (still scores)

  // Don't blow the whole bank early; cap at a fraction of cash.
  const cap = cash * 0.45;
  const noise = 0.7 + Math.random() * 0.6;
  return Math.min(cap, base * noise);
}

const game = new HotGarbage({ seed, playerIds, rounds, chaosChance: chaos });
const ranking = game.run(botBid);

console.log(game.log.join('\n'));

console.log('\n============ GRAND REVEAL ============');
ranking.forEach((p, i) => {
  const medal = i === 0 ? '🏆' : `  ${i + 1}.`;
  console.log(`${medal} ${p.id} — ${p.total} pts (cash ${p.cash})`);
  for (const [cat, b] of Object.entries(p.breakdown)) {
    const set = b.completed ? `SET x${b.multiplier}` : '';
    console.log(`        ${cat}: ${b.count} items, raw ${b.raw} -> ${b.scored} ${set}`);
  }
});

console.log('\nSeed:', seed, '| Players:', numPlayers, '| Rounds:', game.rounds, '| Chaos:', chaos);
console.log('Re-run with the same --seed for an identical game.');
