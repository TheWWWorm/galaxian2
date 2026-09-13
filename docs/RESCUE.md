# Opening rescue

With current Mac Full HD bindings, **Opening → Run opening scene** now runs the
opening, its first fight and escape, then automatically enters the rescue near
Var Hastra. Gunant Breh approaches the tumbling player ship, speaks three original
transmissions, and the scene fades into the first station with current Mac bindings.
This is part of the developing campaign, not campaign completion.

Esc or controller Start pauses the rescue. Focus loss and leaving the tab also
pause it, independently of the user's pause. Flight controls and the flight HUD
remain hidden during this cinematic. Stop or changing content, bindings, language
or textures disposes the scene. Loading consumes no simulation time.

Re-prepare older Mac bindings to obtain the `arrival_session` capability from
reader v88. Older packs retain their earlier boundary. Existing iOS components
remain available; further iOS integration and validation are deferred while
development focuses on the Mac game.

Reader v89 lets the completed rescue prepare a checked packet for the native
[first station](STATION_ENTRY.md). Reader v90 adds its screen and automatic entry.
Older packs hold the final black frame when that capability is absent.

## Scene ownership

The completed Opening prepares the restored player cache and retained kill
totals. Rescue entry recalculates rank, checks the ordinary location and empty
companion group, and establishes the neutral actor from the supported Opening's
bounded reputation outcomes. The new scene validates this packet before replacing
the old world. A preparation failure retains the completed Opening and its black
plate, camera and audio listener.

The shared world constructor builds the station's asteroid field and one authored
NPC, preserving the ordered construction RNG. The NPC target list contains only
the restored player. The player body and statistics stay at the origin while the
model rotates; ordinary flight, shield recharge and repair do not advance during
the cinematic. The controller moves the approaching NPC before its statistics and
mode-five target checks. That activation does not run ordinary pursuit or firing
in the same update. Ship and scenery detail selection reuse the shared owners.

The radio uses a scene-controller clock initialized to zero on entry. It does
not use the campaign's accumulated play-time clock. The first event becomes
eligible at 10,000 ms; source wrapping supplies the display duration. Radio runs
after the controller, so the final finished flag requests the exit fade on the
following frame. The fade ends strictly after 5,000 ms, then the boundary retains
a black plate. There is no automatic reward, save write or earned completion.

Presentation reuses the existing ship, sky, planet, sun, lighting, scenery,
portrait, radio and audio components. Prospective frames are checked before
committing sound playback. Pauses discard wall-clock gaps. Repainting a frame
does not repeat speech. Scene replacement transfers listener restoration before
disposing the previous audio owner.

## Verification and limits

Mac checks cover source-layout changes, pack dependencies, restored state and
target decisions, complete rescue timing, pause combinations, failed-frame retry,
one-time voice events, and the full Opening application transition. GPU captures
cover all three transmissions and the final black plate. They use native OpenGL
rendering with Dummy audio; these captures are not a new audible-output or
original-runtime comparison.

Station launch, subsequent missions, persistent campaign state and
exact reputation remain unfinished. The rescue actor's general combat-stat and
mounted-weapon owners, automatic material/reflection settings, cross-scene music
ownership and persistent campaign play-time also need further work. The supported frozen cinematic does
not establish those features. Trading, exploration, side missions, expansions,
saves and platform delivery remain in the development scope.
