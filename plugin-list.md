# Minecraft 26.3 plugin list

Updated: 2026-10-04
Target: Spigot/Paper 26.3
Runtime: Java 25+

## Recommended / verified for 26.3

| Plugin | Old version | Version for 26.3 | Status |
|---|---:|---:|---|
| ViaVersion | 4.10.2 | 5.12.0 | Explicit 26.3 support |
| Multiverse-Core | 4.3.1 | 5.8.1 | Listed for 26.3 |
| Multiverse-Portals | 4.2.3 | 5.3.0 | Listed for 26.3 |
| Multiverse-NetherPortals | - | 5.1.0 | Listed for 26.3 |
| Multiverse-Inventories | - | 5.3.6 | Explicit 26.3 support |
| Multiverse-SignPortals | - | 5.0.4 | Listed for 26.3 |
| ProtocolLib | unspecified | Development Build (5.5.0-SNAPSHOT line) | Use dev build: includes Minecraft 26.3 packet fixes |
| WorldEdit (Bukkit) | 7.3.0 | 7.4.6 Beta 2 | 26.3 build; beta |
| WorldGuard | 7.0.9 | 7.0.19 | Stable; 26.2-26.3 |
| BlockLocker | unspecified | 1.15 | Explicit 1.20-26.3 support |
| Orebfuscator | unspecified | 5.6.2 | Explicit 26.3 support |

## Current versions that should be tested on 26.3

| Plugin | Old version | Current version | Notes |
|---|---:|---:|---|
| Advanced Portals | 0.9.2 | 2.3.0 | Current release, but its published tested-version list stops at 1.21 |
| GroupManager | 3.2 | 3.2 | Still current; no explicit 26.3 test declaration |
| ProtectionStones | 2.10.3 | 2.10.6 | Current; author says it supports 1.21.10+ but does not explicitly list 26.3 |
| Vault | 1.7.3 | 1.7.3 | Still current upstream; old but commonly remains API-compatible |
| Vivecraft Spigot Extensions | old jar | 1.3.15-1 | Latest published build found; release notes explicitly mention support through 26.1.2, so test on 26.3 |
| CoreProtect Community Edition | 23.0 | 24.1 | Current CE; officially lists through 26.2, so test on 26.3 |
| VoidGen | 2.2.1 | 2.3.8 fork | Current maintained fork lists through 26.2; test on 26.3 |
| Screaming BedWars | 0.2.30 | 0.2.44 | Latest found supports through 26.2; test on 26.3 |
| ZNPCs | 4.5 | 5.3 | Latest release found; test on 26.3 |
| LifeSteal SMP Plugin | 2.3.21 | 3.1.0 | Current release; claims 1.17.1-latest but tested list is older. Requires Helix. |

## Not currently recommended as 26.3-ready

| Plugin | Current version / state | Reason |
|---|---|---|
| NetworkInterceptor | 3.4.3 | Project is End Of Life; certified only through 1.21 |
| xhomes | current Modrinth release | Compatibility metadata only lists 1.21.x and older |
| NoCheatPlus (original Spigot resource) | 3.16.0-RC-sMD5NET-b1134 | Original resource is very old and not 26.3-ready |
| Dynmap | 3.8 | Current metadata found only lists 1.21.x and older, not 26.3 |
| CraftAttack Status | 1.1.2 | Published for 1.21.x; no 26.3 declaration |
| Ultimate Mob Heads Fork Forked | 1.21.11v1 | Current published build targets Paper 1.21.11; maintainer said a newer update is coming |
| Player's Head Drop | 2025-06-22 | Very old release; page claims "latest" compatibility but it is not tested for 26.3 |
| VoidWorld | 1.0 | Could not identify a maintained authoritative 26.3 release from the old filename alone |

## Multiverse set

For your request to include all Multiverse plugins, use these five server plugins together as needed:

- Multiverse-Core 5.8.1
- Multiverse-Portals 5.3.0
- Multiverse-NetherPortals 5.1.0
- Multiverse-Inventories 5.3.6
- Multiverse-SignPortals 5.0.4

Multiverse-Core is the base dependency; the other four are optional modules.

## Proxy / VR notes

- BungeeCord is a proxy server, not a Bukkit/Spigot plugin. Keep it outside the backend server's `plugins/` collection unless you specifically want a separate proxy bundle.
- Vivecraft itself is a client-side VR mod. `Vivecraft Spigot Extensions` is the server-side plugin.

## Upgrade notes

- Back up worlds and plugin data before converting a server to 26.3.
- Minecraft 26.3 uses Java 25.
- WorldEdit's current 26.3 build is a beta, while WorldGuard 7.0.19 is stable.
- For ProtocolLib on 26.3, use the current development build rather than stable 5.4.0 because the development line contains the 26.3 packet fixes.

## cndrbrbr GitHub plugins

The following Minecraft server plugins from https://github.com/cndrbrbr are relevant to this 26.3 setup:

| Plugin | Version | 26.3 status | Release / source |
|---|---:|---|---|
| JSMN / script4kids | 1.1.0 | Tested on Spigot 26.3 / Java 25; dedicated 26.3 build | https://github.com/cndrbrbr/script4kids/releases/tag/v1.1.0-mc26.3 |
| CaveCompass | 0.10.1 | Dedicated Spigot 26.3 build | https://github.com/cndrbrbr/cavecompass/releases/tag/v0.10.1-mc26.3 |
| geomaptools | 4.37 | Runs on Spigot 26.3 / Java 25; dedicated 26.3 build | https://github.com/cndrbrbr/geomaptools/releases/tag/v4.37-mc26.3 |
| Prometheus4Spigot | 0.1.0 | Source targets Spigot API 26.3 and Java 25 | https://github.com/cndrbrbr/prometheus4spigot |

### Direct 26.3 JARs

- `jsmn-1.1.0-mc26.3.jar`  
  https://github.com/cndrbrbr/script4kids/releases/download/v1.1.0-mc26.3/jsmn-1.1.0-mc26.3.jar
- `CaveCompass-0.10.1-mc26.3.jar`  
  https://github.com/cndrbrbr/cavecompass/releases/download/v0.10.1-mc26.3/CaveCompass-0.10.1-mc26.3.jar
- `geomaptools-4.37-mc26.3.jar`  
  https://github.com/cndrbrbr/geomaptools/releases/download/v4.37-mc26.3/geomaptools-4.37-mc26.3.jar

Prometheus4Spigot currently has no matching published GitHub release JAR in the repository. Its current `pom.xml` is already configured for `spigot-api 26.3-R0.1-SNAPSHOT`, Java 25, and plugin version `0.1.0`, so it can be built from source with Maven.
