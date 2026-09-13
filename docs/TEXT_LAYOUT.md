# Source text layout

Dialogue duration depends on the original bitmap layout, even when the remake
renders crisp native text at desktop scale. `content/image_font.gd` reads glyph
rectangles directly from checksum-verified AEI resources. It supports the raw
RGBA font envelopes observed in the supplied packages, skips pixels, and rejects
truncated, duplicate, out-of-bounds or unrecognized data.

`image_font.open_selected` obtains the font group, atlas and signed spacing from
v15 bindings for the selected content language and requested source display mode.
The direct font-resource API remains useful for asset inspection.
`presentation/source_text_layout.gd` takes these metrics, source width and language
margin. It snapshots advances so reopening a font
cannot change an active layout. The independently implemented greedy layout
preserves the source's exact-width boundary, long-word overflow, ASCII-space
trimming and separate CR/LF boundaries. It retains the final source newline;
these lines determine timing, not the vector font's desktop measurements.
Missing glyphs are reported rather than assigned invented advances.

Reader `resource-registration-v14` imports 20 character substitutions from each
edition's language loader. They include Cyrillic/Latin glyph sharing and several
punctuation substitutions. `configure_from_bindings` uses those declarations for
metrics while preserving the original Unicode string. Substitutions apply once,
even when the original character also exists in the atlas. Font and binding
content identities must agree. A failed configuration clears the layout. An alias
whose target is absent is reported when text uses it; unused aliases do not
prevent the secondary A–Z font from handling supported text.

`radio_sequence.configure_from_layout` derives all opening event line counts from
the selected language and these metrics. It rejects content, language or binding
identity mismatches and missing glyphs. The existing explicit-line-count API
remains available for isolated simulation checks. Neither API starts a playable
mission, grants rewards or selects a cinematic pause policy.

## Imported font selection

Reader `resource-registration-v15` adds eight font records, a source language-ID
lookup, language-specific font and spacing choices, and three atlas variants for
each of seven texture IDs. The variants follow verified source registration
branches; no runtime filename guessing or cross-edition ID substitution is used.
The reader also verifies that the setup dispatch table and repeated globals/calls
are linked consistently. Unknown or conflicting layouts leave this scope empty.

Native `resource_bindings.resolve_font` and `image_font.open_selected` expose
main, secondary and language-list roles. The selected language filename determines
its source ID. Resolution is explicit through a source display mode:

| Mode | Atlas branch | Spacing |
|---|---|---|
| 0 | Baseline | Baseline source values |
| 1 | Medium | First source display flag |
| 2 | Baseline | Wide-display source values |
| 3 | Large | High-resolution source values |

These are source composition choices, independent of native text rendering scale.
These cover separate source-flag cases; combined flags and automatic physical
display/device classification remain unverified. UI ownership
must select a matching source mode and panel dimensions together. Secondary and
language-list roles have their own groups and zero spacing. The secondary font
contains A–Z only; registering it does not establish general dialogue coverage.

## Verification and remaining integration

Native and Python readers agree on all glyph rectangles in 42 source font/atlas
files: 48 font groups, 23,370 iOS glyphs and 23,307 Mac glyphs. Selected main fonts
and layout-derived opening radio timing were checked for all 24 edition/language
combinations in all four modes: 96 combinations. Secondary and language-list
selection were checked in all modes for both editions. The 24 baseline line-count
sequences are unchanged from the previous explicit-font checks.

The timing fixtures use an explicit 350-unit width and language margins, so these
checks do not establish complete display-profile selection or original-game
visual/pacing parity. Original radio panel dimensions and speaker-dependent role
selection still need import/runtime integration, followed by source panel frame art,
voice and cinematic/mission ownership. Original localized speaker names
now resolve through v17 bindings. No Arabic language file is supplied; inspecting its
font assets does not establish Arabic text/shaping support.

## Native radio view and inspector

The Radio inspector tab connects the imported opening list, selected language,
v15 main font, baseline 350-unit timing layout and native scheduler to a visible
panel. This is an explicit baseline fixture, not automatic device classification.
The first nine transmissions can play; the preview then stops because the combat
encounter is not implemented. It never supplies defeated actors or claims earned
mission completion. All 24 supplied edition/language combinations have been
exercised through this UI pipeline, including pause, hidden-tab suspension and
content-switch cleanup.

`radio_panel.gd` accepts snapshots for one content/binding/language identity.
Invalid or inactive snapshots clear old text and portraits. Text is rendered
literally, without markup, with native wrapping and scrollable overflow. Desktop
composition is half the phone size; text and borders render at native resolution.
Changing size or reading scale does not alter source line counts or timing. The
panel owns no simulation clock, pause state or dismiss/acknowledge action.

The view accepts pre-resolved speaker names and portrait textures. With v17
bindings the inspector captures original localized names for every opening
speaker. Older packs retain their earlier text-only capabilities. Names clear
on language/content changes and cannot be resolved against a different base.
v16 packs resolve the 152 portrait texture declarations and explicit resource
variants. v17 also distinguishes fixed speaker definitions from procedural and
unavailable appearances. v19 packs add original layer positions and stacking order.
When matching prepared visuals are open, the inspector composes the five supported
opening speakers once before playback and leaves speaker 0 unresolved. The explicit
baseline artwork is independent of the phone-layout toggle. Missing artwork reports
a diagnostic and never borrows another speaker or variant. Failed content, binding
or visual loads reset the preview; playback never loads textures per frame.
The composition checks cover all 243 supported speaker/size pairs per edition;
radio integration was exercised across all 24 supplied edition/language pairs.
Its native frame styling is provisional and does not claim original UI-art parity.
System font coverage and mobile/Web input still require target-platform validation.

Synthetic checks cover malformed font data, signed spacing, exact/near width
boundaries, long words, spaces, CJK margins, line breaks, unknown glyphs, immutable
configuration, imported aliases and layout-derived radio duration:

```bash
godot --headless --path game --script res://tests/font_selection.gd
godot --headless --path game --script res://tests/source_text_layout.gd
godot --headless --path game --script res://tests/radio_panel.gd
godot --headless --path game --script res://tests/scene_bindings.gd
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_font_selection.py -v
PYTHONPATH=tools python3 -m unittest discover -s tests -p test_text_aliases.py -v
```

These public tests contain synthetic data. Original resources, recovered private
fixtures and verification logs stay outside the engine source repository.
