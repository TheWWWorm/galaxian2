# Original audio and native playback

Reader v78 imports the supplied FMOD Designer event declarations. Native Godot
code reads the original sound banks and plays the retained player engine, opening radio voices, ordinary
weapon and NPC destruction sounds
and eight source-selected escape cues, including the layered damaged engine.
Each edition uses its own event project, bank references, samples and base
identity. No FMOD library or original executable runs in the engine.

Radio, weapon, player-engine, NPC destruction and escape audio are connected to
the Opening tab with current bindings. Current Mac packs also play the rescue
and first station conversation.
See [Opening escape](OPENING_ESCAPE.md). Special and NPC engines,
player/scenery destruction and later dialogue still need sound owners.

## Connected rescue speech

The three rescue transmissions now use the shared native radio and voice owners
with explicit campaign cursor 1. Both editions independently select events
501–503 and their own English/German sample banks. Gunant Breh's localized name
and portrait use the existing imported speaker bindings. The first transmission
becomes eligible at 10,000 ms of scene time; its text and speech appear strictly
after the additional 2,000 ms display delay. Following transmissions retain the
source dependencies and separate started/finished flags.

These components have independent timing, language, portrait, playback ownership,
pause and cleanup checks. Reader v88 connects them to the live Mac rescue in the
Opening tab. Radio completion grants no mission completion or reward.

## Connected first station speech

Reader v90 connects the first Mac station conversation after the completed rescue.
Eighteen source-mapped recordings use the original English or German bank, with
the same source language-selection rule as radio. The final instruction is silent.
Speech begins with the first displayed line after the one-second station delay.
Explicit Next/Previous navigation stops the old voice and starts the selected
line; repeated presentation does not restart it. Text requires acknowledgement
and is never dismissed by a voice finishing.

Native PCM recordings verify both languages, voice replacement, retained pause
cursors, silence while paused and cleanup. All 19 lines and 12 Mac text languages
pass native session checks. The source station atmosphere event is identified,
but its authored envelopes and cross-scene music ownership remain unconnected.
See [first station scope](STATION_ENTRY.md) for the remaining scene limits.

## Player engine calculations

Reader v77 adds source-bound player engine selection under `vehicle_response.audio`.
It reuses each edition's handling conversion and upgrade tags, before equipment
bonuses. Three handling thresholds select events 42–45; ships 42, 43 and 40 have
explicit event overrides 1104, 1106 and 1107. These independently verified IDs do
not establish cross-edition save or catalogue compatibility.

Native calculations support the ordinary engines' three parameter channels and
their original pitch, volume and 3D speaker-spread envelopes. The steering input
is the largest absolute retained source command; horizontal input is the source
yaw command times its imported scale plus 0.5. These are command values, before
angular response. Native pitch/yaw inputs become signed squared commands, with
the source yaw sign reversed. Fresh parameters start at their source minima;
the unassigned load channel remains zero during this ordinary path.

Linear and cubic envelopes retain their authored points. Pitch uses eight
octaves across the normalized envelope, centered at 0.5; this differs from raw
event/weapon pitch. Speaker spread is expressed in degrees. Unsupported curve,
parameter and layer types produce a diagnostic. The ship-specific engine layouts
and NPC engine instances still require additional implementation.

The Opening now owns a retained engine instance. The actual starting loadout is
ship 10, selecting event 45 in both supplied profiles. The inspector's default
ship 0 instead selects event 44. Controls are sampled after the camera and used
before the following manual movement pass. Cinematic phases preserve the last
parameter values while the sound follows the player's early movement position.
The slowdown's cached-event stop leaves this separate retained instance alone;
the later source replacement retires it and starts event 156 at the player.
That damaged engine retains its own timed layers and continues following movement.

