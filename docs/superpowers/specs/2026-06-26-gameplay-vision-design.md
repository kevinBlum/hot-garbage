# Hot Garbage — Gameplay Vision Design

**Date:** 2026-06-26
**Status:** Approved for implementation planning

---

## Overview

Hot Garbage is a 3D auction party game. The core loop — rotating auctioneers, sealed bids, chaos events — is solid. This spec layers in mechanics that make the 3D space matter and give the game replayability beyond a Jackbox-style bidding clone.

The additions are:

1. Secret roles with one-shot physical abilities
2. Secret objectives paired to each role
3. Auctioneer precision incentive
4. Black market side economy
5. Forgery mechanic
6. Alternate win conditions and bankruptcy mode
7. Configurable game modes

---

## 1. Secret Roles

### Assignment
At game start, the server randomly deals one role to each player from a pool of 20. The role pool is larger than the player count by design — a 6-player game draws 6 from 20, so no two games feel the same.

### Core rules
- Roles are hidden. You only know your own.
- Each role has exactly **one use** per game. Use it and it's gone.
- Abilities are activated by **physical 3D interaction**: walk near the target or prop, press `E`.
- Using your ability is **visible to the room** — the action is public even if the game doesn't announce the role. Other players piece it together.
- Roles are never officially announced during the game. At the final scores screen, all roles and objectives are revealed simultaneously for the payoff moment.

### Server state per player
```
role: String
ability_used: bool
role_revealed: bool  # true only at final scores
objective_item_id: String
objective_bonus: int
objective_complete: bool
```

---

## 2. Roles Roster (Pool of 20)

All abilities are active and physical — no passives.

