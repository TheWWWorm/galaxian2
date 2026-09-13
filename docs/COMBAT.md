# Combat implementation

The application connects native Opening combat and the subsequent rescue and
first two mining trips with current Mac packs. The shared pool calculator is
`game/src/simulation/combat_vitals.gd`; later encounters require verified contexts.

Mac reader v119 prepares the combat-training player from the actual installed
tutorial equipment and resets the departure pools through the shared cache rules.
`OpeningPlayerState.configure_combat_training` requires that native equipment
owner. Its detached `loadout()` configures the existing primary weapon owner;
no inventory is granted or replaced during flight preparation.

The training NPC weapon owner uses three pirate guns and Gunant's authored gun.
All four use damage 3, a strict interval greater than 586 ms, four slots, a
3,000 ms lifetime and speed 16 source units per millisecond. Gunant's runtime
weapon kind differs from the catalogue kind of his visual item. NPC sound
selection remains per actor. `fire_combat_training` accepts the control owner's
retained firing requests so both shots and sound positions precede movement.

`evaluate_combat_training_update` stages player contacts first, then each gun's
NPC membership, before that gun moves or clears projectiles. Impact geometry is
retained for overlapping targets. NPC damage records nonplayer attribution only
on a lethal hit. Neither contacts nor pool exhaustion grant mission completion,
rewards or loot. Commit all returned owners together; the older player-only
update refuses this encounter because it would omit NPC contacts.

The equipped item-22 primary uses 25 slots and one projectile per successful
launch. Its declared spread consumes three bounded draws from the explicitly
supplied shared random state, before direction normalization. Pass that state to
`PrimaryWeapons.fire` and retain the returned state for later world work. Rejected
permission, interval and capacity consume no draws. Authored mounts replace the
constructor muzzle offset, and primary fire does not consume equipment quantity.

Mac reader v120 connects all four training ships to the shared cargo destruction
owner. Prepare `NpcDestructionResources.configure_combat_training`, then attach
them with `CombatTrainingControl.set_destruction` before the first actor update.
Generated cargo and fragments are retained; Gunant uses the Midorian container
and the pirates use the Nivelian container. First lethal updates record kill
attribution once; Gunant reduces the nonhostile population without pirate credit.
His finite hull can reach zero even before his first normal flight update.

The controller accepts an explicit shared random state after projectile firing.
First lethal updates resolve target and patrol state before entering destruction;
continued tumble/explosion modes skip those updates and their random draws.
Hull and statistics transforms, per-update cargo drift and strict cleanup use
the shared destruction rules. `defeat_status()` reports condition 18 over pirates
0..2 in explosion mode 4, independently of later retirement. That predicate does
not advance campaign progress or award rewards.

Mac reader v121 adds the training projectile and impact mappings to the shared
effect owners. The starter and upgraded player bolts are static meshes; Gunant's
authored projectile uses its own looping model. Player shots retain the firing
ship's up axis. Each slot keeps an independent impact clock, including ordered
NPC-to-NPC contacts and retained sampling on a repeated hit. Effect setup does not
repeat the NPC constructor's random draws or advance the post-scenery stream.

These components are checked on detached encounters, including independent GPU
captures of all six distinct models. The shared encounter stages primary hits
against all four NPCs and 130 source asteroids, then the NPC weapon contacts.
Late player fire passes its random state into NPC movement and destruction;
new shots first contact in the following weapon pass. Failed stages preserve
the accepted encounter, player and scenery together. The complete flight frame
and session, player death, scene/audio integration, story and return are still
required before the combat-training flight becomes playable.

Mac reader v107 adds detached combat preparation for the second mining pirate.
The existing actor/group and weapon owners accept its constructed world, retain
earned rank, and use its factory hull and one-damage primary. The second-trip
player accepts those shots through the ordinary contact path. Source firing
interval is strictly greater than 592 ms, with four slots and a 3,000 ms lifetime.
Reader v108 connects the pirate to the shared guidance and flight controller.
Holding still advances target timers and consumes source random draws. An early
strict 25,000-unit player proximity test activates before mode dispatch; a later
strict 50,000-unit target test activates for the next update. Player suppression
affects the latter test. The separate alternate-body position, when present,
feeds both tests and the immediate steering vector; firing range keeps the
ordinary player statistics position. The controller preserves that distinction.
Model submission requests are retained separately from actor visibility.

Second-trip control takes the same explicit player state as Opening guidance,
plus `ship_id` and `alternate_position` (null for the ordinary player body, or a
finite source-space position). This is separate from the existing special-flight
flag. The world owner must supply these values and advance projectile clocks
before the actor pass. Prepare second-trip destruction resources with
`NpcDestructionResources.configure_full_hold`, then call the configured NPC
controller's `set_full_hold_destruction` before its first update. It consumes the
cargo and fragments retained when that controller was configured. Missing or
mismatched resources reject the entire candidate death pass.

Reader v109 extends the shared death owner with the kind-8 pirate's original
container model. Cargo appears at the hull's post-tumble position with a fresh
identity orientation. Its drift advances once per positive update and decays by
0.98; elapsed milliseconds control lifetime. Cleanup requires more than 60,000 ms
and an inactive explosion. An empty hold still retires on the update after the
explosion ends. Explosion clocks stop when inactive, and generated item records
remain separate from player inventory. Hull and statistics transforms preserve
the source's distinct update order. The original integer angle conversion yields
zero cargo rotation for all supported frame durations.

Kill attribution is recorded at death entry in the shared accounting owner. This
produces counter deltas, not mission completion or an automatic inventory transfer.
Native tests cover source-generated cargo and an empty-cargo seed, both kill
sources, strict boundaries, independent drift/RNG values and failed-frame
preservation. Cargo collection and tractor targeting remain unfinished. The
second-trip native world and renderer now connect the retained pirate, container,
weapons and original effects. Reader v112 connects the second station return,
including current pools after weapon contacts and a hold before later NPC work.
Current v115 Mac packs now offer the second departure through the application's
shared mining session, with accepted audio, return and game-over transactions.

Mac reader v113 adds a detached starter-player destruction component. It reuses
the NPC explosion's authored animation clocks and renderer, with two models and
no debris fragments. The player does not invoke the NPC fragment constructor.
Death starts in the mission poll after lethal contact; later player updates add
0.03 radians to each model Euler component per visit, including zero-time visits.
The physical root, visible model matrix, stored Euler angles and statistics
sample remain separate. Banking writes the visible matrix without changing the
stored angles, so the first death spin can replace a preceding visual bank.
The body disappears at 3,000 ms, when the explosion and its one sound-selection
draw start. Animation advances only with a preceding death time greater than
3,000 ms; equality retains the source's one-update gap. The effect resets strictly
after its 4,500 ms authored lifetime. Failure starts strictly after 8,000 ms,
followed by a delay greater than 3,000 ms and a 4,000 ms fade before exit input.

`PlayerDestruction.configure` requires the prepared second departure, matching
effect resources and unchanged starter equipment. `start` accepts an exhausted
player, current physical pose, retained model Euler angles, camera pose and story
cursor 4 or 5. Supply the optional current visual basis and statistics pose
together when flight has banked or sampled them separately. Call `advance` on
following player passes with the already computed physical pose and shared random
state. Manual motion samples the preceding visual basis by default; guided or
mining motion supplies its own optional `statistics_pose`.
That pose may retain a preceding position. The death tail then advances stored
Euler angles and rebuilds the visual basis without resampling statistics. All
player poses stop after the fade, and rejected inputs preserve accepted state.
Pass `player_tail=false` when an invalid mining target skips that tail; physical
and statistics poses must then remain unchanged, while the later failure poll
still runs. `sample_camera` records the following camera pass and its actual
follow flag, including mining release after death's one-time disable.
Its events preserve sound stops, the
breakup sound, failure sound and ordered particle flag requests; the component
does not play them or simulate physical movement.
After the fade, `request_exit` returns a source-state request once, without
granting progress, healing the player, loading a save or changing cargo.

The second-trip flight frame now starts death after actual projectile contact.
It preserves retained steering/throttle, existing station guidance and drilling,
skips new axis input on the lethal frame, and resumes camera follow when mining
ends. A destroyed mining target returns before the death tail while later world
phases continue. After the fade the world still updates, while player motion
stops. `request_game_over_exit` stages a detached source-state-1 packet; it neither
delivers cargo nor changes earned progress. Packs without death declarations
retain `player_death_required`.

The shared flight scene presents the original body, two-model explosion and
game-over panel, hides ordinary HUD during death, and restores its previous
accepted display if preparation fails. `present` accepts an absolute millisecond
clock for blinking. Native and GPU tests cover motion/mining/camera transitions,
late rejection, fade, retained cargo and original location rendering. Captures
use positioned lethal shots and disclosed close mining placements. The shared
session now connects that presentation and audio to the application. It accepts
continuation only after the fade and commits the native exit on the following
application pass, outside the panel's input callback.

The source state-1 registration resolves to the main menu. Its preceding music
selector 2 chooses event 145; it is a separate operation from the game-state
transition. The remake currently returns to its existing launcher, retaining a
detached diagnostic result and releasing the flight scene, sounds and listener.
The full original menu and music event 145 remain pending. No automatic restart,
save/load, healing, cargo transfer or mission advancement is performed. Failed
exit validation keeps the accepted flight paused and offers a native retry.

The shared `OpeningAudio` player now accepts the native second-trip frame through
`configure_full_hold` and `prepare_full_hold`. It prepares the original pirate
laser, pirate death and breakup, player breakup and nonspatial game-over events.
The frame records separate player-tail, player-poll and late NPC cues. Its sound
serial advances only when those native passes run; action-only, paused and
repeated frames cannot replay retained cues. Failed preparation leaves playback,
sample-selection randomness and the accepted native world unchanged.

