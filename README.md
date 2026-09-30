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

1. Download **IronFront-Windows.zip** (or the Linux build) from the [**latest release**](https://github.com/freeb5d/ironfront/releases/latest) and unzip it.
2. Run `IronFront.exe`. The game opens fullscreen — press **F11** to toggle windowed mode.
3. Windows or your browser may warn about an "unknown publisher" because the game is not code-signed. Choose *Keep* / *More info → Run anyway*; the full source and build log are public in this repository.

Bleeding-edge builds of every commit are also available as artifacts on the [Actions](https://github.com/freeb5d/ironfront/actions/workflows/build.yml) page.

### Features

- Fullscreen, Generals-style interface: command bar, framed minimap, money plate, event messages
- 5 nations, 8 players, LAN / direct-IP multiplayer, bots with Easy / Normal / Hard difficulty
- Base building like the classics: train a **Builder** (`B`), select it and construct a Power Plant (`Y`), Supply Depot (`U`), Barracks (`I`), War Factory (`O`) and Turrets (`P`)
- Research upgrades: Armor Plating, Weapon Tuning (need a Barracks) and Logistics
- A nation-specific **Superweapon** (Orbital Cannon, Nuke Missile, Tactical Nuke, Jericho Strike, Scud Storm): needs a War Factory, long cooldown, 6-second warning ring, huge blast
- Power management: buildings draw power, and on low power production slows down and turrets shut off
- Tech and production queues: Barracks speed up infantry, the War Factory unlocks heavy vehicles (and needs a Barracks first)
- Economy with farmers, $ fields (a Supply Depot shortens the trips) and capturable oil derricks
- Real-time combat with projectiles, explosions, positional sound effects
- Veterancy: units earn ranks (veteran, elite, heroic) from kills and get stronger, heroic units self-repair
- Commander points and powers (per nation): targeted strike, reinforcements, field repair
- Control groups, double-click select, attack-move, scoreboard at the end of each match
- Match options in the lobby: starting money, game speed, unit limit, starting army, teams (free for all, 2 teams of 4, 4 teams of 2), commander powers on/off, bot difficulty
- Gameplay tips for newcomers (can be switched off) and hover tooltips on every command tile
- Settings (saved between sessions): volume, fullscreen, VSync, interface scale, FPS counter, shadows, reduced effects for weak computers, edge scrolling, camera and zoom speed, always-visible health bars

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

- **Challenge** — a 5-stage single-player ladder (Border Skirmish, Oil Rush, Two Fronts, Allied Offensive, The Final Stand). Each stage unlocks the next; progress is saved per nation.
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

- Economy: start with 500. Train **farmers** (`R`) and they harvest the green **$ fields** around the map edges, carrying money back to your HQ. Move combat units onto a yellow **oil derrick** for a few seconds to capture it: each derrick you hold pays +4 per second. The five derricks sit in the contested centre. A small trickle of passive income keeps a broken economy alive.
- Unit cap: 40 per player.
- Units automatically engage nearby enemies. Units you send with a plain move order ignore enemies until they arrive.

## Controls

| Input | Action |
|---|---|
| Left click | Select a unit |
| Left drag on empty ground | Move (pan) the map |
| **F** | Select your whole army |
| Right click ground | Move selected units |
| Right click a $ field | Send selected farmers to harvest it |
| Right drag | Box-select units |
| Right click enemy | Attack that target |
| **Q** / **E** / **R** | Train light unit / heavy unit / farmer |
| **W A S D**, arrows, screen edges | Pan camera |
| Mouse wheel | Zoom |
| Minimap click / drag | Jump the camera |
| **F11** | Toggle fullscreen |
| **Ctrl + 1..9** / **1..9** | Set / recall a control group (press twice to jump the camera there) |
| Double-click a unit | Select every visible unit of that type |
| **Ctrl** + right click | Attack-move (fight everything on the way) |
| **X** | Stop |
| **H** / **Home** | Jump to your base |
| **B** | Train a builder, then select it to see the build menu |
| **Y U I O P** | Place Power Plant / Supply Depot / Barracks / War Factory / Turret (builder selected) |
| **T** / **J** | Build the Superweapon (builder selected) / fire it (then click the map) |
| **K** / **L** / **M** | Research Armor / Weapons / Logistics |
| Right click an unfinished building | Send builders to help construct it |
| **Z** / **C** / **V** | Commander powers: strike (then click the map) / reinforcements / field repair |
| **Esc** | Pause menu and settings |

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

- [x] Veterancy and commander powers
- [x] Base building with builders, power and production queues
- [ ] More buildings and upgrades (tech tree, strategy centre)
- [x] Superweapons and upgrades
- [x] Challenge ladder (single-player stages)
- [ ] Garrisonable buildings
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
