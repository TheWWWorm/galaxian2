# Architecture

`tools/gof2_content` is the desktop import-time boundary. `bundle.py` discovers one
bundle, rejects ambiguous/unsafe paths and exposes bounded streams. It accepts an
iOS app root or a Mac `Contents/Resources` root based on the app's plist identity
and placement, independent of archive filename and checksum.

Only known `.bin` catalogue paths, `.aem`/`.aei` resource trees, supported language
files and named FMOD bank/event resources are ingested. Original binaries,
frameworks, entitlements, native nibs and original shader programs are excluded.
Import envelope checks are separate from the native AEM and import-time AEI readers.
Audio and 26 catalogue files remain opaque. Four catalogue tables have native
readers described below. Optional resource declaration preparation reads original
executables statically through the separate boundary described below.

`importer.py` streams one MiB at a time, with a 256 MiB per-resource and 8 GiB total
limit. Only small localization files are decoded in memory. Every ingested asset
retains its resource-relative path, byte count, hash and validation level. Original
bytes live under `resources/`; declarative normalized data under `definitions/`.
The atomic directory rename exposes a finished manifest only after all writes and
reader checks succeed. No global active-content pointer or existing cache is
modified. A cache-root lock serializes writers; process crashes need manual stale
stage/lock cleanup. File data is flushed, but power-loss durability of directory
metadata is not guaranteed across filesystems.

Content identity hashes schema, edition, structural layout, resource paths, lengths
and resource digests in canonical JSON. Archive names, container metadata and
executables do not participate. Repackaging identical selected resources retains
identity. This initial identity includes all selected assets, so any base asset
change isolates content. Future declarative extraction or format changes must bump
the schema. Supplemental packs are currently empty and cannot override gameplay.

`game/src/content/library.gd` reads the manifest and validates normalized language
hashes lazily before use. It does not load original executables or treat original
resource text as code. Full raw-resource verification is a separate desktop CLI
operation; startup does not rehash gigabytes of unopened assets. The content screen
uses native Godot controls and reports its limited support. Save paths are reserved
as `user://saves/<edition>/<content_id>`; no gameplay save files are created yet.
The project uses a dedicated `gof2-remake` user directory.

The next native renderer/simulation should consume independently normalized data.
Do not import GoF1 constants, mission progression or numeric localization bindings
as GoF2 behavior. Verify movement scale, timing, dialogue modality, mission rewards,
locations and materials against GoF2 evidence. Desktop UI should remain compact,
with the larger phone presentation and touch-control preference carried through
when gameplay UI is implemented.

Python is an initial desktop ingestion implementation, not a proposed browser or
Android runtime dependency. Those platforms need a native or suitable streaming
import adapter, memory budgets and independent validation before exports. No
hosting, Android identifiers or release presets are inherited from other projects.

## Visual data path

`aei.py` and `visuals.py` decode original textures once into a separate private
base-bound cache. G2TX derivatives preserve stored RGBA mip chains and atlas/font
metadata. They are content, never engine source or export assets. Godot's
`visual_library.gd` verifies provenance/checksums and lazily decompresses requested
images. Texture preparation is cancellable between individual resources and
activates through an atomic directory rename. Rebuilds use a new output root;
existing derivative packs are never overwritten.

`aem.gd` reads mesh geometry and animation directly from verified local resource
bytes. `binary_cursor.gd` bounds allocations and reads; `animation_tracks.gd`
provides an independent linear sampler. The asset inspector creates native Godot
meshes, materials and a preview camera. It preserves source geometry units without
borrowing a gameplay scale. This visual tool deliberately labels provisional
material/animation conventions; it is not the final station or flight UI.

See `docs/ASSET_FORMATS.md` for exact supported layouts, checked counts and the
three unresolved AEM resources. A successful inspector must not be used as proof
of gameplay, complete campaign fidelity or source-authored world composition.

## Catalogue data path