Player death first stops the cached current music and current engine events,
then the eight declared equipment events. The current-music request was previously
mislabeled as a primary sound stop. The statistics-active setter issues no sound
request. Stops preserve the existing source fades, and unused equipment stops
do not require loading or approximating their unsupported playback programs.
Player breakup uses its physical explosion position; the particle burst can use
a different retained statistics position during mining.

Native tests cover the actual one-pirate population, firing position, both death
paths, cue order, late rejection, older Mac packs and repeated acknowledgements.
Two dummy-driver mixer captures contain audible samples and silent paused tails;
they are mixed native fixtures, not isolated source recordings or a hardware
listening test. The shared flight session now prepares audio before presentation
and commits it after the scene succeeds; pause/focus/hidden and failed transitions
freeze playback. It registers the audio owner before the first world update and
retains its serial through modal visits and action-only frames. Ordinary flight
engine, mining,
acquisition and music ownership remain separate work.

Reader v114 adds `GameOverPanel`, using original image 1313 from interface-atlas
region 211. The panel accepts the matching `PlayerDestruction` owner (including
its detached frame forks), reads its fade/readiness, and displays the centered
art followed by the original blinking continuation prompt. The shared desktop
text mapping selects 189 from source text 188; all twelve Mac languages are
checked. The desktop composition is half the phone artwork size, with crisp
native text. The blink uses the source float32 sine factor and an absolute
millisecond clock supplied by the caller; drawing never advances simulation.

Configure the panel with the active library, bindings, visuals and destruction
owner, then call `present` with the current frame owner and presentation time.
Continuation emits an intent through Enter, Space, controller A, the existing
fire trigger, a click or touch. It is disabled until the full fade and while the
panel is inactive or hidden. A held fire trigger crossing the fade must be
released before acknowledging. The application must prepare and commit the exit;
the panel does not select a menu, retry, load a save or grant progress. Failed
resource/frame preparation preserves the accepted display. Tests include real
viewport event dispatch, a legacy pack refusal and inspected desktop/Japanese
phone component captures over disclosed neutral scenery.

Mac reader v115 adds the second-trip sprite declarations. The player and pirate
each use preset 9 on the general additive material (texture 11601); only the
pirate also registers smoke 15 and fire 42. Player smoke/fire registration is
limited to opening cursors 0–1. The shared world burst uses preset 11 and creates
one particle at the player's retained statistics position before death spin.
These declarations require the matching departure, starter death and shared
emitter context. Missing declarations remain unsupported in older packs.

`DamageParticleEmitter.configure_full_hold` selects preset 9 or 11 from those
bindings with an explicit independent seed. The existing continuous-emission,
movement, appearance and slot-ring implementation handles the trail. Preset 11
uses `emit_once(position)`: one stationary sprite, the declared size plus jitter,
three private size draws, and an inclusive 1,500 ms lifetime. Its manual flag
blocks automatic births despite an inherited 500/s field. A direct request
ignores emission and visibility flags, while visibility changes still reset
existing slots. Paused manager updates and rejected requests preserve state.

`FullHoldParticles` connects these declarations to the live second-trip frame.
It reuses the opening's smoke/fire owner for the actual one-pirate population,
with a player trail, pirate trail and world burst on the general manager. Each
emitter has its own random stream seeded from the construction's Unix second.
General particles update before smoke and fire. Player breakup resets the trail
and emits the burst before those managers; the later death poll enables emission
without restoring drawing. Subsequent NPC work updates flags and the retained
unbanked root for the next frame. Pirate breakup stops new births while its
existing trail particles finish aging.

The shared sprite renderer handles all five emitters with original textures,
current slot appearance and the accepted camera. Drawing does not advance them.
Frame and scene preparation reject mismatched owners or clocks atomically;
paused and action-only frames do not replay cached breakup requests.

Checks cover source literal recovery, bounded-layout rejection, malformed
bindings, movement/growth, atlas sampling, ring wrap, random isolation and older
Mac packs. Live tests include lethal contact, the distinct mining statistics
position, pirate damage/death, inclusive expiry and late frame/render rejection.
The opening's smoke/fire and first-trip regressions still pass. Actual-location
GPU captures use disclosed lethal hits and close placements; two supplemental
pirate views move only the rendering camera. Separate application tests now cover
the second launch from the earned first return, mined-cargo return under pirate
fire, six acknowledged station lines, equipment boundary and game-over exit.
They retain disclosed close placements and a separate lethal-projectile branch;
they do not establish original-runtime parity or a complete tutorial.

Reader v111 adds the one-time cursor-5 placement of the existing pirate at the
player's physical position plus (5000, 0, 30000) in world axes, facing a source
binary32 pi yaw. `OpeningNpcControl.apply_full_hold_appearance` returns detached
controller/combat candidates. Call it in mission logic before the ordinary NPC
pass; retain the construction's cursor-4 identity while passing current mission
cursor 4 or 5. Health, cargo, targeting flags, bank history, guidance and weapon
clocks survive the cue. It requires the prepared destruction owner even when
the pirate has never activated. Older packs refuse this capability.

The pirate's model factory creates a separate banked mesh. Death now captures
the physical root and retains the mesh bank for the pre-motion statistics copy;
cargo movement can subsequently replace statistics with the container pose.
The placement cue copies the old root basis into statistics before changing root
yaw; the next NPC pass refreshes the banked statistics. An actor already dying or
retired is activated with its exhausted hull and re-enters death on that pass.
This preserves effect animation time, cleanup time and cargo until the next
breakup. The source repeats its death-counter callback in this case; the native
owner records one explicitly marked scripted restart with the retained lethal
attribution. This does not award credits, cargo or mission completion.

Reader v57 adds lethal-hit attribution and death counter changes. Ordinary NPC
statistics start with the nonplayer-kill flag clear. Only an accepted lethal
normal hit with the explicit NPC-source flag sets it; nonlethal, rejected and
postmortem hits cannot change credit. The existing ordinary primary contact API
supplies the player-source flag. Attribution survives actor and world forks.

For the fresh hostile kind-8 actors, the ordered controller records a death once,
after its selection work and before its death-initialization draws. Every such
death contributes −1 remaining hostile and +1 hostile death. Player-attributed
deaths also contribute +1 world player kill, +1 player kill and +1 pirate kill;
other-attributed deaths contribute +1 world other kill. Native
`npc_death_accounting.gd` retains detached events and accumulated **deltas** for
this opening. It does not assume existing save/world totals. Later failure in
another actor, scenery or radio discards the complete candidate, including all
counter changes. Tumble, explosion and retirement do not issue further credit.

Save/world counter baselines, platform achievements, mission outcomes and rewards
remain separate unsupported consumers. These events do not advance the campaign
or grant cargo. Source instruction checks cover both supplied editions; native
tests cover mixed attackers, exact lethal depletion, invalid flags, duplicate
deaths, detached snapshots, late failure and legacy packs without this capability.

```sh
godot --headless --path game --script res://tests/npc_death_accounting.gd -- CONTENT BINDINGS VISUALS
```

With v56 declarations, fresh opening enemies now have native death motion and
animation clocks in `npc_destruction.gd`. A lethal frame retains target-selection
work, then skips live boosts, route progress, aiming, firing and flight. The
ordered controller captures the current ship pose and retained speed, consumes
the four initial shared draws and starts the tumble in that same frame. Local
XYZ spin applies once per positive update; travel uses the captured forward
vector and preserves fractional source units. Countdown equality remains tumble.

Breakup uses the actor position from before that frame's motion. It emits sound
choice 18/19 before four drift draws, resets the countdown and starts the effect
without advancing its clocks on the trigger frame. Both supplied editions resolve
models 16821, 16820 and 14292 with animation range 33–4500 ms. The controller
retains the actual constructor fragment count, rotations and scales. A shared
native model-playback helper also serves scenery effects. Model-end equality
retains playback; effect lifetime expires strictly after 4500 ms and rewinds its
clocks. Fresh opening cargo is absent, so retirement occurs on the following
update before hostility refresh, timers or selection. There is no generic
60-second wait and no loot grant.

The opening session prepares these resources and hands its retained construction
records to the world controller. Returned candidate frames include death events
and body poses; a later actor failure preserves all input owners and random state.
Retired actors become inactive while their existing weapon owners remain retained.
This integration stays within the current opening boundary. Source explosion
geometry is now connected to these owners as described below. Particles, sound
playback, camera shake, save/world counter baselines and subsequent mission
outcomes remain unfinished. Attribution and counter deltas are covered above. Sound IDs are events,
not evidence of audible playback. Nine direct shared random draws are verified;
indirect effect callbacks still require closure before claiming complete parity.

The native regression covers both editions, actual resource and constructor
records, independent random/matrix fixtures, strict timing boundaries, three
ordered lethal actors, frozen live-flight work, early retirement and rollback.
Static source inspection supports these contracts; no original executable was run
for a runtime comparison.

```sh
godot --headless --path game --script res://tests/npc_destruction.gd -- CONTENT BINDINGS VISUALS
```

`npc_death_effect_geometry.gd` now renders the three source explosion models,
using the retained constructor fragment count, rotations and scales. The primary
model uses source material type 18, a later alpha pass; its attached flash and
independent debris use type 2 additive blending. Both profiles use the same atlas
binding and differ in the explicit Mac RGB darkening parameter. Alpha/tint/color
arithmetic shares the native scenery helper. The additive shader uses ONE/ONE
behavior, including when texture or tint alpha is zero.

The main effect and its additive child share a unit-scale camera-facing root at
the recorded explosion position. Each debris root keeps its original local XYZ
rotation and scale, independent of the camera and ship pose. Animation samples
supply surface transforms; scene containers cannot apply these transforms twice.
The intact ship remains visible through explosion elapsed 299 ms and hides at
300 ms. Effect expiry and actor retirement remain simulation decisions.

