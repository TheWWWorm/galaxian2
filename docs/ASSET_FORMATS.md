# Asset readers and verification boundary

## AEM

`game/src/content/aem.gd` implements bounded V2–V5 geometry and keyframe reading.
It preserves source positions, UVs, normals, float vertex colors, pivots, bounding
spheres, signed timestamps and independent submesh channels. Legacy packed vertex
attributes are retained as bytes; their color semantics are not inferred. Readers
check complete consumption, buffer extents, finite values, index bounds, sorted
times, channel modes and allocation budgets. Two observed V2 layouts differ by an
optional single-byte trailer; the marker is preserved without interpreting it.

The verified Mac station V4 files store vertices in engine axes, but their sphere
centers retain authoring axes. The station adapter converts only those centers
with `(x, z, -y)` before merging model bounds. Raw vertex buffers stay unchanged.
This distinction is checked against each model's actual vertex bounds.

The native sampler supports scalar and vector channels, equal-time keys, negative
times, endpoint clamping and linear interpolation. Inspection uses the raw source
timeline; it does not assume a millisecond-to-game-clock conversion. The renderer
currently uses XYZ Euler rotation around stored pivots and provisional percentage
UV transforms. Original interpolation, Euler composition, opacity channels,
material/effect selection and scene binding still need behavior verification.

The scenery effect metadata provider separately establishes millisecond playback
ranges for its verified model set: minimum positive key and maximum key, each
truncated to an integer. Its one-shot clock preserves source float32 speed and
per-update truncation. The general inspection sampler remains unchanged; this
timing support does not verify interpolation or animated effect rendering.

`scenery_animation_keys.gd` compiles the supported effect channels into a shared
integer-time grid before frame sampling. It preserves channel insertion order,
defaults, missing-channel filling and float32 rounding. Split translation axes
map to `(x, z, -y)`; vector translation retains its supplied component order.
Scalar percentages become fractions. Equal timestamps after truncation share a
record, with later component values replacing earlier ones. Raw AEM data remains
unchanged. Keyed UV animation stays unsupported in this component.

All 160 effect surfaces in the two supplied editions match an independently
derived key-table reference, covering 1,556 records. The dedicated
`presentation/scenery_animation_rotation.gd` converts neighboring radian rotation
keys into source-convention quaternions, blends without a hemisphere sign change,
normalizes and constructs a Godot basis. It preserves the verified float32
products and double-precision matrix expressions. Singular or nonfinite results
fail explicitly. These quaternion tuples must not be used as Godot quaternions.

All 6,980 tested rotations across the supplied effect tables match an independent
math reference at float32 precision on the current native runtime. Synthetic
cases also check analytical axis composition, nonunit quaternions, sign handling
and singularities. Original-platform trig rounding and visual parity remain
unverified.

`presentation/scenery_animation.gd` now samples the supported effect tables with
integer time, start/end clamping and retained geometry at the first record. It
converts the rotation axes, applies local-column scale, and composes the parent,
translation and converted pivot using float32 affine arithmetic. Authored scalar
values become a packed color byte by multiplication by 255, integer truncation
and byte wrapping; this is a four-channel color factor, not just opacity. Invalid
arithmetic fails without partially advancing the surfaces. Unanimated surfaces
retain the parent transform and have no animation color factor.

The sampler passes 6,140 independent world-pose and color-byte comparisons across
both supplied editions, covering source keys, neighboring milliseconds,
midpoints, clamping and rewinds. These are pose packets for a future effect
renderer. Material modulation, render passes, bounds/culling and original-game
visual comparison remain unfinished.

The supplied meshes load in Godot as follows:

| Base | Structurally decoded | Total | Submeshes decoded | Source keys |
|---|---:|---:|---:|---:|
| iOS HD | 1,212 | 1,215 | 2,394 | 112,571 |
| Mac Full HD | 1,202 | 1,205 | 2,384 | 112,571 |