`catalogues.gd` reads ships, items, systems and stations from the base content
library with a one MiB limit per file. It checks complete record extents and world
references before publishing a catalogue set. Each decoded row retains source
offset/length and each table retains its source hash. Derived in-memory definitions
are bound to the same base identity; immutable installed caches are unchanged.

Known world names, station membership and system links drive the World browser.
Unknown fields stay positional. The verified system field used for hangar geometry
selection is consumed only through the recovered hangar declarations.
The browser is independent of mission availability and never modifies progression.
See `docs/CATALOGUES.md` for the schema boundary and remaining semantic work.

## Executable-derived declarations

`registrations.py` recognizes bounded Mach-O resource record-initialization
templates. It extracts constants only, never traverses game control flow and
never emits executable bytes or translated logic. `bindings.py` verifies the
original bundle's resources against the imported base, then creates a separate
private JSON pack. The pack identity includes the original executable hash and
declaration data hash as well as the base identity. It cannot be a cosmetic pack.

`ship_models.py` recovers packed catalogue-indexed resource tables only after a
bounded indexed-read template confirms candidate data. `texture_variants.py`
checks source-declared Mac high/low pairs against texture dimensions, atlas layout
and hashes. The normalized pack retains all declarations; quality preference is
applied by the native texture resolver rather than discarding source variants.

`resource_bindings.gd` verifies that identity/data before native ID inspection.
Conflicting, absent and unverified declarations produce diagnostics. Coverage is
partial, so even a unique recovered declaration does not prove active scene use.
No gameplay state consumes these declarations yet. When that is implemented,
definition/save identity must include the binding identity; reusing the reserved
base-only save path would incorrectly conflate different executable content.
See `docs/RESOURCE_BINDINGS.md` for the supported boundary and limitations.

`hangars.py` reads supported station overrides, the system-field selector, root
layer IDs, extra-geometry ranges and the common vertical-axis rotation. It checks
bounded compiler access patterns and catalogue field getters in both architectures.
The resulting v4 pack contains declarative data and provenance only. Native
`hangar_definitions.gd` validates it; `resolve_hangar()` combines it with catalogues
from the same base. Empty rows and missing resources fail explicitly.

`hangar_geometry.gd` stages all required meshes/materials/textures before attaching
the selected layers. It preserves the recorded parent/child geometry structure.
Repeated instances share immutable meshes and textures while keeping their material
parameters independent. A failed rebuild clears the old scene. This is geometry
assembly, not source lighting, camera, docking or progression behavior. The World
browser and Assets station selector currently expose it as an inspection preview.

`ship_placement.py` reads catalogue-indexed hangar Y positions inside the validated
hangar declaration region. Its v5 data contains signed positions and provenance,
not original routines. `resolve_hangar_ship()` combines a position with the chosen
edition's raw hull lookup. The native composer places that hull directly under
the scene, outside the rotated hangar layer hierarchy, and includes it in bounds.
The inspector can frame the hull independently. No player ship state is created;
full hull orientation/attachment/variant fidelity remains a separate requirement.

`ship_lights.py` independently recovers each edition's two catalogue-indexed mesh
layers associated with ship lights. x86-64 masks are checked against all table
sentinels; ARM sentinel checks and attachment calls are validated. v6 packs retain
only IDs and source extents. The native resolver requires every declared resource;
the composer preserves separate slots and parents their mesh instances to the
hull. This does not add scene-light nodes or assume engine flames/LODs are visible
hangar attachments. Their behavior and full ship assembly remain unimplemented.


## Ordinary cruise

`tools/gof2_content/cruise.py` extracts a scalar and axis from each supported
edition's bounded constructor, reset, movement and forward-vector lookup layouts.
No source routine is emitted. The v7 payload adds the data and source extents to
the existing executable/base-bound identity. Native `motion_definitions.gd`
validates it before publication; older packs retain their existing scope.

