'use strict';

const ROLE_POOL = [
  { id: 'thief',         name: 'THIEF',         description: 'Steal the just-auctioned item from the winner.',        activationPhase: 'bid_result', requiresTarget: true  },
  { id: 'smasher',       name: 'SMASHER',       description: 'Destroy the item on the pedestal during pitch.',        activationPhase: 'pitch',      requiresTarget: false },
  { id: 'saboteur',      name: 'SABOTEUR',      description: 'Swap the pedestal item for a random deck card.',        activationPhase: 'pitch',      requiresTarget: false },
  { id: 'insider',       name: 'INSIDER',       description: 'Peek at the current item\'s true value privately.',     activationPhase: 'pitch',      requiresTarget: false },
  { id: 'fence',         name: 'FENCE',         description: 'Sell one artifact you own back to bank at true value.', activationPhase: 'any',        requiresTarget: false },
  { id: 'secret_buyer',  name: 'SECRET BUYER',  description: 'As auctioneer, buy the item yourself.',                activationPhase: 'bid_result', requiresTarget: false },
  { id: 'appraiser',     name: 'APPRAISER',     description: 'Publicly broadcast the true value to all players.',    activationPhase: 'auction',    requiresTarget: false },
  { id: 'mole',          name: 'MOLE',          description: 'Peek at the next item in the deck.',                   activationPhase: 'any',        requiresTarget: false },
  { id: 'vandal',        name: 'VANDAL',        description: 'Secretly reduce the item\'s true value by 30%.',       activationPhase: 'pitch',      requiresTarget: false },
  { id: 'speculator',    name: 'SPECULATOR',    description: 'Predict HIGH or LOW vs true value for a cash bonus.',  activationPhase: 'bidding',    requiresTarget: false },
  { id: 'ghost',         name: 'GHOST',         description: 'Make your winning bid anonymous for one auction.',      activationPhase: 'bidding',    requiresTarget: false },
  { id: 'emcee',         name: 'EMCEE',         description: 'Hijack the auctioneer role for this round.',           activationPhase: 'pitch',      requiresTarget: false },
  { id: 'extortionist',  name: 'EXTORTIONIST',  description: 'Lock a player out of bidding in this auction.',        activationPhase: 'bidding',    requiresTarget: true  },
  { id: 'shill',         name: 'SHILL',         description: 'Submit a fake bid; if highest, auction fails to bank.',activationPhase: 'bidding',    requiresTarget: false },
  { id: 'smuggler',      name: 'SMUGGLER',      description: 'Steal any artifact from any player\'s collection.',    activationPhase: 'any',        requiresTarget: true  },
  { id: 'hoarder',       name: 'HOARDER',       description: 'Vault one artifact so it cannot be stolen.',           activationPhase: 'any',        requiresTarget: false },
  { id: 'price_fixer',   name: 'PRICE FIXER',   description: 'Set a mandatory minimum bid before an auction.',       activationPhase: 'pre_pitch',  requiresTarget: false },
  { id: 'swapper',       name: 'SWAPPER',       description: 'Force a trade: your worst artifact for theirs.',       activationPhase: 'any',        requiresTarget: true  },
  { id: 'philanthropist',name: 'PHILANTHROPIST', description: 'Give 150 cash to a player; own your target to win.',  activationPhase: 'any',        requiresTarget: true  },
  { id: 'arsonist',      name: 'ARSONIST',      description: 'Destroy one random artifact from any player.',         activationPhase: 'any',        requiresTarget: false },
];

const OBJECTIVE_BONUSES = {
  thief: 750, smasher: 600, saboteur: 500, insider: 400, fence: 450,
  secret_buyer: 700, appraiser: 400, mole: 350, vandal: 500, speculator: 400,
  ghost: 650, emcee: 600, extortionist: 500, shill: 400, smuggler: 700,
  hoarder: 550, price_fixer: 400, swapper: 450, philanthropist: 1000, arsonist: 500,
};

function assignRoles(playerIds, deck, rng) {
  if (playerIds.length > ROLE_POOL.length) {
    throw new Error(`Too many players (${playerIds.length}) for role pool (${ROLE_POOL.length})`);
  }
  const shuffled = ROLE_POOL.slice().sort(() => rng() - 0.5);
  const assigned = {};
  for (let i = 0; i < playerIds.length; i++) {
    const role = shuffled[i];
    const targetIdx = Math.floor(rng() * deck.length);
    assigned[playerIds[i]] = {
      role,
      objectiveItemId: deck[targetIdx].id,
      objectiveItemName: deck[targetIdx].name,
      objectiveBonus: OBJECTIVE_BONUSES[role.id] ?? 500,
      objectiveComplete: false,
      abilityUsed: false,
      vaultedItemId: null,
    };
  }
  return assigned;
}

module.exports = { ROLE_POOL, assignRoles, OBJECTIVE_BONUSES };
