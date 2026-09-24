# Attribution

The import staging, content isolation and allowlisted source packaging architecture
reference the Apache-2.0 maintained GoF1/GoF3D replacement engine. The language
record reader adapts its `game/src/content/formats.gd` length-prefixed UTF-8 layout
into bounded Python parsing. The source packager adapts its
`tools/package_source.py`. The original Apache-2.0 license is preserved here.
The flight input adapter also adapts GoF3D's controller ownership and deadzone
pattern from `game/src/input/controls.gd`, with native GoF2 action mapping,
keyboard/touch routing and focus handling. Its deadzone is a configurable remake
input preference, not a recovered original flight parameter. No GoF1 campaign
logic, content or compiled products are copied.

Native station persistence follows the same content isolation, staged write and
previous-save backup approach as GoF3D's `game/src/simulation/session.gd` and
`save_transfer.gd`. Its explicit data schema and owner restoration are designed
for the GoF2 engine; the two games' save formats are separate.

GoF1 previously incorporated DEEP import/save architecture. The release notice
exporter adapts DEEP's Apache-2.0 `tools/export_notices.gd`; desktop packaging
also follows its isolated staging and offline helper pattern.

Godot is MIT licensed: https://godotengine.org/license/ . Desktop releases include
its runtime and complete notices in `GODOT_LICENSES.txt`. Source packages require
a separately installed Godot editor.

Original Galaxy on Fire content belongs to its respective rights holders.
The engine license covers this engine's code only. Promotional screenshots show
locally imported content; no playable original resources are bundled.

AEM/AEI layout investigation consulted BaalNetbek's AEMesh format research:
https://github.com/BaalNetbek/AEMesh . No implementation from that repository is
bundled; native readers and samplers are independently implemented.

Import-time texture decompression uses `texture2ddecoder` 1.0.6,
Copyright (c) 2020 K0lb3, under the MIT license:
https://github.com/K0lb3/texture2ddecoder . Desktop packages include its wheel,
license and upstream notices in the importer's Python site-packages directory.
Its compiled library is not bundled in the engine source ZIP.

Import-time declaration inspection uses Capstone 5.0.6, Copyright (c) 2013
COSEINC, under its BSD 3-clause license. Desktop packages include its wheel and
license in the importer's Python site-packages directory. Neither its compiled
library nor original-game executable bytes are included in source packages.
Capstone: https://www.capstone-engine.org/ .

Desktop import helpers include CPython 3.12.14 from Astral's
[python-build-standalone](https://github.com/astral-sh/python-build-standalone)
20260901 builds. Python and bundled dependency licenses are included under
`importer/licenses/python/`, along with Python's own license in its installation.
Python uses the PSF license; its bundled dependencies have their own licenses.

Android importer builds embed Chaquopy 17.0.0 and its CPython 3.12.12 runtime.
The APK includes the engine, Godot, Chaquopy and Python notices under
`assets/licenses/`, along with `OpenSSL-LICENSE.txt` (OpenSSL 3.0.18),
`SQLite-copyright.html` (SQLite 3.50.4), `LLVM-libcxx-LICENSE.txt`, and
`Android-NDK-NOTICE.toolchain` for the native runtime dependencies.
The custom Capstone and texture2ddecoder wheels retain their
upstream licenses under their `.dist-info/licenses/` directories. Android builds
compile these same pinned importer dependencies for the selected Android ABI;
they do not include original-game content or executable code.
Chaquopy: https://chaquo.com/chaquopy/ .

DMG extraction uses [7-Zip 26.03](https://github.com/ip7z/7zip/releases/tag/26.03),
Copyright (C) Igor Pavlov, under GNU LGPL with the BSD and unRAR restrictions
described in its included `importer/7zip/License.txt`. Corresponding source is
available with that release. The helper is a separate, replaceable executable.
Pinned download URLs and SHA-256 hashes for all desktop dependencies are recorded
in `tools/desktop-dependencies.json` and shipped as `importer/dependencies.json`.

The FEV layout reader and native FSB5/IMA/MPEG audio reader use format research
from [vgmstream](https://github.com/vgmstream/vgmstream): `src/meta/fsb_fev.h`,
`src/meta/fsb5.c`, `src/coding/ima_decoder.c`, and `mpeg_custom_utils.c`.
No FMOD runtime or game executable is linked or bundled. vgmstream is ISC licensed:

Copyright (c) 2008-2025 Adam Gashlin, Fastelbja, Ronny Elfert, bnnm,
                        Christopher Snowhill, NicknineTheEagle, bxaimc,
                        Thealexbarney, CyberBotX, EdnessP, et al

Portions Copyright (c) 2004-2008, Marko Kreen
Portions Copyright 2001-2007  jagarl / Kazunori Ueno <jagarl@creator.club.ne.jp>
Portions Copyright (c) 1998, Justin Frankel/Nullsoft Inc.
Portions Copyright (C) 2006 Nullsoft, Inc.
Portions Copyright (c) 2005-2007 Paul Hsieh
Portions Copyright (C) 2000-2004 Leshade Entis, Entis-soft.
Portions Public Domain originating with Sun Microsystems

Permission to use, copy, modify, and distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

The source DMG importer invokes a separately installed 7-Zip command-line tool
(`7zz` or `7z`) to read disk-image files. No 7-Zip binary is included in this
source tree. Distribution of packaged helpers must include the applicable
7-Zip licensing and notices.
