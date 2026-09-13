# Mining development status

Current Mac bindings connect the application's first two mining trips: station
departure confirmation, original world and briefing, asteroid selection,
guided approach, drilling, cargo collection and the return to Var Hastra.
After the first station conversation, choose Depart and confirm. The cargo
objective opens acknowledged instructions before station return becomes valid.
The returned station's five lines end with a cargo reset and the next 25-ton
objective. Choose Depart again for the second trip. Its one-line briefing and
two full-hold warning lines use the original recordings. The pirate's source
appearance and combat continue during the return to Var Hastra.

The shared native world and renderer also support the prepared second mining
trip with current Mac bindings. Its retained pirate, ordinary projectile
contacts, field, drill, full-hold warnings and authored appearance run in one
prospective flight transaction. Original pirate hull/lights, engine, explosion
and cargo-container models are connected. Reader v112 adds the second station
return and its six acknowledged lines. The application now connects that path
with current v115 Mac packs and prepares combat/death audio before presenting
each accepted frame. Final station acknowledgement removes cargo rows while
retaining the source's deferred cargo cache (25 used, zero free). Current v116
packs then support mission 158's starter equipment shop. The first accepted
inventory operation refreshes the cache from owned items. Mounting a weapon and
armor plate unlocks Gunant's acknowledged completion line, without granting
credits. The combat-training flight remains unfinished; see [equipment scope](EQUIPMENT.md).
Older packs keep their earlier application boundary.

Lethal second-trip contact retains existing movement and drilling, hides the
ordinary HUD, and runs original particles, explosion, sound and game-over display.
After the full fade, Enter, Space, controller A/right trigger, click or touch
returns to the existing remake launcher. A held fire input must be released
before acknowledging. The original main menu and its music remain unfinished.
This exit does not heal, load a save, change cargo or advance the campaign.

| Action | Keyboard | Controller |
|---|---|---|
| Steer / keep the drill centered | WASD or arrows | Left stick |
| Start mining / cancel approach / stop drilling | E or Space | X or right trigger |
| Select / cancel station autopilot | P | Y |
| Change throttle | + / − | D-pad up / down |
| Next / previous instruction | Enter / Left | A / B |
| Pause | Esc | Start |

Flight action buttons follow Touch controls and are hidden by default on desktop.
Touch steering also controls the drill; Mine/Stop handles its current action.
Cancel mining before selecting the station, and cancel station autopilot before
starting another asteroid approach. Briefing and cargo instructions freeze flight
while their original speech continues; explicit pause also pauses speech and
combat/death audio. Focus loss and leaving the tab pause independently without accumulating catch-up time.

Application checks begin at an earned first return, mine and return the second
cargo under live pirate fire, and exercise the equipment boundary. Close asteroid
placement isolates drilling. A separate branch reuses the earned departure and
positions a lethal source projectile for death, pause, rollback and real viewport
continuation input. These are native fixtures, not an original-game comparison
or a complete tutorial playthrough.

Original engine/mining/acquisition sounds, flight music, collision response,
animated station
lights and wormhole interaction remain unfinished. The native source-bound
components and earlier verification history are described below.

The first mining world now includes Var Hastra's original exterior: its main
model, emissive layer and additive lights, placed and rotated from source data.
The lights currently retain their initial sample; their pulse animation remains
unfinished. The source collision record supplies seven boxes, with strict edges
and a broad phase derived from the combined model bounds. Flight reports the
current containing volume without treating proximity as a completed station visit.
Reader v102 adds a separate station-guidance component. It reuses mining steering,
adds the five-sample turn filter and source bank response, and keeps the chase
camera target separate from the visible bank. Cancelling retains the ship pose,
bank and sample values while resetting the history cursor. Reader v103 connects that guidance to the live first-flight controller.
The v104 return capability connects docking and the return conversation.