`simulation/cruise_motion.gd` performs independent continuous translation from
elapsed simulation seconds and the flight pose's normalized local +Z direction.
It requires the expected content identity and copies the recovered rate when
configured. It does not use catalogue handling or mutate ship ownership, scene
geometry or campaign state. Clock, pause, steering, collision and other flight
systems are still separate implementation work. See `docs/MOTION.md` for usage
and the distinction between component checks and full flight fidelity.


## Manual angular motion

`steering.py` adds independently recovered manual angular constants to v8 packs.
`motion_definitions.gd` validates their values, order and per-edition provenance.
`simulation/flight_motion.gd` composes native local pitch/yaw basis operations with
the existing cruise component, bound to the same source identity. It receives
resolved angular units from the pilot-response layer. This keeps source
control ramps, handling/equipment rules and visual banking separate from the
kinematic calculation. Failed configuration clears both components; each invalid
step returns the unchanged pose. The model's presentation scale is not part of
the simulation orientation.


## Pilot response

`pilot_response.py` recovers elapsed-time ramp, target quantization and neutral
return constants into v9 packs. Native validation checks parameters and bounded
per-edition source provenance before publishing any binding state.
`simulation/pilot_response.gd` is a pure response calculation with explicitly
configured vehicle factor and sensitivity. `simulation/pilot_motion.gd` owns the
angular response state and stages response and motion together: old angular units
move the current step, new commands prepare the next one, and failure commits
neither. This ordinary mode does not select special flight states or derive
other equipment effects, device preferences or clock policy. Those integrations remain
required before exposing a playable flight session.


## Vehicle response binding

`vehicle_response.py` recovers per-edition base handling conversion, upgrade bonus,
ordered equipment selector and percentage/response coefficients into v10 packs.
The reader verifies accessor call targets and the equipment jump-table entry;
matching unlinked instruction sequences do not identify a handling definition.
`vehicle_definitions.gd` validates the parameters and named source extents.

`simulation/vehicle_response.gd` snapshots the bound ship/item catalogues and
resolves a factor from an explicit ship, upgrade tags and ordered equipment IDs.
It preserves Mac's base conversion and iOS's direct handling, then applies the
selected device percentage after upgrades. Pilot motion can configure from this
state or replace its factor while preserving angular state. This is a calculation
boundary; an eventual session/loadout model must enforce ownership, slots and
availability and select conditional control modes. No item or upgrade is granted
by resolving its effect.


## Event input and flight timing

`frame_clock.py` adds an independently recovered ordinary frame cap to v11 packs,
validated with the delta supplier and agreeing bounded clamp references. The
native `frame_clock.gd` consumes monotonic microseconds, selects integer-millisecond
deltas, discards excess time above the source cap and rebases pause transitions.
It does not implement alternate source time modes.

`input/flight_controls.gd` adapts the existing controller ownership/deadzone
pattern and adds native keyboard, touch and action routing. Its settings are
remake input preferences. `simulation/flight_driver.gd` owns the explicit pose,
clock, pilot motion and independent pause reasons. A caller must provide scenario
state and route unhandled events only when flight owns input. GUI panels, mission
conditions and cinematic/radio definitions decide whether to request a freeze;
message delivery alone does not stop simulation. Non-pause actions are returned
as requests for future gameplay consumers. No unsupported operation is completed.


### Opening loadout seed

`opening_loadout.py` reads bounded setup declarations into v12 binding packs.
`content/opening_definitions.gd` checks their schema and extents;
`simulation/opening_loadout.gd` resolves catalogue/category/slot references and
preserves ordered equipment stacks and vacant slots in a detached native snapshot.
The snapshot can supply ship/equipment inputs to the flight driver. Configuration
clears old state and fails on an unavailable/mismatched profile or invalid loadout.
It does not instantiate mission state, choose a camera/flight transform or apply
unrecovered startup credits/damage. Full session ownership and earned progression
remain to implement.

### Opening radio

