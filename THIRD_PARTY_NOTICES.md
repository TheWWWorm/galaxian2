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

GoF1 previously incorporated DEEP import/save architecture. No additional DEEP
implementation is bundled in this foundation.

Godot is MIT licensed: https://godotengine.org/license/ . It is a separately
installed runtime at this stage and is not bundled in source packages.

Original Galaxy on Fire content belongs to its respective rights holders.
The engine license covers this engine's code only. No original content is bundled.

AEM/AEI layout investigation consulted BaalNetbek's AEMesh format research:
https://github.com/BaalNetbek/AEMesh . No implementation from that repository is
bundled; native readers and samplers are independently implemented.

Optional import-time texture decompression uses `texture2ddecoder` 1.0.6,
Copyright (c) 2020 K0lb3, under the MIT license:
https://github.com/K0lb3/texture2ddecoder . It is installed separately and its
compiled library is not bundled in the engine source ZIP. Its package carries
its license and upstream third-party notices.

Optional import-time ARM declaration inspection uses Capstone 5.0.6, Copyright
(c) 2013 COSEINC, under its BSD 3-clause license. It is installed separately;
neither its compiled library nor original-game executable bytes are included in
engine source packages. Capstone: https://www.capstone-engine.org/ .

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