The starter scanner considers the first four eligible asteroids inside the aim
window, then chooses the nearest of those. Its four-second catalogue duration
acquires an asteroid after 3,800 milliseconds. Moving the aim away loses the lock.
The original scan ring starts after 500 milliseconds and holds its final frame
on acquisition. Pausing or acknowledging a modal instruction advances no scan
time. Selection alone grants no cargo or mission progress.

Approach steers toward the acquired asteroid using the starter ship's handling
and existing cruise scale. Guidance uses effective handling before equipment and
pilot response scaling; the starter ship's gain is about 3.97955. The asteroid's
scale determines the stand-off distance;
the ship is never snapped into position. Close approach freezes the chase camera
and tilts the visible ship model independently of its physical position. Docking
stops the target's spin and waits for the source settling threshold. The flight
then creates the equipped drill without advancing it on the creation frame.
Cancelling before drilling restores camera updates and spin without consuming
the asteroid. During drilling, the stop action collects earned ore and consumes
the asteroid. Pause holds all these owners together.

The equipped drill supplies stability and extraction rate from the original item
catalogue. The four asteroid classes have four through seven rock layers, with
their original ring diameters. Steering uses signed square analog input. Drift
continues the flight's random stream instead of starting a new one.

Ore accumulates only while the drill point is strictly inside the current ring.
After 6,001 milliseconds inside that layer, the next ring becomes active; excess
frame time is discarded. Time outside the ring accumulates across the entire
attempt. Returning inside resumes drilling without refunding that time. The
original bar shows the remaining tolerance. Exceeding 2,500 milliseconds outside
fails the attempt and loses its ore. Finishing all seven layers produces a core.
Stopping early preserves the integer amount of ore already drilled.

The extraction planner limits the result to available cargo space, placing a
core before ordinary ore. The recovered hard-difficulty rule halves and truncates
partial ore before applying the capacity limit; fully extracted asteroids retain
their yield. Original ore/core IDs, including the special ore mapping, come from
the active content profile. A plan changes no cargo or mission state by itself.

The extraction transaction applies the plan to the first departure's actual
25-ton hold and retires the asteroid together. Full holds, failed drilling and
zero-yield stops still consume the asteroid. Mining creates no combat drop or
explosion. Repeated extraction and mismatched cargo/field histories are rejected.
The first-flight renderer hides the retired asteroid across later detail updates.

The native display uses 17 recovered image aliases from the registered original
interface atlas: alternating ring quarters, the ten-frame drill animation, core,
remaining-time bar and ore readout. Text remains native and crisp. Desktop uses
half the phone composition scale; resizing does not change the drilling reference
coordinates. The original mining hint is available in all 12 Mac languages.
The overlay adds no flight action buttons; the eventual flight input owner must
honor the shared touch-controls preference and retain keyboard/controller actions.

## Cargo objective and return instructions

The first mining mission checks total occupied cargo against ten tons. It does
not require a specific ore ID or count unfinished drilling as cargo. A due check
opens three original acknowledged lines: Gunant asks the player to dock, Keith
responds, then an instruction explains autopilot and docking. Two source recordings
play in English or German; the final instruction is silent. Desktop text substitutes
the caller's active key labels once. All 12 Mac languages use the shared portrait
panel, with compact desktop and larger scrollable phone layouts.

The final acknowledgement advances the story from the cargo objective to the
return-to-Var-Hastra mission. It preserves the hold and grants no credits. The
player still has to return to the station; the mining tutorial is not finished.

The source poll clock is held during departure and modal instructions. After
release, it resumes toward the strict 5,001-millisecond boundary. Unsuccessful
checks reset it to zero and discard excess time. This corrects the earlier
briefing implementation, which counted departure time toward its delay. On the
frame that opens completion dialogue, player motion and weapon contacts have
already updated, but the later controller/camera stages are held. NPCs and
scenery receive a zero-time world pass after that modal opens. Existing modal
frames likewise skip ordinary logic but retain these zero-time world visits.
Explicit application pause omits the whole frame. Navigation advances no world time. A manual
drill stop can satisfy a later due check; automatic extraction precedes the check
within the same accepted frame.

