# Native flight motion foundation

The engine has native ordinary cruise, manual pitch/yaw rotation and elapsed-time
pilot response. These are currently exercised by headless checks. The Opening tab
integrates scripted player travel through the first player-follow handoff.
The shared world frame also supports ordinary steering and primary firing after
that handoff in native tests; the application input remains gated.
Interactive flight presentation, other equipment effects, boost, acceleration behavior,
collision response, autopilot and docking remain unfinished.

## Opening cinematic travel

Reader v58 adds `opening_staging.player_motion`, independently recognized in both
supported editions. The fresh player starts with scripted flight enabled and its
update gate open. Each supported ordinary frame translates the ship along local
+Z by current cruise speed times elapsed milliseconds, without a throttle factor
or manual steering. The ordinary motion path is suppressed, so travel occurs once.
The fresh cruise speed is 2 source units per millisecond.

`opening_player_motion.gd` evaluates that movement from the retained scene pose.
The world frame applies it after recharge/repair and before existing projectile
contacts. The opening controller then consumes prior radio flags, applies any
scripted formation placement, and updates the camera. The formation placement
therefore replaces that frame's earlier travel position. NPC targeting sees the
resulting pose; existing projectile contacts see the moved pose before placement.
Periodic detail selection retains its preceding-frame inputs.

Finished radio event 8 clears scripted flight at camera phase 4. Movement still
runs on that transition frame because the player pass precedes the controller.
The application currently stops at this handoff. The opt-in ordinary owner below
continues the native encounter with v59 data. Earlier binding packs retain their
previous scope.

Actual-profile checks cover signed heading, zero time, the 150 ms ordinary cap,
formation replacement, the final travel step, edge-of-bounds projectile contacts,
foreign identity and failed-frame rollback. Both editions also pass rendered
opening application checks. These establish native behavior against static source
evidence; comparison with a running original game remains outstanding.

```sh
godot --headless --path game --script res://tests/opening_player_motion.gd -- CONTENT BINDINGS VISUALS
```

## Ordinary opening player frame

Reader v59 adds `opening_staging.player_flight`, linked to the existing cinematic,
rotation, response and fresh equipment declarations. `opening_world_frame.gd`
can join `opening_player_flight.gd` and the existing primary-weapon owner through
`configure_player_flight(bindings, catalogues, library, scenery, sensitivity)`
before the first frame. This explicit capability is not enabled by the application
yet. Configuration rejects mismatched content, advanced worlds and weapon resets.

During phase 4, movement consumes the preceding frame's angular response and the
source initial throttle of 1. Player primaries then process existing contacts and
cleanup before NPC weapons. The controller and camera run next. A living player
can fire both installed primaries and sample steering for the following movement
update. Consequently the cinematic release frame still moves in its scripted
heading, but can launch shots and retain new steering. Newly launched slots do
not move or lose lifetime until the next weapon pass. All these owners commit
with the later NPC, scenery and radio work, or remain unchanged on failure.

Sensitivity is an explicit native setting; test value 1.0 does not establish an
original default. This scope has fixed ordinary throttle, unbanked pitch/yaw and
forward primary aim. Throttle input, boost, banking, target assistance, collision
response, alternate flight modes and application input/presentation remain
unfinished. Player death and finished postcombat radio event 10 stop advancement
at their unsupported transitions. No mission completion, reward or save change
is produced.

Both editions pass fresh/release/live flight, delayed steering, initial shot
lifetime, zero time, lethal contacts, death-credit/dialogue integration and late
failure rollback. Controlled contact fixtures establish simulation behavior,
not interactive playtesting or comparison with a running original game.

```sh
godot --headless --path game --script res://tests/opening_player_flight.gd -- CONTENT BINDINGS VISUALS
```

## Ordinary cruise component

Each edition's v7 resource binding pack can contain a `cruise` definition with
`speed_units_per_millisecond`, `forward_axis` and five source extents. Preparation
requires agreeing constructor/reset values and recognized movement and forward
lookup layouts. Unknown or ambiguous layouts produce an empty definition, which
keeps asset inspection available but cannot initialize cruise. Older packs remain
readable without acquiring a guessed speed.

Both supplied editions declare 2 source-coordinate units per millisecond for
ordinary cruise. Static tracing establishes millisecond input and normalized
local +Z translation. That is 2,000 source units in one simulation second at full
throttle. These are original coordinate units, not a claim about real-world meters
or a HUD distance label. Ship catalogue handling is not used as a cruise speed.