Both editions reject the same three resources with diagnostics:

- `supernova/.../sn_cargo_001_midorian_wrecked.aem`: non-finite floating point data
  in submesh 11.
- `supernova/.../sn_ship_047_most_wanted_engine_add.aem`: invalid index block.
- `valkyrie/.../v_ship_040_deep_science.aem`: non-finite UV coordinates.

Do not silently remove these resources from a campaign's requirements or claim
complete mesh support. Resolve their actual layouts/source defects with evidence.

## AEI and native texture derivatives

`tools/gof2_content/aei.py` parses raw RGBA, PVRTC2, PVRTC4, BC1 and BC3 textures,
stored mip chains, atlas regions and font glyph tables. Compressed CPU decoding
uses the optional MIT-licensed `texture2ddecoder==1.0.6`. Runtime Godot code has no
Python dependency. All 2,749 supplied AEIs pass structural parsing and conversion.

Cube resources store six square faces in a vertical RGBA strip while retaining
atlas regions in four-by-three cross coordinates. All observed 0x81 cubes and four
Mac 0xa6 cubes use this raw layout. Native `0x81` cube face upload and sampling
are now verified for both editions; see [environment rendering](ENVIRONMENTS.md).
The native cube loader rejects `0xa6`, which the verified source upload path does
not accept. Location reflection selection is imported in v32; material reflection
rendering remains unfinished. A strip preview alone is
not a faithful environment.

Compressed mip chains are decoded down to 1×1; PVRTC stores minimum block extents
for small levels. Uncompressed 0x03 resources contain only their base image despite
the mip flag. The reader preserves that fact and does not invent source mip levels.

Prepared G2TX files contain a 24-byte little-endian header (`G2TX`, version, width,
height, level count, decoded byte count) and zlib-compressed RGBA pixels for all
stored levels. Native loading validates dimensional and byte budgets before
bounded decompression. Separate manifests bind every derivative to its base
identity and original resource SHA-256, and provide checksums for lazy loading.
No preparation writes into an existing base cache or changes gameplay data.

Native Godot loaded 1,163 iOS textures / 4,044 levels and 1,586 Mac textures /
7,335 levels with zero failures. The three preserved diffuse references per
edition (six total) match the new decoded base RGB pixels exactly. This checks
pixel conversion, not final rendering parity, tiny-mip visual quality or normal-map
orientation. Native rendering uses decoded diffuse RGB and normal RGB/specular
alpha, with independent Godot lighting; lighting parameters are not yet matched
to the original runtime.

Native mesh rendering retains floating-point vertex colors in a four-component
custom attribute, including values above one. Opaque, alpha and additive material
families are also available for source-linked geometry. GPU tests check texture
alpha treatment, transparent depth behavior and preservation of color precision;
they do not establish original lighting or effect parity. The explicit scenery
effect renderer now samples verified scalar channels into packed tint bytes for
its alpha material. The shared renderer now uses the source shader loader's `(u, 1-v)` conversion
for V4/V5 meshes before tangent generation, including ordinary scene geometry
and inspection; raw decoded UVs remain unchanged. Explicit raw-UV inspection is
available, and the existing V2/V3 convention is retained without a parity claim. Generic
inspection animation still has provisional semantics.

## FEV and FSB5 audio

Reader v72 normalizes original FEV event declarations and language-specific bank
references. Native FSB5 reading supports the verified PCM16, Xbox IMA and MPEG
layouts, with source sample rates and loop endpoints. Selected single-clip escape
cues now play in Godot; complex events and other sound owners remain unfinished.
See [audio formats, limits and verification](AUDIO.md).

## Source references

The [AEMesh format research](https://github.com/BaalNetbek/AEMesh) informed field
layout investigation. No implementation from that repository is bundled. All
acceptance counts above come from the supplied private fixtures and this engine's
own readers. Original bundled shader files were inspected statically for texture
channel semantics, but no original shader code is imported or executed.
