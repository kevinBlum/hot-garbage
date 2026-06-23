# Hot Garbage Godot Prototype — Manual Test Checklist

This checklist covers the full networked game loop smoke test. You need Godot 4.3+ installed and two terminal windows open in `hot-garbage-godot/`.

---

## Prerequisites

- Godot 4.3+ on your PATH (verify: `godot --version`)
- Two terminal windows both cd'd to `hot-garbage-godot/`

---

## Step 1: Open Two Instances

Terminal 1 (will be the host / Alice):
```
godot .
```

Terminal 2 (will be the second player / Bob):
```
godot .
```

Both windows should open to the HOT GARBAGE main menu.

**What to check:**
- [ ] Main menu shows a name field, IP field, "Host Game" button, and "Join Game" button
- [ ] No error dialogs on startup

---

## Step 2: Connect

**In Terminal 1 (host):**
- Enter name: `Alice`
- Leave IP field blank
- Click **Host Game**

**Expected:**
- [ ] Window 1 advances to the Lobby scene
- [ ] Lobby shows "Alice" in the player list
- [ ] Start Game button is visible (host only)

**In Terminal 2 (joiner):**
- Enter name: `Bob`
- Enter IP: `127.0.0.1`
- Click **Join Game**

**Expected:**
- [ ] Window 2 advances to the Lobby scene
- [ ] Both windows now show "Alice" and "Bob" in the player list
- [ ] Window 2 does NOT show a Start Game button

---

## Step 3: Start Game

**In Window 1 (Alice / host):**
- Click **Start Game**

**Expected — whichever window is the auctioneer:**
- [ ] Shows `YOU ARE THE AUCTIONEER` label
- [ ] Shows the artifact name, category, and flavor text
- [ ] Shows `TRUE VALUE: §<number>` — the secret value is visible here
- [ ] Shows a bid count label: `Bids received: 0 / 1`
- [ ] Shows a "Force Resolve" button (host only, may appear on either window)

**Expected — the bidder window:**
- [ ] Shows the artifact name, category, and flavor text
- [ ] Shows `Your bid: §` SpinBox and `Submit Bid` button
- [ ] Does NOT show any "TRUE VALUE" text
- [ ] Does NOT show a value number anywhere on screen

---

## Step 4: Submit a Bid

**In the BidderView window:**
- Enter a bid amount (e.g., `150`)
- Click **Submit Bid**

**Expected:**
- [ ] Submit Bid button disables immediately
- [ ] Status line shows "Bid submitted. Waiting for others..."
- [ ] Auctioneer window bid count updates to `Bids received: 1 / 1`
- [ ] Both windows automatically advance to the BidReveal scene (all bids received triggers auto-resolve)
- [ ] BidReveal shows winner name and winning price (e.g., "Bob won for §150!")
- [ ] OR if bid was 0: "No takers. Bank paid §25."
- [ ] After approximately 3 seconds, both windows automatically advance to the next turn

---

## Step 5: Play Through to Final Scores

- Continue through all turns (each player auctioneers once per round)
- Repeat bid submission each turn

**Expected each turn:**
- [ ] Role assignment alternates correctly (Alice auctioneers, then Bob, etc.)
- [ ] BidReveal may occasionally show an appraiser chaos line revealing the true value after the fact — this is intentional game design
- [ ] After all rounds complete, both windows advance to FinalScores

**Expected on FinalScores:**
- [ ] Shows "GRAND REVEAL" header
- [ ] Both players listed with total points, cash, and per-category breakdowns
- [ ] Rankings are in descending order by total score
- [ ] Set completion bonuses shown where applicable (e.g., "SET x2.0")

---

## Step 6: Verify Privacy Invariant (Bidder Never Sees True Value)

### Visual check
During any auction turn where you are the bidder:
- [ ] Scan the entire BidderView screen — confirm no `§<value>` number matching the auctioneer's displayed "TRUE VALUE" appears anywhere
- [ ] The flavor text and name are shown, but the value field is absent

### Remote Debugger check (Godot editor)
1. Open one of the Godot instances from the editor (not a standalone binary) to enable the Remote Debugger
2. Run the game and reach an auction turn
3. In the editor top bar click **Debugger** → **Remote** tab → **Scene Tree**
4. Expand the scene tree for the BidderView window
5. Inspect each Label node's `text` property
6. **Confirm:** No Label text contains the auctioneer's true value number

### Network-layer verification (static analysis result)
Static inspection confirms the privacy invariant is enforced at two layers:

1. **`game_engine.gd` `start_auction()`** returns a public artifact dict with only `id`, `name`, `category`, `flavor` — the `value` field is deliberately excluded.
2. **`network_manager.gd` `rpc_start_bidding()`** broadcasts this stripped dict to all peers including bidders — no `value` key in the payload.
3. **`network_manager.gd` `rpc_reveal_to_auctioneer()`** sends the full artifact (with `value`) only to the auctioneer's specific peer ID via `rpc_id()`.
4. **`bidder_view.gd` `on_start_bidding()`** only accesses `artifact.name`, `artifact.category`, `artifact.flavor` — never `.value`.

The only place `artifact.value` is displayed is `auctioneer_view.gd` line 49:
```gdscript
_value_label.text = "TRUE VALUE: §%d" % artifact.value
```

Note: After auction resolution, `bid_reveal.gd` receives the full result dict (which contains the artifact including value) but only renders `result.winner` and `result.price`. The appraiser chaos event may intentionally reveal the value as a post-round reveal — this is a designed game mechanic, not a leak.

---

## Step 7: Final Commit

Once you have verified all steps above:

```bash
git add .
git commit -m "feat: complete Hot Garbage Godot prototype — full networked game loop"
```

---

## Troubleshooting

**"Failed to create server" / "Failed to connect"**
- Check nothing else is using port 7777: `ss -tlnp | grep 7777`
- Try restarting both Godot instances

**Second player never appears in lobby**
- Confirm both instances are running on the same machine (loopback)
- Confirm the joiner used IP `127.0.0.1` exactly

**Game doesn't auto-resolve after bid**
- Use the **Force Resolve** button visible on the host's auctioneer screen
- This is an escape hatch for dropped connections or missed bids

**Scenes don't transition**
- Host drives all scene transitions; if the host window is stuck, check the Godot Output panel for GDScript errors