The four ordinary clips use each edition's original stereo PCM and sample loop
indices. Lossless channel separation lets the native player rotate the channels
around the source direction according to the authored spread envelope. Shared
samples are decoded and separated once. The fourth clip's zero-degree inner cone
is neutral because its outside gain is also one. Native angular spread and cone
interpretation follow the documented [FMOD channel semantics](https://www.fmod.com/docs/api/content/generated/FMOD_ChannelControl_Set3DMinMaxDistance.html);
output uses [Godot's spatial panner](https://github.com/godotengine/godot/blob/4.7-stable/scene/3d/audio_stream_player_3d.cpp).
Stereo ignores elevation and a coincident source faces forward. Surround output
and exact original-mixer normalization have not been compared.

Both editions pass source mutations, 500 catalogue/upgrade selections, 1,680
envelope vectors, retained-frame checks and application/escape integration.
Nine native clip recordings verify loops, synchronized stereo, changing parameters,
pause silence and cleanup, including an identical-channel phase fixture. Two
additional recordings verify steering and pause in the actual Opening session.
These checks establish native playback; they do not establish original-mixer parity.

## Connected opening speech

All 23 opening transmissions have source-bound recordings. Each edition reads
its own text-to-event table, so different localization IDs resolve correctly.
Speech starts once, strictly after the same two-second delay as its radio text.
Text completion does not stop or restart the recording. Its original sample can
finish independently. Radio remains timed communication; it does not become an
acknowledged modal instruction or freeze ordinary flight.

German text selects the original German bank. Every other supplied text language
uses the original English bank, matching the source language selection rule.
The chosen edition supplies both its bank and recording. A missing recording
remains silent while its text still displays. Changing language closes the old
opening session before a new one can use the selected bank.

Voices use their authored gain and nonspatial playback. The source voice category
allows two simultaneous recordings. A third stops the oldest immediately, without
applying its ordinary 100 ms stop fade. Paused voices and once-only display flags
are retained; failed frames cannot consume a display or emit speech. The standalone
Radio inspector remains text-only. Later dialogue, actor-dependent voice
fallbacks and general dialogue interruption remain outside the connected scope.

## Connected ordinary weapons

The player's opening guns select event 54 (Nirai Charged Impulse); the opening
pirates select event 61 (Enemy Laser). Sounds require a successful launch and an
enabled sound entry. Permission, quantity, interval and capacity denials remain
silent. The two identical starting guns use one audible entry. The source selects
up to two player entries by midpoint price and duplicate item ID, using indices
from a sorted copy without reordering the original firing array. The native owner
preserves this distinction for mixed equipment.

Each edition imports its complete 233-entry player sound table independently;
missing entries remain absent. NPC sound selection uses a separate actor-kind
table. The connected NPC owner is still the three opening pirates. Beam, turret
and other unsupported weapon paths do not become playable from table presence.

Sounds retain the firing owner's position at launch. Player firing precedes each
NPC's firing or destruction cues. Equipment modifiers reuse the existing weapon
interval factor for pitch; the opening loadout leaves it unchanged. The original
samples have independent randomized pitch ranges of ±0.05 octave for event 54
and ±0.02 octave for event 61. Cached active events retain their sample and random
choice while accepting position and pitch updates. Older packs retain their
previous scope until imported with the new weapon audio declarations.

## Connected NPC destruction cues

The lethal NPC update starts event 20; breakup selects event 18 or 19 through
the existing world random stream. Their positions are captured before ship
movement. The audio player independently selects an original weighted sample
and pitch variation. These playlists permit consecutive repeated samples.

| Source event | Original sample choices | Pitch variation |
|---|---:|---:|
| 20, small ship destruction | 2 | ±0.05 octave |
| 18, big ship destruction | 4 | ±0.02 octave |
| 19, medium ship destruction | 5 | ±0.03 octave |

These are one-shot sounds with the original gain and distance range. The game
retains one cached handle per event ID. Starting an audible cached event updates
its position without restarting its sample or drawing new randomness. A finished
event can start again; an explicit stop and restart is also respected. The FEV
maximum for separately acquired instances does not create additional voices.
The native path does not claim an identical original mixer or random sequence.

Reader v74 adds a separate `destruction_audio` capability after verifying the
actual sound calls and position arguments. Older motion-only declarations do
not silently acquire audio ownership.

## Connected escape cues

The source controller selects the following events through its imported IDs.
These mappings were independently checked in both supplied editions; matching
numbers do not establish compatibility for other content profiles.

| Source event | Native behavior |
|---|---|
| 141, Space Combat Mid | Looping music; 800 ms stop fade |
| 143, Intro Atmo | Looping music; 800 ms stop fade |
| 156, Spaceship Engine 05 Broken | Continuous spatial loop and three repeating one-shot windows; 14-sample playlist; 500 ms stop fade |
| 157, Cutscenes Explosion | Spatial one-shot with source range and position |
| 158, Rumble CutScene 01 | Nonspatial one-shot |
| 159, TimeSpaceJumpEnd | Nonspatial arrival sound |
| 160, SpaceTimeJump | Nonspatial departure sound |
| 161, Engine 09 Broken | Spatial loop; 400 ms stop fade |

Event 156 retains its original two layers. A looping parameter advances at the
authored velocity and triggers three one-shot windows over a continuous engine
loop. Each burst selects from the original weighted playlist. A repeated random
selection advances to the next entry, following the supplied library's rule.
Gain varies in linear amplitude from the authored attenuation to full level;
pitch varies by the authored range, equivalent here to ±0.1 octave. The native
audio generator has its own random stream; it does not reproduce the original
shared random sequence or consume gameplay randomness. This sound does not make
the arrival scene complete.

Preparation validates every command before playback. The session commits audio
only after the world and presentation accept the entire frame. A repeated frame
does not restart a sound; a rejected frame preserves layered parameter time and
randomness and emits no new sound. Positions and authored gains follow committed
frames. Stop fades follow the simulation clock.
Pause freezes active and retiring sounds, including a newly queued spatial play
request. Native mixing may finish its already queued buffer before falling silent.
Leaving the session stops its players and releases its listener ownership.

## Imported formats

The bounded FEV reader accepts RIFF `FEV ` / Designer `0x45` projects with the
verified chunk and legacy record layouts. It normalizes the depth-first event
index, event properties, category tree, sound definitions, layer/parameter data,
envelopes and language-specific bank references. Normalizing a layered event does
not imply that its playback behavior is implemented. Other versions and nonempty
FMOD music compositions are rejected. The source event file is limited to 8 MiB.

Schema 2 corrects the sound-setting types: spawn delays are unsigned milliseconds,
followed by maximum spawned polyphony and linear volume. Existing v72/schema 1
packs are normalized in memory, preserving the original delay bits. v73 and newer packs
emit the corrected names and types. Packed playlist modes and parameter loop
flags follow the supplied format version, whose meanings differ from older FEV
layouts. Other scheduling modes, overlapping windows, additional envelope types, delayed spawning
and layer effects remain unsupported.

Both supplied profiles contain 2,293 events, 2,293 sound definitions, 17 logical
banks and 22 physical banks. All bank references and sample indices were checked.
English and German bank variants are retained. Reader v76 connects the original
language fallback to the opening radio owner.

`fsb5.gd` accepts the verified FSB5 version 1 layouts: PCM16, Xbox IMA ADPCM and
MPEG Layer III, mono or stereo, with bounded sample counts, names, rates and loop
endpoints. Xbox IMA is decoded natively, including the predictor sample and the
unused final nibble in each 64-frame block. MPEG frames have their FMOD alignment
padding removed before Godot's MP3 decoder reads them. A partial MPEG loop end is
unsupported. Banks are limited to 192 MiB and individual decoded PCM clips to
64 MiB. The current session supports up to four opened banks and 128 MiB of
decoded PCM.

FEV bank hash prefixes must match the chosen FSB header. The content library also
checks resource size and SHA-256 against the selected base manifest. Imported
declarations and decoded sounds stay in the player's private content; source and
engine packages contain neither.

## Verification and limits

Native checks cover all 4,416 sample headers per edition, synthetic malformed
banks, PCM and IMA boundaries, MPEG durations, loop selection, source gain,
unsupported categories/cones, pause, stop fades and frame rollback. Ten original
IMA samples across both editions match an independent decoder byte for byte.
Music and spatial-effect recordings contain nonzero samples, then silence with
a stationary playback cursor after pause settles. Both editions pass the native
and Linux OpenGL full-escape checks.

Destruction checks cover original playlist sizes and pitch ranges, pre-movement
positions, cached active starts, natural sample completion, pause, cleanup,
rejected frames and source identity. Both editions pass the full opening checks
with each NPC's death and breakup audio matched to its committed frame. Native
recordings contain the original samples and settle to silence after pause and
cleanup. Reader mutation checks reject changed sound calls or detached evidence.

Weapon checks additionally cover mixed and duplicate equipment, source price
ordering, absent events, silent denied launches, equipment pitch, ordered NPC
cues and whole-frame rejection. Application checks drive actual keyboard fire
through committed playback and verify failed/paused frame isolation. Both editions
have real PCM captures checking
cached playback, pause, natural completion and silent cleanup.

Radio checks cover all 23 English/German source displays, strict delay and finish
boundaries, missing recordings, language fallback, malformed packs, once-only
commitment and oldest-voice stealing. Full application and escape checks match
spoken events to their displayed text and committed frame. Real English/German
recordings from both editions verify playback, pause silence, natural completion
and cleanup. These checks do not establish original-runtime mixer parity.

Layered checks cover parameter wrapping, all three repeated windows, weighted
selection, gain and pitch ranges, shared per-definition choice history, unchanged
continuous playback, pause and rejected-frame rollback. Both v73 and legacy v72
packs pass. Native recordings of event 156 include the loop and repeated bursts,
then zero-valued output with stationary voice cursors after pause settles.

The native spatial path uses the authored linear distance range with Godot
panning. Full FMOD reverb, DSP, speaker routing, Doppler, category preferences,
other playlist modes and parameter automation remain unverified or unsupported.
Special/NPC engines, special weapons, player/scenery destruction, scanner feedback, later dialogue and music
transitions still need source-bound owners. These checks do not establish an
original-runtime mix comparison, complete opening fidelity or full-game support.

From the source repository, use matching imported content, bindings and visuals:

```sh
godot --headless --path game --script res://tests/fsb5.gd -- CONTENT BINDINGS VISUALS
godot --headless --path game --script res://tests/opening_audio.gd -- CONTENT BINDINGS VISUALS
godot --headless --path game --script res://tests/weapon_audio.gd -- CONTENT BINDINGS VISUALS
godot --headless --path game --script res://tests/radio_audio.gd -- CONTENT BINDINGS VISUALS
godot --headless --path game --script res://tests/engine_playback.gd -- CONTENT BINDINGS VISUALS
godot --headless --path game --script res://tests/opening_engine_audio.gd -- CONTENT BINDINGS VISUALS
godot --headless --path game --script res://tests/audio_sequence.gd
```

The format work uses [vgmstream's FSB5 research](https://github.com/vgmstream/vgmstream/blob/master/src/meta/fsb5.c)
and [FEV layout research](https://github.com/vgmstream/vgmstream/blob/master/src/meta/fsb_fev.h).
Attribution and the ISC license are in [third-party notices](../THIRD_PARTY_NOTICES.md).
The [FMOD Designer 2010 manual](https://www.stephanschutze.com/uploads/3/1/0/6/3106267/fmod_designer_2010_v1.5_final.pdf)
also informed sound-instance and parameter interpretation; version-specific
selection and scalar rules were checked by static inspection of supplied content.