`npc_destruction_geometry.gd` shares prepared mesh/texture resources across all
three opening actors, with separate materials and animation samplers. A frame
stages every surface and actor before committing presentation. It follows the
same logical death owner across native frame copies and rejects a reconfigured
or unrelated owner. The opening session combines cinematic visibility with the
death body gate and releases all effect geometry on reset. The encounter gate
remains in place; no kill reward or mission completion follows from drawing.

Both editions pass native and Compatibility/OpenGL tests for model populations,
source UVs, transforms, body/effect boundaries, whole-group rollback and cleanup.
GPU checks isolate all effect layers and compare blend/depth/color arithmetic
against an independent constant material. This is an explicit unfogged renderer;
original within-pass sorting, animated culling, settings selection, particle
emitters, audio and camera shake still require implementation or verification.
No original-game framebuffer comparison is claimed.

```sh
godot --headless --path game --script res://tests/npc_destruction_geometry.gd -- CONTENT BINDINGS VISUALS
```

Current bindings initialize the opening player through
`game/src/simulation/opening_player_state.gd`. The native loadout supplies ordered
equipment; the last matching shield or armor item supplies its capacity. Missing
equipment starts at zero; a matching item with a missing property is rejected.
Both supplied editions start with shield 220, equipment armor 250 and the authored
hull override 9,999,999. The player is active with damage enabled and a source
half extent of 1200. Current shield uses binary32 precision; its capacity remains
an integer. Opening frames retain detached player state. Older packs without the
declaration keep their existing precombat support and expose no player body.

Current packs also support ordinary NPC projectile contacts against this body.
`ordinary_player_damage.gd` resolves explicit shooter presence/hostility and
special-flight state. A present nonhostile shooter uses binary32 damage times
0.2, then integer truncation. Otherwise special flight uses sequential binary32
multiplications by 3 and .25 before truncation. The ordinary branch preserves
the integer. The nonhostile branch takes precedence. Damage from the source
opening NPC gun is 3; unsupported additional-damage properties are rejected.

`ordinary_player_contacts.gd` checks strict source bounds for retained projectile
slots, applies the existing shield/armor/hull accounting, and records contact
metadata even when damage permission denies the hit. Target eligibility is
captured once before slots: a lethal hit denies later damage in the pass without
discarding already-selected geometry. Impacts remain until ordinary cleanup.
The fresh player's linked NPC actor is absent, so last-contact actor is null.

`opening_npc_weapons.evaluate_player_update(player, pose, shooter_states,
special_flight, delta_ms)` evaluates each gun in actor order, contacts before
cleanup/movement, carrying damage into subsequent guns. It returns detached
weapon/player owners and per-gun events; callers commit both owners together.
Late failures preserve every input owner. Shooter states must explicitly name
presence and hostility for all three guns. Current opening frames invoke this
operation after player movement and before cinematic and NPC updates, using the
moved player pose and retained shooter state. Fresh enemies start nonhostile, then refresh to hostile
in the NPC pass even while held. The new state affects the next weapon pass.
Failed later frame work discards damage, cleanup and the hostility refresh.
Older packs retain their earlier behavior without this automatic contact scope.

Current v54 packs also initialize ordinary shield recharge. The selected shield's
property 19 supplies duration; both starting editions use 60,000 ms with capacity
220. Native `shield_recharge.gd` calculates capacity / (duration / 100), rounding
each conversion and division to binary32. Positive hull and duration permit the
clock to advance. Strict elapsed > 100 ms emits one pulse, resets the clock and
discards excess time. Full shields still advance the timer; dead hull or zero
duration freezes it. Addition clamps to the equipment capacity.

The world applies recharge before current projectile contacts. Ordinary damage
then truncates any fractional shield charge. Recharge, damage and subsequent
frame work commit together; a late failure preserves the preceding player clock
and pools. Native checks cover both editions, precision, threshold equality,
overshoot, full/dead/disabled states, invalid equipment and older pack absence.

```sh
godot --headless --path game --script res://tests/shield_recharge.gd -- CONTENT BINDINGS VISUALS
```

With v55 declarations, factory hull comes from the ship's base armor field,
with 40 added per source upgrade tag 0. Both supplied opening ships start with
factory hull 200 and no upgrades. The later opening setter raises both current
and maximum hull to 9,999,999. Repair uses that raised maximum: damaged hull
above 200 still blocks armor repair until hull is full.

`equipment_repair.gd` retains separate hull and armor clocks. The last equipped
type-15 device selects timing by its source ID: item 75 uses 600/1,000 ms hull/armor
periods; the other supplied device, item 188, uses 420/700 ms. Positive current
hull and a fitted device advance both clocks. Strictly exceeding a period resets
that clock and discards overshoot, even when no repair is needed. One hull pulse
adds 1 up to maximum hull. The subsequent armor pulse adds 2 up to equipment
capacity only when hull is full, including when the same update just filled it.
Missing devices and dead hull freeze both clocks.

Repair runs after shield recharge and before projectile contacts, within the same
atomic frame. Both original starting loadouts lack a repair device. Tests use
explicit fitted-device and prior-damage fixtures to verify that scheduling without
altering the authentic opening loadout. Unsupported signed-integer overflow is
rejected without changing state. Earlier packs preserve their previous scope.

```sh
godot --headless --path game --script res://tests/equipment_repair.gd -- CONTENT BINDINGS VISUALS
```

Persistent layer feedback and hit intensity, changed-loadout lifecycle, death
consequences and playable encounter scheduling remain unfinished. Ordinary
recharge/repair does not establish special-time or general player lifecycle support.

An encounter owner must supply verified current hull, equipment armor and shield
charge through `configure(hull, armor, shield)`. These values do not establish
maximum capacities, equipment ownership or a starting loadout. The component
stores shield charge with binary32 precision and integer hull and armor values.
Failed configuration clears the component.

`normal_hit(amount, damage_allowed)` applies an explicitly supplied nonnegative
integer hit. The owner must resolve whether damage is allowed, including both
source damage gates. A disabled hit or a hit against zero hull leaves all pools
unchanged. Unsupported arguments return an empty result and preserve the state.

An accepted normal hit truncates shield charge to an integer, consumes shield,
then equipment armor, then hull. Overflow carries between layers. Hull stops at
zero. Exact depletion selects the depleted layer for the impact result; it does
not report an impact on the next layer. Even a zero-damage accepted hit discards
fractional shield charge, matching the independently inspected normal-hit rule
in both supported source editions.

The detached result reports before/after pools, whether the hit was accepted,
its final impact layer and whether this hit reduced a living hull to zero.
Subsequent hits against that hull cannot report a second death. These are local
combat facts, not mission completion, rewards or reputation changes.

This API supports signed-32-bit nonnegative hull, armor and damage values. Shield
charge must be finite and at most 2,147,483,520, the largest binary32 value below
the source signed-integer conversion limit. Larger or negative inputs are
unsupported; they are not healing operations.

Playable weapon firing, encounter collision ownership, target selection, AI,
special damage paths, linked actors, destruction effects, reputation, mission
callbacks and saves remain separate work. Do not route every damage type through
this normal-hit API: source routines for other paths behave differently.

Run the focused arithmetic, boundary, failure and repeated-hit checks with:

```sh
godot --headless --path game --script res://tests/combat_vitals.gd
```

These tests verify the native calculation against recovered rules and explicit
examples. They do not execute the original game or establish combat fidelity.

## Weapon parameters

`game/src/simulation/weapon_loadout.gd` resolves an explicit item and ordered
equipment list against matching content, catalogues and v34 resource bindings.
Configure it with `configure(bindings, catalogues, content_id)`, then call
`resolve(item_id, equipment_ids)`. Failed configuration clears its state. Invalid
or unsupported items return an empty result with a diagnostic. Inputs and results
are detached from its stored definitions.

The result includes integer damage, firing interval in milliseconds, projectile
lifetime in milliseconds and speed in world units per millisecond. Lifetime is
not a distance. Multiplying speed by lifetime gives nominal travel only: source
projectile updates can take a full final time step past expiration, and individual
weapon kinds have further behavior that is not implemented yet.

Primary weapons apply the source equipment damage and interval modifiers with
binary32 arithmetic and truncation to integer results. The last matching modifier
in equipment order supplies the factors. Secondary weapons retain their base
parameters. The resolver also handles the source low-damage branch and explicit
missing-factor sentinel; absent catalogue properties remain unsupported.

Reader v35 additionally distinguishes source item-specific launch modes. Type
zero alone does not establish ordinary projectile behavior: four source items
use an alternate path. The resolver reports `ordinary`, `alternate` or
`unsupported`; older packs without this declaration report `unsupported`.

Both supplied editions resolve 73 weapon parameter records. Seven other weapon
records need separate handling. This is parameter coverage, not 73 implemented
weapons: full firing eligibility, projectile type, targeting, ammunition, energy,
ownership, collision and special damage are still unimplemented. The component
does not connect a resolved damage value directly to an actor or grant equipment.

Focused tests exercise modifier order, rounding, failures, content isolation,
binding provenance and backwards compatibility. Add content/bindings/visuals
triples to check the supplied editions and their opening equipment:

```sh
godot --headless --path game --script res://tests/weapon_loadout.gd -- CONTENT BINDINGS VISUALS
```

## Ordinary projectile timing and flight

`game/src/simulation/ordinary_projectiles.gd` owns native ordinary-primary timing
and projectile slots. `configure(resolved_weapon)` requires a verified ordinary
launch mode and selects the imported v36 capacity. An explicit capacity argument
remains available for isolated fixtures or older packs without capacity data; it
cannot override an imported capacity. Alternate launch modes and kinds are rejected.
Configuration failure clears the live state.

