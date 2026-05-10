# Multiplayer Client Plugin -- Full Audit Report

**Plugin:** Pokemon Pathways Multiplayer Client v1.1.0
**Target:** Pokemon Essentials v19.1 (RPG Maker XP / MKXP-Z)
**Audit Date:** 2026-05-10

---

## 1. ARCHITECTURE OVERVIEW

### 1.1 Module Dependency Graph
```
MP_ClientConfig (001) <-- root, no deps
MP_PacketType   (002) <-- uses MP_ClientConfig for DEBUG_PACKETS
MP_Packet       (002) <-- uses MP_PacketType
RemotePlayer    (003) <-- DEAD CODE, uses Game_Map constants
MP_NetworkManager (004) <-- uses MP_Packet, MP_PacketType, MP_ClientConfig
  -- spawns 3 threads: main_loop, receive_loop, heartbeat_loop
MP_Game_RemotePlayer (005) <-- uses Game_Character, MP_ClientConfig
Sprite_MP_RemotePlayer (006) <-- uses Sprite_Character
MP_OverworldManager (007) <-- uses all above
MP_Hooks        (008) <-- uses MP_NetworkManager, MP_OverworldManager
MP_BattleManager (009) <-- uses MP_NetworkManager, MP_PacketType
MP_TradeManager  (010) <-- uses MP_NetworkManager, MP_PacketType
MP_ChatOverlay   (011) <-- uses MP_NetworkManager, MP_PacketType
MP_VersionManager (012) <-- uses MP_NetworkManager
```

### 1.2 Thread Model
The network layer spawns THREE background threads:
1. **main_loop** -- state machine, reconnection logic
2. **receive_loop** -- reads TCP socket, decodes packets, fires callbacks
3. **heartbeat_loop** -- sends HEARTBEAT every 5s

**CRITICAL:** All packet callbacks execute on the **receive_thread**. UI code (pbMessage) called from here = crash/freeze.

### 1.3 Execution Flow
```
[Game Input] --> [Game_Player.move_generic] --> [MP_Hooks]
                                                      |
                              +-----------------------+-----------------------+
                              |                                               |
                              v                                               v
                    [MP_OverworldManager.update_local_position]    [Scene_Map#update hook]
                              |                                               |
                              +-----------------------+                       |
                                                      |                       |
                              v                       v                       v
                    [MP_NetworkManager.send_packet]  [remote sprite update]  [process_outgoing]
                              |                                                       |
                              +-----------------------+                               |
                                                      |                               |
                              v                       v                               v
                    [send_queue] --> [main_loop] --> [socket.write]          [server]
                                                                                |
                                                                    [receive_loop.read]
                                                                                |
                                                                    [packet callbacks]
                                                                                |
                                                                    [UI = CRASH]
```

---

## 2. CRITICAL BUGS (Severity: CRASH / FREEZE / DESYNC)

### C1: UI Code Called from Network Thread [CRASH]
- **Files:** 009_mp_battle.rb:97, 010_mp_trade.rb:123, 010_mp_trade.rb:149
- **Issue:** `pbMessage` called from `receive_loop` thread
- **Impact:** Immediate crash/freeze on battle request, trade request, or trade open
- **Root Cause:** Packet callbacks execute on receive_thread; no marshalling to main thread
- **Fix:** Implement `MP_NetworkManager.schedule_on_main` queue; drain in Scene_Map#update

### C2: Double Scene_Map#main Hook [CRASH / DOUBLE-EXECUTION]
- **Files:** 000_mp_diagnostic.rb, 008_mp_hooks.rb
- **Issue:** Both files alias `Scene_Map#main`, creating nested wraps
- **Impact:** Scene_Map#main executes twice; ensure blocks run in wrong order; network stopped then logged
- **Fix:** Merge into single hook installation; remove diagnostic main hook

### C3: Position Double-Send [PERFORMANCE / SERVER OVERLOAD]
- **File:** 007_mp_overworld.rb:68-118
- **Issue:** Change-driven + periodic sends both fire on same frame
- **Impact:** ~28-30 PLAYER_MOVE packets/sec at 60 FPS (should be ~10)
- **Fix:** Skip periodic send if change packet was already sent this frame

### C4: Map Change Triple-Send [DESYNC]
- **Files:** 007_mp_overworld.rb:82-88, 008_mp_hooks.rb:69-81
- **Issue:** `update_local_position` + `transfer_player` hook both send MAP_CHANGE
- **Fix:** Only send from transfer_player hook; reset @last_pos in on_map_changed

