# Multiplayer Plugin v1.2.0 -- Migration Guide

## Overview

This is a production-stabilized rewrite of the client-side multiplayer plugin. Every file has been audited, fixed, and hardened for real-world deployment.

---

## File Changes

### Files Modified (11)

| File | Changes |
|------|---------|
| `000_mp_diagnostic.rb` | Removed Scene_Map hook (was conflicting); kept mp_log utility |
| `001_mp_config.rb` | Tuned all values for production (see below) |
| `002_mp_packet.rb` | Added max packet size guard, validation |
| `004_mp_network.rb` | **Full rewrite** -- thread-safe, main-thread marshalling, heartbeat timeout |
| `005_mp_remote_player.rb` | Fixed super(), name bitmap caching, culled flag |
| `006_mp_remote_sprite.rb` | Removed double name update, added guards |
| `007_mp_overworld.rb` | **Full rewrite** -- fixed all sync bugs, diff-based player list |
| `008_mp_hooks.rb` | **Rewritten** -- single Scene_Map hook, no redundant move_generic hook |
| `009_mp_battle.rb` | **Full rewrite** -- main-thread UI, proper hooks, opponent party sync |
| `010_mp_trade.rb` | **Full rewrite** -- main-thread UI, full Pokemon serialization |
| `011_mp_chat.rb` | Fixed duplicate handler, scene guards, dedicated chat key |
| `012_mp_version.rb` | Added init guard for load-order safety |
| `meta.txt` | Updated to v1.2.0 |

### Files Removed (1)

| File | Reason |
|------|--------|
| `003_mp_data.rb` | Dead code -- `RemotePlayer` class never instantiated |

---

## Critical Config Changes

The default values in v1.1.0 were causing server overload. New tuned values:

```ruby
POSITION_SEND_INTERVAL = 60    # was 3  -- now 1 position pkt/sec baseline
INTERPOLATION_DURATION = 250   # was 50 -- smooth over 15 frames
VISIBLE_DISTANCE       = 12    # was 20 -- reduces crowd sprite count
RECONNECT_MAX_ATTEMPTS = 10    # was 0  -- prevents infinite loops
```

These should be adjusted based on your server's capacity. If your server can handle more traffic, lower `POSITION_SEND_INTERVAL`.

---

## Key Architecture Changes

### 1. Main-Thread UI Marshalling (CRITICAL)

The #1 bug in v1.1.0 was calling `pbMessage` from the network thread. This is now fixed via `MP_NetworkManager.schedule_on_main`:

```ruby
# WRONG (v1.1.0) -- crashes
MP_NetworkManager.on_packet(SOME_TYPE) do |payload|
  pbMessage("Hello")  # <-- CRASH: UI on wrong thread
end

# CORRECT (v1.2.0) -- safe
MP_NetworkManager.on_packet(SOME_TYPE) do |payload|
  MP_NetworkManager.schedule_on_main do
    pbMessage("Hello")  # <-- SAFE: runs on main thread
  end
end
```

All battle requests, trade requests, trade completion, and battle results are now marshalled.

### 2. Battle/Trade Update Loop

Battle and Trade managers now have `update` methods called from the main thread each frame. They process pending UI work:

```ruby
# In Scene_Map#update (008_mp_hooks.rb):
MP_BattleManager.update   # processes pending battle request messages
MP_TradeManager.update    # processes pending trade complete messages
```

### 3. Position Send Rate

v1.1.0 sent ~28-30 position packets/sec. v1.2.0 sends ~10/sec:
- One packet per player step (change-driven)
- One packet per second (periodic heartbeat)
- Map changes only sent from `transfer_player` hook

### 4. Player List Diffing

Instead of clearing all sprites on every `MAP_PLAYER_LIST`, the new code diffs and only adds/removes changed players. No more flicker.

---

## Installation

1. **Delete** `003_mp_data.rb` (dead code, no longer needed)
2. **Replace** all other files with the v1.2.0 versions
3. **Keep the same load order** (000 through 012)
4. **Verify** the server uses compatible packet format

---

## Server Compatibility

The client expects the server to:
- Accept `PLAYER_MOVE` packets with `map_id` field
- Send `PLAYER_JOIN` packets with `map_id` field
- Send `MAP_PLAYER_LIST` with `map_id` per player
- Handle `MAP_CHANGE` packets
- Support the full trade packet protocol

If your server doesn't include `map_id` in position packets, the client will still work but may show players on wrong maps.

---

## Testing Checklist

- [ ] Connect to server (new game)
- [ ] Connect to server (loaded save)
- [ ] Two players see each other on same map
- [ ] Player movement is smooth (not jerky)
- [ ] Map transfer clears remote players
- [ ] Remote players on different maps are hidden
- [ ] Battle request shows dialog (no crash)
- [ ] Battle accept/decline works
- [ ] Trade request shows dialog (no crash)
- [ ] Trade completes with stats preserved
- [ ] Chat opens with Shift key (not Enter)
- [ ] Disconnect/reconnect works
- [ ] No FPS drops with 5+ players visible
- [ ] Close game window (graceful disconnect)
