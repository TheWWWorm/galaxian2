# Development and verification

Run commands from the source repository. Python 3.10+ runs the tooling; native
checks require Godot 4.4+. Imported game content, test captures and reports belong
outside the repository. Tests never include original assets or player saves.

## Shared check runner

```bash
python3 tools/run_checks.py source
python3 tools/run_checks.py python --pattern test_run_checks.py
python3 tools/run_checks.py editor --godot /path/to/godot
python3 tools/run_checks.py native asset_readers --godot /path/to/godot
```

`--godot` can be omitted if `godot` or `godot4` is on PATH. Alternatively set
`GOF2_GODOT`. Each check reports elapsed time and returns failure for a nonzero
process exit, a Godot script error, a reported failed assertion or a timeout.

Content-dependent native tests take explicit paths:

```bash
python3 tools/run_checks.py native combat_training_destruction --content /path/to/CONTENT_ID --bindings /path/to/BINDING_ID --visuals /path/to/PACK_ID
```

You can instead use `--args-file /path/to/args.json`, containing a JSON array of
positional content arguments. Relative entries are resolved against that file's
directory. Do not mix it with the named content options. Older tests that accept
only content and bindings can use a two-entry array.

Use `--log /path/to/check.log` and `--report /path/to/check.json` to retain output
and timings. `--timeout SECONDS` sets the process limit. These outputs must stay
outside the source repository. `--gpu` uses the compatibility renderer;
`--captures /path/to/images` appends a capture directory for tests that accept it.
GPU and audio-device checks remain separate from headless simulation checks.

## Focused combat scenarios

The complete combat integration test runs the rescue, both mining returns and
acknowledged equipment tutorial before checking encounter components. Capture
that earned equipment state once:

```bash
python3 tools/run_checks.py native combat_training_destruction --args-file /path/to/args.json --capture-scenario /path/to/equipment-scenario.bin
```

Then run the same construction, control, weapon and destruction component checks
without replaying the application sequence:

```bash
python3 tools/run_checks.py native combat_training_focused --args-file /path/to/args.json --scenario /path/to/equipment-scenario.bin
```

With current Mac bindings, `combat_training_visuals` adds the projectile and
impact checks to that same scenario. Add `--gpu --captures /path/to/captures` to
capture each original weapon model independently.

`combat_training_flight` also exercises the shared scene and the application
from that earned station state through training, return-trip mining, nine return
lines, station reload and a separate game-over branch. Use the same scenario
argument; `--gpu --captures /path/to/captures` adds application screenshots.
`flight_waypoint_marker` checks the source marker crops, distance format, route
boundaries and independent player/companion progress without a tutorial fixture.

The fixture replays the tutorial's accepted inventory transactions and compares
all resulting equipment to the captured state. It rejects mismatched content or
bindings, changed prerequisite code, incomplete acknowledgement and altered
inventory. The runner publishes a capture only after its integration run passes;
a failed run preserves any previous capture. Recapture after a prerequisite
change or when choosing another binding pack.

The focused construction tests cover detached simulation components. Neither
those tests nor the flight fixtures exercise player saves or prove an unmodified
playthrough. Close placements and direct damage isolate the tested transitions.
Retain the complete integration run when changing session transitions or closing
an encounter milestone. No scenario file belongs in a source package.

## Player entry definitions

`game/src/content/player_entry_definitions.gd` resolves the supported opening,
rescue, mining and combat-training entry differences from validated content.
`opening_player_state.gd` uses those definitions for cache preparation and incoming
weapon context. New entry support should extend the resolver with source-backed
rules and affected tests instead of adding campaign-number branches throughout
shared player initialization. Existing unsupported entries remain rejected.

## Source packaging

`source-manifest.json` explicitly lists every public source file. Add new engine
files and their Godot UIDs deliberately. The shared source check validates file
paths, symlinks, resource references, shader includes and UID ownership. The
packager uses the same validation:

```bash
python3 tools/package_source.py /path/outside/repository/gof2-source.zip
```

Only allowlisted source enters the archive. Original game archives, executable
files, imported resources, scenario data, caches and saves must remain outside.
The repository's Git history provides source baselines and change comparisons;
a source package does not include the repository's Git metadata.