### C5: Battle Hook Singleton Method Leak [MEMORY]
- **File:** 009_mp_battle.rb:174-198
- **Issue:** `define_singleton_method` patches scene permanently; stacks across battles
- **Fix:** Use Events.onStartBattle instead of singleton patching

### C6: receive_loop Busy-Wait Burns CPU [PERFORMANCE]
- **File:** 004_mp_network.rb:199-215
- **Issue:** `sleep(0.001)` = 1000 wakeups/sec when no data
- **Fix:** `sleep(0.016)` (1 frame) or use `IO.select`

### C7: handle_player_join Wrong Map [DESYNC]
- **File:** 007_mp_overworld.rb:164
- **Issue:** Always uses `$game_map.map_id` instead of payload's map_id
- **Fix:** Read map_id from payload; only spawn if same map

### C8: create_remote_sprite Viewport Crash [CRASH]
- **File:** 007_mp_overworld.rb:269
- **Issue:** `spriteset.class.viewport` and `Spriteset_Map.viewport` don't exist
- **Fix:** Use `spriteset.viewport` (instance method)

### C9: set_target Double-Call Jerky Movement [VISUAL]
- **File:** 007_mp_overworld.rb:198-206
- **Issue:** `set_target` called twice, restarting interpolation
- **Fix:** Remove outer call; only call inside interpolation branch

### C10: Thread-Unsafe Socket Access [RACE CONDITION]
- **File:** 004_mp_network.rb:271-311
- **Issue:** send_raw checks socket, then writes -- another thread may close between check and write
- **Fix:** Wrap socket access in @mutex

### C11: Integer Overflow in pos_frame_counter [PERFORMANCE]
- **File:** 007_mp_overworld.rb:14
- **Issue:** Counter increments forever, eventually becomes Bignum
- **Fix:** Use modulo reset: `@pos_frame_counter = (@pos_frame_counter + 1) % 3600`

### C12: Chat Input Interferes with Gameplay [GAMEPLAY]
- **File:** 011_mp_chat.rb:64-78
- **Issue:** Chat activates on Input::USE (C/Enter), same as NPC interact
- **Fix:** Add guard: don't open chat if facing event or in menu; use dedicated key

### C13: Trade Owner API Mismatch [CRASH]
- **File:** 010_mp_trade.rb:247
- **Issue:** `Pokemon::Owner.new_foreign` may not exist in v19.1
- **Fix:** Wrap in begin/rescue with fallback

### C14: mp_data.rb is Dead Code [MAINTENANCE]
- **File:** 003_mp_data.rb
- **Issue:** `RemotePlayer` class never instantiated; 99 lines of unused code
- **Fix:** Remove file; integrate useful parts into MP_Game_RemotePlayer

### C15: Trade Serialization Loses All Stats [GAMEPLAY]
- **File:** 010_mp_trade.rb:301-312
- **Issue:** Only sends species/level/name/gender/shiny/form; loses IVs, EVs, moves, nature, ability, item
- **Fix:** Full round-trip serialization/deserialization

### C16: handle_player_leave Double-Dispose [CRASH]
- **File:** 007_mp_overworld.rb:175-184
- **Issue:** No guard against disposing already-disposed sprite
- **Fix:** Add `disposed?` checks in all disposal paths

### C17: super($game_map) Wrong Signature [CRASH]
- **File:** 005_mp_remote_player.rb:11
- **Issue:** `Game_Character#initialize` takes no args
- **Fix:** Call `super()` with no arguments

### C18: handle_battle_result UI Thread [CRASH]
- **File:** 009_mp_battle.rb:216-234
- **Issue:** `pbMessage` from receive_thread
- **Fix:** Marshal to main thread

### C19: Trade Party Index Stale [GAMEPLAY]
- **File:** 010_mp_trade.rb:250-256
- **Issue:** Finds Pokemon by object reference after party may have changed
- **Fix:** Store index at offer time, not object reference

### C20: Chat Sprite Without Scene Guard [CRASH]
- **File:** 011_mp_chat.rb:157-165
- **Issue:** Creates sprite even when not in Scene_Map
- **Fix:** Only create when `$scene.is_a?(Scene_Map)`

---

## 3. MODERATE BUGS