## Contributor integration boundary

`station_exterior_resources.gd` requires the actual supported mining construction,
matching content identities and the station's catalogue faction. It stages all
three models and the bounded `collision.bin` record before replacing its prior
state. Stored sphere centers are converted to engine axes and merged in source
layer order; the V4 vertex buffers already use those axes. Applying that conversion
to vertices again would rotate the station away from its collision volumes.
`first_flight_scene.gd` presents the assembly without adding a random draw or
changing cargo, time, mission progress or input ownership. Earlier packs retain
their previous supported scene.

`mining_targeting.gd` accepts the actual departure owner, source catalogue and
original scan geometry. Its field identity prevents selection from crossing into
a replacement world. `first_flight_frame.gd` samples aim during player movement
with the preceding camera, then projects the field using the current camera.
The complete prospective frame is rejected if any owner refuses the update.
The first-flight scene reuses the original center frame, reticle and scan strip;
the animation asset reader is shared with NPC scanning. Desktop art is half the
phone size; the gameplay scan window uses the actual viewport width.

This selection owner covers the two prepared mining fields. Special tractor
devices, mixed NPC target arbitration, asteroid information/distance panels and
acquisition sound playback remain separate work. Missing equipment
and debris emit source event IDs without granting an asteroid selection.

`mining_approach.gd` binds to the actual construction, field and acquired target.
It retains the source's local alignment state across cancelled attempts. The
flight's `start_mining` method expects a resolved mining action from its future
input owner; it checks released input, acquired target and available cargo space.
Approach replaces ordinary pilot movement. Camera, local model orientation,
per-asteroid spin and selection updates are prepared as one prospective frame.
Failed evaluation changes none of the accepted owners. After alignment and the
separate settling wait, `mining_session.gd` creates the actual owned drill. Earlier
v97 packs retain their explicit `drill_required` support boundary.

The controller reports source engine visibility and audio events; first-flight
engine effects and playback remain unconnected. Its motion scope is the first
ordinary, undamaged departure. Boost handling, collision deflection, general
visual banking and roll recovery are not established by this component.

`mining_session.gd` stages the drill, cargo, asteroid and continued random stream
together. Each drill update precedes scenery randomness; commands are latched
after the update for the following frame. Its optional `latch_command` argument
defaults to true. A flight owner whose later input pass is skipped can pass false
to keep the preceding control while drilling continues. This matches the Mac
exhausted-hull input gate: it does not imply pause, release or cancellation.
The live flight defers its command setter until after weapon contacts, so a
lethal hit on the same frame also preserves preceding drill input. Existing
drilling continues through its normal failure or extraction transaction after
death, and direct stopping remains available before the completed game-over fade.
Death's visual spin feeds back to the mining model without rewriting statistics.
Manual stopping resumes ship movement
on the next frame. Automatic completion or failure resumes ordinary movement and
camera updates on that same frame, using the retained throttle. A destroyed target
cancels before drilling and grants no ore. Exact damaged-target feedback and the
remaining player-update scheduling still need verification.

`mining_drill.gd` accepts the active catalogue, installed equipment and an asteroid
from the active field, plus fixed integer reference coordinates. Its caller must
first establish that approach and docking have completed. Optional body lifecycle
metadata rejects exhausted targets. Controls remain latched until replaced;
releasing a native control must explicitly supply zero. Each valid update accepts
the current shared random state and exposes its continuation. Pause consumes no
time or random draws. Copies and failed configurations preserve the current owner.

`mining_drill.configure_for_scenery` binds the drill to a live field after the
caller has verified docking. A geometric snapshot alone cannot authorize live
extraction. The field's opaque identity survives prospective frames, but not a
new world construction, even if the new field uses the same seed and content.

