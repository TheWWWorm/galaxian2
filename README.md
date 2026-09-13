# Galaxy on Fire 2 remake

An independently designed native Godot replacement engine, importing original
content locally from a player's iOS HD or Mac Full HD copy. This is an early
engine: it renders imported assets, displays original ship base properties and
opens/searches original localization.
Development and current validation focus on Mac Full HD content until that game
is complete. Existing iOS support is preserved; further iOS parity work is deferred.
Source-backed cruise, manual rotation and elapsed-time pilot response are checked
headlessly, including ship handling, handling upgrades and maneuverability devices.
A native flight driver now connects input events, frame timing and explicit pause
owners to that motion. The opening ship, station and equipment loadout are now
read from each supplied edition and assembled with native slot checks. Opening
radio declarations now feed a native scheduler with separate started/finished
flags and verified condition types. Native bitmap metrics, imported character
aliases and text wrapping now derive radio timing. Source font records select
language-specific groups, atlas variants and spacing for an explicit display mode.
The Radio inspector tab now plays the pre-combat opening transmissions through a
native text panel with original localized speaker names and independent compact
desktop and larger phone layouts.
The **Opening** tab runs the recovered scene, first fight and escape. With
current Mac bindings, it continues through the rescue near Var Hastra and into
the first station's original hangar, starter ship and acknowledged conversation.
The station displays the original portraits and all 19 lines, with 18 source
recordings. Enter/Right or controller A advances; Left or controller B returns to
the preceding line. Pause, focus and tab visibility retain scene and speech state.
After the first conversation, choose **Depart** and confirm to fly the starter
ship, acquire an asteroid, mine it and return to Var Hastra. The first mining
trip now runs in the application with original scenery, briefing and return
portraits/text/speech. Steer with WASD/arrows or the left stick; E/controller X
starts or stops mining, and P/controller Y selects or cancels station autopilot.
Esc/controller Start pauses. Flight action buttons follow **Touch controls** and
are hidden by default on desktop. Modal instructions wait for acknowledgement.

