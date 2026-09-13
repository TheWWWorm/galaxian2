# First station visits

Current Mac packs continue through both mining returns into the starter equipment
hangar. Purchases and installed equipment have separate ownership; installing a
weapon and armor plate unlocks Gunant's original acknowledged completion line.
See [equipment controls and scope](EQUIPMENT.md). Combat-training departure is
still unfinished. Earlier implementation checkpoints below describe their
individual support boundaries.

The v104 native mining-flight component can return to Var Hastra after the
acknowledged cargo objective. Station selection is required. Its contact test uses
the player position before movement and a strict 16,000-unit radius; the later
arrival check also accepts the current authored station boxes. An unfinished
initial objective refuses entry and shows the original restriction notice only
on a selected station-volume contact. Proximity grants no reward.

Arrival retains the same ship/equipment, earned cargo and current hull, armor,
shield and energy. Shield and energy are truncated for the next flight cache.
The returned hangar uses the shared camera and portrait scene, with five original
lines and English/German recordings. Cargo stays aboard through those lines.
Final acknowledgement advances cursor 3 to 4, clears the entire hold through the
next mission's source-defined initialization, and selects its 25-ton parameter.
It grants no credits and does not complete the full mining tutorial.

Reader v105 adds preparation for the second mining departure. After the delivery
conversation, the station owner retains the same ship, equipment and earned
progress and requires the emptied hold and 25-ton mission. Departure clears all
four cached pools to −1, then the shared player initializer restores the starter's
95 hull and full energy. Preparing this packet leaves the returned station and
its damaged arrival values intact. It still requires departure confirmation.
Reader v106 adds detached construction of the second world. It uses the ordinary
Var Hastra field and creates the source pirate at (0, 0, −200000), retaining its
generated route and cargo. Its constructor and weapon-effect draws precede the
entry camera draws. Preparation preserves earned progress and the current
station; it does not start the encounter. Reader v107 adds detached combat and
weapon ownership. At difficulty 0.5 the pirate starts with 36 hull without Opening
kills, or 50 hull with one to three credited kills. Its primary does 1 damage at
a strict interval greater than 592 ms. Shared player contacts use those settings.
Reader v108 connects the shared NPC targeting and flight controller, including
the distinct proximity and held-target activation timing. Reader v109 adds cargo-bearing pirate destruction and kill-counter deltas.
Reader v110 adds the one-line second briefing and the two-line warning when the
owned hold reaches25tons. Final acknowledgement selects the source return
mission without a reward. Original portraits and speech use the shared native
owners. Reader v111 adds the authored pirate placement, including preservation
of an early encounter or death. Container rendering, the subsequent station
return and full world/application ownership remain unfinished, so launch is
still unavailable. The starter has no tractor; general recovery is later work.

The application now connects departure confirmation, first-flight controls and
clock, original briefing speech, native drilling and the return flight. It stops
after the returned station conversation; the second mining trip and remaining
engine/mining sound owners are unfinished. Desktop and simulated phone views, all 12 Mac text languages, speech
selection, pause and failed-transition preservation are checked.

With Mac binding reader v90, the Opening tab continues automatically from the
completed rescue into Var Hastra. It shows the original Mido hangar and starter
ship, a moving source-bound camera, original portraits, and the 19-line station
conversation. Re-prepare older Mac bindings to enable this sequence.

Use Enter, Right, controller A or Next to acknowledge a line. Left, controller B
or the previous button returns to the preceding line. Esc or controller Start
pauses; focus loss and leaving the tab also pause independently. Desktop text and
panels stay compact, while the phone layout uses larger text and touch targets.
Long text scrolls. This acknowledged conversation does not use radio auto-timing.

The station replaces the damaged ship's loadout with source ship 0 and items
90 and 81, each in its declared equipment slot with quantity one. It preserves
the rescue's kill credit and rank. Source ship configuration values and item
markings are retained for later consumers; their full effects are not implemented.
The shared loadout assembler validates categories, slot limits and content identity.

The conversation starts after the source's one-second station delay. All 12 Mac
text languages use their original speaker and text bindings. Reader v91 also
imports the Mac desktop text substitutions: desktop instructions say “Click”,
while phone composition retains the source touch wording. Raw text IDs remain
unchanged for voice selection. Eighteen lines play
original speech, in German for German text and English otherwise. Next or Previous
stops the old voice before starting the selected line. The final instruction is
silent. Station portraits have a different source selection table from flight
radio; the native panel imports that table and reuses the shared atlas compositor.

Acknowledging the final instruction advances the story cursor from 1 to 2 and
selects the next source mission declaration. It grants no credit reward and does
not mark mining completed. Repeated acknowledgements cannot advance it again.
With current v104 bindings, Depart now opens the original confirmation and starts
the mining trip. Station services and persistent saves remain unfinished.

Reader v92 adds native preparation for the first departure. It builds a detached
flight packet for the replacement ship: 95 hull, no equipped armor or shield,
empty cargo, the retained earned progress, and mission 154's ten-ton parameter.
All four cached player pools reset to −1 before ordinary initialization, so the
opening ship's special health and damage cannot carry over. Preparation requires
the completed station conversation and leaves the station unchanged on failure
or retry. It retains the original “Depart the station?” confirmation requirement.
This packet feeds the native first-flight session after the departure confirmation.

Reader v93 adds detached construction for that first flight: its original station
and system, the 130-object ordinary asteroid field, no authored NPC ships, the
replacement player's initial position and yaw, and the shared follow camera.
Environment and field construction use separate source time seeds; wormhole
placement draws precede the yaw draw. The wormhole position is recorded for its
future scene owner. Failed preparation preserves the previous prepared world.
This construction does not activate flight or advance the entry or briefing clocks.
The source briefing waits for entry-camera release as well as its own time gate.
The application uses this construction; wormhole interaction remains unfinished.

