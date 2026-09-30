<div align="center">

# IRONFRONT

**A real-time strategy game inspired by the classic *Generals* — with up to 8 commanders, 5 nations, and LAN / online multiplayer.**

[![Build](https://github.com/freeb5d/ironfront/actions/workflows/build.yml/badge.svg)](https://github.com/freeb5d/ironfront/actions/workflows/build.yml)
![Engine](https://img.shields.io/badge/engine-Godot%204.3-478cbf)
![Players](https://img.shields.io/badge/players-1--8-e3b341)
![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey)

</div>

---

## About

IronFront is a fast, readable RTS: pick a nation, build an army, and destroy every rival headquarters on a shared 8-player map. It runs on modest hardware (Godot's lightweight *GL Compatibility* renderer), starts in fullscreen, and every build is compiled, tested and packaged automatically by GitHub Actions — no engine install needed to get a playable game.

> **Status:** early playable prototype. Core loop, lobby, bots and networking are in; base building, pathfinding and final art are next (see the [roadmap](#roadmap)).

## Download & play

1. Open the latest successful run in the [**Actions**](https://github.com/freeb5d/ironfront/actions/workflows/build.yml) tab.
2. Under **Artifacts**, download **IronFront-Windows** (or **IronFront-Linux**) and unzip it.
3. Run `IronFront.exe`. The game opens fullscreen — press **F11** to toggle windowed mode.

## Nations

Every nation trains a cheap **light unit** and a strong **heavy unit** with different strengths.

| Nation | Playstyle | Light unit | Heavy unit |
|---|---|---|---|
| **USA** | Elite, expensive, reliable | Ranger | Abrams |
| **China** | Cheap troops, overwhelming numbers | Conscript | Type 99 |
| **Russia** | Heavy armor, slowest but toughest | Motor Rifle | T-90 |
| **Israel** | Fast, precise, hits first | Commando | Merkava |
| **Iran** | Asymmetric: cheap militia, long-range missiles | Militia | Missile Truck |

You choose your nation on a dedicated selection screen before every match (and can change it in the multiplayer lobby). Two players may pick the same nation.

## Game modes

- **Offline** — you against 7 bots with random nations.
- **Multiplayer (LAN / direct IP)** — up to 8 humans. The host decides for each slot whether it is *Open*, a *Bot*, or *Closed*. Empty slots can be filled with bots.

### Hosting a match
1. Click **Host Multiplayer Game**, pick your nation.
2. Share the address shown in the lobby with your friends.
   - Same network (LAN): nothing else needed.
   - Over the internet: forward **UDP port 24680** to your PC on your router (or use a VPN such as Radmin / ZeroTier / Tailscale).
3. Friends enter your IP on the main menu, click **Join Game**, and choose their nation.
4. Press **Start Game** when everyone is ready. If a player disconnects mid-match, a bot takes over their army.

## How to win

Destroy every enemy **headquarters**. A player whose HQ falls is eliminated and all their units vanish. The last commander standing wins.

- Income: **6 credits per second**, start with 500.
- Unit cap: 40 per player.
- Units automatically engage nearby enemies. Units you send with a plain move order ignore enemies until they arrive.

## Controls

| Input | Action |
|---|---|
| Left click / drag | Select units / box-select |
| Right click ground | Move selected units |
| Right click enemy | Attack that target |
| **Q** / **E** | Train light / heavy unit |
| **W A S D**, arrows, screen edges | Pan camera |
| Mouse wheel | Zoom |
| Minimap click / drag | Jump the camera |
| **F11** | Toggle fullscreen |
| **Esc** | Pause menu |

## How it works

- **Engine:** Godot 4.3, GDScript, GL Compatibility renderer.
- **Networking:** server-authoritative. The host runs the simulation; clients send orders and receive compact snapshots (10 Hz) over ENet/UDP.
- **Data-driven nations:** adding a nation means adding one entry in [`scripts/data.gd`](scripts/data.gd).
- **Bots:** simple economy + wave AI in [`scripts/sim.gd`](scripts/sim.gd).
- **CI:** every push compiles all scripts, simulates a full 8-bot match headless, boots the UI and exercises HUD/input, then exports Windows and Linux builds.

```
scripts/
  data.gd     nations, unit stats, colours
  sim.gd      authoritative simulation + bot AI (headless-testable)
  net.gd      lobby, connection, fullscreen toggle (autoload)
  menu.gd     main menu, nation select, lobby
  game.gd     match: rendering, camera, input, HUD, snapshot sync
  ui.gd       shared theme
  minimap.gd  minimap widget
tests/smoke.gd   headless full-match test run by CI
```

## Roadmap

- [ ] Base building and resource nodes
- [ ] Pathfinding and unit collision
- [ ] Teams / alliances
- [ ] Nation special powers
- [ ] Fog of war
- [ ] More unit types and animations, sound
- [ ] Matchmaking / NAT punch-through for easy online play
- [ ] Localisation

## Contributing

Issues and pull requests are welcome. Open the project in [Godot 4.3](https://godotengine.org/download) (`project.godot`) to work on it locally.

## Credits

All art is CC0 (public domain); thanks to the creators:

- Soldiers, tanks and trucks: [Quaternius](https://quaternius.com) via [Poly Pizza](https://poly.pizza)
- HQ buildings, containers, tanks and water towers: [Kenney](https://kenney.nl) *City Kit (Industrial)*
- Trees, rocks, tents and flags: [Kenney](https://kenney.nl) *Mini Forest*

Licence files are kept next to the assets in `assets/`.

## Legal

IronFront is an independent fan-inspired project and is not affiliated with or endorsed by Electronic Arts or the makers of *Command & Conquer: Generals*. All names, art and code are original.
