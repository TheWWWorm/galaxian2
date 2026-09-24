# Android Mac app importer

The Android build accepts either a player-selected Mac `.dmg` or a ZIP
containing one original Galaxy on Fire 2 Full HD Mac `.app`. The Android
document picker supplies a `content://` URI. The Godot `DmgImport` adapter
calls the `GoF2AndroidImport` plugin, which copies the document into app-private
storage and runs the same Python `gof2_content.game_install.prepare` pipeline
used on desktop. For a DMG, that pipeline uses the bundled 7-Zip helper to
unpack the original Mac app. The original executable is read only for static
declarations; it is never run. The resulting `installation.json` preserves
`mac-dmg` identity for a disk image and `mac-app` identity for an app ZIP.

Android executes the helper from its package-manager-owned `nativeLibraryDir`.
The build names the Android PIE executable `libgof2_7zz.so`, stages it under
`lib/<abi>/` in the APK, and sets Gradle `useLegacyPackaging true` so the
installer extracts it. Executable code is not copied into writable app storage.
The standalone helper links the NDK C++ runtime statically, so its process only
depends on Android system libraries.
Imports need substantial free device storage: the selected archive, extracted
resources, decoded content, and temporary files coexist during preparation.
The preflight estimate is conservative; available space is rechecked while
copying and preparing. Cancellation removes temporary work and leaves a
previous completed import and saves in place.

`build_android.py` stages only source-manifest allowlisted game and importer
files. It builds Android `capstone==5.0.6` and
`texture2ddecoder==1.0.6` wheels for one ABI against Chaquopy Python 3.12,
and compiles unmodified upstream 7-Zip 26.03 from its SHA-256-pinned source
archive. RAR support is disabled; DMG, HFS and APFS readers remain. It then
exports Godot 4.7 with the Java plugin. The build script currently requires
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
custom wheels include Capstone and texture decoder licenses. The APK also
includes 7-Zip's license and full LGPL text under `assets/licenses/`; the exact
upstream source archive and hash are recorded in `build_android.py` and
`THIRD_PARTY_NOTICES.md`. No proprietary game content is packaged.
