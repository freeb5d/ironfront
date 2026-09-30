# IronFront

A Generals-style RTS in Godot 4.3 (GDScript, lightweight GL Compatibility renderer).
Up to **8 players** on one map (humans and bots), **5 countries** (USA, China, Russia, Israel, Iran), LAN / direct-IP multiplayer.

## Play
1. Download the Windows or Linux build from the latest run in the **Actions** tab (Artifacts).
2. **Offline**: "Play offline vs 7 bots".
3. **Multiplayer**: one player clicks *Host*, opens UDP port 24680 if playing over the internet (LAN needs nothing), and shares their IP. Others enter it and click *Join*. The host sets each slot to Open / Bot / Closed, everyone picks their country, and the host presses START.

Controls: LMB select / drag-box, RMB move or attack, WASD or screen edges pan, wheel zoom, Q / E train the light / heavy unit, Esc leaves.

Rules: destroy every other HQ. A player whose HQ falls is eliminated (their units vanish). Last one standing wins. 6 credits/s income, 40 unit cap.

## Layout
- `scripts/data.gd` countries and stats (add a country = add a dictionary entry)
- `scripts/sim.gd` server-side simulation and bot AI (headless testable)
- `scripts/net.gd` lobby and connection (host is authoritative)
- `scripts/game.gd` rendering, camera, input, snapshot sync (10 Hz)
- `tests/smoke.gd` headless 8-bot match, run by CI

## Next
Base building, resource nodes, pathfinding, teams, per-country special powers, fog of war, real art and sound, Steam / EOS matchmaking.