`advance(delta_ms)` advances integer milliseconds. `fire(muzzle, world_direction,
firing_allowed)` requests one shot. The owner must supply source-correct update
order, installed-item eligibility, firing permission, muzzle geometry and aim.
The component normalizes the supplied direction after any owner-resolved spread,
then multiplies it by weapon speed. This also happens when spread is disabled.
Squared components and sums use binary32, the square root uses binary64 before
rounding back, and component division uses binary32 results. A zero-length vector
uses the source positive-Y fallback. Position and velocity calculations preserve
binary32 intermediate results; arithmetic overflow is unsupported.

A newly configured timer equals its interval, and firing requires strictly more
elapsed time. A successful shot uses the first free slot and resets the timer to
zero. Equality, denied permission and full capacity do not fire or reset time.
There is no burst to catch up after a long update.

A projectile with positive remaining lifetime takes the full next time step,
even when that step passes expiration. The result reports its final position and
expiration once. The expired slot is immediately reusable; the following positive
update otherwise clears it. Zero-time calls still clean nonpositive slots and
refresh live geometry without advancing the clock or lifetime. Invalid time or nonfinite
motion rejects the entire update without moving an earlier projectile partially.

Snapshots and events are detached. `retire(id)` removes a caller-selected
projectile without applying damage or rewards. Handles belong to the component
instance and are not reused after reconfiguration. Previous positions are supplied
for presentation; they do not define a verified swept collision test. Source hit
checks precede movement and include additional geometry and actor conditions.

The component is not connected to playable flight yet. Fixed player muzzle
placement is supported below. Aim/spread, collision, projectile artwork and effects, actor ownership and mission
integration remain required. Focused tests run with:

```sh
godot --headless --path game --script res://tests/ordinary_projectiles.gd -- CONTENT BINDINGS VISUALS
```

## Authored fixed weapon mounts