`flight_cargo.gd` prepares the verified fresh departure hold from the ship
catalogue. Other loadouts, capacity upgrades and save restoration remain separate
work. `mining_extraction.plan` remains a pure calculation. Its `evaluate` method
prepares detached cargo and scenery owners and a result receipt; the flight must
accept both owners together. Failed evaluation changes neither input. A matching
mining history prevents combining different prospective branches or applying an
old field to an updated hold.

The source marks a mined asteroid inactive with an exhausted-hull sentinel. The
native engine records an explicit mined state, retaining valid combat pool
history while bypassing zero-hull destruction. Retirement decrements the field
count once, stops subsequent spin and permits no combat pickup or random draw.
No mission completion, credits or achievements are inferred here.

`mining_panel.gd` reads the drill without advancing it. The baseline atlas choice
and native layout are explicit. Automatic source display classification, exact
original framebuffer composition, drilling audio and live input ownership remain
unfinished. Failure enqueues source notice8/text528; it does not require
acknowledgement or stop flight. The physics reference frame currently uses the
recovered ordinary Mac display scalars; legacy phone display modes are not claimed.

`flight_notices.gd` owns the first-flight timed queue. Starting approach adds
“Target: Asteroid”; cancelling adds “Autopilot Off”; a full hold reports its source
warning without starting approach. Failure is enqueued once after drilling ends.
Missing drill/tractor notices retain their source IDs and localized text. Only
these six notice types are supported here. Repeated pending text does not restart
a fade or add a duplicate. Each entry fades in and out over four seconds; the
source retirement boundary is 4,001 milliseconds and discards excess frame time.
Drilling holds and hides the queue; pause and modal briefing hold its elapsed time.

The notice panel uses original image1219 (baseline atlas region118), source white
or red text, and native fonts. The bar fits localized text and keeps its original
borders. Placement uses a native top margin while the complete original HUD
geometry remains unfinished. It adds no action button or acknowledgement. All six
notices are checked in all12 Mac languages on desktop and phone viewports. The
phone text/bar containment regression is covered by a layout check.

The drilling reader checks 61 bounded source spans; targeting checks 18 and
approach checks 26, the session checks 11, notices check 31 and the cargo objective
checks 36. They emit semantic declarations and provenance. Runtime code never
loads an original executable. Earlier v99 declarations remain unchanged; older
packs expose no inferred cargo-objective capability.
Linux headless checks cover timing, shared randomness, equipment, failure, partial
ore, cores and capacity. Linux OpenGL checks cover all 12 Mac languages and both
1280×720 desktop and 420×800 phone-sized layouts. These are simulated phone
viewports, not physical-device, original-runtime or completed-campaign checks.
Extraction checks also exercise the real first-flight field, 25-ton hold, failed
and partial drilling, replay rejection, branch isolation and subsequent flight
updates. Separate close inspection captures verify asteroid removal and rollback;
their test camera does not demonstrate player approach. Targeting checks cover
candidate limits, strict window edges, ties, timing, lost locks, retired bodies,
field identity, failed-frame rollback and source animation pixels. Close pilot
positioning in those captures is a test fixture, not the approach implementation.
Approach checks start near an actual source asteroid, acquire it through the live
scanner, and then use native guidance through docking and the drill boundary.
GPU captures verify the separate model tilt and frozen camera on desktop and
phone-sized viewports. Separate rotating fixtures verify individual spin control;
the first tutorial field's source spin vectors are zero. These checks do not
establish collisions, live input mapping or a completed mission.
Session checks connect the acquired asteroid through approach, drilling, early
stop, failure and full extraction in the live frame. The original panel is shown
in desktop and phone viewports. Checks cover the creation frame, command latency,
shared random order, a four-ton early stop, hard-difficulty two-ton partial yield,
core-first filling of the 25-ton hold, movement resumption and rollback. Campaign
progress and rewards remain unchanged. Further iOS work remains deferred.

