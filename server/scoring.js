'use strict';
/**
 * Pure scoring logic for Hot Garbage. No I/O, no randomness.
 * A player's score = sum over categories of (category value * multiplier) + leftover cash.
 * Multiplier applies when a player owns >= SET_THRESHOLD artifacts of a category.
 */

const SET_THRESHOLD = 3;

/**
 * @param {Array<{category:string, value:number}>} artifacts owned by one player
 * @param {number} cash leftover cash
 * @param {Object} categories map: categoryId -> { setBonus, name }
 * @returns {{ total:number, cash:number, breakdown:Object }}
 */
function scorePlayer(artifacts, cash, categories) {
  const byCat = {};
  for (const a of artifacts) {
    (byCat[a.category] ||= []).push(a);
  }

  const breakdown = {};
  let total = cash;

  for (const [cat, items] of Object.entries(byCat)) {
    const raw = items.reduce((s, a) => s + a.value, 0);
    const completed = items.length >= SET_THRESHOLD;
    const mult = completed ? (categories[cat]?.setBonus ?? 1) : 1;
    const scored = Math.round(raw * mult);
    breakdown[cat] = { count: items.length, raw, multiplier: mult, completed, scored };
    total += scored;
  }

  return { total, cash, breakdown };
}

/**
 * Rank all players. Input: map playerId -> { artifacts, cash }.
 * Returns sorted array (highest first) with full breakdowns.
 */
function rankPlayers(players, categories) {
  return Object.entries(players)
    .map(([id, p]) => ({ id, ...scorePlayer(p.artifacts, p.cash, categories) }))
    .sort((a, b) => b.total - a.total);
}

module.exports = { SET_THRESHOLD, scorePlayer, rankPlayers };