`game/src/simulation/cruise_motion.gd` takes validated bindings and the session's
base content identity through `configure()`. A failed configuration clears the
previous rate. `advance(pose, throttle, seconds)` returns a translated pose using
the supplied heading, normalized throttle in [0, 1], and elapsed simulation time.
It preserves the basis and normalizes its forward column so local model scaling
does not multiply travel speed. Zero elapsed time pauses translation; invalid
inputs return the unchanged pose and an error. `clear()` ends the source context.

This is a continuous native calculation. The caller owns the simulation clock,
input, heading and pause state. The original scene's frame-delta cap and alternate time modes are not applied by
this component. The flight driver below applies the ordinary recovered cap;
alternate time modes still need integration and verification. Passing wall-clock elapsed time after a
modal pause would therefore be incorrect. Hangar inspection transforms are also
not flight poses.

Run focused checks from the source root:

```bash
godot --headless --path game --script res://tests/cruise_motion.gd
godot --headless --path game --script res://tests/scene_bindings.gd
```

To check prepared original sources, append `-- "/path/to/content/CONTENT_ID"
"/path/to/bindings/BINDING_ID"` to the motion command. Multiple pairs may be
provided. Tests cover source units, heading, throttle, timestep subdivision,
scale-independent distance, paused time, invalid input and identity reset.
These checks establish the component's behavior; they are not original-game
observations or proof of complete flight pacing, control or mission fidelity.


## Manual rotation and forward travel

Version 8 binding packs add `manual_rotation`: `angle_unit_scale`,
`radians_per_turn`, `time_scale`, the supported `local_x_y` rotation order and
source extents. Each edition's reader verifies the recognized angular consumer,
its constant references and rotation-helper layout. Missing or ambiguous layouts
remain empty. Older packs retain their existing features.

The supplied sources share an angle-unit scale of 1/65536, a stored float near
2π radians per turn, and a stored time scale near 0.033. Together these convert
resolved angular control units and elapsed milliseconds into pitch/yaw angles.
Those control units are an internal simulation quantity; they are not normalized
stick input or the catalogue handling rating.

`game/src/simulation/flight_motion.gd` configures both rotation and cruise from one
content identity. Its `advance(pose, angular_units, throttle, seconds)` takes
`Vector2(pitch_units, yaw_units)`, composes local X then local Y rotation using
Godot's native basis operations, and moves along the updated local +Z. It requires
a proper orthonormal simulation orientation; model scale belongs to presentation.
Zero elapsed time preserves the pose exactly. Invalid inputs or failed source
configuration cannot leave partially applied translation or rotation.

This component does not map keyboard/controller/touch input into angular units.
The pilot-response component below supplies the ordinary elapsed-time response.
Other source response modes, preference bindings and state modifiers remain unfinished. Banking visuals,
roll maneuvers, automatic target turning and collisions are also separate work.
No starting ship, ownership, loadout, mission or pilot sensitivity is assigned.

```bash
godot --headless --path game --script res://tests/flight_motion.gd
```

The same optional content/bindings argument pairs can exercise v8 packs. Checks
cover signed/local rotation axes, composition order, heading before movement,
single-axis timestep subdivision, a closed flight circle, orthonormality, pause,
invalid poses and source-state clearing. Combined rotations and curved travel
are sampled per simulation step; the tests do not claim arbitrary timestep sizes
produce identical trajectories or reproduce original input response.


## Elapsed-time pilot response

Version 9 packs add `pilot_response`, independently recovered for each edition:
`target_gain`, integer `target_divisor`, `ramp_bias`, `ramp_scale`,
`neutral_divisor`, the `elapsed` mode, `signed_square` command curve and source
extents. Bounded readers require agreeing signed neutral constants and ramp
references. Unsupported layouts remain empty; earlier packs receive no guessed
response parameters.

`simulation/pilot_response.gd` takes signed logical pitch/yaw commands in [-1, 1]
and produces angular control units. Configuration requires the same content
identity, an explicit vehicle response factor and an explicit sensitivity value.
The vehicle resolver below can derive that factor from supplied catalogue state.
There is no assigned default ship, loadout or saved preference. With factor F,
sensitivity S and elapsed milliseconds dt, the supplied sources use:

- Target: truncate(truncate(command × |command| × 750 × F) / 63).
- Neutral return: dt × F / 126, toward zero without overshoot.
- Driven response: dt × F / ((3.3 - S) × 20), using the stored source float for 3.3.

Neutral return also happens during held input on the ordinary path. Directional
input then approaches its target only while the current value lies short of that
target in the command direction. Reducing a held command does not instantly clamp
the response to its smaller target. Small nonzero commands with a zero-quantized
target can still brake an opposite turn. Release and driven response have distinct
rates.