Reader v94 adds the first mining briefing as a separate native component. Its
entry clock releases at 7,001 ms. The corrected poll clock holds during departure,
then resumes toward its strict 5,001-millisecond briefing threshold. The HUD checks
readiness before the controller. Acknowledged instructions
hold simulation time. The final acknowledgement clears the pending briefing and
resumes time without changing cargo, mission completion, rewards or story progress.
Four lines use original speech, followed by a silent instruction. The shared
portrait panel supports the original touch wording and the desktop variant with
the caller's active mining/dock key label. Switching between phone and desktop
layouts also resizes the shared panel correctly, keeping navigation onscreen.
The application now uses this component for its acknowledged mining briefing.

The native first-flight frame now connects this construction and briefing to
ordinary ship motion, asteroid updates and the shared camera. During entry the
ship travels forward while the camera eye stays fixed. At 7,001 ms the controller
enables damage and switches to the following camera on that same frame. The
briefing opens when its separate poll clock becomes due and still advances the
world on that creation frame; later modal frames hold it. Explicit acknowledgement resumes ordinary steering without
altering mission progress. Prospective frames and navigation preserve the current
world if validation fails.

The companion scene renders the original replacement ship, sky, planets, sun,
asteroid field and briefing. This is a development component using supported
bindings. It does not yet implement ship/scenery collisions,
animated wormhole geometry or engine/mining sounds. Station geometry and spoken
instructions are connected. The
collision permission flag is recorded independently of collision support.

Reader v95 adds a separate native drilling component and original-art display,
with equipment-based performance, ring progression, failure and capacity-limited
extraction plans. A native transaction now prepares the updated 25-ton cargo hold
and asteroid retirement together, rejects replay and mismatched branches, and
hides mined geometry in the first-flight scene. The v98 live connection is described below; see [mining scope](MINING.md).

Reader v96 connects source asteroid acquisition to the first-flight frame and
renders its original scan ring, center frame and aim reticle. The starter scanner
uses the nearest of the first four candidates inside the aim window and loses
selection when the aim moves away. Pause and modal instructions stop acquisition.
The application still stops after the station conversation.

Reader v97 adds native approach to an acquired asteroid, including guided travel,
source stand-off, local ship tilt, frozen close camera and per-target spin control.
Cancellation, pause and rejected-frame rollback preserve its owners.

Reader v98 connects approach to the equipped drill, original mining panel and
atomic cargo/asteroid extraction. Creation advances no drill time. Later frames
update drilling before scenery randomness and latch input for the next frame.
Stopping collects earned ore; failure loses it; full extraction places the core
first within the 25-ton hold. Automatic finishing resumes movement on that frame;
manual stopping resumes it on the next. These components grant no mission reward.
Reader v99 adds the six source mining notices, their timed queue and original
blue-bar artwork. Approach/cancel, full-hold refusal and drill failure now enqueue
localized feedback; a notice does not require acknowledgement. Drilling hides and
holds the queue. All12 Mac languages are checked on desktop and phone viewports.
Reader v100 adds the ten-ton total-cargo predicate and three acknowledged return
instructions, using two original recordings and a silent final instruction. The
last acknowledgement selects the return mission at Var Hastra, retaining cargo
and granting no credits. It also corrects the departure-held poll clock; the
earlier immediate-after-release briefing claim is superseded. The application now
connects launch, input, acknowledged speech and the first station return.

## Verification and remaining presentation work

The station accepts a detached rescue packet only after checking its identity,
player cache, progress, three finished transmissions and final black fade. Failed
preparation retains the completed rescue. Scene navigation validates before
committing story changes or speech. Loading consumes no scene time; pause gaps
are discarded and hidden scenes cannot accept conversation input.

Native checks cover the full Opening-to-station application path, 19 keyboard
acknowledgements, retained earned progress, all 12 text languages, camera motion,
pause, invalid declarations and rollback. Native OpenGL screenshots cover desktop
and simulated phone layouts; PCM recordings check English/German playback,
replacement, pause silence and cleanup. These are Linux checks, not physical
mobile/controller QA or an original-game framebuffer or mixer comparison.

The v90 static reader verifies 53 additional bounded source spans and emits only
semantic data and provenance. Camera motion uses recovered angles, projection,
axis limits and interpolation with an isolated native RNG; it does not reproduce
the original global random history. Hangar animation stays at its initial pose
until its playback clock is verified. Material lighting remains provisional:
source light parameters are recovered, but original shader/render state is not
fully connected. Station atmosphere envelopes and cross-scene music are also
unfinished. Older packs have no inferred station presentation capability.
Further iOS work remains deferred.

The mining briefing has separate native timing, ownership and navigation checks,
all 12 Mac text languages, and English/German voice decoding and selection checks.
Linux OpenGL captures cover 1280×720 desktop and 420×800 phone-sized viewports,
including layout changes and scrollable translations. These are component checks,
not a playable mining scene, physical phone/controller validation or a new mixer
comparison. The v94 reader verifies 23 bounded additional source spans and depends
on the previously verified flight, portrait/voice and desktop-text declarations.

The live first-flight component passes 80 checks for travel, camera ordering,
entry permissions, pause, delayed steering, frame ownership, rejected updates
and preserved campaign state. Seven OpenGL captures cover entry, release,
briefing and resumed motion, including a phone-sized viewport. The shared rescue
scene also passes 714 regression checks. These checks do not establish full
mining gameplay or fidelity against a recording of the original executable.