Docking preserves earned cargo and current ship vitals. Five original station
lines precede the cargo reset and next full-hold objective. Current Mac packs
then offer the second departure, with its original briefing, mining, pirate
appearance and combat, warnings and six-line station return. The hangar then
offers the source-defined starter weapons and armor at their zero tutorial price.
Acquire and mount a weapon and armor plate to reach Gunant's acknowledged
completion line. Equipment stays owned, and the application stops before the
unfinished combat-training flight. See [starter equipment](docs/EQUIPMENT.md).
If the starter ship is destroyed on the second mining trip, its original effects,
sounds and game-over prompt lead back to the remake launcher after acknowledgement.
The full original menu and its music, later campaign, general station services, saves,
collision response, animated station lights/wormhole and ordinary flight
engine/mining/acquisition sounds remain unfinished.
See [mining development status](docs/MINING.md).
See [first station scope](docs/STATION_ENTRY.md).
Older packs retain their earlier supported boundary; re-prepare Mac bindings for
the current sequence. The rescue preserves the opening's normal ship cache and
earned kill totals, recalculates rank, and builds the source-defined destination.
Its player remains frozen during the cinematic. Scene changes validate before
replacing the preceding world; failed preparation retains the completed scene.
No persistent save is written. See [rescue support](docs/RESCUE.md) for its limits.
The opening's asteroid field owns source-bound collision bodies and vitals. The initial
NPC/asteroid target inventory and combined ordinary-weapon contact pass are
verified, with ordinary asteroid destruction and retained junk integrated. Native
opening enemy components now retain holding-state clocks and connect ordered
target decisions, speed boosts, firing and steering. Source-generated looping
patrol routes now retain their waypoint progress across player acquisition.
Fresh NPC construction now consumes shared spawn, route, discarded cargo and
breakup-fragment draws in order for all three opening actors. Fresh world setup
then preserves default and assigned weapon-effect draws and hands the resulting
RNG state to the opening session before its first frame. The session now advances
player motion, weapons, cinematic logic/camera, NPCs, scenery and radio in the recovered order.
NPC clocks, route state and flight poses persist through the first player-follow
handoff; new shots remain unadvanced until the following weapon pass. Current
bindings also initialize the player's source shield, equipment armor, hull and
damage permission, retaining that state across opening frames. Native ordinary
NPC contact components now apply source-scaled player damage and ordered per-gun
cleanup with atomic rollback. Opening frames now move the player along its current
heading, then run those contacts against the moved pose and retained NPC hostility
before updating the enemies. Scripted formation placement happens afterward, and
the camera follows the resulting pose. Cinematic travel ends after the first
player-follow handoff frame; supported ordinary flight takes over afterward.
The optional v59 native world owner now carries ordinary steering and player
primaries through the first fight. Contacts run before the camera; firing and
steering input follow it, preserving next-frame shot and movement timing. Native
fixtures verify kills, death accounting and the following two radio events with
frame-wide rollback. v60 bindings also connect the original travelling
projectile models, shared weapon animation clocks, flight/camera orientation and
final-second shrinkage. Both editions pass independent GPU model checks. The
v61 bindings add the original player and NPC impact flashes, per-slot one-shot
clocks and retained hit positions. Both editions pass native contact/rollback
checks and GPU captures. The Opening tab now joins player flight automatically
when current bindings provide the required capabilities. Steer with WASD, arrows
or the controller left stick; fire both equipped primaries with Space or the right
trigger. Esc or controller Start pauses. Touch controls enable a steering pad,
Fire and Pause; these actions default hidden on desktop. Focus loss, pausing and
leaving the tab clear held input. The original center targeting frame appears
during ordinary flight, using each edition's atlas mapping and the compact
desktop layout. Current bindings also provide ordinary opening NPC markers,
source hull bars and timed target acquisition with the original scan animation.
Acquisition audio/notifications and the target information panel remain unfinished.
After the first fight, current bindings continue into the escape. The combat HUD
and touch flight controls disappear while timed radio and keyboard/controller
pause remain available. Older packs retain their cinematic or postcombat boundary.
The equipped shield now recharges before those contacts, with source pulse timing,
binary32 precision and frame rollback. Current bindings also recover the fresh
maximum hull and both repair-device timings. Native hull/armor repair runs before
contacts when a device is equipped; the authentic opening loadout has none.
Current bindings add native enemy tumble, explosion clocks and cargo-free
retirement. The ordered NPC controller preserves selection draws before death,
retains constructor fragments and returns sound events without awarding progress.
The opening scene now presents source explosion models, the later alpha pass,
additive flash/debris, independent fragment transforms and timed body hiding.
Current bindings also retain lethal-hit attribution and record verified player,
pirate and world counter changes once when each hostile opening death begins.
Those changes commit with the world frame. Save counter baselines, achievement
and mission consumers, other particle effects, sound playback, camera shake, player hit
feedback, mining, later encounters and mission progression remain unfinished.
See [combat scope](docs/COMBAT.md).
With v71 bindings, damaged opening NPCs now emit the original smoke and fire
sprites. Trails stop at breakup and existing particles fade out. The escape
also enables the player's authored damage effects after the jump and clears old
particles during relocation. Both editions retain their own source settings.
With v76 bindings, the Opening session plays all source-selected radio recordings
in English or German; German text selects German speech, and other text languages
use English speech. Voices start when their delayed text appears.
With v75 and newer bindings, ordinary opening guns play their original sounds on successful
launches, preserving duplicate selection, equipment pitch and launch positions.
Opening NPC deaths and breakups play their original randomized
samples at the captured ship positions. The escape also plays its music, explosion,
rumble and jump sounds through native Godot audio. Original FEV declarations
select each edition's own FSB5 samples. The layered damaged engine retains its
continuous loop and repeating randomized bursts. Older v72 audio packs remain
compatible; death playback requires v74's additional source declarations.
With v77 bindings, the Opening also plays its retained player engine. Its starting
loadout selects the source clip, and preceding steering inputs drive the original
pitch, volume and stereo-spread envelopes. The engine follows the player through
cinematics and its source-defined damaged-engine replacement. Special/NPC engine
layouts, special weapons and dialogue beyond the recovered rescue remain unfinished; see
[Audio](docs/AUDIO.md#player-engine-calculations) for playback scope and mixer limits.
See [audio support and checks](docs/AUDIO.md).
Current bindings also resolve 152 authored portrait texture IDs and their explicit
resolution variants. Native composition uses source layer positions and draw order.
Fixed portrait definitions are imported separately from procedural and unavailable
appearances. Image aliases and native cropping now preserve original atlas regions
and alpha. The Radio preview displays available baseline portraits; unsupported
appearances remain absent with diagnostics. Original panel geometry/frame art
and procedural portraits remain unfinished. The standalone Radio inspector is
text-only; spoken playback belongs to the Opening session.
Opening actor declarations now initialize the three source hulls and current-hull
overrides in native state. Initial player placement and the first three-ship
formation now follow source declarations and the radio completion gate. Imported
camera declarations now drive native fixed-eye views, target cuts and pans through
the first player-follow handoff. A native camera rig now supports ordinary follow
with imported target-relative offsets and separate eye/look response curves. Full
special-time/paused scheduling, remaining cinematic phases and actor behavior remain
unfinished. The opening view owner now preserves formation translation, immediate
pan refreshes and the subsequent ordinary follow update. Source-bound actor drift
now runs before camera evaluation, skips the formation reveal frame and stops
after the source phase boundary. Elapsed simulation time remains an explicit
input to the lower-level motion component. A fresh opening timeline now owns
source-seeded elapsed time, advances it before scene work and freezes the whole
sequence under an explicit pause state. Save/resume, special-time transitions and
AI outside the supported opening remain unfinished.
A native opening sequence now updates actors/camera before radio presentation.
New radio completions affect the next scene update, and radio conditions see the
current cinematic phase. Failed frames preserve both states; source combat gates
remain blocked while their required behavior is unsupported.
Imported flight projection now drives native Camera3D presentation with vertical
FOV, clip planes and viewport aspect handling. Far-plane selection requires an
explicit verified location-match result; the world/save owner is still unfinished.
The opening background now assembles the original star and nebula layers with
source station-seeded rotation, explicit layer ordering and camera-relative
projection. Both editions pass GPU composition/depth checks through the recovered
pre-combat views. Source lighting and the remaining location geometry/effects
are unfinished; see [environment scope](docs/ENVIRONMENTS.md).
The main scene opens the asset inspector; its Opening tab includes the recovered
first fight. Complete authored scenes, mission progression, commerce and the
remaining sound owners are unfinished. See [motion scope and checks](docs/MOTION.md)
and [text layout scope](docs/TEXT_LAYOUT.md).

Either edition works independently. The engine includes no original game content
and never runs the original executable. The iOS and Mac catalogues and language
indices remain separate; supplying a second edition does not merge their data.

## Try the desktop foundation

Requirements: Python 3.10+ and Godot 4.4+ (verified here with Python 3.12 and Godot
4.7 on Linux). The importer currently runs from the command line. It uses only the
Python standard library. The Godot runtime does not depend on Python.

From the repository root, choose one source:

```bash
python3 tools/import_content.py import "/path/to/game.ipa" --cache "/path/to/private/gof2-content"
python3 tools/import_content.py import "/path/to/Game.app" --cache "/path/to/private/gof2-content"
python3 tools/import_content.py import "/path/to/app.zip" --cache "/path/to/private/gof2-content"
```

The command reports an installed directory ending in a content identity. Launch:

```bash
godot --path game -- --content "/path/to/private/gof2-content/CONTENT_ID"
```

Or launch `game/project.godot` in Godot and use **Open imported content** to select
that directory's `manifest.json`. Choose a language and search the original rows.
Row numbers are edition-specific and are not verified gameplay bindings.
The Assets tab can inspect original mesh geometry immediately; decoded texture
derivatives enable textured models and atlas inspection.
The World tab searches original system/station names and follows the catalogue's
system links. It exposes the verified world relationships; campaign availability
and travel rules remain to be implemented.
With v15 or later resource bindings open, choose **Radio → Play opening radio** to preview
the opening transmissions in the selected localization language. **Pause preview**,
**Stop** and **Phone layout** affect only this inspector. Switching tabs pauses
the preview; changing content, language or bindings stops it. The preview stops
when the missing combat encounter is required and never completes a mission.
You can open this tab and start playback with `--radio-preview` alongside
`--content` and `--bindings`. Its fixed baseline timing fixture and remaining
presentation limitations are documented in [text layout](docs/TEXT_LAYOUT.md).
With current bindings and prepared textures open, choose **Opening → Run opening
scene** for the combined scene. **Esc** or controller **Start** toggles pause;
the on-screen Pause action follows **Touch controls**, which defaults off on desktop.
Focus loss and leaving the tab pause independently. **Stop** or a change of content,
language, bindings or prepared textures clears the scene. With current bindings,
the Mac sequence continues through the rescue and stops at unfinished station
entry, without completing a mission or granting rewards. Launch it
directly with `--opening-preview` alongside `--content`, `--bindings` and `--visuals`.
The scene currently uses the established PBR presentation; the new forward material
still requires automatic source settings selection. See [environments](docs/ENVIRONMENTS.md)
for rendering and timing verification limits.
With prepared textures and current resource bindings open, double-click a station
to inspect its source-selected hangar geometry. You can also enter a **Station ID**
in Assets or pass `--station-id ID`. Root layers and extra geometry are assembled
from the chosen edition's declarations. Current v5 bindings also place a hull at
its source-defined hangar height. While a hangar is open, **Ship catalogue ID**
changes that hull; **Frame hull** centers it. `--station-id ID --ship-id ID` selects
both from the command line. Hull 0 is the inspector's initial selection, not a
starting loadout or player-owned ship. Full ship assembly, original lighting,
cameras and animation behavior are not yet reproduced. v6 bindings add the
source-declared ship light meshes as hull-local layers. Unresolved required light
references produce a diagnostic; no replacement light mesh is guessed.

## Prepare original textures

Use an isolated Python environment for the optional CPU decoder:

```bash
python3 -m venv /path/to/gof2-import-env
/path/to/gof2-import-env/bin/python -m pip install -r tools/requirements-visuals.txt
/path/to/gof2-import-env/bin/python tools/prepare_visuals.py "/path/to/content/CONTENT_ID" --output "/path/to/private/gof2-visuals"
```

On Windows, use the environment's `Scripts/python.exe`. Preparation writes a
separate derivative directory, reports its path, and leaves base content intact.
Open its `visuals.json` with **Open prepared textures**, or launch with
`--visuals "/path/to/visuals/PACK_ID"` after the content argument. Both editions
work independently. Derivatives can occupy several additional GB; compressed
mip levels and original atlas metadata are retained. No Python library is needed
by the Godot runtime after preparation.

In Assets, filter filenames, select a mesh or texture, drag to orbit and scroll to
zoom. Scrub **Source time** to inspect animation data; **Frame pose** recenters a
moved model. Without prepared resource bindings, filename-matched materials are
provisional. Prepared bindings supply source material/texture references for
supported meshes; diffuse/normal-specular, opaque, alpha and additive material
families are rendered.
Other material modes report their unsupported status. Lighting and animation
presentation remain provisional.
This screen does not claim a verified ship/location pairing or original timing.

Optional [resource declaration preparation](docs/RESOURCE_BINDINGS.md) enables
numeric resource ID inspection and source material lookup. It reads declarations statically from the chosen
edition's executable and exports data only, including supported hangar geometry
selection. It does not execute original game code.

New binding packs also support **Ship catalogue ID** lookup (`--ship-id ID`). Mac
materials can select verified high/low texture variants in Assets. These controls
inspect recorded resources; complete ship assembly and gameplay remain unfinished.

Imports need approximately 1.3 GB for iOS or 2.7 GB for Mac, plus space for staging
another import. Content remains outside the engine repository. Ctrl+C cancels an
import and removes its staging directory; previously activated caches remain
unchanged. Imports into the same cache root are serialized by a lock.

Direct DMG ingestion is not implemented. Extract the `.app` with an appropriate
archive tool or ZIP the extracted app. The original app does not need to run.
Bundle names and archive names may differ. The importer recognizes the bundle
identity, layout, known resource envelopes and edition-specific table sizes.
Unrecognized layouts fail with diagnostics. This does not certify arbitrary
versions with matching headers as fully playable.

A forced process kill or power loss can leave `.import-lock` and `.stage-*`
directories. After confirming no importer is running, remove only those abandoned
entries and retry. Activated identity directories are never overwritten. A corrupt
existing cache produces an error; choose a new cache root or move the damaged
identity directory aside before reimporting.

## Validation and source packaging

```bash
python3 -m unittest discover -s tests -v
python3 tools/import_content.py verify "/path/to/content/CONTENT_ID"
godot --headless --path game --script res://tests/asset_readers.gd
godot --headless --path game --script res://tests/content_library.gd -- "/path/to/content/CONTENT_ID"
godot --headless --path game --script res://tests/catalogues.gd -- "/path/to/content/CONTENT_ID"
python3 tools/package_source.py "/path/outside/repository/gof2-source.zip"
```

Public tests create synthetic fixtures; no original content is included. Source
packaging uses an explicit file allowlist. Never package imported caches, saves,
original archives or executable files. No public release or hosting is configured.

See [support status](docs/SUPPORT.md), [combat implementation scope](docs/COMBAT.md)
and [architecture](ARCHITECTURE.md).
