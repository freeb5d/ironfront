# Changelog

All notable changes to IronFront. Newest first. Every release is built and tested by GitHub Actions.
Each version needs a `## vX.Y.Z` section here; the release job publishes that section as the release notes.

## v0.11.0
### Added
- **Second map, Crossfire**: two bases in each corner, `$` fields along the edges, oil in a cross through the middle, grass terrain. Choose it in the lobby under *Match options -> Map*.
- Layered explosions: flash, fireball, hot core, rising smoke, sparks and a ground shockwave ring.
- Smoke trails and muzzle blasts for tank shells; sparks and dust puffs for rifle hits.
### Changed
- CI now takes screenshots of both maps.

## v0.10.0
### Added
- README screenshots section.
### Changed
- **Map is 1.5x bigger** (450 x 450). Bases, money fields, oil, props, minimap and strike limits all scale; the camera can zoom out further.
- **Smaller in-game HUD**: shorter command bar, 150 px minimap, smaller command tiles, nation panel, money plate, player list and messages.

## v0.9.1
### Fixed
- Main menu was cut off on 1366x768 screens: it is now compact and scrolls when the screen is very small.
### Changed
- New rank insignia (chevron shields in bronze, silver and gold) by Skoll from game-icons.net, CC BY 3.0, credited in the README and menu.
- Version number and credits line in the menu footer.

## v0.9.0
### Added
- Fog of war option, better sky, lighting and tone mapping, painted roads and base pads, rock rim around the map.
- Units steer around buildings.
### Changed
- Overall graphics pass (props, base decoration, shadows).

## v0.8.0
### Changed
- Single-player and challenge modes open **no network socket at all** (no firewall prompt).
- The pause menu really pauses an offline game.
### Added
- Right-click on the minimap sends the selected units there (Ctrl = attack-move).

## v0.7.0
### Added
- **Challenge ladder**: 5 stages with saved progress per nation.
- Hints for new players and tooltips on every command tile.
- Difficulty and tips settings.

## v0.6.0
### Added
- **Upgrades** (Armor Plating, Weapon Tuning, Logistics) researched at the Barracks.
- **Superweapon** building with a 6 second launch delay, large blast and 180 second cooldown; bots use it too.

## v0.5.0
### Added
- **Base building**: builders place Power Plants, Supply Depots, Barracks, War Factories, Turrets and the Superweapon.
- Power system: low power slows production and shuts turrets down.
- Production queues, builder assist, tech requirements (Heavy tanks need a War Factory).

## v0.4.0
### Added
- **Match options** in the lobby: starting money, game speed, unit limit, starting army, teams (FFA, 2 teams, 4 teams), commander powers, fog of war.
- Team victory rules and team colours.

## v0.3.0
### Added
- **Veterancy**: units gain experience and rank up (Veteran, Elite, Heroic) with rank badges.
- **Commander points and powers**: Air Strike, Rapid Deploy, Field Repair per nation.
- Scoreboard with kills, losses and money earned.

## v0.2.0
### Changed
- **Menu overhaul**: professional main menu with a 3D diorama background, nation cards with live 3D previews, lobby, settings screen (audio, display, performance, controls).
- Rajdhani font and a consistent UI theme.

## v0.1.1
### Fixed
- Black screen when starting the game; the main menu is shown correctly.

## v0.1.0
### Added
- First playable prototype built with Godot 4: 8 players on one map, 5 nations (USA, China, Russia, Israel, Iran), LAN and online multiplayer, bots, farmers harvesting money fields, oil capture, fullscreen.
- Windows and Linux builds published automatically by GitHub Actions.
