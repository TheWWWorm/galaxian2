# Environment rendering

The Mac first-mining component now renders the actual Var Hastra exterior from
three original model layers. Its authored collision boxes share the station's
world placement. Native checks cover layer selection, combined model bounds,
strict point queries and atomic scene replacement; GPU checks cover both sides
of the station and the departure camera. Light pulses, docking and other station
exteriors remain unfinished. See [mining scope](MINING.md).

The native opening background now uses the imported star layer and skybox 003
nebula from either supported edition. Camera translation does not move these
layers; the current camera orientation and perspective do. This component is
checked together with the recovered opening ship poses and camera sequence.

The Opening tab combines these backgrounds with native ships, scenery and combat.
It continues through the escape's destination sky replacement, old scenery
retirement, all 23 transmissions and final fade. Current Mac bindings continue
through the rescue and first station conversation. See [opening escape support](OPENING_ESCAPE.md)
and [first station scope](STATION_ENTRY.md).
With v68 bindings, both original sun planes and the screen lens flares are also
connected. Complete location reconstruction remains unfinished.

Binding reader v81 adds the rescue's ordinary system sky and current planet
selection. A matching restored player cache supplies the retained location. The
shared sky and planet renderers select each edition's original resources, while
rebuilding the current planet at its full constructor size. The opening's smaller
size is calculated from an integer that was halved and truncated; simply doubling
that displayed scale would sometimes lose one unit of precision.

Native and GPU checks cover both profiles, source rescue camera placement,
texture quality independence, background translation, scene replacement and
legacy refusal. With v85, the shared sun and lighting adapters also resolve the
restored rescue location. Ship rendering accepts the source player tumble and
incoming actor poses, keeping hulls and lights visible while the rescue engine
effect is disabled. GPU checks cover the source camera and a separate hull
inspection view in both editions. Complete world scenery, NPC decisions,
reflection-context ownership and application handoffs remain unfinished.

With v86, Mac rescue scenery uses the station-seeded center `[12298, 36830, 77237]`
and 130 objects. A separate Unix-seeded stream places the field and continues into
the rescue NPC and weapon-effect construction. Shared geometry presents this
field together with the incoming ship and source camera in native/GPU checks.
With v87, a completed Mac Opening supplies the retained cache and entry conditions
through its handoff packet. Reader v88 connects the live rescue in the application;
v90 continues into the original Mido hangar at Var Hastra. The station uses
source camera projection, angles and bounded movement. Its native material
lighting is provisional and its animation remains at the initial pose pending
verified playback timing. New iOS parity work and validation are deferred.

Binding reader v67 adds original sun and planet resource tables. The native
constructor layout selects the fresh opening's station planets, sizes, orientations
and positions using the original station-seeded random sequence. It resolves
textures independently for each base edition and quality setting. The Opening
tab draws these planets when the imported bindings supply this capability. Older
packs retain their existing background until declarations are prepared again.

Binding reader v68 adds the system color-type table, six original flare colors,
three image IDs and their static atlas aliases. Each edition resolves its own
interface atlas. The renderer uses the original sun texture, two additive plane
passes, up to seven centered screen sprites and the final color wash. The second plane
retains world depth testing. Screen flares use ordinary alpha blending.

The 3D poses consume the preceding screen intensity. New native sessions start
with an explicit zero because the source constructor leaves that value
unspecified. Preparing or replaying a frame does not consume another intensity;
pauses and rejected frames retain the prior presentation. Offscreen projection
resets the next intensity. Fogged and special sun contexts remain unsupported.

## Imported selection

Binding reader v29 adds `opening_sky`: the source opening world/campaign condition,
one sky mesh/texture pair, and three system-indexed star mesh/texture alternatives.
The independent ARM32 and x86-64 readers validate bounded compiler contexts,
linked resource calls, the system ID getters and the existing campaign getter.
Relocated synthetic fixtures change the resource IDs and verify that they are
read rather than substituted. Missing or conflicting layouts leave the feature
unavailable. Earlier binding packs remain readable but cannot supply this feature.