`mining_objective.gd` consumes the real cargo and matching field only when the
flight's poll clock is due. It stages dialogue and acknowledged progress with the
rest of the frame. The renderer retains the same world when the return mission is
selected. A successful cargo check is recorded separately from acknowledgement
and station return. Live application input, clock/audio scheduling, docking is still required before exposing this sequence to players.

## Station guidance component

`station_autopilot.gd` requires the prepared first departure and its actual station
resource owner. `observe_manual(pose, angular_units)` supplies the preceding
ordinary movement response; `start(current_pose)` selects that station without moving the
ship; the optional pose accounts for intervening mining movement. `advance(milliseconds, pitch_units, throttle, paused)` receives the current
pitch response explicitly. It returns logical motion and local visual bank in
its snapshot. Only the owning flight controller may decide arrival or transfer
cargo and current vitals. This component does not resolve ship/scenery contacts,
apply late input/neutral response, or construct a station scene.

The Mac starter gain is approximately 3.97955, its scaled pilot response 25.59091,
and its bank limit 365.58447 source units. These have separate meanings. The
precision-sensitive owner requests binary32 rounding from the shared vehicle
resolver; existing callers retain their established behavior.

Verification includes independent trajectory and bank samples through forty
frames, history warm-up/wrap, mirrored turns, explicit pitch, zero-time and paused
updates, strict near-distance timing, detached snapshots and cancellation. Four
GPU views use a synthetic initial pose and inspection camera in the original
mining world. These views verify the component, not an application docking run.

## Live station flight

Reader v103 connects station selection and cancellation to `first_flight_frame.gd`.
The native controller presents the preceding manual pitch/bank sample before
neutral return and input preparation. Active guidance performs one movement step
and ignores new manual steering. A preceding command can hold that axis on the
first guided frame; subsequent frames decay toward neutral. Opening a cargo
instruction retains neutral return and bypasses late pilot commands. The follow camera
continues to use the logical player pose independently of the model bank.

Mining approach contributes to the same five-sample turn history, including
zero-time guidance calls. Close alignment and drilling do not add turn samples.
Mining retains the preceding manual bank, and selecting the station afterward
uses the current position. Cancellation preserves the model, position, angular
response and stored samples, resets the history cursor/flag, and permits immediate
restart once an initial manual sample has been established. The next ordinary
frame resumes from the retained response.

Station selection queues the original localized target text and catalogue name;
cancellation queues the original off notice. The source mission-restriction text
is prepared for the future arrival check. Timed notices do not pause movement.
The API requires finishing or cancelling mining before station selection, and
cancelling station guidance before starting mining. General target-menu routing
and application controls remain unfinished. No action here docks, transfers cargo,
awards credits or completes the tutorial. Older packs retain their prior boundary.

Mac verification covers the complete first-flight owner, rejected frames and
modal/pause holds, input suppression, response continuity, mining-to-station
history and the actual follow camera. Eight inspected GPU images show flight
transitions and English/German notice layouts. All 12 Mac language compositions
and desktop/phone notice bounds pass; phone checks use simulated viewports.
The application now connects this controller through the first station return.

## First station return

Reader v104 connects the acknowledged delivery mission to docking. Station
selection and either the preceding player contact radius or the current authored
station volume are required. Initial mission 154 remains restricted; its notice
requires current volume contact. The accepted transition holds further flight
updates and preserves current hull, armor, shield, energy and the complete cargo
hold. Invalid identity or mining history cannot commit the transition.

The shared station scene presents five source lines with original portraits and
speech. Only the final acknowledgement clears cargo and selects the next
25-ton objective at cursor 4. It gives no credit reward or completed-tutorial
status. Native checks include acquisition and extraction from an authored
asteroid, the guided trip back, radius timing, modal/pause holds, damaged vitals,
all 12 languages and inspected desktop/phone views. Initial asteroid placement
and isolated boundary/vital cases are disclosed test fixtures. The application now connects this trip and its acknowledged speech. The second
trip and remaining flight sound owners are unfinished.