`opening_dialogue.py` reads the finite event declaration grammar for each edition
and retains independent localization bindings in v13 packs. It reads constant
dispatch data and constructor layouts; it never runs or translates mission code.
`content/dialogue_definitions.gd` validates the data, while the independent native
`simulation/radio_sequence.gd` owns single-speaker activation/display/completion.
The future mission owner supplies simulation time, actor hull state, cinematic
phase and a verified source layout (or explicit line counts for isolated checks).
`content/image_font.gd` reads verified bitmap glyph metrics. The native
`presentation/source_text_layout.gd` captures those metrics and applies v14
`text_aliases` declarations without altering stored Unicode text. Its greedy
layout supplies radio duration independently of desktop vector-font measurements.
Content, language and binding identities are checked before configuration.
v15 `font_bindings` select source font IDs, groups, atlas branches and signed
spacing from the active language and an explicit source display mode.
`image_font.open_selected` retains the binding identity in its immutable layout
inputs. `presentation/radio_panel.gd` passively displays identity-checked snapshots
with native text, scrollable overflow and separate desktop/phone composition sizes.
It owns no clock, pause state or acknowledgement action. Speaker names and textures
can be supplied after content resolution; missing speakers do not inherit old art.
v16 `portrait_textures` adds 152 authored texture IDs with explicit suffix variants.
The bounded import reader verifies record construction and source string links;
`content/portrait_texture_definitions.gd` validates the scope before activation.
`resolve_portrait_texture` resolves only a selected source-present variant within
the active base. These texture declarations do not yet provide speaker-to-layer
composition, frame art or automatic portrait display selection.
v17 `speaker_bindings` imports the edition-local name lookup and fixed portrait
pointer-table declarations through independently linked speaker accessors.
`speaker_definitions.gd` validates the scope. The Radio preview resolves and
captures each opening speaker’s localized name before playback; content or
language changes clear the previous names along with the scheduler.
Fixed portrait records are available through `resolve_speaker_portrait`, while
procedural and unavailable records remain explicit. Layer and frame assembly
are separate integration work.
v18 `image_regions` retains explicit image alias alternatives and bounded numeric
ranges. `resolve_image_region` rejects conflicting alternatives unless an explicit
texture ID identifies one mapping. `atlas_region.gd` reads the selected rectangle
from checksum-verified original AEI metadata and crops same-base prepared pixels.
It preserves raw pixel size and alpha; source display selection and portrait
composition still need integration.
`presentation/radio_preview.gd` connects the content library, font metrics, wrapping,
scheduler and view in the inspector using the explicit baseline timing fixture.
It supplies no defeated actors or cinematic phases and stops at the first combat
gate. Preview pause and hidden-tab suspension do not pause the scene tree.
Radio state never grants mission completion or rewards. Display-mode
classification, original panel geometry, speaker font roles and portrait assembly,
voice, cinematic integration, persistence
and actual opening gameplay remain unfinished. See [text layout](docs/TEXT_LAYOUT.md).


### Opening geometry

`presentation/opening_geometry.gd` is a passive body/light renderer for the
source-selected opening hulls. It consumes detached staging snapshots and checks
identity, visibility and proper transforms before committing the entire frame.
It has no clock or mission authority. Hidden actors require a pose before reveal.
`presentation/model_resources.gd` provides shared resource staging for opening
and hangar assembly, with independently mutable per-instance materials.
The opening renderer restricts meshes to zero animation keys. Full ship effects,
LOD, mounted equipment, authored environment and playable scene integration remain
separate work; inspection lighting is not a world definition.


### Ship detail selection

`ship_lod.py` adds v27 ordinary-factory body/child tables, distance declarations and
edition-specific squared-threshold factors. Native `ship_lod_definitions.gd`
validates the scope before activating a binding pack. `resolve_ship_detail` rejects
special factories and unavailable resource IDs while preserving each LOD's child
mesh. `ship_detail.gd` owns only distance/detail selection;
`ship_geometry.gd` displays the chosen body/light level. Scene reference position,
preferences, engine effects and mounted equipment are separate responsibilities.
