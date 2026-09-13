# Galaxy on Fire 2 Remake

A native Godot recreation of Galaxy on Fire 2 that uses content imported locally
from your own copy of the game. Original game files are not included.

This project is in early development. With current Mac Full HD content, you can
play the opening encounter, rescue, two mining trips, starter equipment tutorial,
and combat training through its return to Var Hastra. The following station
mission and later campaign are still being built.
Persistent saves, the complete economy and the remaining base-game and expansion
missions are not ready. See [what is supported](docs/SUPPORT.md).

## What you need

- A supported Mac Full HD app, an app ZIP, or iOS HD IPA. Either edition can be
  imported on its own. Development currently focuses on Mac Full HD; iOS gameplay
  support does not match the current Mac sequence.
- Godot 4.4 or newer and Python 3.10 or newer to run from source. The current
  desktop checks use Godot 4.7 and Python 3.12 on Linux.
- Space outside this repository for imported content and prepared textures.
  Base content needs approximately 2.7 GB for Mac or 1.3 GB for iOS; textures and
  temporary import files need additional space.

There are no packaged releases yet. Windows, macOS, Android and Web delivery
remain development targets; this source checkout does not establish device support.

## Import your game

Run these commands from the repository directory. Replace the example paths with
your own. Keep the original game, imported content and prepared files outside this
source folder.

```bash
python3 tools/import_content.py import "/path/to/Game.app" --cache "/path/to/gof2-content"
```

You can use an app ZIP or IPA in place of the `.app`. Direct DMG import is not yet
available: extract the app first. The original executable is never run.
The command prints the installed content directory; use that complete path below.

Prepare the import tools in a Python environment:

```bash
python3 -m venv /path/to/gof2-import-env
/path/to/gof2-import-env/bin/python -m pip install -r tools/requirements-visuals.txt -r tools/requirements-bindings.txt
/path/to/gof2-import-env/bin/python tools/prepare_visuals.py "/path/to/gof2-content/CONTENT_ID" --output "/path/to/gof2-visuals"
/path/to/gof2-import-env/bin/python tools/prepare_bindings.py "/path/to/Game.app" "/path/to/gof2-content/CONTENT_ID" --output "/path/to/gof2-bindings"
```

On Windows, use the environment's `Scripts/python.exe`. Each preparation command
prints a separate output directory. Use content, textures and bindings from the
same edition and import. These Python dependencies are only needed during import;
the running game uses Godot.

## Start playing

```bash
godot --path game -- --content "/path/to/gof2-content/CONTENT_ID" --bindings "/path/to/gof2-bindings/BINDING_ID" --visuals "/path/to/gof2-visuals/PACK_ID" --opening-preview
```

Alternatively, open `game/project.godot` in Godot. Use **Open imported content**,
**Open resource bindings** and **Open prepared textures** to select their manifest
files, then choose **Opening → Run opening scene**.

**Esc** or controller **Start** pauses the scene. Leaving the window pauses it
independently. **Touch controls** enables on-screen flight actions; they are hidden
by default on desktop. Follow the original tutorial instructions as they appear.
An unfinished mission stays unavailable instead of awarding progress.

The launcher also includes asset, world and radio inspectors. These previews let
you explore imported models, original catalogue names and dialogue independently
of the playable sequence. A preview is not a completed campaign mission.

## Updating and troubleshooting

After changes that add content support, prepare bindings again with the current
tools. Existing imports keep their identities; a failed or cancelled import leaves
previously installed content intact. Use **Ctrl+C** to cancel a command-line import.

If preparation reports an unsupported layout or missing resource, keep the error
message and the edition/version details when reporting it. Do not attach original
archives, executables, imported content or saves to a public issue. Details about
individual systems and current limitations are in the [support overview](docs/SUPPORT.md).

## Building and contributing

See [development and verification](docs/DEVELOPMENT.md) for focused tests, scenario
fixtures and source packaging, and [architecture](ARCHITECTURE.md) for the engine
structure. The source package contains an explicit allowlist of engine files.

The engine is licensed under [Apache 2.0](LICENSE.md). Original game content keeps
its original ownership and is imported separately. Reused components and their
licenses are listed in [third-party notices](THIRD_PARTY_NOTICES.md).
