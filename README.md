# IronFront

A small Command & Conquer: Generals-style RTS in Unreal Engine 5.4 (C++). All content is created in code (primitive meshes, runtime lighting), so the project needs no editor work.

## Play
- **LMB** click / drag: select units
- **RMB**: move, or attack an enemy unit/building
- **Q**: train a soldier (100 credits; you earn 10/s)
- **WASD / screen edges**: pan, **mouse wheel**: zoom
- Destroy the red HQ before yours falls. Enemy waves grow every 25 s.

## Building in the cloud (GitHub Actions)
1. Link your GitHub account to Epic Games: https://www.unrealengine.com/en-US/ue-on-github
2. Create a GitHub personal access token with `read:packages`, then add repo secrets `GHCR_USER` (your username) and `GHCR_TOKEN`.
3. Push to `main` (or run the workflow from the Actions tab). The Linux build is uploaded as an artifact.
4. A Windows build needs a self-hosted runner with UE 5.4 installed (`UE_ROOT` env var); trigger it manually.

## Ideas for next steps
Navmesh pathfinding, more unit types, resource buildings, fog of war, real art, a proper map.