The opening overrides the normal location sky. The source renderer assigns
textures explicitly, so the native background resolves mesh IDs and texture IDs
separately. It does not weaken the ordinary material lookup's ambiguity checks.
Texture quality selects the base edition's available variant.

## Native components

`presentation/opening_sky.gd` builds the fresh opening's two static layers from
content, visual and binding libraries and the catalogue. Its caller must provide
campaign cursor, world type and location-match state. Unsupported contexts fail
with an empty scene. This is not a selector for arbitrary locations or saves.

`simulation/scenery_orientation.gd` generates three station-seeded angles with
source float precision and XYZ rotation order. It uses a local native 48-bit
linear congruential generator; it does not alter global random state. An absent
station has a different seed from a station record whose ID is -1. System sky
indices 17 and 18 suppress this rotation. The special light-oriented background
path is explicitly unsupported.

`simulation/sun_placement.gd` computes the station scenery's first sun pose from
the station ID and catalogue `planet_type`. It uses a separate station seed,
preserves the random draw consumed by fixed angular alternatives, and returns
the XYZ basis, source-space position and normalized direction toward the sun.
It does not render a sun. `simulation/opening_planet_layout.gd` continues that
random stream for the fresh ordinary opening, preserving catalogue record order,
angular rejection draws, the selected planet override and source float precision.
`opening_sky.planet_resources` supplies the shared mesh and separate sun, near and
distant planet texture tables. Earlier packs remain readable but cannot construct
this new layout. Special location contexts remain unfinished.

`presentation/opening_planet_geometry.gd` draws the original two-sided plane and
alpha textures in station order behind world geometry. Distant planets retain
their constructor orientation and size. Camera translation offsets all planes;
the current planet additionally uses the source clamped camera-Z size adjustment.
The contributor escape session swaps its texture at relocation. The source draw
pass recalculates size from the constructor baseline after the controller's
one-time scale change. Failed frames restore the preceding textures and poses.
The renderer rejects fogged contexts that need a different material mode.

Binding reader v31 imports three separate RGB tables through linked source lookup
contexts: 19 sun colors, 27 planet colors and 19 rim colors. The
reader preserves edition provenance, rejects malformed/overlapping data, and
reads values from the supplied content rather than shipping original colors.
The v30 importer mislabeled the third table as material ambient. Existing v30
packs are normalized to rim color in memory; new imports use the corrected name.

`simulation/environment_lighting.gd` combines these colors with sun placement
and the verified ordinary-location setup factors. It keeps global ambient,
rim color, diffuse and specular contributions separate, including values
above 1.0. Sky 15's campaign-dependent changes are explicitly unsupported.
`presentation/opening_lighting.gd` adapts the fresh opening's two light directions,
diffuse energies and global ambient to Godot. It requires matching content
identities and explicit fresh-opening context. The separate rim color
and original shininess/normal-map response still need source shader integration;
they are not folded into Godot's environment ambient as a substitute.

Binding reader v33 also imports the ordinary environment's material ambient,
diffuse and specular RGB multipliers and specular exponent. Each value is linked
to its source setup and setter. `presentation/material_light_state.gd` prepares
separate per-light ambient, diffuse and specular colors from these declarations.
It requires explicit light colors and normalized directions, and clears its
prepared state on failure.

`presentation/surface_response.gd` and its independently authored forward shader
render opaque material 28 with both source light contributions, packed normal and
specular data, a rim response and a source cubemap. The adapter requires the
explicit `two_light_cube` variant and explicit texture biases; automatic source
settings selection is not yet implemented. It preserves imported UV animation
parameters through the shared coordinate helper. The opening assembly stages all
material replacements before applying them to mesh instances and animation owners,
and requires matching content, binding and location identities.

