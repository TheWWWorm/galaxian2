# Resource declarations

Original bundles contain resource ID/path declarations outside the standalone
catalogue files. The optional desktop preparation tool statically reads recognized
declaration structures from the iOS ARM32 or Mac x86-64 executable. It never runs
that executable, follows game control flow, or translates game routines into
runtime scripts. The native engine receives JSON data only.

Reader v111 adds optional Mac `full_hold_appearance`: the one-time cursor-5
pirate placement and activity changes. Fifteen guarded spans bind the controller,
model factory, placement, activation, effect trigger and constants. This requires
the second-trip story and destruction capabilities. All v110 declarations remain
unchanged. Native ownership preserves physical and banked statistics poses,
health, cargo and lifetime state, including an already exhausted actor's source
death restart. Complete second-flight world/application integration remains open.

Reader v110 adds optional Mac `full_hold_story`: the second mining briefing,
25-ton cargo requirement, two acknowledged pirate-warning lines and cursor-5
return mission. Ten guarded source spans bind dialogue, voices, next mission and
shared acknowledgement/entry behavior. Every v109 declaration remains unchanged.
The shared native briefing, objective, portrait panel and speech owners select an
explicit departure cursor. Complete second-flight world/application integration
remains unfinished; v111 adds the separate authored pirate placement capability.

Reader v109 adds Mac-only `full_hold_destruction`, with twenty guarded source
spans for retained pirate cargo, its container model, per-update drift, strict
cleanup clocks and the shared kill-counter context. The shared destruction and
NPC controller now support the second-trip pirate. Statistics and hull transforms
are retained separately, including the source's pre-motion statistics copy.
Previous v108 declarations remain unchanged. Collection/tractor behavior,
container rendering and the complete second-trip application remain unfinished.

Reader v108 adds Mac-only `full_hold_control`, with sixteen source spans for
player-only targeting, held-state activation and ordinary NPC control. The shared
guidance/controller/flight owners now update the second-trip pirate. The earlier
strict 25,000-unit proximity path can enter flight immediately; the later strict
50,000-unit held-target path defers flight until the next update. An explicit
alternate player position feeds the proximity branch separately from weapon
range. Earlier v107 declarations remain unchanged. The v109 capability adds
cargo-bearing death; collection and mission/application integration remain open.

Reader v107 adds Mac-only `full_hold_pirate`: rank/difficulty hull values,
ordinary primary weapon settings and separate activation declarations. Twenty-four
source spans guard the factory, current/max pools, constructor health sample,
weapon setup and activation paths. Earlier declarations remain unchanged. Shared
combat/projectile owners can prepare the detached pirate and resolve its shots
against the second-trip player. The v108 control capability adds targeting and motion; v109 adds retained
cargo destruction. Collection and mission progression remain unfinished.

Mac Opening guidance now takes its initial health sample from the verified combat
body. This corrects the historical rank-one fallback without changing imported
legacy declarations. Existing iOS guidance behavior is preserved and deferred.

Reader v106 adds Mac-only `full_hold_flight`: the second mining world's ordinary
location, one pirate, retained generated cargo and route, and ordered weapon
effects. Fourteen additional source spans bind this context to the shared native
constructors; v105 declarations remain unchanged. World preparation now includes
the pirate's random draws before placing the camera. The separate v107 capability
adds combat preparation; activation and mission dialogue remain unfinished.

Reader v105 adds Mac-only `full_hold_departure`: the second mining departure's
source confirmation, cleared player pools and 25-ton mission context. It requires
the first departure and acknowledged station-return capabilities, verifies nine
additional source spans and emits only values and extents. All v104 declarations
are preserved. The native station/player owners prepare this departure. The
world uses the separate v106 capability; the live encounter remains unfinished.

Reader v104 adds Mac-only `station_return`: first-mining docking gates, current
player-pool caching, five return-dialogue records and the next mission's cargo
reset. Thirty-nine static source spans bind these declarations. The capability
requires the live station flight, cargo objective and station presentation;
unsupported layouts emit no return capability. Earlier v103 declarations remain
unchanged. Arrival preserves cargo; only the final station acknowledgement clears
it and selects the next full-hold objective. This does not complete the tutorial.

Reader v103 adds Mac-only `station_flight`, connecting ordinary movement samples,
station guidance input policy, shared mining turn history and original notices.
It requires the validated first flight, station exterior, guidance and notice
queue. Twenty static source spans bind these declarations; unsupported layouts
emit no capability. All earlier v102 declarations remain unchanged. This capability
does not declare arrival, cargo transfer or a completed docking transition.

Reader v102 adds Mac-only `station_autopilot`: guidance and bank parameters for
the actual first-mining station. Static checks bind the effective handling getter,
separate pilot scaling, bank history/slew, local visual matrix and logical camera
target. It requires the first flight and station exterior; unsupported layouts
emit no guidance capability. No executable bytes enter the runtime, and this
capability does not declare docking or collision avoidance.

Reader v101 adds Mac-only `station_exterior` for the first mining location. Its
source-bound declarations select Var Hastra's three model layers, station pose,
collision layout and ordered sphere-bound parameters. The native reader loads
authored volumes from the original resource; executable bytes never enter that
runtime. The capability requires first-flight construction and does not declare
light animation, autopilot or a completed docking transition.

Reader v100 adds Mac-only `mining_objective`: the ten-ton total-cargo predicate,
resettable poll timing, three acknowledged return lines and source voice mappings.
The final acknowledgement selects the return mission without granting credits or
removing cargo. Source extents and the earlier briefing, presentation and desktop
text capabilities must match. Unknown layouts emit no objective capability; no
completion is inferred from elapsed drilling time. See [mining scope](MINING.md).

Reader v89 adds Mac-only `station_entry`: the first station loadout, 19 ordered
conversation records, acknowledgement and next-mission declarations. The native
state owner accepts a completed rescue packet; station presentation and application
entry remain unfinished. See [first station scope](STATION_ENTRY.md).

Reader v88 adds Mac-only `arrival_session`: scene-clock initialization and
advancement, the radio's clock input, the constructed player target and NPC list
selection. It requires the existing rescue staging, motion, world and Opening
handoff capabilities. The native application now replaces the completed Opening
with a prepared rescue scene and stops at unfinished station entry. See
[rescue support](RESCUE.md) for its verified scope.

Reader v87 adds Mac-only `opening_handoff`. The native session can prepare a
detached entry packet after all Opening transmissions and actor deaths finish.
It carries the actual cached ship values and verified death-accounting totals,
then recalculates the next flight's rank. With three player-credited pirates,
the rescue score is 10 and rank is 1. Preparing entry leaves the old scene intact
and grants no mission reward. Earlier packs gain no inferred handoff capability.

The packet also establishes the fresh retained location and empty companions.
A bound on the three pirates' possible reputation changes establishes a neutral
rescue actor; it does not yet provide exact reputation values for a persistent
campaign. Other travel, mining, trading, hiring and save-loaded states remain
outside this Opening-only path. Mac rescue integration uses this packet; station
entry and the persistent campaign remain unfinished.

Reader v86 adds `arrival_world_initialization`. The Mac rescue draws its field
center after the station count, then reseeds before placing scenery. It constructs
one actor, retains cargo, assigns default weapon item 0 followed by item 25, and
preserves four effect-orientation draws for each assignment. Item 25 uses effect
mesh 14606; its weapon kind remains 0. A weapon item ID is not its kind.

Native initialization shares the existing field, NPC and effect algorithms. Its
caller supplies the matching restored player cache, ordinary location and empty
companion state. There is no independent free-roam setting in this condition:
the source predicate tests whether the campaign cursor exceeds 44; rescue cursor
1 is below it. The old `requires_campaign_mode` JSON label is retained for pack
compatibility. Native callers no longer supply the misleading `free_mode` flag.
The v87 handoff provides this context for the supported Opening. Further iOS
validation is deferred.

Reader v85 corrects `arrival_staging` visibility. The authored false flag targets
the last attached engine mesh, resource 18030, rather than the entire ship.
`actor_model_draw_enabled` is true and `actor_engine_draw_enabled` is false.
New source proofs cover child attachment, instance lookup, drawing gates, model
defaults and preservation of the engine attachment through detail construction.
Older packs remain readable, but native rescue staging, construction and motion
require the corrected declarations. Packs claiming v85 reject the old values.

The shared ship renderer accepts rescue poses and retains the hull and light
layers while the stopped engine effect remains absent. Whole-model activation
does not enable that effect. Sun and ordinary station lighting also accept the
restored rescue cache through the shared native implementations. These are
rendering components; complete world and application ownership remain unfinished.

Reader v84 adds `arrival_actor_construction` for the rescue actor's factory
records. Both source profiles generate a random spawn, patrol, cargo and breakup
fragments in that order. The authored rescue keeps the cargo, replaces the patrol
with two non-looping points, and places the actor at its authored coordinates.
Placement copies the body transform into statistics. The fresh body basis and
model-local transform are identity, with unit scale.

The shared native construction owner accepts the matching restored player cache
and an explicit RNG state immediately before the NPC factory. It preserves the
discarded random work and returns detached records and motion initialization
poses. Invalid input cannot partly create an actor or consume the caller's RNG.
With v86, the shared Mac world builder supplies the preceding RNG boundary.
Remaining actor combat statistics, faction/target decisions and a playable rescue
world are unfinished. Older packs have
no inferred construction capability; an explicit empty capability remains valid.

Reader v83 corrects the fresh opening's NPC hull data. Flight entry recalculates
rank before constructing the world: zeroed fresh counters select rank 0, so the
factory base is 20 at campaign cursor 0. The earlier reader used the temporary
new-game rank default of 1 and base 34. New bounded proofs cover the recalculation,
rank thresholds, counter resets and ordering before world construction in both
editions. Existing prepared packs remain readable for inspection; combat rejects
the outdated hull declaration with a request to prepare bindings again. Packs
claiming v83 must contain the corrected proof when hull support is present.

Reader v82 adds `arrival_actor_motion`: constructor mode/activity, the script's
mode-five selection, early body/model-to-statistics synchronization, the inactive
route gate with a target list, and strict activation bounds. Both editions use a
50,000-unit half-extent at this location. Activation enables model drawing
and statistics activity; it does not enable the attached engine effect or
re-enter ordinary movement in that update. Scripted body overrides preserve the
shared NPC flight owner's banking history.

The native motion owner requires matching constructed, unscaled poses and an
explicit world decision that mode five and the target-list route branch remain
selected and the actor is nonhostile. Earlier hostility checks can select another
mode, and hostile mode five has a separate visibility branch. The owner rejects
those contexts instead of choosing a disposition. Target eligibility and the
resolved relative position are explicit inputs. This does not implement the full
NPC factory, faction/target decisions, combat or rescue world. Older packs have no
inferred motion capability, and an explicit empty capability remains supported.

Reader v81 adds `arrival_environment`: ordinary system sky selection, the current
planet's near texture, and its full constructor size at rescue entry. Its bounded
source spans join the existing sky, planet, staging and player-cache declarations.
Missing or changed layouts remain explicitly unsupported. The native resolver
requires the matching restored rescue cache and edition-local catalogues. The sky
and planet renderers share their geometry, shaders and camera handling with the
opening. Older packs remain readable but cannot supply this rescue environment.
Sun rendering is now shared with rescue; field and complete rescue-world adoption
remain separate work.

Reader v80 adds `opening_actors.player_initialization.flight_cache` for the fresh
opening-to-rescue lifecycle. It verifies entry restoration, ordinary ship cache
refresh, the opening's temporary hull override, and the source gamma reset context
in each edition. Only values and provenance extents enter runtime packs.

The native player owner keeps its live opening hull separate from the ordinary
ship cache. Rescue initialization restores nonnegative cached values, preserves
zero, clamps armor and binary32 shield to their capacities, and raises maximum
hull when the restored hull requires it. This verified location resets gamma to
100 on entry. The cache then contains ordinary ship capacities for the next
transition. Snapshots are detached and bound to content, bindings, ship, ordered
equipment, location and scene. Older or unsupported packs cannot initialize this
rescue state. Outgoing travel/docking cache writes, saves, radiation environments,
later quests and actual world/application handoffs remain separate work.

