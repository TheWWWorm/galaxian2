# Android Mac app importer

The Android build accepts a player-selected ZIP containing one original Galaxy
on Fire 2 Full HD Mac `.app`. The Android document picker supplies a `content://`
URI. The Godot `DmgImport` adapter calls the `GoF2AndroidImport` plugin, which
copies the document into app-private storage and runs the same Python
`gof2_content.game_install.prepare` pipeline used on desktop. The original
executable is read only for static declarations; it is never run. The resulting
`installation.json` has the ordinary `mac-app` receipt and content IDs.

Android `.dmg` extraction is not implemented. The picker and importer only
offer a Mac `.app` ZIP, and a selected `.dmg` receives an explicit ZIP error.
Imports need substantial free device storage: the selected ZIP, extracted
resources, decoded content, and temporary files coexist during preparation.
The preflight estimate is conservative; available space is rechecked while
copying and preparing. Cancellation removes temporary work and leaves a
previous completed import and saves in place.

`build_android.py` stages only source-manifest allowlisted game and importer
files. It builds Android `capstone==5.0.6` and
`texture2ddecoder==1.0.6` wheels for one ABI against Chaquopy Python 3.12,
then exports Godot 4.7 with the Java plugin. The build script currently requires
a Linux x86-64 host because its NDK compiler path is platform specific. Build
inputs are the Godot editor,
its matching `android_source.zip` export template, Android SDK (API 36 and
build tools), Android NDK r27d, JDK 21, CMake, and host Python 3.12. Use
`--abi arm64-v8a` for distribution; `x86_64` is only for emulator diagnosis.
Pass separate, fresh `--work` and `--output` paths outside the source tree.
Those paths contain build downloads and a task-local signing key and must not
be committed. The build rejects original content and save files in the APK.
For a player build, pass `--release --version-name VERSION --version-code CODE`
and `--keystore` with a dedicated private release key. Set
`GOF2_ANDROID_KEYSTORE_ALIAS` and `GOF2_ANDROID_KEYSTORE_PASSWORD` in the build
environment. Keep the same package ID, signing key and increasing positive
version code for future updates that retain private imports and saves. The
release build displays the name Galaxian2. Without `--release`, the existing
debug export and diagnostic label remain available; omitting `--keystore`
creates a fresh diagnostic key that cannot update another installation.
Signing credentials, work directories and output APKs remain outside the source
repository.

The plugin bridge exposes `startImport(uri, dataDirectory, statusPath,
cancelPath)`, `isImportRunning()`, `lastError()`, and `cancelImport()`. Status
JSON and the final receipt follow the desktop importer contract. The APK
includes the public project license/notices and pinned Godot, Chaquopy,
CPython, OpenSSL, SQLite, LLVM libc++, and Android NDK toolchain notices; the
custom wheels include Capstone and texture decoder licenses. No proprietary
game content is packaged.