The ordinary scene check defaults to the older Godot PBR adapter. Its optional
native response path exercises all five recovered opening phases and demonstrates
visible reflection/rim contributions on both supplied editions. Original tangent
generation, exact reflection-coordinate equivalence, final color-space/filter
parity, reduced shader variants and source-game comparison remain under
verification. Native forward rendering is not a full renderer fidelity claim.

`content/cube_texture.gd` loads checksum-verified raw AEI cubemaps directly from
the active content library. Both source renderers upload the strip in the order
positive Y, negative X, positive Z, positive X, negative Z, negative Y. The native
loader reorders whole faces for [Godot's Cubemap API](https://docs.godotengine.org/en/stable/classes/class_cubemap.html)
without rotating or flipping their pixels, adding mipmaps or changing their color
space. The atlas cross is retained metadata, not the pixel layout.

The verified upload format is `0x81`: 23 source textures on iOS and 42 on Mac.
Four Mac low-resolution Supernova `0xa6` strips remain available to the ordinary
image importer, but are explicitly rejected by the native cube loader because
the verified original cube path does not accept that format. Missing, changed or
malformed source files also fail. Existing visual-pack orientation metadata is
unchanged; this loader reads original resource bytes and does not depend on it.
This loader alone does not add ship reflections to the opening.

Binding reader v32 imports the reflection selector's two resource IDs through
independent linked ARM and x64 contexts. `presentation/environment_reflection.gd`
uses the active system's sky index, an explicit location-match condition and those
IDs to prepare the source cube. Both editions resolve all 34 catalogue systems.
The special branch uses its own imported texture ID. The fresh opening uses the
system's reflection map even though its visible background has a separate override.
No native save/world field is guessed for the location-match condition; the state
owner must supply it explicitly. The opening helper only accepts the recovered
fresh opening context.

The component requires matching content, binding and catalogue identities. It
resolves registered texture paths and existing verified quality mappings, then
loads the original cube; it does not infer paths or substitute a nearby system's
artwork. Failures clear both the selected resource and prepared cube. The opening
scene check now prepares this resource together with the sky, camera and geometry.
Exact reflection-coordinate and material-response parity remains unverified;
resource selection does not establish original shader parity; the separate native surface response provides
an explicit, component-tested reflection path.

The stars precede the additive nebula, and both precede transparent world
geometry. Native shaders remove camera translation and place the background at
far depth without writing world depth. Shared texture/UV/color sampling also
serves the ordinary material families.

## Checks

- 42 independent random-sequence vectors cover positive/negative seeds, signed
  integer extremes, power-of-two and general bounds, and rejection sampling.
- Nine station orientation vectors check float32 angles and independent XYZ
  matrix equations, including the absent-station and signed-wrap cases.
- 36 sun-placement vectors check every planet-type alternative, signed seed
  wrapping, rejection sampling, source distance and light-vector direction.
  Both editions' 135 station records supply the recovered planet-type field.
- Both original profiles build the opening background and run through the five
  recovered pre-combat camera phases.
- Planet checks cover both profiles' five original planet planes, camera-relative
  placement, scale clamp, destination texture replacement, older binding packs
  and failed-frame restoration. Desktop GPU checks cover each distant planet,
  foreground depth, camera translation and the connected escape presentation.
- Linux OpenGL checks verify that both layers contribute, camera translation
  preserves the image, turning changes it and opaque foreground geometry
  occludes the background. Wrong content identities and unsupported contexts fail.
- The lighting adapter checks linear RGB energy and the direction toward each
  source; disabling its lamps changes the rendered opening geometry. Color
  import tests relocate synthetic tables and reject invalid data or lookup links.
- Cube tests cover malformed/truncated files, source checksum failures, six axis
  probes and 24 off-axis probes. Linux OpenGL rendering checks every texel of all
  390 supported source cube faces against their original RGBA bytes. This proves
  face sampling, not the original ship shader's reflection-vector calculation.

Run the native scene check with content/bindings/visuals directory triples:

```sh
godot --path game --rendering-method gl_compatibility \
  --script res://tests/opening_sky.gd -- CONTENT BINDINGS VISUALS
```

This combined scene check requires v33 bindings. Use `--headless` for the
data/state checks. Pixel and depth checks require a GPU
backend. Passing them does not establish original renderer color-space, filter,
lighting or complete scene parity. Other platforms remain unverified.

Add `--surface-response` after `--` to use the native two-light reflection path
with the explicitly verified supplied-fixture settings. That test option does
not select settings for arbitrary content or enable a playable campaign:

```sh
godot --path game --rendering-method gl_compatibility \
  --script res://tests/opening_sky.gd -- --surface-response CONTENT BINDINGS VISUALS
godot --path game --rendering-method gl_compatibility \
  --script res://tests/surface_response.gd
```

The synthetic shader checks use colored lights and cube faces, nonunit decoded
normals, interpolated highlight vectors, rim response and rotated objects. They
compare against independently calculated contributions passed through a constant
Godot shader. This isolates material arithmetic from the Compatibility renderer's
approximate display transfer. It does not prove original-game output color parity.
See Godot's [spatial shader contract](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)
and [4.7 Compatibility color conversions](https://github.com/godotengine/godot/blob/4.7-stable/drivers/gles3/shaders/tonemap_inc.glsl).

Run the cube component checks with one or more imported content directories:

```sh
godot --path game --rendering-method gl_compatibility \
  --script res://tests/cube_texture.gd -- CONTENT [CONTENT...]
```

Use `--headless` for parser/provenance checks without GPU sampling.

Check source material declarations and native light-color preparation with:

```sh
godot --headless --path game --script res://tests/surface_material.gd -- \
  CONTENT BINDINGS [CONTENT BINDINGS...]
```

## Application opening scene

`presentation/opening_session.gd` combines the existing source-ordered detail
and radio timeline, geometry, background, lighting and camera in one native scene.
Its caller supplies monotonic time. Resource loading consumes no simulation time;
the camera retains the verified fresh renderer identity until the first
positive-time update. User, focus and hidden-tab pauses are independent and rebase
the frame clock, preventing catch-up when resumed.

`presentation/opening_preview.gd` hosts that session in the application's
**Opening** tab. Timed transmissions use the same original bitmap-derived line
counts and localized speakers as the Radio tab, prepared by
`opening_radio_resources.gd`. Viewport resizing and compact/phone presentation do
not change the source timing. The current baseline layout is an explicit fixture;
automatic source display classification and original radio panel artwork remain
unverified. Voice is not connected.

The session recognizes the first imported combat-conditioned radio gate. After
the preceding transmissions and recovered player-follow handoff, it freezes the
scene and reports that combat is required. It never fabricates defeated actors,
starts later transmissions, completes a mission or grants rewards. Restart begins
a fresh opening; stop and content/language/resource changes release the old scene.

Run component and application checks with imported directory triples:

```sh
godot --headless --path game --script res://tests/opening_session.gd -- \
  CONTENT BINDINGS VISUALS
godot --path game --rendering-method gl_compatibility \
  --script res://tests/opening_application.gd -- CONTENT BINDINGS VISUALS
```

The application check covers visible source radio, window resizing, synthetic
Escape/controller Start events and context invalidation. Physical controller,
mobile and Web validation remain outstanding. This application integration does
not extend the supported cinematic phases or add playable combat.


## Ordinary scenery population

`simulation/scenery_population.gd` prepares an edition-bound count for an explicit
signed source station ID using v41 declarations. Each request owns a fresh random
generator and returns detached state immediately after the count draw. The supplied
iOS range is 40–79; Mac is 80–159. Station 78 yields 50 and 130 respectively.
Thirty independent integer-reference vectors check both edition ranges, a changed
synthetic range, signed seed extremes and repeated calls.

The source reseeds its generator before placing objects. Count state must not be
used to invent a deterministic station placement stream. The field constructor
requires its own explicit random state and center. Scene ownership of the reseed
and center, bodies and collision-list integration remain unfinished. The fresh opening owner now supplies the verified zero center and a separate
Unix-seconds seed, and attaches the field to the application scene.


`simulation/scenery_ores.gd` derives each station's ore availability from source
system map coordinates and item origins. It preserves distance truncation,
minimum availability, stable ordering of tied weights and the rank discount.
Its sampler visits the source's first six ranked entries, carries an explicit
cursor, resets that cursor after a failed draw, and returns detached random
state. The scene owner must interleave this state with its other construction
draws; the component never chooses a seed.

The caller supplies the source location-match condition, selected special-ore
flag and campaign cursor. The location branch bypasses random selection, even
when the special flag replaced the availability table's item IDs. Automatic
mission/save ownership of those conditions remains unfinished. Unavailable ore
tables fail explicitly; no substitute resource or fabricated reward is returned.

Both supplied editions pass all 135 station distributions, with 1,485 ranked
rows per edition independently compared against the original BIN records.
Synthetic checks cover distance boundaries, equal weights, campaign overrides,
random-state interleaving, impossible distributions, malformed input and detached
ownership. These availability checks complement the opening application integration below.


`simulation/scenery_field.gd` assembles the initial field from those count and ore
components. It interleaves ore sampling with candidate positions, scales, size
selection and constructor orientation draws in one caller-supplied random stream.
Large objects use the source's smaller placement volume. Its spacing test accepts
a candidate when it is far enough from **any** predecessor, preserving the source
rule and its truncated float32 distance. An explicit work limit makes an exhausted
placement fail without publishing a partial field or changed caller state.

The returned rows carry content identity, source item and model IDs, position,
scale and initial XYZ orientation. System 22 selects the second ordinary mesh
alternative; the location condition and special ore can override it. Constructor
axis values are retained; intact scenery spin is implemented with per-frame
float32 Euler accumulation, matching the source presentation update.
World centers and the selected special-ore flag still require a verified scene
owner; callers must not infer them from station IDs alone.

`presentation/scenery_geometry.gd` assembles source-bound static models over shared
meshes and textures with independent per-object materials. It validates identity,
model alternative and pose before construction, and clears failed rebuilds.
All four alternatives and their three LODs assemble in both supplied editions.
The magma base model has identity-only transform keys, so it needs no animation
clock. A strict static-track predicate accepts these identity transforms while
rejecting real transform, scalar and UV animation. Destruction uses a separate
animated owner described below; mining remains unfinished.

Seven synthetic reference fields check exact float32 positions, scales, angles,
spin values, ore choices, placement retries and the final random state. Actual
content checks generate all four alternatives in both editions and assemble the
four static alternatives. Private GPU overview and close-up captures verify
visible geometry against the opening sky and lighting, using inspection cameras.
These checks do not establish original-renderer parity or a playable environment.


`simulation/opening_scenery.gd` owns the fresh field, intact motion and scenery
LOD state, with native body ownership when supplied the prepared base-model radii.
The application always prepares those radii. Unix seconds seed construction once; the monotonic frame clock supplies
later updates. Source positions remain fixed, while retained XYZ Euler angles add
float32 spin increments each presentation frame without wrapping. User/focus/tab
pauses and the unsupported encounter boundary freeze the field. Timed radio and
opening cinematics continue scenery motion; hiding a mesh for LOD does not stop it.

Scenery and ships reuse `presentation/geometry_detail.gd` and the same native
refresh scheduler. Scenery has three alternates and no maximum-distance cull.
Its source large-display distances differ from ordinary large/small object
thresholds. The desktop host selects the source large-display context; iOS content
on mobile uses physical screen dimensions, and Mac content retains its startup
large-display setting. Texture quality and embedded viewport resizing do not
silently change this context. LOD uses the previous renderer reference, with the
source formation's immediate refresh, and remains synchronized with ship LOD.

The opening session now renders the actual generated field through its recovered
camera sequence. Tests check all four visible mesh levels, zero-duration startup,
shared refresh timing, pause/resume, spin during radio and the encounter boundary.
The source presents scenery between simulation and the radio overlay; the current
combined timeline evaluates radio first because it has no dependency on intact
scenery. Future mining, combat or radio interactions must preserve source ordering.
The session also retains one body per generated object. Body positions and vitals
remain independent of spin, detail selection and timed radio. With current v43
bindings, zero hull now starts the integrated destruction lifecycle. Older packs
without effect declarations retain their explicit destruction boundary. The
ordinary contact pass and fresh mixed target inventory are covered in [combat scope](COMBAT.md); automatic encounter
contacts and mining gameplay remain unfinished.

## Scenery effect resources and timing

`content/scenery_effect_resources.gd` resolves the v43 edition-local model pairs
for ordinary, void, ice and magma scenery. It checks content identity, registered
paths and supported AEM layouts, then retains only model IDs, paths and integer
playback ranges. Each model starts at its minimum strictly positive key time,
truncated to milliseconds; its end is the maximum truncated key time across all
surfaces and channels. Empty UV tracks are supported; keyed UV layouts remain
unavailable in this component.

In both supplied editions, the ice models start at 33ms and other models at 50ms.
The ice breakup ends at 10000ms; all other models end at 10050ms. Each effect uses
the larger of its two model ends as its unscaled duration. These values come from
the loaded resources and are checked against independently inspected originals.

`simulation/scenery_effect_clock.gd` owns a fresh, single-use effect. Triggering
captures the full body pose without advancing time. For stored scale `s < 1`,
playback speed is `1 + (1 - s) * 3`, with float32 rounding at each operation;
otherwise speed is one. Duration is the truncated float32 quotient of the source
duration and speed. Every update truncates its own scaled model-time increment,
without carrying fractions. Each model clamps and stops only after exceeding its
own end; a separate lifetime advances by unscaled frame milliseconds.

Lifetime equality stays active. Exceeding the duration rewinds both models and
finishes the one-shot effect. Zero-time updates preserve state. Validation and
detached frame copies prevent malformed requests or speculative updates from
changing a live effect. Tests cover both edition resources, five representative
scales, separate model/lifetime boundaries and frame subdivision.

The opening world connects these clocks to the lifecycle and renderer described
below. Finishing a clock does not grant pickup, a reward or campaign completion.
Sound, source culling and mining outcomes remain separate work.

`presentation/scenery_effect_pose.gd` now supplies root transforms from an active
native effect clock. The breakup model retains the captured body transform. The
alpha model preserves its root position and rebuilds its basis from the current
camera's up and backward axes, including roll. Two normalized cross products use
source float32 arithmetic and its exact-zero +Y fallback; the backward axis keeps
its original length. Uniform scale is applied once. Presentation does not advance
the clock, and untriggered or finished effects remain invisible.

Independent bit-pattern vectors cover normal, rolled, nonunit and degenerate
camera axes. Both source profiles also pass active/inactive pose checks for all
four effect types. This establishes root orientation; child animation and explicit material
presentation are covered by the subsequent checks below. Original framebuffer
parity remains unverified.

The native effect key compiler now builds the source's shared integer-time
records from separate channels, including missing values and insertion-order
rounding. Synthetic boundary checks and complete comparisons of both editions'
effect tables pass. A separate native rotation helper now verifies radian Euler
conversion, normalized quaternion blending without a sign flip and the source
matrix convention. All 6,980 tested rotations match an independent calculation
across both editions. The general model inspector retains its provisional
animation path.

The native effect sampler now provides world poses with verified key selection,
coordinate conversion, local scale and pivot/parent composition. First-record
sampling retains existing geometry and color, including after a rewind. Scalar
tracks produce a packed color byte for all four channels. Its 6,140 tested world
poses and color bytes match an independent reference across both editions.
`presentation/scenery_effect_geometry.gd` now assembles and renders the four
source effect pairs through an explicitly selected `unfogged_two_light_cube`
variant. It binds one logical effect, accepts its transactional clock copies, and stages
both model samples before committing,
uses the verified world poses, and hides finished effects without advancing time.
The alpha material consumes packed parent/animation color modulation and explicit
renderer tint. Mac's extra RGB darkening is kept separate from the iOS path.
Opaque fragments use the existing two-light cube response and ignore that tint.

The V4/V5 shader loader converts texture coordinates to `(u, 1-v)` before tangent
generation. Shared model preparation and the inspector now use that conversion by default
for V4/V5. Raw decoder arrays remain unchanged; explicit raw-UV inspection is
still available. Resource caches distinguish the conventions. V2/V3 rendering
keeps its existing UV convention; its source parity remains unverified. Both editions pass headless assembly checks
and Linux OpenGL captures of separate alpha, solid and combined layers.

The opening connects this renderer using an explicit native preview preset.
Automatic source shader/settings selection, renderer tint ownership, animated culling and
transparent draw ordering still require integration and verification. Godot owns
current mesh bounds and sorting. Tangent, framebuffer, Android and Web parity are
not established; fogged variants are unsupported.


`simulation/scenery_destruction.gd` owns the ordinary per-actor transition from
zero hull through breakup and delayed retirement. Its caller supplies a detached
body snapshot, the intact model pose and the current shared RNG state. A trigger
returns one accounting event and an optional actor-owned cargo candidate; it
consumes neither effect time nor spin on that tick. Later playback and the active
state-4 retirement tick still permit intact-model spin. Effect expiry, statistics
deactivation and the final inactive-actor step remain separate updates.

Source classes 4–7 have verified drop branches, including core conversion,
quantity draw counts and ore-specific junk models. Cargo is retained separately
from player inventory and is not an earned pickup. Disabled drops consume no RNG.
The fresh opening world now stages actors in source array order against one RNG
stream carried forward from field construction. It commits lifecycle clocks,
body retirement, per-actor spin masks, detail state and accounting together.
Trigger frames skip spin; playback and active retirement frames retain it. Zero
presentation time does not trigger a death or advance playback. Failure at a later
actor leaves earlier actor state, RNG and accounting unchanged. Counters describe
this field's remaining/destroyed objects; they do not restore profile statistics.
`take_events()` supplies one-time accounting events to future native consumers.

`presentation/scenery_destruction_geometry.gd` shares prepared models/textures,
creates effect nodes only when needed, and stages every actor's samples before
changing the scene. The opening stages its frame clock, timeline and scenery
together, so a failed world frame can be retried without losing elapsed time.
Finished effects release their nodes. Dropped junk uses its
source model at the asteroid position with identity rotation and unit scale. It
remains visible after both effect expiry and actor retirement. LOD updates cannot
resurrect the intact mesh. A renderer follows one logical world identity, even
when another world uses identical content bindings.

The preview explicitly selects unfogged alpha plus two-light cube response,
diffuse bias -1, normal bias 0, neutral parent/global tint and darkening 1. Intact
scenery, its LODs, breakup fragments and cargo use that same opaque response to
avoid switching lighting models during destruction. Ships retain their previous
PBR presentation. This preset is a native selection, not restoration or proof of
the original platform's automatic settings. Godot still owns bounds, sorting and
tangent generation.

Both editions pass world-order/RNG, atomic failure, spin/retirement, pause,
resource sharing/cleanup, and retained-cargo checks. Linux OpenGL checks compare
each intact/breakup/cargo layer with that layer hidden, and inspect captured
frames. Older v42 precombat behavior remains supported. Automatic encounter
scheduling, RNG interleaving with other gameplay consumers, displaced bodies,
mining, tractor pickup, sound and profile achievement/reward consumers remain
unfinished. The opening still stops before its unsupported combat encounter.

```sh
godot --headless --path game --script res://tests/scenery_world.gd -- CONTENT BINDINGS VISUALS
```