`game/src/content/weapon_mounts.gd` reads the base content's checksum-checked
`weapons_hd.bin` directly. `open(library, catalogues)` requires matching content
identities and clears previous state on failure. `resolve(ship_id, category, slot)`
returns a detached authored position with resource hash and byte extent. Slot
means the equipment instance's slot within its category, so two copies of the
same weapon select separate mounts. Missing ships, categories and slots fail
explicitly. See [the attachment layout](CATALOGUES.md#weapon-attachment-table).

`ordinary_projectiles.fire_from_mount(mount, ship_transform, world_direction,
firing_allowed)` supports the fixed player-primary path. It adds the verified
100-unit local Z shift to the authored position, rotates it with the supplied ship
basis and adds ship translation. Each multiplication and ordered addition retains
binary32 rounding. The supplied aim remains a world vector and goes through the
same normalization, permission, interval and capacity checks as `fire`.
Invalid identities, unsupported categories and nonfinite geometry leave live
projectiles and timers unchanged.

Both source constructors initialize alternating-mount flags to false. Alternating
mount configurations, turret launch geometry and secondary firing remain outside
this API's supported scope. Callers remain responsible for the current ship,
equipment eligibility, source update ordering and actor permission. Reading an
attachment does not establish those permissions or make an encounter playable.

```sh
godot --headless --path game --script res://tests/weapon_mounts.gd -- CONTENT BINDINGS VISUALS
```

## Ordinary primary ownership and aim

`game/src/simulation/primary_weapons.gd` assembles ordinary primary weapons from
an explicit equipment state. `configure(bindings, catalogues, mounts, loadout)`
checks content/binding identity, ship slot capacities, each installed item's
category and quantity, and the ordered equipment IDs used for modifiers. The
loadout has the same shape as `opening_loadout.snapshot()`. Unarmed ships are
valid; unsupported installed primaries fail configuration rather than disappearing.
Each gun retains its equipment slot, authored mount, effective weapon parameters,
independent timer and projectile pool. No equipment purchase or ownership is
inferred by configuration.

Source ordinary-primary setup supplies a zero local aim offset and zero spread.
`ordinary_projectiles.fire_forward_from_mount(mount, firing_transform, permission)`
therefore selects the transform's positive-Z basis column and lets the existing
launch boundary normalize it once. Positive Z is the source forward direction;
using Godot's camera negative-Z convention would reverse firing. This supports
the ordinary default setup, not target selection, aim assistance or other launch
types with local offsets or spread.

The primary owner exposes separate `advance(delta_ms)` and `fire(transform,
firing_allowed)` operations. The encounter must call them in source order;
in particular, projectile hit checks precede movement. A firing request visits
guns in reverse installed-slot order, matching the source group construction.
Sparse slots preserve their original authored mount indices. Each gun independently
applies permission, quantity, interval and capacity gates. Ordinary shots require
nonzero installed quantity and do not consume that quantity.

Both operations stage their changes before committing the entire group. Failure
in a later gun leaves earlier gun timers, handles and projectiles unchanged.
Events and snapshots are detached. `retire(mount_id, projectile_id)` selects one
gun's projectile; both handles are required because projectile IDs are local to
a gun. Mount handles are local to a primary owner and are not reused after
reconfiguration. The low-level `fork_state()` helper exists for staging that same
logical gun, not for creating a distinct game weapon with new identity.

The application still stops before the encounter. This owner does not establish
actor firing permission, AI timing, hit targets, collision, shot effects or
mission consequences. Source opening loadouts from both editions pass through
this native owner in the focused checks:

```sh
godot --headless --path game --script res://tests/primary_weapons.gd -- CONTENT BINDINGS VISUALS
```

## Ordinary contact geometry and impact cleanup

`game/src/simulation/ordinary_hit_geometry.gd` supplies a native contact query
for an explicitly eligible target. `bounds(position, velocity_per_ms, center,
half_extent)` evaluates `(center - position) + velocity_per_ms` with binary32
rounding after each operation, then requires all three coordinates strictly
inside the negative and positive integer half extent. Touching a face misses.
This is a cube test, not a sphere or swept segment. Velocity is used directly,
without multiplying by frame time. Ordinary kind-zero shots do not use the
distance-based enlargement found in a different source weapon kind.

When a target enables point geometry, its provider tests the unshifted projectile
position. `point_geometry(position, explicit_result)` preserves that provider's
boolean result. A negative point result must not fall back to bounds. The provider
itself and actor eligibility are not implemented by this helper; callers cannot
infer a result from model presence or substitute an unverified mesh query.

`ordinary_projectiles.mark_impact(id)` sets remaining lifetime to the verified
impact sentinel while retaining the projectile's position, velocity and handle.
`primary_weapons.mark_impact(mount_id, projectile_id)` scopes this to one gun.
The next update clears it without moving it, including a zero-duration update.
Both editions explicitly call world updates with zero elapsed time. Paused
owners must suppress updates.
An impacted or naturally expired projectile can still be queried before cleanup.
The source checks targets outside the projectile-slot loop, so immediately removing
a hit projectile would incorrectly prevent contact with later overlapping targets.
`retire` remains an immediate administrative removal, not the collision operation.

These helpers do not apply damage, run an encounter, determine target eligibility,
implement point providers, play impact effects or grant mission progress. Connecting
normal damage requires the source weapon policy described below; a complete
contact owner still needs target ordering, impact marking and effects.
The opening application continues to stop before combat. Focused geometry tests
cover strict faces, cube corners, binary32 operation order, invalid arithmetic,
repeated contacts, expiration and deferred cleanup. Primary-owner tests verify
impact isolation using both supplied opening loadouts.

```sh
godot --headless --path game --script res://tests/ordinary_hit_geometry.gd
```

## Opening NPC bodies

`game/src/simulation/opening_combat_actor.gd` combines an authored opening actor,
v37 NPC initialization declarations and native normal-hit accounting.
`configure(bindings, catalogues, actor_id, difficulty)` requires matching content
and binding identities, a source actor ID and an explicit finite source difficulty
value. It resolves the actor's hull resource, current hull, equipment armor,
shield charge, flags and collision half extent. Unsupported player, point-provider
and special-impact paths fail explicitly. Failed configuration clears the body.

Opening NPCs start inactive: the opening disables them after construction. The
body retains separate activity, damage and firing flags. `set_permissions` accepts
explicit lifecycle updates from the encounter owner; visibility and radio alone
do not grant permission. `normal_hit(amount)` applies both activity and damage
gates through the native pool calculator. Amount must already include the source
weapon/target modifiers. This operation does not implement shot effects or rewards.

`apply_scene(scene)` validates content/binding/actor identity and synchronizes the
source position and any supplied orientation. `set_pose` accepts an explicit
source-space transform. Placement updates preserve live hull and permissions;
staging snapshots cannot heal or resurrect the body. Fresh statistics use their
default identity axes until cinematic formation supplies the visible heading.

`collision_context()` returns a detached target eligibility and bounds snapshot.
An encounter must capture it once per target before visiting projectile slots,
matching the source loop. Later damage does not mutate an already-captured context;
a new context excludes a dead or inactive actor. Damage immunity alone does not
remove collision geometry.

Tests check all three source NPCs at four difficulty values in both editions,
independent damage, inactive initialization, explicit permission changes, content
isolation, stale/invalid scene data and synchronization through all five opening
phases. NPC movement/AI, target-list ownership, resolved weapon impacts and playable
application combat remain unfinished.
The application continues to stop at its precombat boundary.

```sh
godot --headless --path game --script res://tests/opening_combat_actor.gd -- CONTENT BINDINGS VISUALS
```


## Opening activation and live actor ownership

Reader v38 adds the authored activation cue. `opening_combat_group.gd` owns the
three native bodies and applies that cue once, on entering phase 3 after the
preceding radio state reports event 7 finished. It enables activity, records actor
mode 1 and the source spatial half extent, and preserves separate damage/firing
permissions. Visibility alone does not activate an actor. The actor-ID inventory
is not yet a verified weapon target list.

Group updates stage every body before committing. Missing or malformed scene
rows, cross-content radio state, a regressing phase or a premature activation
leave the previous group intact. A later frame cannot replay the cue to reactivate
a disabled body. Scene synchronization preserves damage and death. Detached
frame forks keep rejected updates from changing the running state.

The opening sequence, timeline and detail timeline accept an optional explicit
difficulty argument. With supported activation declarations, they synchronize
combat bodies before radio presentation and expose their live hull values to
both the scene and radio gates. Pause stops this work. Legacy packs keep their
existing precombat behavior. The application preview explicitly chooses the
source Normal value, 0.5; saved difficulty selection/restoration remains unfinished.

The application now runs this lifecycle through its existing encounter boundary.
It still stops before the unsupported fight, without fabricated kills or rewards.
Tests cover both source editions, prior-frame radio timing, pause, atomic failure,
once-only activation, JSON numeric IDs, fork isolation and legacy application
behavior. They do not verify combat AI or a completed encounter.

```sh
godot --headless --path game --script res://tests/opening_combat_group.gd -- CONTENT BINDINGS VISUALS
```


## Ordinary weapon damage against NPCs

Reader v39 imports `weapon_parameters.ordinary_hit_policy`. The weapon resolver
uses its additional-damage property binding and exact integer absence sentinel,
then carries `ordinary_hit_policy` into ordinary projectile owners and their
forks. The resolved record keeps the property value, whether its separate path is
required, and the already-modified non-player damage amount. An explicitly
present zero does not mean the property is absent. Alternate launch paths and
older packs receive no inferred hit policy.

`opening_combat_group.weapon_hit(actor_id, resolved_weapon)` connects these
resolved declarations to native NPC pools. It requires matching content/binding
identities and a supported ordinary primary. The group independently checks the
additional value against its own imported absence sentinel and rejects unsupported
additional damage before changing state. Accepted normal hits retain the body's
activity/damage gates and one-time death behavior. The non-player amount is the
resolved weapon's integer damage; player-specific scaling is not used here.

Both supplied editions have eleven supported ordinary items with the additional
property absent. Tests cover every one, equipment-modified damage, explicit zero
and negative additional values, malformed properties, source identity mismatches,
permission gates, repeated hits through death, and retained policy in gun forks.
Pack-version tests verify old scalar-only behavior and required new scope keys.
This operation receives an already-selected contact; it does not choose targets,
run collision loops, mark projectiles, emit impact effects or award progress.
The application still stops before the unsupported encounter.

```sh
godot --headless --path game --script res://tests/ordinary_hit_policy.gd -- CONTENT BINDINGS VISUALS
```


## Ordered NPC contacts

`ordinary_npc_contacts.evaluate(projectiles, combat, ordered_actor_ids,
bounds_selection = null)` combines the native geometry, damage and deferred impact
operations for one ordinary gun. Target IDs must be supplied in the world's
verified order. The pass preserves duplicates and uses target-outer, slot-inner
iteration. It samples activity and positive hull once per target, so later slots
still mark a contact after an earlier slot destroys that target. Damage immunity
also preserves contact marking. Retained real shots participate even when their
remaining lifetime is nonpositive; never-launched or cleaned slots do not.

Reader v40 follows the ordinary constructor and collision selector in each edition.
Both constructors disable the weapon-specific extent override, so a resolved
ordinary gun carries `collision_bounds: {"mode":"target"}`. Omitting the bounds
argument uses this imported default. Older packs without the declaration require
an explicit selection. `{"mode":"target"}` uses each NPC's source half extent;
`{"mode":"fixed","half_extent":N}` supplies an explicit weapon extent for a
caller-owned state. Later source changes to the override flag remain unimplemented.
World target-list construction remains unfinished; callers must not silently
substitute the opening actor inventory for a complete collision list.

A successful result contains detached `projectiles` and `combat` owners plus
ordered contact records. The encounter owner commits both together, then performs
source-ordered motion/cleanup. Failure returns an empty result and leaves both
input owners unchanged, including when arithmetic fails after an earlier staged
hit. This pass does not advance time, select targets, implement player/other-object
contacts, play effects or award mission progress. It is not yet connected to the
application's stopped encounter.

Tests use both actual source weapon/NPC profiles with controlled placement to
check overlap, strict faces, explicit extent overrides, duplicates, inactive and
immune bodies, one-time death, retained expired shots, cleanup and late rollback.
They also verify imported bounds defaults, detached metadata, malformed-policy
rejection and continued explicit selection for legacy packs.

```sh
godot --headless --path game --script res://tests/ordinary_npc_contacts.gd -- CONTENT BINDINGS VISUALS
```


## Primary NPC updates

`primary_weapons.evaluate_npc_update(combat, ordered_actor_ids, delta_ms,
bounds_selection = null)` runs the freshly assembled primary owner's ordinary
NPC contacts and motion on detached owners. Source effect wrappers append in
weapon creation order, and both editions update that world list forwards. This
visits installed primary slots in ascending order, whereas the firing array runs
in reverse slot order. Gun and mount identities stay unchanged between the two
orders; empty equipment slots keep their original slot numbers.

For each gun, the pass checks contacts against the current staged NPC pools,
then advances or clears that gun's shots. Damage from an earlier gun consequently
changes eligibility for the next gun. Impacted shots clear during that same gun
update, including at zero elapsed time. Zero-time updates preserve firing clocks
and live-shot positions/lifetimes; they are not a pause mechanism. The separate
`advance` helper performs motion/cleanup without evaluating contacts.

Success returns detached `primaries` and `combat` owners and ordered per-gun
contact/motion events. The encounter owner commits both. A failure in a later
gun discards earlier staged hits, cleanup and time changes. An unarmed owner
still validates content identity, time and its explicit target list.

This method handles one newly assembled player's ordinary primary group. It does
not construct world target lists, schedule other actors' weapons, implement
player/other-object impacts, maintain dynamic equipment changes, play effects or
complete missions. The application remains stopped at its encounter boundary.
Tests using both imported opening loadouts check distinct firing/update orders,
shared sequential damage, immunity, zero-time cleanup, legacy explicit bounds,
content checks, detached state and rollback after a later gun's time overflow.

```sh
godot --headless --path game --script res://tests/primary_npc_update.gd -- CONTENT BINDINGS VISUALS
```

## Ordinary scenery bodies and contacts

`content/scenery_body_resources.gd` reads the authored AEM sphere for each imported
base-model binding. Supported bases have one surface, zero pivot and only identity
transform keys; changed or unsupported layouts fail with a diagnostic. The radius
is the stored sphere radius, independent of its center, visual AABB, model spin or
selected LOD. The provider retains only radii and content/binding identity.

`simulation/scenery_bodies.gd` initializes each generated field object with native
vitals and source flags. Collision half extent truncates the binary32-rounded
radius times scale times 0.7; hull truncates binary32-rounded scale times 100 plus
30. Armor and shield start at zero. Collision uses the fixed placement position
and a strict axis-aligned cube. Damage permission is independent of contact
eligibility. Ordinary damage shares the existing pool arithmetic and resolved
weapon validation with NPCs, while scenery owns its distinct consequences.

The ordinary contact prelude resets the motion scalar even when damage is denied.
Accepted damage marks its selected pool, sets the damaged flag and adds binary32
0.065 feedback without a cap. Markers accumulate here; their separate frame reset
and visual feedback owners are unfinished. An accepted zero-damage hit marks the
shield branch. Contact metadata separately records the contact flag and the
unnormalized sign-negated incoming velocity, including signed zero. It is retained
even if permission denies damage or an earlier projectile exhausted hull.

`ordinary_scenery_contacts.evaluate(projectiles, bodies, ordered_object_indices,
bounds_selection = null)` stages both owners and visits explicit targets in order,
with projectile slots inside each target. It preserves duplicates and retained
impacted/expired shots, samples eligibility once per target, and returns ordered
contacts plus `last_contact_object_index`. It advances no time. A failed query
returns no staged result and leaves both inputs unchanged. This scenery-only pass
must not replace the complete mixed world target list.

The application prepares all opening bodies and retains them alongside the field.
The body component exposes zero hull without granting inventory or mission
progress. With v43 bindings, the opening world processes it through native breakup,
one-time field accounting and delayed retirement, and retains possible floating
junk. See [environment lifecycle](ENVIRONMENTS.md) for timing and renderer scope.
Older packs without effect declarations keep the explicit destruction boundary.
Source mining is a separate operation and cannot be substituted with ordinary
weapon damage. Automatic encounter contact scheduling, impact/feedback effects,
pickup, audio and mining remain unfinished.

Focused tests cover independent binary32 reference values, immutable ownership,
permissions, feedback accumulation, strict cube faces, weapon overrides, overlapping
targets, mid-target death, retained slots and late-failure rollback. Both editions'
actual fields, base radii and ordinary weapon declarations pass. The complete
precombat opening still passes its radio, camera, pause and encounter-boundary
checks with body ownership enabled.

```sh
godot --headless --path game --script res://tests/scenery_body_resources.gd -- CONTENT BINDINGS
godot --headless --path game --script res://tests/scenery_bodies.gd -- CONTENT BINDINGS VISUALS
godot --headless --path game --script res://tests/ordinary_scenery_contacts.gd -- CONTENT BINDINGS VISUALS
```

## Fresh opening target inventory and combined primary updates

`opening_target_inventory.gd` derives the initial player gun's complete membership
from its content profile. It requires the verified opening world/campaign context,
starting equipment, source NPC order, scenery count, center and location. Installed
equipment types establish that the optional third group is absent in this fresh
world. Changed equipment, non-opening contexts, extra/missing targets or moved
scenery do not silently retain that exclusion. NPC poses, activity and live vitals
may change without changing target membership. The application prepares and retains
this inventory with its scene.

`ordinary_opening_contacts.evaluate(projectiles, combat, bodies, inventory,
bounds_selection = null)` checks the source NPC list, then the complete scenery
list, using their separate damage/contact owners. It preserves an impacted shot
across the group boundary and returns all three detached owners, ordered contacts
and a last target identified by group plus index. This operation assumes the
caller supplies the player's gun; the primary owner below enforces the complete
fresh player loadout. No movement or cleanup occurs between groups.

`primary_weapons.evaluate_opening_update(combat, bodies, inventory, delta_ms,
bounds_selection = null)` validates that canonical loadout and both target owners.
It visits guns in equipment creation order. Each gun checks its entire target
list, then advances/clears its shots; damage from that gun affects eligibility for
the next gun. Impact cleanup also occurs at zero elapsed time. Success returns
staged `primaries`, `combat`, `bodies` and per-gun events. A late scenery query or
later gun failure discards all earlier staged work.

NPC contacts now retain the shared post-hit contact flag and unnormalized
sign-negated velocity, even on denied damage. Last contact wins within each gun's
explicit pass; an empty result resets that gun's last target to null. Gun snapshots
and forks retain detached `last_contact_target` and `contact_pass_evaluated` fields.
The initial false/null pair means that the native owner has evaluated no pass;
it does not claim a verified original constructor value. Actor contact markers
are not reset by an empty pass; their frame reset and visual response are separate
unfinished work.

Tests use both actual profiles with controlled overlapping geometry and retain
all source target members. They verify cross-group projectile availability,
source group/gun order, mid-update deaths, immunity, last-target ownership,
zero-time cleanup and rollback across both failure boundaries. Inventory tests
cover fresh-context/type guards, static ownership, live-state tolerance, detached
snapshots and failed configuration. Complete precombat application checks still
pass with the inventory attached.

These components do not yet schedule NPC weapons or player combat pools, drive
AI, present projectile impacts or complete missions. Scenery destruction is now
owned by the opening world; NPC destruction remains unfinished. The application
continues to stop at its encounter boundary.

```sh
godot --headless --path game --script res://tests/opening_target_inventory.gd -- CONTENT BINDINGS
godot --headless --path game --script res://tests/primary_opening_update.gd -- CONTENT BINDINGS VISUALS
```

## Opening NPC weapons

Reader v44 adds the fresh opening enemies' main-weapon declaration. Each of the
three source actors receives item 19, kind 1, damage 3, a 600 ms interval, a
3,000 ms lifetime, speed 16 source units per millisecond and four projectile
slots. These generated values come from the NPC factory, independently of the
player's equipment modifiers and larger projectile pools. The declaration also
binds the source weapon mesh and its zero local muzzle offset.

`opening_npc_weapons.gd` owns one independent pool per actor and reuses the native
ordinary projectile simulation. An encounter owner explicitly supplies firing
requests and elapsed time. Requests run in actor order and require an active,
living actor with firing permission and an explicit source pose. Launch uses its
positive-Z forward vector and source origin. It does not apply the player's
fixed-mount Z offset. A projectile is identified by both its actor and pool handle.
Firing and updates commit only after all requested operations succeed. Detached
frame copies preserve timers, handles and projectiles without sharing mutable state.

Kind 1 uses the same verified straight launch, normalization, travel and expiry
path as kind 0. The player contact operation described above now handles this
ordinary gun with explicit shooter state. The application still stops at the
encounter boundary: automatic contact scheduling, projectile artwork/audio and
combat outcomes remain unfinished. No campaign event or reward is completed by
these component tests. Later missions, companions and changed loadouts require
separate declarations and verification. Older binding packs remain usable but
report these NPC weapons unavailable.

The separate ordinary NPC flight component now supplies source-tuned heading,
bank and travel math. It still requires explicit direction, speed and permissions
from an encounter controller. Its unbanked pose belongs to steering and forward
travel; its banked pose belongs to ship presentation and combat geometry. These
poses are driven by the fresh-opening guidance and ordinary frame components
below. Fresh world frames now schedule the explicit player contact operation;
full encounter scheduling remains unfinished.
See [motion support](MOTION.md) for numerical behavior and limitations.

## Fresh opening enemy decisions

`opening_npc_guidance.gd` consumes the v46 declarations for a living, activated
opening enemy, with v47 holding-state support described below. Its supported population is the three source kind-8 actors with
hull IDs 2, 23 and 2 in the fresh opening context. Each enemy's target list contains
the player; the other two enemies are excluded. This differs from the player's
NPC-and-scenery inventory. Other populations, companions and saved mission states
require separate verification.

The controller takes integer milliseconds, the current actor snapshot, its
unbanked root pose, explicit player state and the shared generator state. It
returns a desired world direction, speed, steering permission, firing intent and
the updated generator state. Target selection uses strict engagement bounds and
a refresh strictly after 5,000 ms. Refresh can select a straight-flight interval
and preserves the source draw consumed even when there is only one target. A
refresh does not itself acquire firing desire; acquisition can occur on the next
ordinary update.

Cruise starts at 2 source units per millisecond. Periodic or damage-triggered boosts
select 5.5, with a duration of 5,000 plus a bounded 0–2,999 ms draw. Speed approaches
the selected value using source binary32 multipliers once per update, including
zero-time updates. Damage accounting preserves the constructor's earlier hull
sample separately from the opening's later current-hull override and maximum.
Current Mac guidance uses the combat body's verified factory sample: difficulty
0.5 samples 20 before current and maximum become 150; difficulty 10 samples 210,
while the override changes current to 150 and leaves maximum at 210. Only damage
strictly above 40% of maximum triggers that boost. This corrects the historical
rank-one guidance fallback, which could cause a spurious initial boost. Existing
iOS guidance behavior is preserved pending its deferred validation.

A target strictly within the 8,000-unit axis box preserves the current forward
heading; an explicitly supplied special-flight state expands it to 12,000. Local
aim uses the banked combat basis. Firing requires the imported local X/Y tolerance
and strict 35,000-unit axis bounds. There is no additional positive-local-Z test.
Player activity, hull, targeting suppression and the special-flight height rule
remain explicit inputs. The weapon owner separately enforces firing permission.

Decisions precede firing from the existing combat pose; steering and travel follow.
Native composition checks exercise that order with actual imported weapon and
flight declarations from each edition. Invalid input, changed membership, bad
generator state or late numerical failure leaves controller state unchanged.
Snapshots and frame copies are detached.

Active enemies can follow a generated route when player acquisition fails.
Reader v48 and the native route owner below supply its construction and current
waypoint. Guidance still requires that generated state to be attached before its
first update; an absent route is reported when fallback needs it. An already
acquired target can remain selected until the next refresh. Selection and firing
desire are separate retained states: a range refresh can clear selection while
leaving desire set, delaying reacquisition until a later refresh.

This component does not establish full world scheduling, player-hit ownership or
NPC destruction. The application still stops at
`encounter_required`. No mission or reward is completed by these tests, and no
comparison with a running original is claimed.

```sh
godot --headless --path game --script res://tests/opening_npc_guidance.gd -- CONTENT BINDINGS VISUALS
```

## Holding state and ordered enemy control

Reader v47 adds `opening_actors.npc_initialization.holding`. The authored opening
places enemies in mode 5 with inactive combat stats and a 50,000-unit engagement
extent for the fresh location context. The player's initial targeting suppression
prevents the source holding mode from activating itself. Selection and boost
timers start at zero and continue increasing during holding. Target acquisition,
straight intervals and their random draws also continue; boost decisions and
motion wait until active flight. Holding preserves acquired desire even while the
player's suppression flag is set. Active player targeting clears firing desire
when that flag prevents firing; coordinate patrol bypasses that firing branch.

`opening_npc_control.gd` retains all three guidance instances across holding and
activation. `evaluate(combat, weapons, delta_ms, player, random_state)` visits
actors in source array order. For each active actor, it makes the decision, requests
any shot from the old combat pose, advances native flight, and updates the returned
combat pose. Initial flight uses the final cinematic placement; subsequent frames
check that the combat and flight owners still agree. Holding enemies retain their
cinematic poses. An unowned self-activation or return to initial holding is rejected.

The result contains detached controller, combat and weapon owners, the resulting
generator state and ordered per-actor events. Callers adopt the complete result
only on success. A failure in the last actor discards earlier staged shots,
movement and timer/RNG changes. The actor pass does not advance projectiles: their
contact/flight pass belongs to the world's earlier weapon update. A zero-duration
actor pass still performs source decisions; omitting a paused pass is a separate
outer scheduling choice.

Both profiles pass holding/activation checks and 600 subsequent actor passes with
independent gun timers and matching combat/flight poses. The opening application
now adopts this owner through the ordinary frame composition described below.
Complete encounter scheduling, player combat and NPC
destruction remain necessary before playable encounters.

```sh
godot --headless --path game --script res://tests/opening_npc_control.gd -- CONTENT BINDINGS VISUALS
```

## Generated opening patrol routes

`npc_route.gd` generates the fresh kind-8 enemies' coordinate patrols from v48
bindings. Four candidate points use the imported absolute origins and axis bounds.
The source consumes twelve coordinate draws, then a count draw selecting two to
four points, then candidate draws with retries for duplicates. This preserves the
shared random stream; repeated candidates are not replaced by a shuffle.

Configure a route for its content identity and actor, call `generate(random_state)`
once, then attach it with guidance's `set_initial_route(route)` or the ordered
controller's `set_initial_route(actor_id, route)` before its first actor pass.
Generation returns the state after those draws. The caller must supply the RNG at
that source constructor boundary. The engine has not yet recovered the complete
interleaving of world construction, route draws and other random consumers; it
must not simply reseed each route or generate all three at activation.

When selection chooses patrol, guidance advances its route before choosing the
heading. Arrival requires all three coordinate differences to be strictly within
2,000 source units. It advances at most one waypoint per pass, even at zero elapsed
time, and wraps at the last point. Acquisition pauses route progress. Holding does
not advance routes. Coordinate patrol uses its waypoint heading without the
player's close-heading override and never requests firing; normal speed decisions
and gradual steering still run. Arrival and route wrap do not complete objectives
or grant rewards. Routes with associated objects and other mission contexts remain
unsupported.

Route, guidance and ordered-controller copies own detached state. Both profiles
pass fixed generator results for all supported point counts, duplicate retries,
strict arrival boundaries, patrol/pursuit transitions, retained progress, later-
actor rollback and 600 repeated native patrol passes. These checks establish the
bounded native component behavior; the application still has its encounter gate.

```sh
godot --headless --path game --script res://tests/npc_route.gd -- CONTENT BINDINGS VISUALS
```

## Opening NPC construction

`opening_npc_construction.gd` composes all three fresh opening actors from a shared
random state supplied immediately before the first NPC factory call. Configure it
with matching bindings and catalogues, then call `generate(random_state)` once.
For each actor it consumes factory XYZ draws, generated route draws, cargo draws
and breakup-fragment draws in source order. It preserves duplicate route retries
and the cargo sampler's bounded candidate retries. Fragment angles and scales use
source binary32 conversion.

The opening explicitly clears each actor's generated cargo. Returned `cargo` is
therefore empty; `discarded_cargo` records initialization diagnostics only and must
never become loot or a reward. Fragment records describe preallocated geometry;
they do not trigger a death or render an explosion. `route(actor_id)` returns an
independent route owner suitable for the ordered NPC controller. Configuration,
generation failure and returned snapshots preserve ownership and content identity.

Only the exact fresh opening ship, equipment and enemy population are supported.
The source special cargo override is excluded by this loadout. General NPC cargo,
player cargo changes, world reseeding, NPC death,
player-hit handling and playable encounter scheduling remain unfinished. Existing
packs without v49 construction declarations report the feature as unavailable.

The focused construction test covers both supplied editions, seven deterministic
stream fixtures (including both scenery-generated boundary states), bounded cargo
fallback, cargo discard, source float conversion, route handoff and invalid state:

```sh
godot --headless --path game --script res://tests/opening_npc_construction.gd -- CONTENT BINDINGS VISUALS
```

## Fresh world initialization

`opening_world_initialization.gd` continues the scenery field's RNG through all
three NPC constructors, then through their ordinary weapon setup. Each NPC first
assigns item 0 with four effects, then item 19 with four replacement effects.
Every effect consumes one bounded draw; zero means flipped. The 24 draws remain
part of the shared stream even though the default effects are discarded. Returned
records keep the default assignment separate from the active one and preserve
per-slot orientation. Rendering those effects remains separate work.

The source fresh loadout excludes optional equipment populations, attached hull
actors and companions. Other loadouts and mission contexts are unsupported.
The opening session now completes this initialization before its first scenery
update. Its scenery owner retains the resulting RNG for later destruction and
provides detached initial NPC routes. Completion is allowed once before any
successful update, including a zero-time update. Failed attempts preserve the
field; frame copies and snapshots preserve ownership. Older binding packs retain
their prior capabilities and report world initialization unavailable.

Both editions pass fixed NPC/weapon stream results and full field-to-world
initialization checks. Cargo exclusions normalize imported JSON numbers to
integers; a synthetic catalogue regression forces forbidden candidates through
all 100 retries and verifies the fallback and RNG boundary. These checks establish
the recovered initialization contract, not original-game runtime parity.
Complete encounter weapon/contact ordering, player damage, NPC death and
encounter outcomes remain unfinished; the application retains its encounter gate.

```sh
godot --headless --path game --script res://tests/opening_world_initialization.gd -- CONTENT BINDINGS VISUALS
```

## Ordinary opening frame

`opening_world_frame.gd` connects the initialized world to the opening session
when v50 world initialization is available. It retains the three NPC controllers,
their generated routes and weapon pools across frames. The application runs the
fresh opening through the first phase-four player-follow frame. Its optional v59
player-flight owner extends native simulation through the first three-actor fight
and radio events 9/10, stopping at the following unsupported transition.

The ordinary source frame has three passes. Logic first applies supported player
shield recharge, equipment repair and scripted forward travel, then checks
existing NPC projectile contacts against the moved player pose and retained
shooter hostility. It advances the slots before cinematic placement, drift,
activation and camera updates using preceding
radio flags. The world pass visits NPCs in array order, firing from their current
poses before flight, then updates scenery with the resulting shared RNG. Radio
presentation runs last and observes the new actor and cinematic state. A radio
completion can therefore activate an actor only on the next logic pass. A shot
created by the NPC pass retains its initial position and lifetime for this frame.

The scene adopts each returned combat pose while keeping the camera view already
computed for this frame. The next camera update sees that retained pose. Holding
selection clocks run from startup; their strict five-second refresh and overdue
boost checks survive cinematic activation. The fresh player has the imported
current-hull override, active statistics and no special-flight mode. Source target
suppression clears on the phase-three to phase-four transition. This limited
target descriptor reads the retained player damage pools; complete player flight,
changed equipment and hit feedback remain separate work.

With v58 player-motion declarations, cinematic travel uses current cruise speed
without throttle or steering. The formation cue replaces that frame's earlier
travel position. The release cue clears scripted flight after the player has
already moved, so the phase-four handoff frame still travels once. Tests cover
both sides of the player collision boundary where using its preceding pose would
give the opposite hit result. See [motion scope](MOTION.md).

With v59 ordinary player flight explicitly configured, player primaries process
contacts and cleanup before NPC weapons. Both weapon arrays run before the
controller/camera. After that camera pass the living player may launch forward
primaries and update retained steering for the next frame. Source player equipment
construction precedes scenery reseeding; joining the primary owner does not reset
the retained scenery/NPC RNG. Ordinary impact rendering does not consume constructor cosmetic flags; their RNG draws remain retained.

Controlled fixtures kill all three actors using the actual primary equipment and
contact paths, record one-time player kill deltas, and start hull-gated radio event
9 in the same frame. Event 10 can finish; further advancement then fails without
mutation. A lethal player contact also suppresses later firing and stops at the
unsupported death transition. Failed final radio presentation rolls back damage,
death motion, fragments, accounting, steering, shots and all frame clocks.

Frame evaluation returns detached owners. Invalid duration, stale timeline/world
identity, bad shared RNG, actor/scenery failure or invalid final radio presentation
leaves the input owners unchanged. The application also restores them if scene
presentation fails. Pauses retain the whole frame state. Older packs continue
using their previous opening capabilities without constructing this frame owner.

Both editions pass radio/activation ordering, persistent movement, first-shot
lifetime, strict holding refresh, simultaneous NPC/scenery RNG, failed-frame retry,
pause and legacy compatibility checks. Initial weapon-effect records retain their source RNG provenance. Full player lifecycle, remaining NPC death effects and counter consumers,
special-time behavior and subsequent mission outcomes remain unfinished. Older binding packs stop at
`encounter_required`; current packs support the ordinary opening fight. These are native
checks against statically recovered behavior, without an original runtime comparison.

```sh
godot --headless --path game --script res://tests/opening_world_frame.gd -- CONTENT BINDINGS VISUALS
```

## Opening travelling projectile presentation

Reader v60 identifies the fresh player's item-2 model and the item-19 models used
by all three opening NPCs. These are travelling models; the earlier effect-slot
IDs and random flags belong to impact model setup. v61 adds their ordinary presentation below.

`opening_world_frame.configure_projectile_visuals(bindings, library)` attaches
animation ownership once before time advances. Configure optional player flight
first to include its two guns. Each weapon shares one animation clock across its
slots, including while empty. New shots do not restart animation. Source ranges
come from each imported model: 33–200 ms for player bolts and 33–700 ms for NPC
pulses. Looping wraps only after the final timestamp and uses the source absolute
end modulo: `start + time % end`. Existing one-shot effect clocks retain their
previous behavior. Failed world frames commit neither animation time nor shots.

`projectile_geometry.gd` reuses imported meshes/textures, the native surface
animation sampler and type-2 additive material. Player shots align to normalized
velocity with world-up cross products. NPC shots use the camera X/Y axes and
negated Z axis. The renderer compensates Godot's automatic cull reversal on
reflected transforms, preserving the source matrix and triangle layout. Final
lifetimes below 1,000 ms scale by their signed fraction of one second; the final
overshoot remains until normal slot cleanup. Empty and hidden-sentinel slots do
not render. A reduced billboard scale is an explicit preset, not an inferred
original device preference.

The renderer prepares all weapon surfaces before committing any of them. It
checks content identity, retained animation ownership, population and current
world time. OpeningSession connects the three NPC models; the application retains
the later mission-transition boundary with current bindings.
GPU checks independently render both weapon models for both editions and inspect
the opening scene. Native checks cover shared clocks, release-frame firing,
loop/expiry boundaries, cull selection, legacy rejection and failed-frame rollback.
These checks establish native rendering against static source declarations, not
pixel parity with a running original game. Other weapon types,
particles, audio, fog and automatic graphics settings remain outside this scope.

```sh
godot --headless --path game --script res://tests/projectile_geometry.gd -- CONTENT BINDINGS VISUALS
```

## Opening ordinary impact presentation

Reader v61 identifies the original item-2 and item-19 impact models (14600 and
14605) independently in both supplied editions. Each projectile slot owns a
separate model and one-shot clock, initially disabled. Original animation ranges
are 33–466 ms. Impact samples advance before ordinary contacts. A hit restarts
the clock but preserves the previous sampled pose until the next update, including
when a still-visible slot is reused. Playback remains active at the exact final
timestamp; an overshoot stops playback after sampling the final key.

`ordinary_impact_state.gd` retains these clocks and the projectile's position
before deferred cleanup. It consumes the existing ordered player/NPC contact
results without changing collision, damage or random draws. The ordinary source
update, contact and draw paths do not read the constructor's random effect flags.
The renderer therefore copies the complete current camera basis and uses the
stored hit position, without adding a random mirror or a lifetime shrink.

`ordinary_impact_geometry.gd` shares imported mesh/texture preparation, native
animation sampling and the additive surface adapter with travelling projectiles.
All slots prepare before a render commit. OpeningSession connects the available
NPC impacts and, when interactive flight is enabled, both primary weapons.
Focused checks cover actual player/NPC contacts, overlapping hits, slot reuse,
final sampling, camera roots, source provenance and failed-frame rollback. GPU
captures independently show both original impact models in both editions.
Particles, sound, other weapon types and remaining player hit feedback are still
unfinished. These checks do not establish original-runtime framebuffer parity.

```sh
godot --headless --path game --script res://tests/ordinary_impact_geometry.gd -- CONTENT BINDINGS VISUALS
```

## Opening application input

The Opening tab enables ordinary player flight when its bindings include the
verified player, world, projectile and impact capabilities. `OpeningSession`
retains an explicit noninteractive mode for older previews and native fixtures.
Interactive sessions configure both player primaries before any clocks advance.
WASD/arrows or controller left stick feed the native normalized command state;
Space/right trigger holds primary fire. Input follows the source camera pass,
with retained angular response affecting the following motion step.

Pause remains available through Esc/controller Start throughout the opening.
Touch preferences control the native steering pad, Fire and Pause, defaulting to
hidden desktop actions and visible mobile actions. The pad supports independent
steering/fire fingers. Focus loss, hidden tabs, pause and stop clear held input;
controller disconnect clears only that controller. Radio remains timed while
ordinary flight continues. No new mission conditions or imported parameters were
added for this native input adapter.

After radio event 10 finishes, the session enters `mission_transition_required`.
Player destruction enters `player_death_required`. Both states freeze simulation
without inventing later radio, rewards or earned campaign completion. Restarting
currently reconstructs the fresh opening; saved recovery and the next mission
scene remain unfinished. Controlled contact fixtures verify these boundaries;
physical controller and Android device validation have not been performed.
The original center targeting frame now uses image alias 1223 from the active
profile. Its four native texture controls preserve the source horizontal and
vertical mirror arrangement and original alpha. Explicit baseline atlas selection
uses texture 10062 / region 122 on iOS and texture 10063 / region 6 on Mac.
The original pixel dimensions differ: 152×114 and 328×245 per quarter. The remake
normalizes the complete frame to 304 logical pixels wide on phones and 152 on
desktop, preserving each source image's aspect ratio. This native layout choice
does not modify simulation, scanner timing or aiming rules. The frame ignores
input, stays separate from touch-action preferences and clears with the scene.
Existing image bindings provide the art; no new binding pack is required.
Current v64 bindings add ordinary opening NPC markers and scanning below.
Remaining HUD elements, aim assistance, other flight actions and full player hit
presentation remain separate work.

The native target-projection component is also tested independently of selection.
It uses imported vertical perspective, integer viewport centers and the frame's
logical ellipse radii. Onscreen points keep their projected position even outside
the ellipse. Failed projections contract to the center frame when possible;
rear and zero-depth cases preserve the recovered camera-space fallback. The HUD's
positive near-plane comparison differs from normal scene clipping, and it has
no far-plane visibility test. These rules are separate from mesh visibility.
Checks cover both editions' authored opening cameras, landscape/portrait sizes,
viewport edge inclusivity, rear targets and invalid coordinate handling.
The component currently supports a viewport already oriented by Godot; numeric
overflow with architecture-dependent pixel conversion returns a diagnostic.
The v64 retained scanner and marker owner now share this projection. The source
scan window follows the retained moving aim point described below.


## Ordinary opening aim and reticle

Reader v62 adds `opening_staging.player_aim` for the explicitly selected
projected-forward native control mode. The player pass projects a point 22,000
source units along normalized forward, after player motion and before controller
relocation or camera updates. It uses the preceding camera pose, with the fresh
renderer identity as the initial camera. Nonpositive camera depth uses binary32
0.2 new / 0.8 previous weighting once per update, including zero-time updates.
Positive depth copies the raw point. History begins at zero and remains retained
through viewport resizing. Aim shares the target projector's raw perspective;
it does not use the target-marker ellipse or truncate until presentation.

The original idle image 1216 and contact image 1230 use texture 10062, regions
115 and 129 in both profiles. Their 40×40 source rectangles are preserved, with
20×20 desktop composition and 40×40 phone composition. These aliases come from
separately verified bulk declarations; they are explicitly bound in the new aim
capability rather than inferred from another image or edition.

Player ordinary NPC contacts set the contact flag even when the damage policy
applies no damage. Scenery contacts do not set it in this supported path. The
contact image is sampled before the accumulated timer reaches 201 ms and clears
the flag. Repeated contacts do not restart the timer; a subsequent idle draw
resets it. Hidden cinematic draws retain the pending flag without advancing this
timer. The reticle appears for the living player in phase 4, ignores input and
remains independent of the touch-controls preference.

Aim, feedback, motion, contacts and radio commit together through the world frame.
Session pause, hidden/focus pauses and failed simulation or presentation preserve
the retained sample. Older binding packs do not gain guessed aim declarations.
Focused checks cover both editions, analytic projection/lag, resize history,
actual NPC contacts, timer boundaries, rollback, original pixels and GPU drawing.
Original cursor-steering modes, equipment variants and remaining HUD/mission
systems are still unfinished. No original-runtime or
physical-device parity is claimed.

```sh
godot --headless --path game --script res://tests/opening_aim.gd -- CONTENT BINDINGS VISUALS
godot --headless --path game --script res://tests/flight_aim_reticle.gd -- CONTENT BINDINGS VISUALS
```

## Fresh NPC hull capacity

Reader v63 introduced the opening actors' maximum-hull rules separately from
their current-hull overrides. Reader v83 corrects the entry rank: the source
recalculates it from fresh zeroed counters before constructing the flight world.
This selects rank 0 and factory base 20 at campaign cursor 0.
For the source's ordinary opening subtype and hull population, factory hull is
`truncate(((difficulty - 0.5) * 20) + 20)`, with binary32 rounding after each
operation. The opening setter then assigns current hull 150 and raises the
maximum only if that factory value is lower. At difficulty 10, for example, the
NPC begins with current hull 150 and maximum hull 210. At normal difficulty 0.5,
the authored override still makes both current and maximum hull 150.

The combat actor retains `factory_hull` and `max_hull`. Its `hull_percent` sample
uses the source's float division/multiplication followed by integer truncation;
87 of 150 gives 58. Damage changes current hull, while pose updates, activity
changes and destruction preserve maximum hull. Detached actors retain these
values through the existing atomic contact/world/presentation transactions.
Packs predating hull support omit these fields. Packs with the older rank-1/base-34
declaration must be prepared again before combat can use them; they remain
readable for inspection. Unsupported populations and later campaign contexts
cannot reuse the fresh formula.

Focused checks cover both source profiles, accepted difficulty bounds, integer
percentage edges, inactive/denied hits, deaths, detached changes and failed world
frames. The auxiliary pool is not treated as a shield or hull capacity. The v64
NPC markers consume these percentages for their health bars. This does not establish original-runtime or device parity.

```sh
godot --headless --path game --script res://tests/npc_hull.gd -- CONTENT BINDINGS VISUALS
```

## Ordinary opening NPC scanner and markers

Current bindings add a retained scanner for the fresh three-ship population.
Equipment is read from the actual opening loadout: the last type 17 item supplies
property 29 for duration and property 31 for cargo inspection. Both supplied bases
equip item 82 with duration 3000 ms. Mac uses viewport width divided by 18 for its
integer acquisition radius; iOS uses width divided by 16. This gameplay window is
independent of compact desktop artwork sizing. Its strict square uses integer
truncation *after* subtracting radius from the retained floating aim point.
The first eligible onscreen NPC in source population order becomes the candidate.

Candidate changes reset the timer before adding that frame's duration. Exactly
3000 ms does not complete acquisition; a later positive increment does. Selection
changes once, clears elapsed time, and records source sound 26 and cargo-message 22
requests. Reacquiring the same selection emits neither request. Those requests
are exposed as frame events; sound playback and notification presentation are
not connected yet. The fresh actors have no retained cargo, as established by
their construction declarations. No invented cargo or rewards are granted.

Losing the window clears elapsed time. It retains the candidate while a selected
NPC exists, and otherwise clears it. A selected NPC entering destruction mode 3/4
clears both pointers before markers are sampled. Markers use the selection from
before that frame's acquisition. Scan animation uses the post-acquisition timer.
The whole sample commits with the existing contact, actor, scenery and radio
transaction; rejected frames and session pauses preserve it.

Original health bars appear for onscreen NPCs within the inclusive 24000-unit
coordinate box around the player, with brackets on selected targets. Far or
failed-projection targets use dots/rings, using the established center-frame
ellipse. Scanner acquisition has no 60000-unit Euclidean cutoff. Fresh hostile
NPCs use red art; nonhostile fresh NPCs use yellow because their friendly flag
starts false. Health fill widths use source integer percentages and binary32
truncation. Atlas images are cropped without pixel replacement, with integer
half-image anchors. Art is normalized to 41 logical pixels for phone brackets,
then halved on desktop, preserving the edition's source proportions.

Image 1110 is the source 25-frame 40×40 animation strip at texture 10062 region 10 in
both editions. It appears at retained aim, with frame index derived from elapsed
scan time. Its original pixels are verified independently of rendering.

This implementation currently enables the ordinary phase 4 HUD. Earlier cinematic
HUD visibility has not been established. Other target groups, special scanner
modes, cargo-bearing populations, auxiliary bars, selected distance labels,
information panels and acquisition audio/notifications remain unsupported.
Native and GPU checks do not establish original-runtime or physical-device parity.

```sh
godot --headless --path game --script res://tests/npc_scanner.gd -- CONTENT BINDINGS VISUALS
godot --headless --path game --script res://tests/flight_npc_markers.gd -- CONTENT BINDINGS VISUALS
```