| # | File | Issue | Severity |
|---|------|-------|----------|
| M1 | 007_mp_overworld.rb:215 | MAP_PLAYER_LIST mass-clear causes flicker | Visual |
| M2 | 005_mp_remote_player.rb:131 | create_name_bitmap allocates GPU texture every call | Performance |
| M3 | 004_mp_network.rb:364 | send_party_data only sends 1st Pokemon | Gameplay |
| M4 | 002_mp_packet.rb:83 | No max packet size check | Security |
| M5 | 007_mp_overworld.rb:120 | Updates culled characters every frame | Performance |
| M6 | 011_mp_chat.rb:167 | Inefficient array copy on every message | Performance |
| M7 | 010_mp_trade.rb:205 | Safe navigation operator for old Ruby | Compatibility |
| M8 | 007_mp_overworld.rb:96 | move_generic hook redundant with Scene_Map#update | Performance |
| M9 | 004_mp_network.rb:315 | handle_disconnect not mutex-protected | Race |
| M10 | 011_mp_chat.rb:40 | CHAT_SYSTEM handler registered twice | Logic |
| M11 | 009_mp_battle.rb:135 | Opponent party = player's party (placeholder) | Gameplay |
| M12 | 005_mp_remote_player.rb:50 | Name sprite updated twice per frame (redundant) | Performance |
| M13 | 004_mp_network.rb:376 | No graceful disconnect on SIGTERM | Edge Case |
| M14 | 007_mp_overworld.rb:140 | cull_remote_players only toggles visible, still updates | Performance |

---

## 4. CONFIGURATION ISSUES

| Setting | Current | Issue | Recommended |
|---------|---------|-------|-------------|
| POSITION_SEND_INTERVAL | 3 frames | Too frequent; causes packet spam | 60 frames (1s) |
| INTERPOLATION_DURATION | 50ms | Too short; jerky at high packet rates | 250ms |
| VISIBLE_DISTANCE | 20 tiles | Large; causes many sprites in towns | 12 tiles |
| RECONNECT_MAX_ATTEMPTS | 0 | Infinite loop if server down | 10 |
| SEND_INTERVAL | 0.05s | Ok but should be configurable per-state | Keep |

---

## 5. IMPLEMENTATION PLAN

### Phase 1: Network Layer (004)
- Add `@main_thread_queue` for marshalling UI work to main thread
- Wrap socket/state access in mutex
- Fix busy-wait in receive_loop
- Add packet size validation
- Make all disconnect paths thread-safe

### Phase 2: Overworld (007) + Remote Player (005) + Sprite (006)
- Fix double position send
- Fix map change triple send
- Fix set_target double-call
- Fix viewport access crash
- Fix player_join map check
- Add culled-player update skip
- Fix pos_frame_counter overflow
- Fix super() call signature

### Phase 3: Hooks (008) + Diagnostic (000)
- Merge Scene_Map#main hooks
- Remove move_generic redundant hook
- Make hook installation idempotent

### Phase 4: Battle (009)
- Add main-thread marshalling for all UI
- Replace singleton method hook
- Implement actual command execution
- Fix opponent party placeholder

### Phase 5: Trade (010)
- Add main-thread marshalling for all UI
- Full Pokemon serialization
- Fix party index tracking
- Fix owner assignment

### Phase 6: Chat (011)
- Fix duplicate CHAT_SYSTEM handler
- Add scene guard for sprite creation
- Fix input interference
- Add disposed? checks

### Phase 7: Data (003) + Version (012) + Config (001)
- Remove dead code (003)
- Fix version error callback timing (012)
- Adjust config values (001)

---

## 6. FILES PRODUCED

| File | Status |
|------|--------|
| 000_mp_diagnostic.rb | Rewritten (removed Scene_Map hook, kept mp_log) |
| 001_mp_config.rb | Updated (tuned values) |
| 002_mp_packet.rb | Hardened (max size check, validation) |
| 003_mp_data.rb | Removed (dead code) |
| 004_mp_network.rb | Fully rewritten (thread-safe, marshalling, performance) |
| 005_mp_remote_player.rb | Fixed (super(), name bitmap cache, culling) |
| 006_mp_remote_sprite.rb | Fixed (nil guards, double-update) |
| 007_mp_overworld.rb | Fully rewritten (position sync, map changes, spawning) |
| 008_mp_hooks.rb | Rewritten (single hook, idempotent) |
| 009_mp_battle.rb | Rewritten (main-thread UI, proper hooks) |
| 010_mp_trade.rb | Rewritten (full serialization, main-thread UI) |
| 011_mp_chat.rb | Fixed (duplicate handler, scene guards) |
| 012_mp_version.rb | Fixed (callback safety) |
| meta.txt | Updated (v1.2.0) |