`simulation/pilot_motion.gd` combines this with flight motion. `advance(pose,
commands, throttle, seconds)` moves using the established angular state, then
commits the response prepared for the next step. This follows the observed
ordinary source update order. A failed step changes neither the pose nor the
stored angular response. Zero simulation time preserves both. Changing the
response factor preserves current angular state; failed reconfiguration clears
all source-bound motion state.

This component covers the ordinary path with one supplied response factor. Source
conditional response penalties, physical device axis mapping, sensitivity
persistence, captured-mouse response and special flight
states are not integrated. The caller must not apply it indiscriminately to those
modes. Clock caps and modal/cinematic pause ownership remain separate work.

```bash
godot --headless --path game --script res://tests/pilot_motion.gd
```

Optional content/binding pairs exercise v9 packs. Checks cover signed/squared
commands, integer targets, held/released/reversed input, smaller and tiny targets,
update order, pause, invalid-step atomicity, parameter isolation and content
identity. The real-pack checks supply explicit test factors and sensitivity;
they do not validate an original ship's loadout. Static source evidence and native
component tests do not replace an original-game controls or pacing comparison.


## Ship handling and maneuverability equipment

Version 10 packs add `vehicle_response`. Each edition's static reader verifies
linked handling and equipment accessors, setup constants, the equipment-type
selection table, item property lookup and positional item-type binding. The pack
contains the conversion coefficients, upgrade tag/bonus, equipment type/property
selectors, percentage divisor, response scale and source extents. Unknown layouts
remain explicitly unsupported.

`simulation/vehicle_response.gd` binds these parameters and catalogue snapshots
to one content identity. `resolve(ship_id, upgrade_tags, equipment_ids)` accepts a
ship catalogue index, integer upgrade tags and ordered occupied equipment
catalogue indices. It calculates the ordinary response factor:

1. Convert the base handling rating using that edition's coefficients.
2. Add the source bonus for each matching handling upgrade tag.
3. Select the last installed maneuverability device's percentage.
4. Apply that percentage to upgraded handling and multiply by the source scale.

The supplied iOS source uses normalized catalogue handling directly. Mac uses
approximately `(h - 0.45) / 1.1 × 0.85 + 0.7`, preserving its stored float
coefficients. Both add approximately 0.2 per upgrade tag 3. Equipment type 16
supplies percentage property 28; multiple matching entries use the last value in
source list order. The final factor is `handling × (1 + percentage / 100) × 20`.
The calculation does not assume the catalogue rating itself is an angular speed.

`pilot_motion.gd.configure_vehicle(...)` resolves the selected ship state before
initializing motion. `set_vehicle(...)` applies a changed factor without resetting
an ongoing turn. Invalid ship/equipment data or mismatched identities cannot
partially change an existing factor; failed initial configuration clears motion.
The lower-level explicit-factor API remains available for tests and other verified
response modes.

This resolver computes the maneuverability contribution from a supplied state.
It does not establish ownership, upgrade availability, slot compatibility, device
stacking eligibility, prices or mission loadouts. It neither installs items nor
awards upgrades. Other equipment effects and the source conditional cargo/difficulty
response modifier still need native implementation and integration. Sensitivity
remains explicit until saved preferences and device mapping are connected.

```bash
godot --headless --path game --script res://tests/vehicle_response.gd
```

Optional content/binding pairs exercise v10 data. All 64 iOS and 61 Mac base ship
records and their combinations with each edition's five maneuverability devices
were checked, including a handling upgrade. Synthetic checks cover alternative
coefficients, upgrade tags, ordered equipment selection, packed catalogue arrays,
missing properties, immutable configuration, rejected changes and pilot-motion
integration. These are component checks, not a complete loadout or original-game
flight validation.


## Native controls and the flight driver

Version 11 packs add `frame_clock`. Both supplied sources cap ordinary scene
elapsed time to 0–150 milliseconds. Import verifies all cap constants agree and
that every recognized delta call resolves to the same supported millisecond
supplier. The native clock quantizes absolute microsecond timestamps to integer
milliseconds before subtraction. This retains fractional frame intervals across
frames: 120 updates over one second still advance one second. A long frame is
capped once; discarded wall time is not replayed on later updates.

`input/flight_controls.gd` is the remake's event adapter. Route unhandled events
only while flight owns input. Its default bindings are:

| Action | Keyboard | Controller |
|---|---|---|
| Pitch/yaw | W/S and A/D, or arrow keys | Left stick |
| Fire | Space | Right trigger |
| Missiles | R | Left trigger or B |
| Boost | Shift | A |
| Pause | Escape | Start |
| Time action | T | Back |
| Autopilot | P | Y |
| Dock | E | X |
| Throttle increase/decrease request | Equals / Minus | D-pad up / down |

These are native remake bindings, not recovered original keyboard/controller
preferences. Deadzone and pitch inversion are configurable. The most recently
active controller owns its axes/buttons; resting events from another device do
not take over. Disconnects and focus loss clear held controller state. Keyboard
holds remain independent, so releasing one device does not release another.

Touch command/action APIs support the same actions, including Pause, Time,
Autopilot and Dock. The touch preference defaults off on desktop and on for
mobile builds. Hiding touch controls clears held and queued touch input while
preserving keyboard/controller input. Native touch panels and saved preference UI
are still to be connected; no flight buttons are currently shown by the inspector.

`simulation/flight_driver.gd` composes controls, clock and ship-bound pilot motion.
`configure(...)` requires explicit content, catalogue ship/equipment/upgrades,
sensitivity and an initial proper flight pose. It does not choose a mission,
starting ship or location. `accept(event)` queues valid flight inputs;
`step(now_microseconds, throttle)` returns the pose, selected elapsed time, pause
state and action requests. Throttle remains an explicit normalized value until
the source throttle-control behavior is integrated.

Pause owners are independent: `user`, `focus`, `modal`, and `cinematic`. A caller
must request a freeze explicitly; a timed radio message is not a pause owner.
Removing one reason leaves other active reasons intact. Every transition rebases
timing and clears held/queued commands, so acknowledging a modal or returning
focus cannot fire an old press or replay paused time. `set_focused()` additionally
disables event input while unfocused. A simultaneous unpause and action press is
consumed without dispatching that action.

Only the pause request is executed by this driver. Other buttons return requests
and held state for their eventual gameplay systems; they cannot dock, change time,
shoot, award items or advance a mission on their own. Source time overrides,
special response/cargo modes, combat, docking, autopilot, mission-specific freezes,
camera/scene composition and GUI input ownership still need integration.

```bash
godot --headless --path game --script res://tests/flight_driver.gd
```

Optional content/binding pairs exercise v11 packs. Native checks use real Godot
input-event objects and cover keyboard/controller/touch routing, controller
ownership, release/disconnect, touch visibility, inversion/deadzone, action edges,
frame cap, high-rate clock precision, nested pauses, focus return and commands
reaching native motion. This is headless driver validation, not physical controller,
mobile-device or original-game pacing validation. The main scene still opens the
asset inspector; an authored playable flight scene remains unfinished.

## Ordinary NPC flight

Reader v45 recovers ordinary NPC turn and bank tuning independently from either
base edition. `simulation/npc_flight.gd` advances one explicitly configured ship
in source coordinates. An encounter controller supplies a desired world direction,
nonnegative speed in source units per millisecond, integer elapsed milliseconds,
and separate steering/travel permissions. This component does not choose targets,
speed changes, close-range avoidance, random straight-flight intervals or dodges.
The separate fresh-opening guidance component now supplies direction, speed and
steering decisions for the three source enemies. See [combat support](COMBAT.md)
for its player-only target scope and remaining scheduling work.

Heading changes gradually using the source normalizer and binary32 operation
boundaries. A strict L1 threshold snaps a sufficiently close heading to the desired
direction. Banking uses five turn-angle samples, including the source warmup rule
that excludes the newly written sample until the buffer wraps (the first sample
is used immediately). Bank response is bounded and moves toward its target at the
imported rate. Disabling steering resets that history and returns the bank toward
level while preserving independent forward travel.

Travel truncates speed multiplied by elapsed milliseconds to a whole source unit
before applying the new forward axis. Fractional distances do not accumulate across
frames. Zero-time updates can still snap the heading or update bank history but do
not advance travel or bank response. The unbanked root pose is retained separately
from the banked visual/combat pose, so roll cannot feed back into heading updates.

`source_vectors.gd` shares the verified binary32 normalization and arithmetic with
ordinary projectiles. Configuration requires a finite, unscaled initial pose.
Invalid input, numerical overflow and degenerate output axes fail atomically;
frame copies and snapshots do not share mutable history. These checks establish
native numerical behavior against static source evidence, not full enemy AI or
observed in-game parity. The opening application still stops before combat.

```sh
godot --headless --path game --script res://tests/npc_flight.gd -- CONTENT BINDINGS VISUALS
```