## Second-trip story components

Reader v110 adds the source briefing and full-hold warning to the existing native
mining owners. `MiningBriefing.configure` and `MiningObjective.configure` select
the prepared departure's cursor. The source 7,001-ms entry release, held poll
clock and acknowledged modal behavior are shared. The second briefing has one
line; 25 tons of total owned cargo offers the two-line pirate warning. Its final
acknowledgement selects cursor5, mission11 at Var Hastra. Cargo is preserved;
credits, station arrival and completion of the full tutorial are not granted.

The shared portrait panel, audio-resource owner and speech player accept an
optional `campaign_cursor` on their mining configuration methods, defaulting to2.
Pass4 for the second trip. All12 Mac text languages and English/German source
recordings are checked. Component captures verify compact desktop and larger
phone layouts; they do not show a complete second-flight scene.

The starter carries a mining drill and scanner, with no tractor beam. General
wreck recovery belongs to later equipment support. The live flight/application
boundary still excludes the second trip until the player-death transition and
application transaction are connected. Reader v111 adds the detached
authored pirate placement after the full-hold warning, preserving an existing
encounter and its death/cargo state. See [combat scope](COMBAT.md).

## Second-trip phase composition

`full_hold_encounter.gd` retains the prepared pirate's combat, guidance, weapon,
death and projectile/impact owners. `first_flight_frame.gd` stages current player
motion and existing-slot contacts, then the one-time mission cue and camera,
then the ordered NPC/scenery pass. Geometry detail uses preceding NPC roots and
the previous renderer reference in the earlier weapon phase. A newly fired shot
keeps its launch position until the next ordinary weapon update. Every later
rejection discards the complete candidate, including damage, clocks and RNG.

The cargo objective uses only owned cargo. Its final acknowledgement selects
cursor5/kind11 without arriving at the station, healing the pirate or paying
credits. The following logic frame applies the authored pirate cue. Rendering
uses the retained statistics pose, while flight and death keep the physical root
and bank separately. The engine child has its own visibility flag; disabling it
does not remove a tumbling hull. A retained container can draw independently of
the actor's activity. Source cargo-collection activity flags do not gate drawing.

Focused Mac checks cover live drilling, modal clocks, moved-player contacts,
NPC-before-scenery random allocation, cue placement, failure rollback and original
model rendering. Close camera/player placement and lethal inputs are explicit
fixtures. They do not establish a complete second-trip application playthrough.

## Second station return

Reader v112 adds the cursor-5 return at Var Hastra. The shared docking owner
requires the acknowledged full-hold objective, matching earned cargo and station
selection. Arrival captures the current player pools after weapon contacts and
holds the remaining camera, NPC and scenery work. The station retains those
pools, equipment, progress and cargo throughout its six original lines. Five
recordings accompany the conversation; the final equipment instruction is silent.

Final acknowledgement selects cursor 6 and mission 158, which requires the
station equipment tutorial. It removes every cargo row while preserving the
source's cached used/free quantities at this exact transition. The station marks
that cache stale; a later inventory operation must refresh it. No equipment,
credits or tutorial completion is granted. Until that service owner is connected,
the native station reports `station_equipment_required` and refuses departure.

The shared station speech and panel return methods take an optional return
cursor, defaulting to 3; pass 5 for this visit. Focused Mac checks cover a native
41.8-second guided return under pirate fire, retained current vitals, failed
arrival rollback, cargo lifetime, all 12 text languages, English/German voices
and compact desktop/larger phone component views. The starting mining placement
and damaged initial pools are disclosed fixtures. Older Mac packs retain their
previous boundary. This is not a full second-trip application playthrough.
