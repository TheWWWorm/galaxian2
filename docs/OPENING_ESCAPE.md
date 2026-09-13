# Opening escape sequence

The native `opening_escape.gd` owner reconstructs the choreography after the
opening pirate fight through the final radio transmission and fade request.
The standalone choreography requires v65 or newer bindings. v66 additionally
connects it to an explicitly enabled native timeline, with preceding-speed player
travel, immediate and ordinary camera passes, shared world randomness, retained
hyperdrive orientation and separate model rotation. The Opening tab automatically
enables the escape when the imported pack supplies all connected capabilities.
The session renders the original hyperdrive,
player tumble and visibility, the source sky and current-planet texture changes,
retirement of the old scenery, the original sun and lens flares with v68 bindings,
and the five-second black fade. v71 connects smoke/fire ownership, drawing and
relocation reset. v72 adds the verified single-clip music and escape effects through
native audio; v73 adds the layered damaged engine and v74 connects preceding NPC
death and breakup audio. v75 connects the preceding ordinary weapon sounds;
v76 adds all 23 source-selected radio recordings and English/German speech;
v77 supplies retained player-engine selection and playback. The HUD is hidden
during the initial shots, enabled for ordinary flight, then hidden on escape
entry. Touch flight controls follow the same gate and the user's preference;
keyboard/controller pause and timed radio remain available. Current Mac bindings
continue automatically into the [rescue](RESCUE.md), then stop at unfinished
station entry. This is not a full opening or campaign fidelity claim.

Reader v71 connects the verified smoke/fire presets and emitter defaults to the
live opening. Damaged NPCs leave trails; breakup stops new births while retaining
existing particles. The post-jump ship restoration enables the player's pair.
Relocation clears preceding particles and captures a fresh movement baseline on
the following positive update, avoiding a trail across the jump. The effects use
original textures and separate random streams and join frame rollback. Older
packs without the complete connected capabilities keep the postcombat boundary.

Reader v72 imports the original FEV event-to-bank mappings and playback settings.
The session now commits the verified music, explosion, rumble and jump cues after
the whole frame validates, with source gains, looping, positions and stop fades.
Pause reaches every active or retiring sound. v73 connects the layered arrival
engine with its continuous sample, repeating parameter windows and randomized
playlist. Older v72 audio declarations are normalized for the same native path.
v74 adds NPC destruction playlists, pre-movement positions and cached-event
restarts to the opening encounter; this capability is also used without escape.
v75 adds player and NPC firing cues with source duplicate selection and captured
launch positions. v76 matches each radio display to its edition's original voice
and preserves source language fallback and the two-voice category limit. These
sounds join the same ordered, atomic audio frame.
See [audio formats, checks and limitations](AUDIO.md).

The owner consumes the preceding radio state and the current player and camera
poses. It emits prospective changes, and supports detached frames so a failed
world or presentation update can be discarded. The composed timeline owns movement/camera scheduling when explicitly enabled;
callers retain authority over drawing, sound, pauses, fade completion and scene
transitions.

The source declarations preserve:

- Event 10 finishing as the entry gate, event 12 finishing before slowdown,
  event 13 finishing before the first pan, and event 14 **starting** before
  disturbance. Event 15 finishing starts the departure effect.
- Cruise speed multiplied by the original float32 0.98 value once per eligible
  update, including a zero-time update. Movement must use the preceding speed
  because ordinary player movement occurs before the controller.
- Original camera offsets, pans, shake ramps and strict time thresholds. An
  immediate pan refresh carries its preceding shake parameters; the ordinary
  camera pass uses the newly assigned parameters.
- The original `hyper_drive.aem` range, read from the player's selected content.
  The supplied editions contain 21 surfaces and an animation from 50 to 3000 ms.
  The shared native model clock stops only after its last key. Resetting the
  clock preserves the last sampled pose until the next animation update.
- The source camera **backward axis** for effect orientation, with world +Y as
  the up argument. Departure uses the immediate camera refresh; arrival uses
  the preceding renderer view. This is not an eye-position look-at operation.
- Player visibility changes, position/heading reset, separate ship-model tumble,
  the original sky/planet resource substitutions and restored cruise speed.
  Ship restoration keeps input blocked and the ordinary HUD hidden.
- Later camera cuts, final radio completion and the source five-second fade
  request. A completed external fade exposes `arrival_transition_required`.
  The owner never completes a mission or grants a reward.

The importer recognizes each executable architecture independently and emits
only declarations and provenance offsets. Missing or changed source spans disable
this capability. Legacy packs keep their existing behavior.