| Role | Activation | Effect |
|---|---|---|
| **Thief** | Post-reveal: walk to winner, press E | Steal the just-auctioned item. Winner gets their money back; you take the artifact. |
| **Smasher** | Pitch phase: walk to pedestal, press E | Destroy the item. Auction cancelled; auctioneer gets bank floor only. |
| **Saboteur** | Pitch phase: walk to pedestal, press E | Swap the item for a random deck card. Auctioneer pitches the wrong item. Reveal shows the real one. |
| **Insider** | Any time: walk to pedestal, press E | Privately peek at the current item's true value (shown in your HUD only). |
| **Fence** | Any non-bidding phase: interact with HUD | Sell one artifact from your collection back to the bank at its true value. |
| **Secret Buyer** | Bid reveal phase: walk to podium, press E | Only usable on your auctioneer rounds. Buy the item yourself at the highest bid price. Other players see "ACQUIRED BY AUCTION HOUSE." |
| **Appraiser** | Any moment during an auction: walk to pedestal, press E | Publicly broadcast the item's true value to all players. Timing is the power. |
| **Mole** | Any time: walk to deck box prop, press E | Peek at the next item in the deck (category + value band: LOW = below 150, MED = 150–350, HIGH = above 350). |
| **Vandal** | Pitch phase: walk to pedestal, press E | Secretly reduce the item's true value by ~30% for scoring. Effect is not announced until final scores. |
| **Speculator** | Before bidding closes: walk to chalkboard prop, press E | Lock in a HIGH or LOW prediction on whether the final bid exceeds true value. Correct = cash bonus from bank; wrong = small penalty. |
| **Ghost** | Before bidding opens: walk to mask prop, press E | Your winning bid shows as `???` in the reveal. Nobody knows who bought the item. |
| **Emcee** | Pitch phase (when you're a bidder): walk to podium, press E | Hijack the auctioneer role for this round. You run the auction and collect the proceeds. Original auctioneer becomes a bidder. |
| **Extortionist** | Before bidding closes: walk up to target player, press E | Lock that player out of bidding in this auction. |
| **Shill** | Before bidding closes: walk to back-room prop, press E | Submit a fake bid at a chosen amount. If no real bid beats it, auction fails to BANK (floor payout). Sets a price floor without spending money. |
| **Smuggler** | Any non-bidding phase: walk up to target player, press E | Steal any artifact from that player's existing collection — not just the most recent sale. Targets set completion directly. |
| **Hoarder** | Any time: walk to safe prop, press E | Vault one of your artifacts. Vaulted artifacts cannot be stolen by Thief or Smuggler for the rest of the game. |
| **Price Fixer** | Before an auction opens: walk to chalkboard, press E | Set a mandatory minimum bid for the next auction. All players must meet it or not bid at all. |
| **Swapper** | Any non-bidding phase: walk up to target player, press E | Force an immediate trade: your least valuable artifact for theirs. No choice, instant. |
| **Philanthropist** | Any non-bidding phase: walk up to target player, press E | Transfer 150 cash from your wallet to theirs. Strategic aid or quiet alliance-building. |
| **Arsonist** | Any time: walk to back wall, press E | One random artifact from any player's collection (randomly selected across all players) is permanently removed from the game. |

---

## 3. Secret Objectives

Every role ships with a paired secret objective. The role gives the ability; the objective gives the reason.

At game start the server secretly assigns each player one **target artifact** from the deck. Completing the objective earns a cash bonus revealed at final scores.

### How objectives pair with roles

The target artifact for different roles can deliberately overlap — creating hidden conflict:

- **Thief** → steal the target item → 750 bonus
- **Smasher** → smash the target item → 600 bonus *(may target same item as Philanthropist)*
- **Philanthropist** → own the target item at game end → 1000 bonus *(they quietly bid for it while gifting cash to manipulate others)*
- **Vandal** → damage the target item before it sells → 500 bonus
- **Ghost** → win the target item anonymously → 650 bonus
- **Smuggler** → steal the target item from whoever owns it → 700 bonus
- **Hoarder** → vault the target item before anyone else takes it → 550 bonus

Not every pair of roles points at the same item — the server seeds 1–2 deliberate overlaps per game for drama. Players infer each other's objectives by watching who reacts to which items appearing on the pedestal.

---

## 4. Auctioneer Precision Incentive

### Mechanic
After each auction, the auctioneer receives their payout multiplied by a **precision modifier** based on how close the winning bid was to the item's true value.

The curve is asymmetric — overbidding is salesmanship and is rewarded; underbidding is a failed pitch and is penalized:

| Bid vs. True Value | Multiplier | Interpretation |
|---|---|---|
| ≥ 125% | 1.25× | You hustled the room |
| 90–125% | 1.15× | Sweet spot — honest market |
| 60–90% | 1.0× | Baseline, no change |
| < 60% | 0.8× | Failed pitch |

### Visibility
The multiplier is applied silently. Other players see only the nominal sale price. The auctioneer sees only their cash balance go up.

At final scores, each player's auctioneer rounds are broken down with their precision bonuses and penalties shown — the "wait, you were getting 1.25× this whole time?" moment lands alongside role reveals.

---

## 5. Black Market

A permanent prop in a corner of the room — a shadowy stall. Walk up, press `E` to browse. Stock is **limited and first-come-first-served** — typically 2–3 copies of each item per game. Costs real cash, directly competing with your bidding budget.

### Item catalogue

| Item | Cost | Effect |
|---|---|---|
| Tranquilizer Dart | 100 | Walk up to a player, press E — they cannot bid in the next auction. |
| Smoke Bomb | 75 | Throw it — all HUD timers go dark for one round. Everyone bids blind. |
| Forgery Kit | 200 | Unlocks the forgery table for one use — lets you copy one artifact you own. |
| Bribe Envelope | 250 | Walk up to any player, press E — peek at their role. |
| Auction Hammer | 100 | Force the current auction to close immediately at the highest bid so far. |
| Insurance Policy | 150 | Protect one of your artifacts from Thief and Smuggler for the rest of the game. |

Black market items are not role-locked — anyone can buy and use them. Using a Tranquilizer Dart or Auction Hammer is visible; the purchase itself is private.

---

## 6. Forgery Mechanic

### Prerequisites
- Own at least one artifact
- Have purchased a Forgery Kit from the black market

### Flow
1. Walk to the **forgery table** prop (distinct corner of the room), press `E` with kit in inventory.
2. A **mini-game** starts: a timer-based shape-sculpting interaction (play-dough style). Success rate scales with time invested.
3. On success: the real artifact moves to your **secret stash** (not visible to other players). A forgery copy enters your regular visible inventory.
4. On your next auctioneer turn, you can place the forgery on the pedestal. Your auctioneer overlay shows `[FORGERY]` — you know what you're pitching.
5. The buyer acquires the forgery. **Forgeries score at 40% of true value** at final scores. The buyer discovers the con at the reveal.
6. Your real item remains in your secret stash and scores at full value.

### Counterplay
If the **Appraiser** activates during a forgery auction, the broadcast true value will look suspiciously low relative to what people expect, potentially tipping off the room. The **Vandal** hitting a forgery creates a double-damage situation the seller didn't anticipate.

---

## 7. Win Conditions & Bankruptcy

### Primary win condition
Highest total score at end of all rounds. No change from current behavior.

### Alternate win condition — Set Rush
The first player to own **3 artifacts of the same category** triggers an **immediate game end**. Scores are calculated on the spot.

- The scoreboard displays `ONE AWAY` when any player owns 2 of a category — visible to all, putting everyone on alert.
- This creates a race that directly motivates Thief, Smuggler, Smasher, and related objectives.
- Set Rush and the existing set bonus multiplier stack — completing a set mid-game is worth it both as a win trigger and as a scoring advantage if the game doesn't end immediately (e.g., tie-break).

### Bankruptcy — Broke Mode
When a player's cash hits 0 they enter **Broke Mode** rather than being eliminated:

- Can still move freely in the 3D space
- Can still use their role ability if unused
- Can still visit the black market if they acquire cash (e.g., via Philanthropist)
- **Cannot bid** on items
- Cannot win the primary victory but still holds their current artifact collection for scoring

No bailout, no respawn cash. Bankrupt players become wildcards — they can use their one-shot ability to disrupt leaders and influence who wins without a path to victory themselves. Keeps everyone in the room and engaged.

---

## 8. Game Modes & Configuration

The lobby host sees a settings screen with individual sliders. Three presets pre-fill the settings; the host can tweak after selecting a preset.

### Configurable settings

| Setting | Options |
|---|---|
| Max players | 2–20 |
| Rounds per auctioneer | 1 / 2 / 3 |
| Pitch timer | 10s / 20s / 30s / 60s / unlimited |
| Bid timer | 5s / 10s / 15s / 30s / 60s |
| Roles | on / off |
| Objectives | on / off *(requires roles on)* |
| Black market | on / off |
| Forgery | on / off *(requires black market on)* |
| Chaos chance | off / low / medium / high |

### Presets

| | Standard | Party | Blitz |
|---|---|---|---|
| Max players | 8 | 16 | 20 |
| Rounds per auctioneer | 1 | 1 | 1 |
| Pitch timer | 30s | 20s | 10s |
| Bid timer | 30s | 15s | 8s |
| Roles | ✓ | ✓ | ✗ |
| Objectives | ✓ | ✗ | ✗ |
| Black market | ✓ | ✓ | ✗ |
| Forgery | ✓ | ✗ | ✗ |
| Chaos | Medium | High | High |

**Standard** (~30–45 min): full experience, all systems enabled.
**Party** (~15–20 min): speed format for larger groups, roles without objectives, no forgery.
**Blitz** (~5–8 min): pure auction chaos, no roles or side economies, maximum players.

---

## 9. End-of-Game Reveal Sequence

All hidden information surfaces at the final scores screen in one dramatic sequence:

1. **Scores** — artifact collections, set bonuses, category multipliers
2. **Auctioneer breakdown** — per-player precision multipliers across their auctioneer rounds
3. **Objective results** — who had which target item, who completed their objective, bonus payouts
4. **Role reveal** — all 20 roles revealed simultaneously, players see who had what and "aha" moments land

The reveal sequence is the payoff for all the hidden information that accumulated during the game.

---

## Implementation Notes

- `GameEngine` handles role assignment, objective seeding, precision multiplier calculation, and set-rush detection.
- Black market stock and purchases are server-authoritative (same as bids).
- Forgery state (real item vs. forgery copy, secret stash) is tracked per-player server-side; clients never receive stash contents for other players.
- Role ability activation goes through the existing `interact` input action (`E` key, already in the input map).
- Game mode config is set at lobby creation and sent to `GameEngine` opts on `_init`.
- Proximity chat / in-game voice is **out of scope** for this design — most players coordinate via Discord. The Mute role, if implemented, targets in-game UI feedback rather than voice.