Reader v79 adds `arrival_staging`, containing the source rescue actor declaration,
route points, visibility controls (corrected in v85), player position/model rotation, scripted
and frozen player flags, engine-stop cues, fixed camera parameters, approach/tumble
rates and two five-second fades.
Both editions use one ordinary actor, kind 3 and hull 30, with the same authored
placement. Recognizers are anchored to the verified staging declarations and
require the shared actor, motion and rescue-radio capabilities. Changed or absent
layouts produce an explicit unsupported capability; runtime packs contain values
and provenance extents only.

The native rescue choreography accepts the actor's statistics position and body
pose separately. It emits prospective body movement and camera/model changes,
preserving binary32 arithmetic and per-frame angle quantization. The final radio
event requests a fade; only its later expiry produces `station_transition_required`.
No campaign cursor, quest completion or reward is applied. Fade arithmetic is
shared with the opening escape. World construction, NPC mode/route behavior,
complete player lifecycle and application handoffs remain required
before this constitutes a playable rescue scene.

Reader v78 adds `arrival_dialogue` for campaign cursor 1: three original rescue
transmissions, their source time/dependency gates and source-selected voices.
The bounded reader follows dispatch slot 1, verifies the shared opening record
constructor, timing and declaration exit, and recognizes iOS's separate final
record store. Only data and provenance enter the pack. Missing or changed layouts
remain unsupported; older packs gain no inferred rescue capability. Shared native
radio components accept an explicit scene selector. The rescue world and scene
handoff remain unfinished; see [rescue speech](AUDIO.md#rescue-speech-preparation).

Reader v77 adds `vehicle_response.audio`: independently verified player-engine
selection thresholds, ship-specific overrides and source control indices. Its
provenance joins the existing handling and manual-motion declarations. The Opening
session uses these declarations for its retained player engine, source envelopes
and native stereo spread. Playback uses the existing v77 pack format. See
[Audio](AUDIO.md) for the connected scope and remaining mixer limits.

Reader v76 adds `opening_dialogue.voice`: the original voice IDs for the 23
opening text rows, once-only delayed display ownership and English/German speech
selection. Fifteen Mac and sixteen ARM extents bind the selection, source text
getter, 1,504-row lookup table, playback call, completion path and language setup.
The existing source timing and text-language declarations must agree. Only the
23 selected IDs are emitted; actor-dependent lookup fallbacks and other campaign
voice owners remain unsupported. A source entry of -1 stays silent. The native
reader checks each selected ID against that edition's FEV event catalogue.
See [opening speech](AUDIO.md#connected-opening-speech).

Reader v75 adds `weapon_parameters.audio`: the independent per-edition 233-entry
player sound table, NPC kind table, ordinary launch gate, sound-entry limits,
midpoint-price and duplicate selection, launch position and equipment pitch rule.
Twenty-six Mac and twenty-five ARM spans bind these declarations to source
installation, firing and dispatch owners, the existing price layout and the
existing weapon interval getter. The source's sorted-copy index behavior is
preserved. Unknown layouts produce an empty capability; missing table entries
remain -1. The native ordinary primary and opening NPC owners consume this data.
Other weapon kinds and generic NPC encounters remain outside the connected scope.
See [weapon audio](AUDIO.md#connected-ordinary-weapons).

Reader v66 adds `opening_staging.escape_camera`: fixed-target refresh rules,
three ordered look-shake draws, the shared 48-bit random generator contract and
the selected shake scale. Thirteen bounded extents per architecture connect the
fresh camera defaults, fixed/cockpit selectors, ordinary-time gate, pan refresh,
look target and random helpers. Both profiles select scale 1.0 despite different
table ordering. The scope does not support transient eye shake, cockpit or extra
roll. Original executable bytes are discarded; runtime packs retain declarations
and offset/length provenance. The native timeline can explicitly join the v65
choreography while the application's presentation boundary remains unchanged.

Reader v65 adds `opening_staging.escape`: source radio gates, per-update cruise
slowdown, camera/effect timing, model rotation and environment resource cues for
the fresh postcombat sequence. Both architecture readers validate their code and
literal-data spans before emitting declarations. The choreography has standalone checks; v66 adds native world/camera integration.
Presentation integration remains unfinished.
See [opening escape](OPENING_ESCAPE.md) for the precise boundary.

Reader v64 adds `opening_staging.npc_scanner`: source equipment/property keys,
profile-specific viewport divisor, fresh selection/timer defaults, near-box extent,
marker aliases, and image 1110's explicit animation atlas/region. Eighteen Mac and
eleven ARM bounded static extents establish these declarations. The importer
requires verified fresh NPC hull/flags/construction and retained player aim;
unknown layouts emit an empty capability. Runtime data contains values and byte
extents only. It cannot execute source instructions. Older packs retain their
existing capabilities without acquiring guessed scanner support.

Reader v63 adds `opening_actors.npc_initialization.hull` for the fresh opening
population. Reader v83 extends its proof to 23 Mac and 21 iOS bounded spans,
including flight-entry rank recalculation, cursor and subtype gates, difficulty
arithmetic, initial/current/maximum hull and integer percentage calculation.
The corrected imported base is 20 at fresh entry rank 0, cursor 0;
the native actor applies the supplied difficulty and the authored current-hull
override. This scope requires the verified fresh world and its `[2,23,2]` hull
population. Unsupported layouts remain empty; older packs receive no inferred
maximum hull. Only normalized values and source extents enter the pack. See
[fresh NPC hull capacity](COMBAT.md#fresh-npc-hull-capacity).

Reader v62 adds `opening_staging.player_aim`: projected-forward distance,
per-update weights, initial aim/contact state, contact expiry and original reticle
image/atlas IDs. Bounded static recognizers cover 20 Mac and 17 iOS declaration
spans, including the player update, constructor, contact setter and bulk image
alias records. The capability requires verified player flight, motion, impacts
and perspective. Only constants and provenance extents enter the pack. Unsupported
layouts remain explicit and older packs acquire no aim capability. See
[ordinary opening aim](COMBAT.md#ordinary-opening-aim-and-reticle).

Reader v60 adds `opening_staging.projectile_visuals` for the fresh item-2 player
and item-19 NPC weapons. It binds their travelling mesh IDs, camera-facing kind,
lifetime shrink threshold/divisor, hidden-position sentinel, explicit reduced
billboard scale and shared looping animation policy. Each edition has 25 bounded
recognizer spans linking the existing staging owner to the weapon factories,
wrapper, animation mode and draw path. Constant-table reads remain section-bound.
Only values and provenance extents enter packs. Changed layouts remain unsupported;
older packs acquire no projectile graphics. Travelling models are distinct from
the previously retained impact-effect IDs and random flips. See
[projectile presentation](COMBAT.md#opening-travelling-projectile-presentation).

Reader v59 adds `opening_staging.player_flight`: zero initial angular response,
ordinary throttle, the phase-4 control handoff, living-hull primary permission,
player-primary-before-NPC weapon order, camera-before-fire/input timing and the
postcombat event-10 boundary. Separate compiler recognizers connect the fresh
staging, ordinary movement/response and primary equipment paths. The output holds
only declarations and source extents. Unknown or disconnected layouts remain
unsupported; older packs gain no ordinary flight capability. Native encounter
checks use this data explicitly; application controls remain gated. See
[motion scope](MOTION.md#ordinary-opening-player-frame).

Reader v58 adds `opening_staging.player_motion`: fresh scripted-flight enablement,
the open player update gate, throttle-independent forward travel, ordinary-motion
suppression and release after radio event 8 at camera phase 4. Bounded recognizers
link both editions' staging, player update, cruise constructor/helper and ordinary
player-before-weapons-before-controller order. Packs contain only flags, event/
phase values and source extents. Changed or disconnected layouts remain unsupported;
older packs gain no movement capability. See [motion scope](MOTION.md).

Reader v57 adds `opening_actors.npc_initialization.death_accounting`: initial
kill-source state, accepted-lethal attribution, hostile kind-8 death credit and
world/player/pirate counter deltas. Both compiler layouts are tied to the existing
guidance update, statistics constructor and ordinary weapon damage entry. Packs
contain constants and extents only. Changed or disconnected layouts produce an
unsupported capability, and older packs acquire no attribution or counter data.
No initial save totals, achievement state, mission result or reward is inferred.
See [combat scope](COMBAT.md).

Reader v56 adds `opening_actors.npc_initialization.destruction`: fresh kind-8
tumble and explosion modes, strict clocks, local spin, captured travel direction,
sound choices, model IDs and cargo-free retirement. Its bounded static compiler
recognizers are linked to the verified guidance update and construction scope.
Both supported editions emit constants and source extents only. Changed compiler
layouts remain unsupported; archive names and fixture hashes are not acceptance
rules. Native resources read animation ranges from the supplied AEM models.
Older packs do not gain a destruction capability. See [combat scope](COMBAT.md).

Reader v55 adds `opening_actors.player_initialization.repair`: ordered hull/armor
repair clocks, device type and source-ID selection, pulse sizes and maximum-hull
bindings. It links the player factory, statistics and ship constructors, clone,
equipment dispatch and the update directly following shield recharge. Both
timing tables and the ARM integer-to-float import are verified. The fresh ship's
base hull and empty upgrades are distinguished from its scripted current-hull
override. Missing devices remain absent, and earlier packs gain no repair scope.

Reader v54 added `opening_actors.player_initialization.recharge`: equipment
property 19, binary32 pulse calculation, strict elapsed threshold and ordinary
player-before-weapons ordering. It cross-checks equipment/capacity getters,
constructor clock/flag resets, the application frame anchor, world entry and
both architectures' divisor values. Unsupported layouts expose an empty
capability. The native fresh player resolves duration from its selected shield;
the world frame stages recharge before projectile contacts. Older packs retain
their prior behavior. Special-time, death and complete player lifecycle
ownership remain unfinished.

Reader v53 added `opening_actors.npc_initialization.hostility` for the fresh
kind-8 opening actors. It links the statistics/base constructors, fresh-game
override reset, ordinary NPC update and later flag getters. Actors start
nonhostile and refresh to hostile during their NPC update, including while held
and on zero-time frames. Native world contacts consume the retained preceding
state. Changed mission, faction, companion and saved contexts remain unsupported.

Reader v52 added `weapon_parameters.player_hit_policy`: nonhostile damage scale,
ordered special-flight multipliers, conversion precision and branch precedence.
It links to the existing ordinary hit route, validates the Mac constants and ARM
live multiplier registers, and rejects changed or disconnected layouts. Native
contacts require explicit current shooter and flight state. This declaration
does not establish complete player damage effects. With v53 hostility available,
the fresh world schedules these contacts before its cinematic and NPC passes.
Older packs retain their previous support without this automatic contact scope.

Reader v51 added `opening_actors.player_initialization`, containing the fresh
player's collision extent, active/player/damage flags and ordered equipment
capacity bindings. It cross-checks the existing NPC statistics constructor,
vehicle type/property table and opening staging anchors. Both architecture
readers verify shield and armor setters, zero defaults and increasing slot order.
Unrecognized layouts produce an empty capability. The native loader checks
parameters and source extents; no source instructions are emitted at runtime.

This reader is partial. It recognizes bounded record-initialization templates,
not every possible registration mechanism. A recovered declaration establishes
that an ID/path association exists in the source; it does not establish when it
is active, whether another unrecognized declaration overrides it, or which scene
uses it. Do not infer complete registration, rendering or campaign support.

## Prepare and inspect

Use the optional import environment described in the README, then install:

```bash
/path/to/gof2-import-env/bin/python -m pip install -r tools/requirements-bindings.txt
/path/to/gof2-import-env/bin/python tools/prepare_bindings.py "/path/to/game.ipa" "/path/to/imported/CONTENT_ID" --output "/path/to/private/bindings"
```

The source can also be an extracted Mac `.app` or app ZIP. Each edition works
independently. The tool checks every selected source resource against the imported
base before using its executable declarations. A second edition is not a donor
for the chosen edition's bindings. Direct DMG extraction remains unsupported.

Open the resulting directory's `bindings.json` with **Open resource bindings**.
In Assets, enter a numeric resource ID and press Enter to inspect its recorded
resource. Or pass `--bindings "/path/to/bindings/BINDING_ID" --resource-id ID`
after the normal `--content` and optional `--visuals` arguments.

Enter a **Ship catalogue ID** (or pass `--ship-id ID`) to inspect the resource
recorded in the edition's hull table. This is a base-resource lookup, not complete
ship assembly. Special ship overrides, attachments, lights and active registrations
remain separate work. Out-of-range IDs and missing resources produce diagnostics.

Multiple distinct declarations for an ID, resources absent from the base, unknown
registration types and IDs without a recovered declaration produce diagnostics.
Repeated identical declarations retain their provenance. No branch order or
filename heuristic chooses between conflicting registrations. The native lookup
returns only a unique, supported declaration from the recovered set. Scene usage
and active selection remain unverified even when that lookup succeeds.

Prepared bindings also supply mesh material IDs and material texture IDs. The
inspector uses those references for supported diffuse/normal-specular materials;
it also renders supported opaque, alpha and additive families and reports
missing/conflicting references and unsupported rendering modes.
With bindings open, it does not substitute filename guesses for missing material
data. Without bindings, the original provisional filename inspection remains.

## Content and identity boundary

Preparation creates two private JSON files: `registrations.json` with records and
coverage diagnostics, and `bindings.json` with hashes, architecture and sizes.
Records retain the numeric ID, raw registration type, original resource string,
normalized resource path and source file offset. Consecutive path separators are
collapsed for resource lookup; the original string is retained. Traversal, absolute
paths and unsafe path components are rejected. Executable bytes, instructions,
scripts, symbol tables and disassembly are never exported.

Reader `resource-registration-v2` adds optional `material_id` / `mesh_flags` fields
to recognized mesh registrations and a `materials` array in the data file. Each
material retains its ID, eight unsigned 16-bit texture IDs (65535 means no slot),
raw render-type enum, four unsigned 32-bit parameter bit patterns and source file
offset. Pointer fields are never emitted; only recognized null-pointer layouts
are accepted. Parameter semantics and rendering modes are not inferred from
their numeric values. The runtime still accepts v1 packs for resource inspection;
prepare a new pack to obtain material declarations.

Reader `resource-registration-v3` additionally retains texture registration
parameter bits, verified same-edition `texture_variants`, and a `ship_models`
object. Older v1/v2 packs remain readable with their original feature scope.

The Mac texture mappings require a shared declared ID, identical material
parameter bits, corresponding high/low paths, source hashes, matching aspect
ratio and proportionally identical atlas regions. Font and cube textures are
excluded. Compression formats and stored mip chains may differ, as they do in
the supplied source; both are decoded by the native texture preparation path.
In Assets, **High-resolution textures** / **Low-resolution textures** select these
verified pairs for materials. High is the default. This is a same-base rendering
preference; it neither changes gameplay definitions nor imports another edition.
The generic `resolve()` still reports ambiguous IDs; `resolve_texture()` applies
the requested quality to a verified pair. Other ambiguities remain unsupported.

The ship table stores unsigned 16-bit resource IDs indexed by catalogue ship ID,
with source offsets for table copies and the recognized index reader. Resource
name anchors locate candidates, then a bounded ID-getter/indexed-read template
must confirm the association. Names alone do not generate the mapping. Conflicting
copies fail recovery. The native reader checks edition-specific table size and
provenance extents. Raw table entries do not establish complete ship visuals:
some original ships use separate construction paths instead of the common hull.

Reader `resource-registration-v4` adds `hangars`: ten four-slot geometry rows,
extra mesh IDs per row, rotation, station overrides, a verified system-field
selector and source extents. Separate readers recover each edition's constants.
Resource anchors alone are insufficient: indexed access, catalogue getters and
the bounded selector layout must agree. No fallback selection is invented when
recovery fails. Older v1–v3 packs keep their earlier inspection features.

In World, double-click a station to preview its selected hangar geometry; in
Assets, enter a Station ID, or launch with `--station-id ID`. The native resolver
checks catalogue/base identity and every layer/child resource. The composer loads
required materials and textures before exposing geometry. Missing requirements
clear the preview and report a diagnostic. All 135 station records in each
supplied edition resolve to six populated source rows. This does not establish
which stations are reachable or reproduce special game-state scenes.

The supported material families use opaque rendering, source-alpha mixing,
ONE/ONE additive blending, and diffuse/normal-specular lighting. Transparent
families do not write depth. These blend states have source evidence and GPU
pixel checks; original lighting/shader selection and complete visual parity remain
unverified. Float vertex colors use a full-precision custom attribute. The native
unlit implementation of the simpler families and current inspection lights remain
provisional. Scalar animation channels are retained but their effect is not yet
applied; source clock and interpolation behavior also remain unverified.

Reader `resource-registration-v5` adds `ship_placement`: signed per-ship hangar
Y positions and table/accessor/getter source extents. Both readers require the
previously validated hangar declaration region, a catalogue-ID getter, signed
indexed conversion and the placement-call layout. They recover 64 iOS or 61 Mac
positions without substituting one edition's table for the other. Native placement
uses X/Z zero and the recorded Y. This verifies the placement data; hull orientation,
attachments, special construction and full ship assembly remain separate work.

The hangar inspector uses hull 0 initially and accepts another **Ship catalogue ID**.
When both `--station-id` and `--ship-id` are provided, the hull appears inside the
selected hangar. **Frame hull** and **Frame pose** inspect the hull or whole scene.
These selections never grant ownership, change a loadout or initialize a campaign.
Missing raw hull references still fail explicitly. Older v4 packs can inspect
hangar geometry without a positioned hull.

Reader `resource-registration-v6` adds `ship_lights`: two resource slots for each
catalogue ship, with original table and accessor extents. Recovery requires the
already identified hull table, matching indexed accesses, sentinel or mask checks,
and a shared attachment-call target. The Mac compiler's masks must agree with
every table sentinel; no branch bytecode or masks are exported as runtime logic.
The iOS and Mac tables are recovered independently.

The native scene parents each declared light mesh to its hull at the same local
origin. Separate slots can use the same mesh and remain separate instances, sharing
immutable geometry while keeping independent material state. These are emissive
mesh layers, not a reconstruction of the original scene lights. Engine-flame
geometry and LODs are not added as extra visible hangar layers. Their complete
behavior, special construction, attachments and animation remain separate work.

With the supplied v6 packs, missing light declarations prevent complete resolution
for hulls 42 and 43 in addition to the four unresolved raw hull IDs. The inspector
reports the specific missing layer rather than silently omitting it. Raw hull
inspection remains available outside a hangar. This is incomplete recovery, not
proof that the original content is absent.

Material lookup rejects distinct descriptors for the same ID, ambiguous texture
IDs, absent textures, wrong resource kinds and unverified mesh flags. Mesh-path
lookup also rejects conflicting or incomplete material references across the
recovered declarations. Material values stay edition-specific.

The binding identity hashes a versioned recipe containing the base content
identity, entire original executable hash, selected architecture and declaration
data hash. Different executable declarations cannot silently share an identity
merely because their resource files match. Existing base/texture caches remain
immutable. Future gameplay definitions and saves must include this executable-bound
identity when they consume these declarations; the current base-only reserved
save namespace is not sufficient for that future gameplay state.

The runtime checks the declaration data checksum and identity, resource path/kind,
record bounds and base identity before publishing the set. Failed opens clear the
previous set. Import cancellation removes staging output and preserves installed
packs. A forced process termination can leave an abandoned `.bindings-stage-*`
directory, which may be removed after confirming that the importer has stopped.

## Limits and validation

The supported executable envelope is a bounded Mach-O image (or a fat image with
one matching architecture slice), with unencrypted file-backed text and C-string
sections. Unsupported/encrypted layouts fail explicitly. Only small recognized
declaration windows are decoded; calls and branches are not executed. Capstone is
an optional import-time dependency for ARM instruction decoding, not a runtime
dependency. Mac templates are read with bounded byte patterns.

Synthetic tests cover malformed envelopes, truncation, changed template pointers,
source matching, cancellation, content identity and native lookup failures. The
material checks cover complete field assignments, both descriptor layouts,
payload/stack alias identity, malformed fields and conflicting texture graphs. The
two supplied originals were also imported separately and inspected natively.
The generated diagnostics identify incomplete coverage; they must not be treated
as proof that every remaining ID is absent from the original game.


Reader `resource-registration-v7` adds `cruise`: the ordinary forward scalar,
verified forward axis and bounded source extents. Constructor and reset constants
must agree, and the movement consumer must target the recognized forward helper.
Both supplied editions use the same rate, recovered independently. The runtime
validates the declaration before exposing it. Empty definitions and older packs
remain valid for their existing inspection features but cannot initialize cruise.
See [native motion and its verification limits](MOTION.md).


Reader `resource-registration-v8` adds the `manual_rotation` constants and source
extents used by native pitch/yaw rotation. It requires supported ordinary cruise,
a unique manual angular consumer, bounded constant loads, finite parameters and
a recognized rotation helper. Each edition is read independently; matching values
do not merge profiles. Old or empty definitions do not acquire guessed controls.
The native kinematic component consumes resolved angular units; input response
and handling modifiers are not part of this declaration. See `docs/MOTION.md`.


Reader `resource-registration-v9` adds elapsed-time `pilot_response` parameters
and source extents. It requires supported manual rotation, a unique recognized
integer target calculation and agreeing ramp/neutral declarations. Only constants
and provenance enter the JSON pack. The native response component requires an
explicit vehicle factor and sensitivity; source input modes, equipment effects and
saved preferences are not inferred from these constants. Missing or malformed
fields fail atomically; an explicitly empty definition retains earlier features.
See [pilot response and verification limits](MOTION.md#elapsed-time-pilot-response).


Reader `resource-registration-v10` adds `vehicle_response`: base handling
conversion, handling-upgrade tag/bonus, item-type positional binding, maneuverability
equipment selector/property, percentage divisor and response scale. Named source
extents cover each linked accessor, data reference and selection table. Both
architectures recover these independently. Mac's conversion remains distinct from
iOS's direct base rating. The native resolver can feed pilot motion without
assigning a starting ship or granting items. Empty/older packs retain their earlier
features. See [ship handling and equipment scope](MOTION.md#ship-handling-and-maneuverability-equipment).


Reader `resource-registration-v11` adds `frame_clock`: ordinary maximum frame
milliseconds, the millisecond time unit and source clamp/supplier extents. Multiple
clamp references and delta-call targets must agree. Native validation rejects
missing/malformed data atomically; explicitly empty or older packs retain their
previous features. It does not recover alternate time-mode overrides. See
[native controls and flight timing](MOTION.md#native-controls-and-the-flight-driver).


Reader `resource-registration-v12` adds `opening_loadout`: a ship catalogue index,
station index, seven equipment item/slot/quantity records, item-category array
binding and named source extents. Each architecture recognizes a bounded setup
declaration, links repeated equipment calls to the same category installer and
verifies the single-item/stack copy layouts. The category binding requires the
already recognized item-constructor layout in `vehicle_response`. Unsupported or
ambiguous layouts emit an empty definition. Missing/malformed fields fail native
pack loading atomically; empty and older packs retain earlier support.

`simulation/opening_loadout.gd` resolves the source station's system and assembles
slots in primary, secondary, turret and equipment order using the selected ship's
catalogue capacities. It preserves quantity and empty slots, rejects conflicts and
out-of-range assignments, and returns detached snapshots tied to both content and
binding identities. Its ordered occupied item IDs can configure the flight driver.
This is a loadout seed, not a new-game save or a playable mission: opening camera,
pose, objectives, event sequence, credits, damage and reward rules remain separate
work. No mission is completed and no reward is granted by this component.

Focused checks:

```sh
PYTHONPATH=tools python -m unittest discover -s tests -p test_opening_loadout.py
godot --headless --path game --script res://tests/opening_loadout.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
```

## Opening radio events

Reader `resource-registration-v13` adds `opening_dialogue`, independently read
from each edition's opening event list. The bounded reader checks dispatch slot
zero, all 23 assignments, the single/range constructors and radio timing layouts.
It emits localization IDs, speaker IDs, condition parameters and source extents;
original executable bytes are discarded. Unsupported or ambiguous layouts leave
this scope empty. Earlier packs remain usable without radio definitions.

`content/dialogue_definitions.gd` validates the imported schema atomically.
`simulation/radio_sequence.gd` is an independent single-speaker scheduler using
mission simulation time. Its supported conditions are elapsed time, a previously
started radio event, depleted hull for all selected actors, and an exact cinematic
phase. Missing actor state never satisfies the combat condition. Started and
finished flags are separate, snapshots are detached, and failed configuration
clears prior state. Base/binding identities and the selected language are checked.

Source radio display begins strictly after a 2,000 ms delay. The subsequent
interval is 1,500 ms plus 2,000 ms for each wrapped source-layout line. The caller
provides an explicit source layout or line counts; wrapping native desktop text
at a different width must not silently change mission timing. Native bitmap
metrics and imported aliases now derive counts for explicitly selected layouts.
Automatic source font/width selection remains unfinished; isolated scheduler
tests also retain synthetic line-count fixtures.
The scheduler does not present UI, play voice, acknowledge modal instructions,
advance the cinematic, complete a mission, award rewards or create saves.
With v76 declarations, the separate opening audio owner consumes accepted radio
display changes and commits the matching original voice after frame validation.

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_opening_dialogue.py
godot --headless --path game --script res://tests/radio_sequence.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
```

## Language glyph aliases

Reader `resource-registration-v14` adds `text_aliases`: 20 Unicode pairs and
source declaration/switch-table extents. Each architecture has a bounded reader
for its language-loader declaration. Ambiguous, malformed or unknown layouts
produce an empty scope. Only pairs and provenance are emitted; no executable
bytes or translated source logic enter the runtime. Older packs retain their
previous capabilities without inventing this field.

Native schema validation checks unique source characters, scalar values and
source extents. Layout configuration checks the binding's base identity and each
target glyph. Substitutions affect advances once, preserving the original string
for native text rendering. See [text layout and verification](TEXT_LAYOUT.md).

## Font declarations and atlas modes

Reader `resource-registration-v15` adds `font_bindings`: eight font records,
16 source language-index/file associations, font selection and spacing tables,
and three branch-linked atlas choices for seven texture IDs. File association
comes from the source language dispatch; string-table order is not assumed.
Each architecture has its own bounded record, dispatch and setup recognizers.
The emitted data contains no executable code or runtime source addresses.

Native validation checks record/selection references, unique IDs and filenames,
source extents and exact atlas registration/provenance matches. Atlas choices
remain within one base. `resolve_font` returns a selected resource, group and
spacing; `image_font.open_selected` checksum-verifies the resource and retains
base/binding/language identity. Older packs keep their earlier capabilities.

Source display mode remains an explicit input. Matching radio geometry, device
classification, speaker role selection and UI/mission ownership remain separate
integration work; see [text layout](TEXT_LAYOUT.md).

## Portrait texture declarations

Reader `resource-registration-v16` adds `portrait_textures`: 152 source-declared
IDs, filename stems, four explicit suffix variants and file-offset provenance.
Both architecture readers verify the bounded allocation, string concatenation,
record, payload and cleanup shapes. They read each authored ID and stem; filenames
and IDs are never assigned from directory ordering. Unknown or inconsistent
declarations leave the scope empty. Only data is retained in the pack.

`content/portrait_texture_definitions.gd` validates counts, IDs, paths, variants
and source extents before the native loader activates the pack. The resolver
`resolve_portrait_texture(id, variant)` accepts `baseline`, `expanded`, `medium`
or `large`. The choice is explicit: portrait display flags differ from font mode
selection and must not be inferred from the font mode number. Missing variants
report an error and never substitute another portrait or content edition.

Each supplied edition contains 602 of the 608 declared variant paths. Four
family-12 medium variants and two family-4 expanded variants are absent. Missing
paths are included in preparation diagnostics. Older packs remain usable with
their earlier capabilities. These declarations do not yet establish speaker
names, composite layers, portrait frame art or UI placement.

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_portrait_textures.py
godot --headless --path game --script res://tests/portrait_textures.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
```

## Speaker names and fixed portrait records

Reader `resource-registration-v17` adds `speaker_bindings`. Linked speaker
accessors, bounded name selection and the fixed portrait pointer-table grammar
establish the edition-local name offset, agent boundary and portrait records.
The reader copies five-word fixed definitions as data. It never executes source
initializers, procedural appearance generation or dialogue code.

`resolve_speaker_name(id, library)` uses the active base and language. Names
outside the supported lookup or selected string table report diagnostics. The
Radio inspector captures these names before starting playback and clears them
on content/language changes. Ordinary labels display Unicode literally.

`resolve_speaker_portrait(id)` returns a detached fixed definition. In each
supplied edition, 61 records are supported. Speaker 21 uses a procedural branch;
speaker 0 points to zero-filled storage whose final initialization has not been
verified. Both remain explicit and unavailable for composition. Authored-agent
and other procedural appearances are also separate work. These records describe appearances;
image aliases and layer placements are imported as separate scopes.

Native validation rejects malformed counts, ID sequences, parts, statuses and
provenance before activating the scope. Failed pack loads clear old speaker data.
Earlier packs remain usable without invented speaker declarations.

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_speaker_bindings.py
godot --headless --path game --script res://tests/speaker_bindings.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
```

## Image-region aliases and cropping

Reader `resource-registration-v18` adds `image_regions`: explicit type-3 image
records and one bounded alias range for the portrait parts. It preserves differing
declarations for the same numeric ID. The supplied iOS source yields 281 explicit
records; Mac yields 203. Both define the 152 portrait-part aliases independently.
This is partial image-registration coverage, not a complete UI reconstruction.

`resolve_image_region(id, texture_id)` returns a texture ID and region index.
Omitting the texture selector succeeds only when the mapping is unambiguous.
Conflicting or absent aliases report a diagnostic; filename order never selects
a layout. An explicit selector does not establish the matching source display
profile or texture filename variant.

`atlas_region.gd` crops a selected source resource and region. It checks base
identity, reads the rectangle from checksum-verified original AEI metadata and
requires prepared pixels of the same dimensions. Empty, out-of-bounds, cube and
unsupported atlas layouts are rejected. The returned AtlasTexture preserves
source size and alpha and clips filtering to the region. Padded texture dimensions
do not become portrait dimensions. The native portrait compositor consumes these
crops; frame/profile selection and full UI integration remain.

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_image_regions.py
godot --headless --path game --script res://tests/image_regions.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
godot --headless --path game --script res://tests/atlas_region.gd
```

## Portrait layer placement and native composition

Reader `resource-registration-v19` adds `portrait_layers`: 13 families of four
part-image bases, four explicit placement tables, and source stacking order
`[2, 1, 0, 3]`. Bounded declaration patterns verify the table references, indexing,
repeated references and call from the layer-list constructor. Only declarative
numbers and source extents leave the importer. A changed or ambiguous layout
produces an unsupported empty scope.

`portrait_layer_definitions.gd` validates the scope before activation and creates
a detached part plan for a fixed speaker and an explicit texture variant.
Negative part/base sentinels omit the source-absent layer. Top and bottom anchors
retain signed offsets. Zero anchor entries are retained: the last family's
medium table is zeroed in both supplied editions, and its medium artwork is absent.

`portrait_compositor.gd` resolves each part through its image and texture bindings,
loads source atlas crops from the same content base, and alpha-composites them in
native Godot code. The result carries the original bounding rectangle, base and
binding identities. Missing required layers fail the whole composition; no partial
face or substituted appearance is returned. Source panel backgrounds and foreground
frames are separate, unresolved display-profile work.

Both supplied editions yield 243 supported speaker/variant pairs: all four sizes
for 60 fixed speakers and three sizes for speaker 56. Speaker 0 still lacks verified
initialization and speaker 21 needs procedural appearance generation. The complete
486-image set was compared against independent composition from separately probed
source tables, with at most three 8-bit channel levels of rounding difference.
The Radio inspector displays available baseline portraits alongside localized names.
This does not establish original-game UI or cinematic parity.

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_portrait_layers.py
godot --headless --path game --script res://tests/portrait_layers.gd
godot --headless --path game --script res://tests/scene_bindings.gd
```

## Opening encounter actors

Reader `resource-registration-v20` adds `opening_actors`. The supported
cursor-zero population declaration supplies actor indices, hull catalogue indices,
source actor kind, initial positions, current-hull overrides and a separate player
current-hull override. The reader verifies dispatch and loop links, cursor access
and current/max hull setter semantics. It emits no executable instructions.

Both supplied editions initialize three actors with hull indices `[2,23,2]`,
kind 8, position `(50000,50000,50000)` and current hull 150. The player receives
a prologue current-hull override of 9,999,999. These values precede the cinematic's
visibility and position changes. They are not a complete rendered opening scene.

`opening_actor_state.gd` creates detached, content-bound initial actor records and
resolves each hull resource through its edition's catalogue mapping. It reports
missing models and mismatched content rather than creating replacements. It does
not infer maximum hull, AI behavior, visibility, mission progress or rewards. The
source hull setter raises maximum hull only when needed; current 150 does not
establish maximum 150. Factory stats and cinematic initialization remain required.

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_opening_actors.py
godot --headless --path game --script res://tests/opening_actors.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
```


## Opening scene staging (v21)

Version 21 adds `opening_staging`: initial player position and forward/up axes,
three initially hidden actor IDs, a first formation with per-actor positions and
orientations, and its finished-radio-event gate. Camera position parameters remain
explicit data; the original camera computes its final view separately. These
vectors must not be treated as resolved camera world poses.

The initial player is at `(0,0,-60000)`. After opening event index 2 finishes, the
player moves to `(18000,-12000,-40000)` and the three actors become visible at
`(-10000,500,0)`, `(-10000,-300,-1700)`, and `(-10000,-200,2000)`, facing +X with
+Y up. The native staging component preserves their catalogue resources and hull
state. It distinguishes radio start from completion and applies the reveal once.

The reader checks both cursor-zero dispatches, actor loops, shared identity/pose
helpers, visibility setters, camera parameter setters and the event-finished
getter. It accepts relocated supported declarations and reports unsupported scopes
as empty. Native pack validation checks all source extents, finite vectors and
orthonormal orientation axes. Failed loads clear the previous staging scope.
Older packs remain readable without acquiring staging data.

This is scene initialization and the first reveal, not a playable cinematic or a
completed mission. Camera mode integration, continuous ship motion, subsequent
phases, input ownership, AI, combat and rewards remain unfinished.

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_opening_staging.py
godot --headless --path game --script res://tests/opening_staging.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
```

### Fixed-eye camera geometry

`simulation/camera_view.gd` provides native fixed-eye look-at geometry with explicit
eye, target transform and target-up inheritance inputs. The eye stays fixed while
the camera points at the target position. Up is either the target's local +Y or
world +Y. Godot's camera looks down local -Z, independently of the flight model's
+Z forward convention. Nonfinite, scaled, reflected and degenerate poses fail
with a diagnostic instead of producing a camera transform.

The corresponding mode and look-at geometry were checked in both supplied
editions. This stateless helper does not select mission camera modes or targets,
apply follow lag, shake, extra roll or cockpit transforms, or establish source
field of view and clipping planes. With v21 staging, opening
position parameters are exercised as explicit eye inputs in tests; connecting
them automatically still requires verified phase ownership and camera flags.

Checks cover roll inheritance, world-up behavior, target centering, proper
orientation, large-coordinate precision and invalid poses. `Camera3D` projection
checks verify center and screen-right orientation using both editions' imported
initial and formation positions, with headless and OpenGL runs.

```sh
godot --headless --path game --script res://tests/camera_view.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
```

## Opening camera choreography (v22)

Version 22 adds `opening_camera`, recovered independently from both supplied
editions. It declares the initial player target and fixed-eye mode, inherited
target up, the first enemy target cut, pan velocity and finished-radio gates.
The reader checks the surrounding opening dispatch, phase branches, constructor
defaults, target/mode setters, eye setter and increment helper. Relocated supported
declarations remain readable. Unsupported scopes are empty with no guessed camera.
Previous pack fields and older-version behavior remain unchanged.

`simulation/opening_camera.gd` owns this camera sequence:

| Radio event finished (zero-based) | Camera behavior |
|---|---|
| Before 2 | Fixed eye at the initial staging parameter, tracking the player |
| 2 | Use the first formation eye, continuing to track the player |
| 6 | Track actor 0 from `(-5000,300,-5000)` and begin panning in this update |
| 7 | Continue panning with the same actor target; advance to source phase 3 |
| 8 | Pan for this update, then request player-follow mode |

The pan adds `(0.2,0,2.2)` source units per millisecond of supplied simulation time,
using the imported float values. The formation reveal occupies its own update;
entering phase 2 immediately pans once, including when event 7 is already finished.
Phase 2 becoming phase 3 never doubles movement in that frame. A zero-time update
can consume a finished cue but adds no pan displacement; the scene's pause owner
must suspend updates during a pause. Invalid time, foreign content, malformed completion flags
and regression behind consumed gates leave state unchanged.

The director resolves the current target's supplied scene pose each time a view
is requested. It preserves content identity and never moves ships, starts combat,
completes missions or grants rewards. The director itself only resolves fixed-eye
views; following its handoff requires the stateful camera rig described below.
It does not silently keep rendering the prior fixed-eye mode. Projection settings
and opening drift are described below. Effects, later phases and the authored scene
remain unfinished. Tests with radio and staging cover the first nine events in
both supplied profiles; they do not establish a playable opening or source pacing.

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_opening_camera.py
godot --headless --path game --script res://tests/opening_camera.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
```


## Ordinary follow camera (v23)

Version 23 adds `camera_follow`: target-relative eye/look offsets, two response
rates, a reciprocal numerator and a 5-by-9 constant response matrix. Independent
ARM32 and x86-64 readers recover these declarations, retain bounded provenance,
and discard the executable. Older packs remain readable; missing or malformed v23
scopes fail loading and clear prior state. Empty scopes explicitly mean unsupported.

`simulation/camera_rig.gd` owns previous eye/look positions and resolves target
poses supplied by the scene. Fixed-eye updates seed its history. Follow updates
transform the imported offsets through the current target pose and interpolate eye
and look separately using their imported response curves. The rig uses native
Godot transforms, vector interpolation and generic polynomial evaluation. It
inherits target up in ordinary follow mode and keeps the camera's -Z forward
convention separate from the ship's +Z forward convention.

Both supplied profiles declare look `(0,600,-650)`, eye `(0,600,-1338)`, and float
response rates near `0.005` and `0.006`. Those numbers come from each player's
import. Runtime code does not supply replacement values when a scope is missing.
The matrix's rows describe increasing powers of frame milliseconds; each row's
columns describe increasing powers of response rate. Curve evaluation uses double
precision, with float rounding for the reciprocal and final interpolation weight.
There is no extra clamping of the source weight.

Ordinary view updates require positive integer milliseconds within the imported
frame cap. Zero-time ordinary updates validate their inputs and retain the rendered view;
explicit formation translations and immediate pan refreshes are handled separately
by the opening view owner below. Pause owners must suspend
simulation calls. Invalid time, identity, target poses and unsupported modes leave
history intact. Reconfiguration clears history, and follow cannot invent an initial
view. Snapshots are detached; save/restore integration remains unfinished.

Tests cover synthetic rotated offsets, distinct eye/look response, moving targets,
zero-time handoffs, invalid state and pack cleanup. Both original profiles pass
radio/staging/director/rig composition through nine opening transmissions,
independent curve evaluation over every permitted positive frame interval, and
follow convergence within calculated float32 rounding bounds. These checks do not
establish full source scene scheduling or visible cinematic fidelity. The opening view owner now preserves source pan refreshes before the ordinary
update, as described below. Full radio, actor-motion and special-time scheduling
remain to be integrated. Shake, cockpit/orbit transforms,
extra roll, later response changes, projection and continuous actor motion are
not implemented by this component.

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_camera_follow.py
godot --headless --path game --script res://tests/camera_rig.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
```


### Opening view update ownership

`simulation/opening_view.gd` combines the native director and rig using the
ordinary update order verified independently in both supplied games. The scene
passes current player/actor poses and radio completion flags. The owner first
advances the camera sequence, applies any immediate view change, and then performs
the ordinary view update with the supplied frame milliseconds.

The formation reveal translates the existing rendered camera pose while retaining
its orientation. A positive ordinary update then resolves its look-at direction;
at zero milliseconds the translated old orientation remains visible. Pans instead
refresh a complete fixed-eye view, even when displacement is zero. On the follow
handoff, that refresh still targets the actor. The subsequent ordinary update uses
its eye/look history to follow the player. A zero-time handoff therefore changes
the director's requested mode while retaining the freshly resolved actor view;
the next positive frame applies follow response.

Immediate changes are consumed only by their successful frame. The owner stages a
prospective director and adopts it only after the rig validates and commits the
whole update. Missing actors, invalid player poses, foreign content, regressed
radio flags or invalid frame time cannot consume cues or partially change history.

This component does not advance radio, move ships, select special time modes,
acknowledge modal instructions or grant mission progress. The caller owns pause
and scene updates. Tests exercise both zero and positive handoffs, moving actors,
formation orientation retention, failure/retry and one-time refresh consumption,
plus both original profiles through the nine pre-combat transmissions.

```sh
godot --headless --path game --script res://tests/opening_view.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
```


## Opening actor drift and scene motion (v24)

Version 24 adds `opening_drift`, recovered independently from the recognized
opening camera context and its wave, elapsed-time, sine and translation helpers.
It contains the frequency, bias, affected actor IDs, phase limit, application rule
and provenance. It exports no executable behavior. Older packs remain readable;
empty scopes are explicitly unsupported, while missing or malformed v24 scopes
fail loading and clear previous state.

Both supplied editions use a frequency near `0.0005` per simulation millisecond,
with `abs(sin(elapsed * frequency)) - 0.5` applied to each of three actors' world Y
positions once per controller update. This is an incremental displacement, not a
velocity multiplied by frame delta. It also occurs during zero-time updates unless
the scene owner has suspended updates. The formation reveal skips drift; phase 2
receives its final displacement before switching to phase 3. Later phases stop it.

`simulation/opening_drift.gd` uses native sine evaluation with the source's float
rounding boundaries. `simulation/opening_scene_motion.gd` stages placement and
actor displacement, then evaluates the opening view against those current poses.
It commits the scene and elapsed-time marker only after the view succeeds. Invalid
frames cannot consume a reveal, accumulate drift or leave partial camera history.
The player is not displaced, hidden actor orientations are not invented, and
current hull/content identities remain unchanged.

The caller supplies elapsed simulation milliseconds explicitly. The component
accepts nondecreasing integral values through `2^53-1`; it does not equate elapsed
time with wall-clock time or guess a new-game/save origin. Radio advancement,
modal pauses, actor AI/activation, player flight and complete scene scheduling
remain outside this component. Direct source clock writes are still being traced
before integration with new-game and saved sessions.

Synthetic checks cover relocated readers and altered constants, corrupted helper
links and layouts, malformed packs, numeric/identity validation, float boundaries,
per-update behavior at repeated time, formation skipping, phase cutoff and atomic
failure. Both original packs also pass placement/drift/camera composition through
nine opening transmissions. This establishes component behavior, not a playable
opening or original-game visual/pacing parity.

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_opening_drift.py
godot --headless --path game --script res://tests/opening_scene_motion.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
```


## Flight perspective (v25)

Version 25 adds `flight_projection`. Each edition independently supplies vertical
field of view in radians, near plane, ordinary far plane and an alternate far
plane selected before a campaign-cursor threshold when the source location-ID
comparison succeeds. The reader verifies the startup declaration, projection
setter, parameter storage/aspect calculation, location comparison and cursor
accessor. A mismatch leaves the scope unsupported. No original executable code
is emitted into a content pack.

`presentation/flight_camera.gd` takes these parameters and explicit campaign cursor
and location-match inputs. It selects the clip distance and applies a native
Camera3D perspective to a validated view pose. KEEP_HEIGHT preserves vertical FOV
on viewport resize; Godot owns device rotation. Invalid inputs clear configuration;
an invalid view leaves the camera unchanged. This layer does not select a world
location or infer the location comparison from an actor or station ID.

Both supplied profiles yield 1.2200000286102295 radians vertical FOV, near 20,
ordinary far 300000 and alternate far 450000, with campaign cursor below 80.
The exact world/save fields supplying the comparison still need an independently
verified owner. Opening-clock lifecycle, radio/controller scheduling, effects,
cockpit/orbit modes, full scene rendering and playable missions remain unfinished.
These projection checks do not establish original-game visual or pacing parity.

Tests use changed synthetic declarations at relocated addresses, malformed
contexts, clip-distance threshold boundaries, invalid inputs and transactional
pack loading. Native Camera3D matrices are checked against analytic frustum
corners and near/far clipping at landscape, portrait and square sizes, including
live viewport resizing. Both original packs pass the same checks, plus camera
presentation through the recovered opening cuts and follow handoff. Linux
headless and OpenGL compatibility checks pass.

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_flight_projection.py
godot --headless --path game --script res://tests/flight_camera.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
```


## Ordinary opening scene and radio ownership

`simulation/opening_sequence.gd` joins scene motion and radio in the recovered
ordinary frame order. The scene consumes radio flags from the preceding
presentation, then updates actor placement, drift and the camera. Radio processing
uses the resulting cinematic phase and current actor hulls. A transmission that
finishes now can reveal a formation or cut the camera on the next scene update.
Both supplied engines invoke their state update before the radio presentation
callback; native logic preserves this dependency without executing source code.

The caller supplies elapsed simulation time, ordinary frame duration and an
explicit radio-presentation flag. Suppressing radio leaves its state untouched
while allowing scene updates to consume already finished cues. It does not act as
a general pause; a pause owner must suspend scene updates and the elapsed clock.
Source display line counts still control radio duration. Clock origin, all radio
suppression conditions, paused/special-time behavior, ship AI and combat remain
unimplemented by this component.

Frame forks isolate mutable actor, camera-history and radio state until the whole
update succeeds. Invalid frames and failed configuration publish no partial
changes. Returned snapshots are detached. Live source actors do not satisfy
combat-dependent transmissions; this owner never invents kills, mission progress
or rewards. It is not yet wired into a playable authored scene.

Tests cover next-update formation/cut/pan/follow gates, same-frame phase visibility
to radio, suppressed active/pending transmissions, malformed frames, detached
snapshots and isolated forks. Both original packs pass the complete pre-combat
sequence using explicit baseline line counts. These checks establish native
component sequencing, not original-game pacing or a full campaign.

```sh
godot --headless --path game --script res://tests/opening_sequence.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
```


## Fresh opening elapsed clock (v26)

Version 26 adds `opening_clock`. Both editions independently declare a zero
elapsed-time seed in new-game reset. A bounded reader checks that field against
the drift clock getter and the ordinary frame's increment helper. The native
runtime receives the seed and source extents, never original executable code.
Missing or malformed v26 scopes fail atomically; earlier packs and explicitly
empty scopes have no supported fresh timeline.

`simulation/opening_timeline.gd` owns the opening sequence and its elapsed time.
It adds each validated ordinary frame duration before actor/controller/radio work,
then commits the clock only when the entire sequence succeeds. The imported frame
cap applies. Zero-duration updates retain the source's per-update actor drift;
blocked frames suspend the entire sequence and clear the frame's outgoing radio
changes. The caller supplies explicit pause and radio-presentation states.

This is a fresh base-opening timeline. It does not restore saves, choose a skip
policy, infer modal ownership, model accelerated time or reset time on a mission
transition. The current radio component's supported elapsed range ends at
2147483647 ms; exceeding it fails without partial changes rather than wrapping.
Neither this owner nor its zero seed proves initialization of every new-game field.

Tests use both imported profiles with actual accumulated 100 ms frames through
all nine pre-combat transmissions and the first follow-camera handoff. They cover
first-radio timing, pause during active radio, zero-time drift, rejected-frame
rollback, overflow, nonzero synthetic seeds and unsupported combat gates.

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_opening_clock.py
godot --headless --path game --script res://tests/opening_timeline.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID"
```


## Opening hull and light presentation

`presentation/opening_geometry.gd` builds the player body and three opening
actors from the active edition's loadout, actor, hull and light declarations.
`resolve_ship_layers` exposes body/light bindings independently of hangar height;
`resolve_hangar_ship` adds the existing height for hangar inspection.
The opening renderer applies native simulation poses directly in source units.
Light geometry remains a child of its hull at the identity transform. Hidden
actors stay hidden until the simulation provides both visibility and a valid pose.
Content identity, actor identity, hull selection and all transforms are checked
before any node in a frame changes.

`presentation/model_resources.gd` stages geometry and textures for both hangar and
opening assembly. Repeated hulls share immutable mesh/texture resources while
keeping independent shader materials. Opening assembly rejects meshes with any
animation keys because source animation evaluation has not been verified. The
body and light meshes for the supplied opening hulls 2, 10 and 23 pass this
restriction in both editions. No binding-pack version change is required.

This is partial ship presentation. Engine geometry/effects, mounted equipment,
special hull assembly, detail selection, authored sky/lighting and playable
scene ownership remain unfinished. The graphics check uses neutral inspection
lighting and explicit baseline radio line counts and projection state. It
captures the first frame of each recovered camera phase; these images are not
original-game comparisons. The main inspector still has no playable opening.

The native test covers both editions, shared meshes with independent materials,
source light hierarchy, hidden/revealed actor poses, five camera phases, rejected
frame rollback and failed-build cleanup. Existing hangar placement checks also
pass after the shared loader change.

```sh
godot --headless --path game --script res://tests/opening_geometry.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID" "/absolute/visuals/PACK_ID"
# Omit --headless and use --rendering-method gl_compatibility for GPU checks.
# Optional GOF2_CAPTURE_DIR writes local screenshots; never include these in source packages.
```


## Ordinary ship levels of detail (v27)

`ship_lod` contains the first two alternate body IDs and matching child IDs from
each edition's ordinary factory tables. The source tables have a three-entry
stride, but this factory consumes only two entries. A value of 65535 is absent;
zero resource IDs remain unresolved and are not converted into invented models.
Special hull factories for IDs 13–15 are excluded by the native resolver.

Both supplied editions use distance declarations 5000 and 13000 and a maximum
of 80000 source units. Switching to a lower-detail mesh occurs strictly beyond
its threshold; reaching the maximum distance culls the geometry. Squared source distance
is calculated in single precision, truncated to an unsigned integer, and converted
back to single precision for the threshold comparison. Mac multiplies squared
thresholds by 0.5, 0.75 or 1.0, selected with source detail boundaries approximately
0.33 and 0.66. Equality uses the preceding band. iOS uses factor 1 throughout.
The multiplier applies to squared distance, not directly to distance.

`presentation/ship_detail.gd` selects a level from these declarations with an
explicit squared reference distance and finite source detail input.
`presentation/ship_geometry.gd` stages original body/light meshes and shows only
the selected level, preserving independent materials and hull-local light children.
It starts with every level hidden until the caller supplies a valid selection.
Invalid inputs leave the previous selection unchanged. Parent visibility remains
available to the scene's authored visibility owner.

This component does not infer the source reference position, Mac preference value,
engine effects, mounted equipment or special hull assembly. It requires static
meshes; animated hulls report unsupported animation. The opening renderer offers
full-detail inspection and a scheduled-detail mode described below. Static table presence is not proof of complete ship support: zero entries,
missing resources and unsupported materials/animation can prevent assembly.

Tests use relocated synthetic compiler layouts with changed tables, thresholds
and detail factors, plus malformed contexts and native pack rejection. Both real
profiles pass threshold equality, band boundaries, culling and return-to-full-detail
checks. Original hulls 2, 8, 10 and 23 and their alternate/light meshes pass native
and OpenGL checks; hull 37 is explicitly rejected for its unverified animation.
GPU captures use fixed neutral inspection lighting and viewing distance to inspect
each mesh. They do not establish original-game visual parity or authored scenery.

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_ship_lod.py
godot --headless --path game --script res://tests/ship_detail.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID" "/absolute/visuals/PACK_ID"
# A graphics run may omit --headless and use --rendering-method gl_compatibility.
# Set GOF2_CAPTURE_DIR to retain private comparison screenshots.
```

## Ship detail refresh clock (v28)

`lod_refresh` imports the ordinary geometry manager's initial timer value,
refresh threshold, reset value and time unit. Both supplied editions start at
1001 milliseconds, refresh when the accumulated timer reaches 1001, and reset
to zero. The first unsuppressed update is therefore already due. Time beyond the
threshold is discarded. Explicit forced refreshes leave this timer unchanged.
Bounded static contexts must link the periodic entry to its batch selection path
and the previously verified ship selector. Older packs expose no refresh scope;
missing or malformed v28 declarations prevent pack activation.

`presentation/ship_detail_group.gd` owns that timer and an atomic batch of ship
selections. The caller supplies integer frame milliseconds within the imported
frame cap, explicit suppression, registered ship positions, the source reference
position and detail setting. Suppressed updates leave the timer and selections
unchanged. Between refreshes, it retains the previous selections without demanding
unused position inputs. Ships with no alternate mesh are not registered with the
source manager and are rejected by this group. `ship_geometry.apply_selection`
accepts the held selection for an already-built mesh assembly.

The source batch reads the active renderer camera's translation. The ordinary
world check precedes the opening controller and camera update; the formation
reveal also forces a refresh after repositioning. The generic group requires its reference explicitly. A fresh-opening owner now
provides that reference and update order as described below. Saved Mac detail
preferences and the ownership of other suppression/forced-refresh call sites
remain unfinished. The separate source
mode that uses each geometry's own position is not exposed by this component.

Both real profiles pass initial and boundary timing, overshoot, suppression,
forced refresh, culling, changed reference positions and atomic invalid-input
checks. Tests also pass changed imported thresholds to the native group and
exercise selection handoff to original ship geometry. Synthetic reader tests
change clock constants and code addresses and reject broken contexts and links.

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_lod_refresh.py
godot --headless --path game --script res://tests/ship_detail_group.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID" "/absolute/visuals/PACK_ID"
```


## Opening detail presentation

`simulation/opening_detail_timeline.gd` combines the fresh opening timeline and
ship detail manager. Both source startup paths allocate and select a new renderer
camera with an identity transform before constructing the opening. The native
owner therefore uses the origin for the constructor refresh and retains the
imported timer seed. This does not replace the authored camera-position parameter:
that parameter reaches the renderer during its later camera update.

Ordinary periodic checks consume the preceding scene positions and renderer eye.
The formation reveal forces a second check using its relocated positions and
immediate camera translation; ordinary detail suppression does not suppress this
controller refresh. The resulting camera eye becomes the next frame's reference.
Paused updates preserve geometry selection and its timer. Each update operates on
detached state and commits scene, radio, camera and detail together after success.
The source detail value and ordinary suppression flag remain explicit inputs.
This owner covers a fresh ordinary opening, not saves, transitions, accelerated
time or the still-unimplemented combat/AI simulation.

Use `opening_geometry.build(..., "high", true)` for detail mode and pass the
resulting timeline's `snapshot().scene` to `apply_state`. This mode prepares all
required levels once, shares repeated meshes, keeps independent materials and
validates the whole frame's poses and selections before changing nodes. Until the
initial batch arrives, its detail levels remain hidden. The existing full-detail
inspection mode remains available without requiring a detail timeline.

Native tests run both supplied profiles through the five recovered pre-combat
camera phases. They check the initial origin, zero-time update, previous-frame
reference, timer boundaries, held choices, forced refresh during ordinary
suppression, pause and atomic failures. Original model assemblies also render in
Linux OpenGL checks with neutral inspection lighting. Source environments, visual
parity, saved preferences and playable mission ownership remain unfinished.

```sh
godot --headless --path game --script res://tests/opening_detail_timeline.gd -- "/absolute/content/CONTENT_ID" "/absolute/bindings/BINDING_ID" "/absolute/visuals/PACK_ID"
```

## Opening background (v29)

`opening_sky` records the supported opening condition, sky mesh/texture IDs and
three system-indexed star mesh/texture alternatives. Its six provenance extents
link the selection block, resource calls and system/campaign accessors. It does
not describe other location overrides. The background resolves explicit texture
assignments separately from ordinary mesh material lookup. See
[environment rendering](ENVIRONMENTS.md) for native scope and checks.

## Environment colors (v31; v30 compatibility)

`environment_colors` contains `sun_rgb` (19 RGB rows), `planet_rgb` (27 rows),
`rim_rgb` (19 rows), and source provenance. Separate ARM and x64
lookup contexts establish system sky-index and station planet-type indexing.
The reader follows relative table addresses and links the system getter to the
already recovered opening-background declarations. It rejects ambiguous lookup
contexts, unsupported getters, invalid float values and overlapping extents.
Only constant data and file extents leave the importer.

The native loader validates table dimensions, numbers and provenance before
activating a pack. An empty declaration disables the feature. Versions before
v30 remain readable but do not supply environment colors. Version 30 used the
incorrect name `material_ambient_rgb` for the rim table.
The loader normalizes that historical field and its provenance in memory, without
changing the checksummed pack. Conflicting or incomplete legacy declarations are
rejected. Version 31 requires the corrected names (`rim_rgb` and the `rim` lookup
provenance); it does not accept legacy aliases. The opening lighting adapter
accepts either version. Table presence alone does not implement every location
or expansion lighting condition; see [environment rendering](ENVIRONMENTS.md).

## Location reflection selection (v32)

`reflection_selection` contains `texture_base`, `special_id` and provenance.
The ordinary branch adds the system's sky index to the imported base and narrows
the result to an unsigned 16-bit resource ID. The location-match branch uses the
separate ID without a sky lookup. That condition is the same verified predicate
used by the flight projection definitions; its owner must supply native state
explicitly rather than infer an unknown save/world field.

Independent ARM and x64 patterns validate the selector and cube-binding call
context. The reader checks the predicate against flight projection provenance,
the system getter against opening-background provenance, the sky-index getter,
and the shared texture-load context. Repeated binding/helper calls must agree.
Only numeric IDs and file extents are emitted. Missing or ambiguous contexts leave
an empty declaration; there is no guessed resource base.

The native loader checks dimensions of the provenance extents, nonoverlap and
links to the active projection/background definitions before publishing a pack.
Earlier packs remain readable but do not supply this selector. The native
reflection component resolves registered paths in the active base and prepares
the selected cubemap. Selection/preparation is verified for both editions' 34
systems and the fresh opening; material reflection rendering is still unfinished.

## Ordinary environment surface material (v33)

`surface_material` contains `ambient_rgb`, `diffuse_rgb`, `specular_rgb`,
`specular_power`, `provenance` and `value_sources`. The importer recognizes the
material setup immediately following the active environment's rim-color setup.
Repeated renderer getters must agree, and each setter must write its verified
material field. Values are read from constant floats on x64 and immediate float
bit patterns on ARM. The runtime receives no original executable instructions.

RGB arrays contain three finite values in 0–16; the finite specular exponent must
be greater than zero and at most 1024. These are reader bounds, not gameplay
clamps. No values are substituted when the source context is unsupported.
An empty declaration keeps the remaining bindings usable.

Provenance includes setup, rim lookup, renderer getter and the four setter
prefixes. x64 extents are 118, 48, 21, 70, 70, 70 and 34 bytes respectively;
ARM extents are 90, 80, 14, 92, 92, 92 and 44 bytes. Contexts must not overlap.
The rim extent must match `environment_colors`, and setup must immediately follow
it. x64 values each occupy four constant bytes; exact aliases are allowed for
compiler-pooled values, but partial overlaps or overlap with code are rejected.
ARM RGB immediates occupy 12 bytes at setup offsets 8, 32 and 56; the exponent
occupies six bytes at offset 80. Native validation checks the same relationships
against the original executable size.

Older packs remain readable with an empty surface material declaration. Loading
failure clears the new data along with other declarations. The native material
light component preserves separate light contributions, but this import does not
establish full shader or visual parity.

## Weapon property bindings and modifiers (v34)

`weapon_parameters` binds damage, firing interval, projectile lifetime and speed
to edition-local item properties. It also binds the damage and interval percentage
properties of the source equipment modifier type, the item type/category value
indices, the primary category and low-damage threshold. Numeric constants include
the percentage divisor, default and missing multipliers, and low-damage interval
scale. These are numeric declarations, not executable runtime logic.

The static reader requires unique bounded contexts for parameter selection,
primary scaling, equipment modifiers and default initialization. Calls must link
to the edition's verified item helpers, the equipment jump table must uniquely
select the modifier type, and the category getter must match the opening loadout.
Constant references must be finite, file-backed and within their expected section.
Disjoint code contexts and constant extents are recorded in `provenance` and
`value_sources`; exact aliases of constants are allowed, partial overlaps are not.
Unsupported layouts produce an explicit empty declaration instead of guessed
property IDs or default gameplay values.

The native loader validates all numeric fields and source extents, checks shared
catalogue provenance, and commits the new scope only after the entire pack passes.
Older packs remain readable with an empty weapon scope. A missing or malformed
scope in a v34 pack is rejected and leaves no partially loaded state.

The [native weapon resolver](COMBAT.md#weapon-parameters) consumes these bindings
with the selected content catalogue. Parameter resolution does not establish
weapon-kind behavior, equipment ownership or a playable combat system.

## Item-specific weapon launch modes (v35)

`weapon_parameters.launch_modes` contains `alternate_item_ids` and `provenance`.
The importer recovers a consecutive item range and one additional item from the
source launch classification, then verifies the flag's launch selector and its
selected path. The classification must call the already verified property getter.
Each architecture is recognized independently; fixture item numbers are not import
acceptance rules. Ambiguous or unsupported declarations produce an empty scope.

Native validation checks unique bounded item IDs and non-overlapping executable
extents. Classification/selector/selected-path/getter sizes are 65/14/9/42 bytes
on x64 and 56/14/4/48 on ARM. The getter provenance must match the weapon property
scope. Imported IDs are normalized to native integer catalogue indices before
membership checks.

The resolver distinguishes ordinary type-zero primary launch from the alternate
item-specific path. Other kinds remain unsupported by the ordinary projectile
owner. Older v34 scalar packs still load but cannot establish a launch mode.
Nonempty weapon parameters in v35 must explicitly include the launch-mode scope;
an empty scope preserves scalar support while reporting launch support unavailable.

## Ordinary projectile capacity (v36)

`weapon_parameters.projectile_capacity` contains `slots` and `provenance`. The
reader links the weapon factory call, type-zero selector and table entry to its
bounded capacity selection and constructor arguments. The alternate item range
and singleton must agree with `launch_modes`; the item setup call must lead to
that same classification. Unsupported contexts produce an explicit empty scope.

Native validation accepts 1–4,096 slots as an implementation bound, checks context
extents and relationships, and links the capacity back to the current weapon
factory and item classification. Reader v36 requires the capacity scope on
nonempty weapon parameters. Older packs remain readable without it.

Only ordinary launch records receive the resolved `projectile_capacity` value.
The native projectile owner selects it by default and rejects a conflicting
explicit override. This does not imply support for alternate launch paths or
their capacities, actor ownership, collisions or projectile rendering.

## Opening NPC initialization (v37)

`opening_actors.npc_initialization` contains ordinary NPC half extents, the exact
source difficulty selector, initial equipment armor/shield values and activity,
damage, firing and collision flags. The reader follows the already-recognized
opening factory call into bounded constructor, argument and getter layouts.
The opening's deactivation call overrides the constructor's active flag; imported
opening NPCs are initially inactive. All declarations retain file extents.
Unsupported layouts emit an empty scope, without guessed values.

Both supplied editions use a half extent of 1,000, selecting 650 when the source
difficulty value equals 1.5. Ordinary NPC equipment armor and shield begin at zero;
current hull comes from each authored opening override. These are NPC declarations,
not the player's equipment pools or a maximum-hull formula. The new native body
requires an explicit source difficulty value; it does not select a game difficulty
or infer settings from a saved profile.

Reader v37 requires the scope key for nonempty opening actor declarations. Older
packs remain usable for their existing precombat features; they cannot initialize
combat bodies. Native validation checks field types, bounded values and all
architecture-specific nonoverlapping provenance extents. Only declarative values
and provenance enter the binding pack, never executable bytes.


## Opening NPC activation (v38)

`opening_actors.npc_initialization.activation` is independently recovered from
both source editions. The reader links the recognized camera engagement cue,
opening actor factory wrapper, constructor-installed virtual table, activation
method and the same activity setter used by initial opening deactivation.
The imported declaration contains event 7's finished gate, phase 3, actor IDs
0–2, active=true, actor mode 1 and a spatial half extent of 50,000. The spatial
value is not a timer or collision extent. Broader AI semantics of mode 1 remain
unsupported.

Six bounded provenance extents cover the cue, actor wrapper, table initializer,
virtual slot, activation method and activity setter. Native validation checks
architecture-specific sizes, ranges and nonoverlap. Unknown links or layouts
produce an empty activation scope. Reader v38 requires this scope key whenever
NPC initialization is supported. Older packs retain their previous functionality;
new native owners cannot infer activation when the declaration is absent.
Only the values and provenance enter the pack; no original instructions become
runtime code.


## Ordinary non-player hit policy (v39)

`weapon_parameters.ordinary_hit_policy` binds the ordinary weapon's additional
damage to item property 10 and the integer missing-property sentinel -979797979.
This integer differs from the rounded floating-point sentinel used by weapon
modifiers. The reader follows the recognized item classification/property getter,
checks that the value is stored in the field tested by the additional-hit gate,
and verifies the adjacent damage route and linked normal-hit entry. Non-player
targets take the resolved integer weapon damage directly (scale 1); the branches
for player targets do not define NPC damage.

The scope has six provenance extents: classification, property getter, additional
store, additional gate, damage route and normal-hit entry. Native validation also
checks linkage to this weapon catalogue, contiguous store/gate relationships,
exact architecture-specific lengths and nonoverlap. Reader v39 requires the scope
key for supported weapon declarations. Empty scopes remain explicitly unsupported;
legacy packs retain their prior capabilities. Only constants, bindings and file
extents are imported. Additional-damage execution, player damage routing and the
complete collision/effects owner remain separate unfinished work.


## Ordinary constructor collision bounds (v40)

`weapon_parameters.collision_bounds` records `mode: "target"` for the recognized
ordinary constructor. The factory's existing projectile-capacity call links to
its constructor wrapper and base constructor. Both editions initialize the bounds
override flag to false; their collision selectors consequently use the target's
extent. ARM verification includes the preserved zero register through constructor
calls and the final flag store. The selector also links to the already verified
ordinary additional-damage gate.

Five bounded provenance spans cover the factory call, wrapper, constructor entry,
default initialization and selector. Native validation checks exact lengths,
nonoverlap and the parent capacity/hit-policy links. Reader v40 requires this scope
key for nonempty weapon declarations; an empty scope reports unsupported recovery.
Legacy packs remain loadable. Only the declarative mode and provenance enter an
import pack. The native resolver copies the mode to ordinary weapons, and the NPC
contact pass uses it when the caller omits an explicit bounds selection. No later
runtime override changes, complete target lists or world weapon order are inferred.


## Scenery population counts (v41)

`scenery_population` contains the ordinary scenery group's `count_base` and
`count_bound`, recovered independently for each edition. The reader verifies the
linked station getter, signed station identifier and complete seed, bounded draw
and random-bit helpers. ARM integer remainder also resolves to the expected
external arithmetic symbol. Six nonoverlapping file extents retain provenance.
Unknown or disconnected layouts yield an empty scope.

The supplied iOS edition uses base 40 and bound 40; Mac uses 80 and 80. Native
counts use a local station-seeded 48-bit generator. This preserves an edition
difference in world population, independently of texture quality. Center draws
follow the count in the source, and the source reseeds before object placement;
the count's returned random state is not a placement seed.

Reader v41 requires the scope key. An empty scope explicitly means unavailable;
older packs remain readable without count support. Only values and provenance
enter runtime data. Scenery positions, resources, bodies and world target-list
assembly are not implemented by this declaration.


## Scenery ores and resource alternatives (v42)

`scenery_resources` adds catalogue bindings for ten ordinary ores and two special
items, availability and sampling parameters, and four source model base IDs.
The reader links the population setup to its availability builder and bounded
sampler, verifies repeated station/system/item getters, the item schema and square
root helper, and reads the model table through its source selection context.
ARM uses hardware double square root; the Mac helper must resolve the imported
`sqrt` symbol. Twelve file extents preserve the source evidence.

The schema binds each ore's origin to its original item array and the system's
map position to the original catalogue fields. Native availability depends on
those records, so resources from one edition never supply another edition's
population. The current fixtures happen to share these catalogue values.
Unknown compiler layouts or missing/disconnected prerequisites emit an empty
scope. Reader v42 requires the key; older packs retain their previous features.
Missing or malformed v42 scopes fail without retaining partially loaded content.

Model identifiers are imported alternatives. They do not by themselves construct
scenery or prove that every variant's placement, material, collision or mining
behavior works. See [environment component scope](ENVIRONMENTS.md).

## Scenery effect declarations (v43)

`scenery_effects` binds each of the four scenery base models to its source effect
type and ordered alpha/breakup model pair. Each edition is read independently.
The scope also carries the fresh-instance scale threshold, base playback speed
and scale coefficient. Linked constructor, resource-selection and scale-setter
layouts guard extraction; provenance contains file extents only. Neither code nor
animation key values enter this scope.

Native validation checks all four base-model links, type order, distinct model
pairs, supported parameters and nonoverlapping provenance. Reader v43 requires
the scope key; an empty scope reports unavailable recovery. Older packs remain
loadable without effect support. Unsupported or malformed declarations do not
produce partial effect resources.

The separate native resource provider reads the registered AEMs to derive integer
playback ranges. The native clock owns quantized model time and an independent
effect lifetime. These components do not activate destruction in the opening or
establish animation/rendering fidelity; see [environment scope](ENVIRONMENTS.md).

## Opening NPC main weapons (v44)

`opening_actors.npc_initialization.primary_weapon` contains the supported fresh
opening weapon parameters, actor IDs, source item/kind, weapon mesh resource,
zero local muzzle and executable provenance extents. The import-only reader
recognizes the ordinary NPC constructor arguments, follows the actor-kind table,
checks the item setter against the edition's existing launch classification,
and links the shared constructor to the independently recovered player factory.
It verifies the fresh scaling input, base damage selection, timing/capacity
arguments, speed value, campaign-cursor getter and NPC ownership flag setter.
No executable bytes are emitted into a binding pack.

The scope supports the three ordinary opening actors only. An unknown layout or
missing dependency produces an empty scope; the native weapon owner then reports
it unavailable. It must not be reused as a generic enemy loadout generator or
used to infer parameters for later campaign states. Runtime validation checks
all fields, architecture-specific extent sizes and nonoverlapping provenance.
The source catalogue category/kind and model resource must also resolve when the
native owner is configured. Reader v44 requires the scope key when opening NPC
initialization is present; earlier packs retain their existing feature support.

## Ordinary NPC flight (v45)

`opening_actors.npc_initialization.flight` provides the turn step, heading-snap
threshold, five-sample bank history size, bank limit/gain, bank response rate and
angle conversion constants. The importer follows the already verified actor
constructor and activation vtable to the ordinary update method. Separate Mac and
ARM layouts recognize the relevant tuning, history/reset and travel conversion
blocks and read their immediate values or section-bounded constants. Binding
packs contain values and provenance extents only.

Runtime validation checks finite supported values, constant semantics and exact,
nonoverlapping per-architecture extents. Unknown layouts produce an empty scope.
Reader v45 requires the scope key when NPC initialization exists; earlier packs
remain usable with ordinary NPC flight unavailable. This declaration does not
select a target, derive speed, enable a dodge or define an AI state machine.

## Fresh opening NPC guidance (v46)

`opening_actors.npc_initialization.guidance` declares the player-only target scope,
selection periods and random bounds, cruise/boost speeds and response factors,
boost duration and damage threshold, proximity/fire ranges, alignment tolerance
and fresh constructor hull scale. Independent Mac and ARM readers follow the
verified factory, constructor and virtual update anchors. They also recognize
the target-list membership and player insertion blocks. The scope requires the
three authored kind-8 actors with hull IDs 2, 23 and 2 and the fresh-level weapon
declaration; unsupported branches are not generalized to other missions.

Immediate declarations and referenced binary32 constants must match supported
layouts inside their proper sections. Packs retain 24 scalar/string values and
21 Mac or 20 ARM provenance extents; executable bytes are discarded. Native
validation checks exact supported semantics, extent sizes and nonoverlap. Missing
or changed layouts produce an empty scope. v46 requires the scope key when NPC
initialization is present, while older packs can load with guidance unavailable.

The native controller additionally requires the fresh opening context and
canonical population. Its decisions, source arithmetic and verification limits
are documented in [combat support](COMBAT.md). These declarations do not establish
world scheduling, player hits, destruction or campaign completion.

## Opening NPC holding state (v47)

`opening_actors.npc_initialization.holding` adds the authored mode 5, initial
engagement extent, player targeting suppression and zero selection/boost timers.
The reader follows the existing NPC constructor/update and opening deactivation
anchors. It verifies the constructor's location-comparison call against the
projection predicate, recognizes the fresh player suppression assignment, and
checks the ascending world NPC traversal, unconditional timer increments and
the complete activation method that preserves those timers.
The 50,000 extent applies only to the already-required fresh nonmatching location
context; matching locations use another source branch.

Each edition retains five values and eight nonoverlapping provenance extents.
Native validation checks the supported field types/values and architecture-specific
sizes. v47 requires this key when NPC initialization exists; missing layouts leave
the feature explicitly unavailable. Older packs retain active guidance support
but cannot construct the ordered controller that preserves preactivation state.

## Generated opening NPC routes (v48)

`opening_actors.npc_initialization.routes` contains four candidate origins, three
coordinate bounds, count minimum/bound, candidate-selection bound, initial index,
loop flag and arrival half extent. These are declarations for fresh opening
coordinate patrols, not a general mission-route format.

Each architecture follows its recognized NPC constructor and virtual update,
route constructor/copy, loop setter and waypoint advance methods. Recognition
checks the ordered coordinate/count/selection draws against the guidance RNG
method, duplicate retry structure, fresh route selection, strict arrival literals,
route steering and fire gates. Only normalized values and provenance are retained;
original executable bytes never enter the runtime pack.

The scope retains 17 Mac or 18 ARM nonoverlapping extents, including the two arrival
literals and existing selection/update anchors. Native validation checks exact
supported values, array element types and architecture-specific extent sizes.
v48 requires the scope key when NPC initialization exists. Unsupported layouts
leave it empty; older packs load with generated routes unavailable. Route state
belongs to its base content, binding identity and actor. The [combat documentation](COMBAT.md)
describes initialization order and the remaining world/RNG integration limit.

## Opening NPC construction (v49)

`opening_actors.npc_initialization.construction` adds factory position bounds,
cargo catalogue-field bindings, rejection/quantity/fallback parameters and breakup
fragment count, resource, angle and scale declarations. It follows the recognized
NPC factory/constructor, item layout, guidance RNG and equipment dispatch anchors.
Each edition independently verifies the generated-cargo helper, source getters,
fragment initializer, initially empty fragment list, special-drop predicate and
the opening's explicit cargo discard. Only normalized data and provenance are
retained.

The scope contains 33 parameters and 23 Mac or 24 ARM nonoverlapping provenance
extents. Unsupported layouts produce an empty scope. Native validation checks
exact supported values, types, sizes and overlap. v49 requires this scope key when
NPC initialization exists; older packs remain loadable without this capability.

The Mac route-generation signature now begins at an instruction boundary. The
native reader accepts both the corrected 726-byte extent and the older v48
733-byte extent. Route semantics and generated values are unchanged.

## Fresh world initialization (v50)

`opening_actors.npc_initialization.world_initialization` declares the supported
fresh context, absent optional populations and ordered NPC weapon-effect setup.
It follows scenery, opening actor/loadout, primary weapon, guidance RNG and base
actor anchors. Each edition checks its own world helper calls, population gates,
fresh companion reset, weapon overrides, default/assigned effect table entries
and per-slot random orientation loop. Only normalized data and provenance enter
the pack; no original executable code becomes runtime scripts.

The scope has ten parameters and 27 Mac or 31 ARM nonoverlapping provenance
extents. Native validation checks exact values, types, sizes and bounds. v50
requires the scope key when NPC initialization exists; unsupported source layouts
leave it empty. Older packs remain loadable without world initialization.
The native opening frame uses this capability to retain generated routes and the
shared stream through ordinary weapon, cinematic/camera, NPC, scenery and radio
passes. This scheduling adds no new imported parameters or binding version.
The [combat documentation](COMBAT.md) describes native ownership and the remaining
live encounter boundary.

## Ordinary impact models (v61)

`opening_staging.projectile_impacts` declares the two fresh weapon-to-impact
mappings, disabled initial playback, one-shot speed, camera/position rules and
sample-before-contact restart behavior. Recognition follows edition-local player
and NPC weapon setup, allocation, model mode, contact, update and draw anchors.
Each architecture has 15 bounded provenance extents. Only normalized declarations
and offset/length provenance enter the pack. Executable bytes are discarded.

The capability requires travelling projectile presentation and both ordinary
contact policies. v61 requires the scope key when staging is present, and leaves
it empty for unsupported layouts. Older packs remain loadable without impact
presentation. Native validation rejects altered values, extents and disconnected
anchors. The [combat scope](COMBAT.md) describes retained sampling and current
presentation limits.

## Ordinary opening sun flares (reader v68)

`opening_sky.sun_flares` contains three image IDs, their texture/region aliases,
a 34-entry system color-type table and six RGB colors. The ARM and Mac readers
recognize bounded constant declarations linked to the existing system getters.
The Mac color selector uses its original relative table; ARM supplies three
channel tables. Static image aliases retain independent per-edition provenance.
Missing, conflicting or malformed declarations leave this capability unavailable.

The runtime validates all table dimensions, IDs, color ranges and non-overlapping
source extents. The opening selects its original baseline interface atlas only
when that path is registered by the active profile, and verifies region metadata
against that profile's decoded pixels. Standalone similarly named flare textures
are not substitutes for those aliases. v67 and older bindings remain readable.
These declarations support the ordinary opening presentation; they do not establish
special-location behavior or campaign completeness.

## Damage particle sprites (readers v69–v71)

`damage_particles` contains the explicit sprite overrides of the source smoke
and fire presets, plus their material IDs. Independent ARM and Mac readers
recognize the differently sized source records and the two material-construction
sites. They retain capacity, size and size variation, lifetime, emission rate,
growth, colors, fade-in, declared scattering and velocity factors, and animation
tiles. v70 also recognizes the initialization of eleven additional fields used
by these emitters: auxiliary sizes, velocity-dependent sizing, initial fade,
base and local velocity, local X offset and minimum squared speed. Their verified
zero values are retained in `emitter_defaults`. Other values in these fields are
currently unsupported. Other particle presets and global adjustments remain
outside this capability.

Only normalized values and three (v69) or four (v70) provenance extents enter the
binding pack. Unsupported, conflicting, truncated or malformed declarations
produce an empty capability. Native loading validates the fields and extents;
v68 and older packs remain usable without this capability. Texture lookup uses
the active profile's original material and texture registrations.

`damage_particle_appearance.gd` independently implements integer particle age,
per-update signed-short size growth, the inclusive lifetime boundary, color fade
and stable slot-based sprite mirroring. It consumes an explicit size sample and
returns detached state. Sampling does not advance emitter or world randomness.
The growth field changes quad size; it is not angular velocity. Synthetic
mathematical vectors and both supplied content profiles are checked headlessly.
`damage_particle_emitter.gd` adds native emission and motion for v70. It requires
the active content identity, an available preset and an explicit independent
random seed. The owner supplies a source world transform, integer frame
milliseconds and the particle manager's shared elapsed milliseconds. This
preserves the source velocity refresh threshold, fractional emission remainder,
even spacing, source inverse-length approximation, scatter, seven draws per
ordinary birth, residual newborn travel and insertion ring. Moving less than one
source unit produces just one newborn while consuming all requested emission
intervals. Existing particles advance before emission.

Disabling emission retains existing particles. Hiding resets the emitter's
sprites; reset preserves its cursor, flags and independent RNG while requiring
a fresh movement baseline. A native zero-duration frame changes no state.
Invalid frames are rejected atomically, including overflow, and owners can fork
the component while staging a world frame. Sprite-only v69 packs remain usable
but cannot configure an emitter. Tests cover mathematical birth examples, timer
and velocity boundaries, reset, lifecycle, rollback and both supplied editions.

Reader v71 adds `damage_particles.owners`, with a further sixteen bounded
provenance extents per edition. An empty owner scope means that live integration
is unavailable while the earlier standalone components remain usable. The rules
bind the strict NPC hull threshold, mode-nine suppression/release, initially clear
damage flag, player campaign-cursor registration gate and authored restore cue.
Mac's damage-on and breakup transitions use its positive detail gate; the supplied
iOS paths do not. Opening staging mode five is separate from mode nine.

`opening_damage_particles.gd` connects the four paired smoke/fire owners to the
world's early weapon pass. Each emitter owns an independent random stream. Current
ordinary player motion and preceding NPC logical roots are sampled before the
controller and NPC pass. NPC damage/mode/death transitions then prepare emission
for the next frame. Logical roots exclude visual bank and cinematic model tumble.
The authored player restore cue enables its pair; ordinary player hull does not.
Relocation resets all eight pools without reseeding them or resetting manager time.

`opening_damage_geometry.gd` draws the original sprites with camera-facing squares,
arithmetic signed half-size, animated/mirrored UVs and floating vertex colors.
It reuses the native source material families: smoke uses alpha blending and fire
uses ONE/ONE additive blending without multiplying RGB by texture alpha. Geometry
is prepared before a world frame commits and does not advance any clock or RNG.
Tests cover both profiles, legacy absence, transition edges, retained roots,
relocation, geometry and rejected-frame rollback. This integrates these two
opening effects; it does not establish full-game rendering or campaign parity.

## Audio event declarations (reader v74; legacy v72/v73 supported)

The `audio` capability contains normalized FEV event metadata, categories,
sound definitions/settings, layer and parameter declarations and explicit bank
variants. It binds the original FEV resource and SHA-256 to the selected base.
The importer checks the project after matching the supplied source resources to
that base. Runtime validation preserves this identity and verifies every bank
reference before playback. Old packs retain their previous capabilities without
inventing audio declarations.

The supported FEV event system ID is its depth-first event ordinal. This was
checked independently against both source audio wrappers and each FEV project.
Playback resolves an event through its sound definition to a logical bank,
language variant and sample index; it does not match samples by guessed names or
reuse another edition's table. Reader v73 emits audio schema 2: unsigned spawn
milliseconds, maximum spawned polyphony and linear sound-definition volume have
their verified types and names. Legacy v72/schema 1 values are normalized in
memory by preserving the original float32 bits of the two delay words. Other
capabilities and base identities remain separate.

Reader v74 adds `opening_actors.npc_initialization.destruction_audio` independently
of the older death-motion capability. Bounded source checks connect the initial
sound call, breakup position argument and common sound dispatch to the verified
NPC update. The pack contains event IDs, the position/instance policy and source
extents. Unknown layouts produce an absent capability; no source instructions
become runtime scripts. Older packs keep their previous audio ownership.

Native playback supports the NPC death and breakup playlists and the damaged
engine's source-defined layers, looping parameter and weighted random playlist.
Retaining other layered metadata
does not imply support for its scheduling, DSP or spawning behavior.
See [audio behavior and format limits](AUDIO.md).