For native integration, call `configure_escape(bindings, library)` on a freshly
configured `opening_detail_timeline.gd`, before its first frame. Its corresponding
`opening_world_frame.gd` must have connected player flight and weapons. This path
retains the encounter's three actor owners and requires their earned radio and
zero hulls before later phases. Camera shake consumes three bounded random values
per positive-strength pass, in axis order. A pan refresh precedes the ordinary
positive-time pass; a zero-time ordinary frame retains the previous view. NPCs
then receive the camera's resulting stream, followed by scenery.

The timeline's `escape` snapshot exposes pending audio, environment and fade cues,
`model_rotation`, `effect_pose`, camera state and the explicit arrival boundary.
`fade_active` remains an external input for standalone world owners; an absent
fade does not complete itself. Legacy timelines keep their existing postcombat
boundary.

For contributor graphics checks, the final `with_escape` argument to
`opening_session.gd.configure()` enables the connected escape presentation, with
player controls also enabled. This is an explicit development path: the normal
Opening tab does not select it. The session draws the original 21-surface
hyperdrive through the shared additive renderer. Stopping or resetting playback
retains the last sampled surfaces. Visual ship rotation composes beneath the
logical player pose, including its body, lights and selected detail level.

With v67 planet declarations, the session also draws the five fresh opening
planets. Relocation changes the current planet's original texture. Its visible
size follows the source draw pass's constructor baseline plus a clamped camera-Z
adjustment, which overwrites the controller's earlier one-time doubling. The
other planet planes retain their constructor poses. With v68 bindings, the sun
planes and screen flares preserve their frame ordering through escape and
rollback. Legacy sessions remain usable without these additional capabilities.

The session advances the native fade before evaluating the mission frame, then
applies a new fade request afterward. Its first frame has zero alpha. Alpha uses
the original byte truncation; 5000 ms remains active and opaque, while 5001 ms
completes it. Arrival retains a black plate and stops at
`arrival_transition_required`. With v88 Mac bindings the application prepares and
replaces that scene with the rescue. Older packs retain the boundary message.
The overlay covers the game viewport. Failed presentation frames roll
back the fade together with the world owners. Pauses freeze both.

Run the focused native check with matching imported content, bindings and visuals:

```sh
godot --headless --path game --script res://tests/opening_escape.gd -- CONTENT BINDINGS VISUALS
godot --headless --path game --script res://tests/opening_escape_camera.gd -- CONTENT BINDINGS VISUALS
godot --headless --path game --script res://tests/opening_escape_world.gd -- CONTENT BINDINGS VISUALS
godot --headless --path game --script res://tests/opening_escape_presentation.gd -- CONTENT BINDINGS VISUALS
```

The tests cover all sequence stages, strict boundaries, mixed started/finished
radio gates, effect restart sampling, independent model rotation, rollback and
rejection of foreign/regressed inputs. A composed scheduling fixture uses the
original text layout and radio scheduler in every supplied language. Defeated
hulls are explicit test inputs; that fixture is not evidence of a live earned
encounter or original-runtime parity. The v66 world test separately uses
controlled launch positions to deplete the full original NPC hulls through native
projectile contacts. Both editions then complete all 23 English transmissions,
movement/camera/effect-state progression and an explicitly supplied external fade
completion. This establishes native integration, not pilot playtesting, rendered
escape fidelity or original-runtime parity. Late radio failures preserve all
retained owners and random state.

The session presentation test also depletes the full NPC hulls through controlled
contacts, progresses through all English transmissions, checks original model
visibility and independent Euler composition, and completes the connected fade.
It tests pause, exact fade boundaries, foreign-owner rejection and a failed final
animation surface without committing a partial frame. Run it with a graphics
driver and `--captures=OUTPUT_DIRECTORY` before the content arguments to save
departure, arrival and fade images. These images include the destination sky,
current planet texture and removal of the old scenery. The test also rejects a
later scenery presentation during relocation and verifies the preceding planet,
sky, sun intensity, camera and world state are restored. Particle reset remains
unfinished.

During relocation the sky owner switches the nebula mesh and texture; the
original stars and sky orientation remain. Both backgrounds are prepared during
loading so an unsupported destination resource fails before the opening runs.
The world retires its original scenery actors and immediately deactivates their
statistics, which also removes them from ordinary weapon collision eligibility.
It preserves membership, hulls, contact history, earned cargo, counters and RNG.
This is scripted removal, without destruction or drop rewards. The following
positive update disables their updaters; zero-time relocation does not fabricate
that later update. Intact/effect drawing stops, while existing cargo is retained.

`tests/opening_escape_environment.gd` covers these lifecycle, collision, identity,
rollback and sky-selection rules. The complete session test also checks relocation
through the original radio/encounter path on both editions.
