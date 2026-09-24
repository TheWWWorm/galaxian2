#!/usr/bin/env python3
"""Build an engine-only Godot Android APK with a direct Mac app ZIP importer.

Build dependencies are downloaded into --work, verified, and compiled for one
Android ABI. Original game files and prepared imports are never build inputs.
"""
import argparse
import base64
import hashlib
import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request
import zipfile


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "platform/android_importer"
PYTHON_TARGET = "3.12.12-0"
CHAQUOPY = "17.0.0"
NDK_VERSION = "27.3.13750724"
NDK_NOTICE_SHA256 = "cbe3237be53c0a819f8df6aac5358fdee848eee3b6571b4e2ca20767ebd7465e"
API = 29
ARCHES = {"arm64-v8a": "aarch64", "x86_64": "x86_64"}
SOURCES = {
    "capstone-5.0.6.tar.gz": (
        "https://files.pythonhosted.org/packages/source/c/capstone/capstone-5.0.6.tar.gz",
        "b11a87d67751b006b9b44428d59c99512e6d6c89cf7dff8cdd92d9065628b5a0"),
    "texture2ddecoder-1.0.6.tar.gz": (
        "https://files.pythonhosted.org/packages/source/t/texture2ddecoder/texture2ddecoder-1.0.6.tar.gz",
        "88f04d8951018ac13b8dacd07e57e8adad4a6f1cfe5509646e8a1020346a81ca"),
}
TARGET_HASHES = {
    "arm64-v8a": "7a4a278ec1fed0e0d0359fbec71d6d481d79a7efbc8e2090267a91046417027a",
    "x86_64": "d4140d76c0a3c73bbbb89a7139e9bcc3080b37f210f2c343acfdea8b21113aad",
}
RUNTIME_NOTICES = {
    "Godot-LICENSE.txt": (
        "https://raw.githubusercontent.com/godotengine/godot/4.7-stable/LICENSE.txt",
        "b0435e3b3e4e55238f05f4b306f30524a1b2e20147810d436eaa554fa6855c80"),
    "Godot-COPYRIGHT.txt": (
        "https://raw.githubusercontent.com/godotengine/godot/4.7-stable/COPYRIGHT.txt",
        "cb1980c88089573bcacd7221d777c689bb8bbd778799f24c27fca0fe5f774d6d"),
    "Chaquopy-LICENSE.txt": (
        "https://raw.githubusercontent.com/chaquo/chaquopy/17.0.0/LICENSE.txt",
        "345a9fdfeed355d37b18569ef277ba56eb0ab7c0b17a08a90163ce8d33d2b862"),
    "CPython-LICENSE": (
        "https://raw.githubusercontent.com/python/cpython/v3.12.12/LICENSE",
        "3b2f81fe21d181c499c59a256c8e1968455d6689d269aa85373bfb6af41da3bf"),
    "OpenSSL-LICENSE.txt": (
        "https://raw.githubusercontent.com/openssl/openssl/openssl-3.0.18/LICENSE.txt",
        "7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a"),
    "SQLite-copyright.html": (
        "https://www.sqlite.org/copyright.html",
        "44ca9f793055c8e32fc65f65a4f5bcf813a33f5bdaaa084067dd617a4ed3cc70"),
    "LLVM-libcxx-LICENSE.txt": (
        "https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-21.1.0/libcxx/LICENSE.TXT",
        "539dd7aed86e8a4f12cbdd0e6c50c189c7d74847e4fecc64ce2c6ee3a01da38b"),
}


def checked_download(url, target, expected=None):
    if not target.is_file():
        with urllib.request.urlopen(url, timeout=60) as response, target.open("wb") as output:
            while block := response.read(1024 * 1024):
                output.write(block)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    if expected is not None and digest != expected:
        raise ValueError("Dependency checksum mismatch: " + target.name)
    return target


def command(args, *, cwd=None, env=None, log=None, timeout=900):
    if log is None:
        subprocess.run(args, cwd=cwd, env=env, check=True, timeout=timeout)
    else:
        with log.open("w") as output:
            subprocess.run(args, cwd=cwd, env=env, stdout=output,
                           stderr=subprocess.STDOUT, check=True, timeout=timeout)


def wheel(output, name, version, tag, files, licenses):
    dist = f"{name}-{version}.dist-info"
    files.update({f"{dist}/licenses/{name}": data for name, data in licenses.items()})
    rows = {}
    for path, data in files.items():
        digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()
        rows[path] = f"sha256={digest},{len(data)}"
    files[f"{dist}/METADATA"] = (f"Metadata-Version: 2.1\nName: {name}\n"
                                  f"Version: {version}\n").encode()
    files[f"{dist}/WHEEL"] = (f"Wheel-Version: 1.0\nGenerator: GoF2 Android build\n"
                               f"Root-Is-Purelib: false\nTag: {tag}\n").encode()
    for path in (f"{dist}/METADATA", f"{dist}/WHEEL"):
        data = files[path]
        digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()
        rows[path] = f"sha256={digest},{len(data)}"
    record = f"{dist}/RECORD"
    files[record] = ("\n".join(f"{path},{rows[path]}" for path in sorted(rows))
                     + f"\n{record},,\n").encode()
    path = output / f"{name}-{version}-{tag}.whl"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for member, data in sorted(files.items()):
            archive.writestr(member, data)
    return path


def native_wheels(work, ndk, abi):
    deps = work / "deps"
    deps.mkdir()
    for filename, (url, digest) in SOURCES.items():
        path = checked_download(url, deps / filename, digest)
        with tarfile.open(path) as archive:
            archive.extractall(deps, filter="data")
    target_name = f"target-{PYTHON_TARGET}-{abi}.zip"
    target_url = (f"https://repo.maven.apache.org/maven2/com/chaquo/python/target/"
                  f"{PYTHON_TARGET}/{target_name}")
    target_zip = checked_download(target_url, deps / target_name, TARGET_HASHES.get(abi))
    target = deps / "chaquopy-target"
    with zipfile.ZipFile(target_zip) as archive:
        for name in archive.namelist():
            if name.startswith("include/") or name == f"jniLibs/{abi}/libpython3.12.so":
                archive.extract(name, target)

    capstone = deps / "capstone-5.0.6"
    capbuild = deps / "build-capstone"
    command(["cmake", "-S", str(capstone / "src"), "-B", str(capbuild),
             f"-DCMAKE_TOOLCHAIN_FILE={ndk}/build/cmake/android.toolchain.cmake",
             f"-DANDROID_ABI={abi}", f"-DANDROID_PLATFORM=android-{API}",
             "-DCMAKE_BUILD_TYPE=Release", "-DBUILD_SHARED_LIBS=ON",
             "-DBUILD_STATIC_LIBS=OFF", "-DCAPSTONE_ARCHITECTURE_DEFAULT=OFF",
             "-DCAPSTONE_ARM_SUPPORT=ON", "-DCAPSTONE_X86_SUPPORT=ON",
             "-DCAPSTONE_BUILD_TESTS=OFF", "-DCAPSTONE_BUILD_CSTOOL=OFF"],
            log=work / "capstone-configure.log")
    command(["cmake", "--build", str(capbuild), "-j", "4"],
            log=work / "capstone-build.log")
    cap_files = {f"capstone/{path.relative_to(capstone / 'capstone').as_posix()}": path.read_bytes()
                 for path in (capstone / "capstone").rglob("*.py")}
    cap_files["capstone/lib/libcapstone.so"] = (capbuild / "libcapstone.so").read_bytes()

    texture = deps / "texture2ddecoder-1.0.6"
    clang = ndk / "toolchains/llvm/prebuilt/linux-x86_64/bin" / f"{ARCHES[abi]}-linux-android{API}-clang++"
    sources = [str(path) for path in sorted((texture / "src").rglob("*.cpp"))
               if path.name not in {"Texture2DDecoder.cpp", "AssemblyInfo.cpp"}]
    decoded = deps / "_texture2ddecoder.abi3.so"
    command([str(clang), "-std=c++17", "-fms-extensions", "-w", "-fPIC", "-O2",
             "-shared", "-DPy_LIMITED_API=0x030B0000",
             "-I" + str(target / "include/python3.12"),
             "-I" + str(texture / "src/Texture2DDecoder"), *sources,
             "-L" + str(target / f"jniLibs/{abi}"), "-lpython3.12",
             "-o", str(decoded)], log=work / "texture-build.log")
    tex_files = {"texture2ddecoder/__init__.py": (texture / "texture2ddecoder/__init__.py").read_bytes(),
                 "texture2ddecoder/_texture2ddecoder.abi3.so": decoded.read_bytes(),
                 "texture2ddecoder/_texture2ddecoder.pyi":
                     (texture / "texture2ddecoder/_texture2ddecoder.pyi").read_bytes(),
                 "texture2ddecoder/py.typed": b""}
    wheels = work / "wheels"
    wheels.mkdir()
    suffix = abi.replace("-", "_")
    cap_licenses = {"LICENSE.TXT": (capstone / "LICENSE.TXT").read_bytes(),
                    "LICENSE_LLVM.TXT": (capstone / "src/LICENSE_LLVM.TXT").read_bytes()}
    tex_licenses = {"LICENSE": (texture / "LICENSE").read_bytes()}
    return (wheel(wheels, "capstone", "5.0.6", f"py3-none-android_{API}_{suffix}",
                  cap_files, cap_licenses),
            wheel(wheels, "texture2ddecoder", "1.0.6", f"cp311-abi3-android_{API}_{suffix}",
                  tex_files, tex_licenses))


def replace_once(path, before, after):
    content = path.read_text()
    if content.count(before) != 1:
        raise ValueError("Godot template changed: " + str(path))
    path.write_text(content.replace(before, after))


def stage_project(work, template, wheels, abi, ndk, *, release=False,
                  version_name=None, version_code=None):
    sys.path.insert(0, str(ROOT / "tools"))
    from source_checks import manifest_files
    stage = work / "stage"
    stage.mkdir()
    allowed = manifest_files(ROOT)
    for name in allowed:
        if not name.startswith("game/") or name.startswith("game/tests/"):
            continue
        destination = stage / Path(name).relative_to("game")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, destination)
    project = stage / "project.godot"
    replace_once(project, "[rendering]", "[rendering]\ntextures/vram_compression/import_etc2_astc=true")
    build = stage / "android/build"
    build.mkdir(parents=True)
    with zipfile.ZipFile(template) as archive:
        for member in archive.infolist():
            if member.filename.startswith("/") or ".." in Path(member.filename).parts:
                raise ValueError("Unsafe Godot build template entry")
        archive.extractall(build)
    (stage / "android/.build_version").write_text("4.7.stable\n")
    (build / ".gdignore").touch()
    (build / "gradlew").chmod(0o755)
    replace_once(build / "settings.gradle", "id 'org.jetbrains.kotlin.android' version versions.kotlinVersion",
                 "id 'org.jetbrains.kotlin.android' version versions.kotlinVersion\n"
                 f"        id 'com.chaquo.python' version '{CHAQUOPY}'")
    replace_once(build / "build.gradle", "id 'org.jetbrains.kotlin.android'",
                 "id 'org.jetbrains.kotlin.android'\n    id 'com.chaquo.python'")
    replace_once(build / "build.gradle", "String[] export_abi_list = getExportEnabledABIs()",
                 f'String[] export_abi_list = ["{abi}"]')
    replace_once(build / "build.gradle", "main.res.srcDirs += ['res']",
                 "main.res.srcDirs += ['res']\n"
                 "        main.assets.srcDirs += ['src/licenses/assets']")
    replace_once(build / "config.gradle", "ndkVersion         : '29.0.14206865'",
                 f"ndkVersion         : '{NDK_VERSION}'")
    manifest = build / "src/main/AndroidManifest.xml"
    replace_once(manifest, "    </application>",
                 '        <meta-data android:name="org.godotengine.plugin.v2.GoF2AndroidImport"\n'
                 '            android:value="io.github.thewwworm.gof2.android.AndroidImportPlugin" />\n'
                 '    </application>')
    java = build / "src/main/java/io/github/thewwworm/gof2/android/AndroidImportPlugin.java"
    java.parent.mkdir(parents=True)
    shutil.copyfile(SOURCE / "AndroidImportPlugin.java", java)
    python = build / "src/main/python"
    python.mkdir(parents=True)
    shutil.copyfile(SOURCE / "android_import_worker.py", python / "android_import_worker.py")
    if "tools/import_game.py" not in allowed:
        raise ValueError("Shared importer is missing from the source allowlist")
    shutil.copyfile(ROOT / "tools/import_game.py", python / "import_game.py")
    package = python / "gof2_content"
    package.mkdir()
    for name in allowed:
        if name.startswith("tools/gof2_content/") and name.endswith(".py"):
            shutil.copyfile(ROOT / name, package / Path(name).name)
    # Godot regenerates src/main/assets for each export. A separate Gradle
    # assets source set keeps notices in the final APK through that cleanup.
    notices = build / "src/licenses/assets/licenses"
    notices.mkdir(parents=True)
    for name in ("LICENSE.md", "THIRD_PARTY_NOTICES.md"):
        if name not in allowed:
            raise ValueError("Public license file is missing from the source allowlist: " + name)
        shutil.copyfile(ROOT / name, notices / name)
    for name, (url, digest) in RUNTIME_NOTICES.items():
        checked_download(url, notices / name, digest)
    ndk_notice = ndk / "NOTICE.toolchain"
    if hashlib.sha256(ndk_notice.read_bytes()).hexdigest() != NDK_NOTICE_SHA256:
        raise ValueError("Android NDK toolchain notice changed")
    shutil.copyfile(ndk_notice, notices / "Android-NDK-NOTICE.toolchain")
    wheel_dir = build / "src/main/wheels"
    wheel_dir.mkdir(parents=True)
    for path in wheels:
        shutil.copyfile(path, wheel_dir / path.name)
    chaquopy = ("\nchaquopy {\n    defaultConfig {\n        version '3.12'\n"
                f"        buildPython('{sys.executable}')\n        pip {{\n"
                + "".join(f"            install('src/main/wheels/{path.name}')\n" for path in wheels)
                + "        }\n    }\n}\n")
    with (build / "build.gradle").open("a") as output:
        output.write(chaquopy)
    options = [
        'gradle_build/use_gradle_build=true', 'gradle_build/export_format=0',
        'gradle_build/min_sdk="29"', 'gradle_build/target_sdk="36"',
        'architectures/armeabi-v7a=false', f'architectures/arm64-v8a={str(abi == "arm64-v8a").lower()}',
        'architectures/x86=false', f'architectures/x86_64={str(abi == "x86_64").lower()}',
        'package/unique_name="io.github.thewwworm.galaxian2.androidimport"',
        'package/name="Galaxian2"' if release else 'package/name="Galaxian2 Android Import"',
        'package/signed=true',
        'package/classify_as_game=true', 'screen/immersive_mode=true',
        'permissions/internet=false', 'permissions/read_external_storage=false',
        'permissions/write_external_storage=false', 'permissions/manage_external_storage=false',
    ]
    if version_code is not None:
        options.append(f'version/code={version_code}')
    if version_name is not None:
        options.append(f'version/name="{version_name}"')
    (stage / "export_presets.cfg").write_text(
        '[preset.0]\nname="Android Import"\nplatform="Android"\n'
        'runnable=true\nexport_filter="all_resources"\ninclude_filter=""\n'
        'exclude_filter="tests/*"\nscript_export_mode=2\n\n[preset.0.options]\n'
        + "\n".join(options) + "\n")
    return stage


def environment(work, sdk, ndk, java, templates, supplied_key=None, release=False):
    overlay = work / "sdk-overlay"
    overlay.mkdir()
    for child in sdk.iterdir():
        if child.name not in {"ndk", "platform-tools"}:
            (overlay / child.name).symlink_to(child, target_is_directory=child.is_dir())
    ndk_root = overlay / "ndk"
    ndk_root.mkdir()
    (ndk_root / NDK_VERSION).symlink_to(ndk, target_is_directory=True)
    platform = overlay / "platform-tools"
    platform.mkdir()
    for child in (sdk / "platform-tools").iterdir():
        if child.name != "adb":
            (platform / child.name).symlink_to(child, target_is_directory=child.is_dir())
    adb = platform / "adb"
    adb.write_text(f'#!/bin/sh\nexec "{sdk / "platform-tools/adb"}" -P 5049 "$@"\n')
    adb.chmod(0o755)
    settings = work / "config/godot"
    settings.mkdir(parents=True)
    data = work / "data/godot"
    data.mkdir(parents=True)
    (data / "export_templates").symlink_to(templates.parent, target_is_directory=True)
    if supplied_key is None:
        key = work / "key/android-debug.keystore"
        key.parent.mkdir(parents=True)
        alias, password = "androiddebugkey", "android"
        command([str(java / "bin/keytool"), "-genkeypair", "-noprompt", "-storetype", "PKCS12",
                 "-keystore", str(key), "-alias", alias, "-storepass", password,
                 "-keypass", password, "-keyalg", "RSA", "-keysize", "2048",
                 "-validity", "3650", "-dname", "CN=Android Import Diagnostic,O=GoF2,C=PL"],
                log=work / "key.log")
    else:
        key = supplied_key.resolve()
        alias = os.environ.get("GOF2_ANDROID_KEYSTORE_ALIAS", "")
        password = os.environ.get("GOF2_ANDROID_KEYSTORE_PASSWORD", "")
        if not key.is_file() or not alias or not password:
            raise ValueError("A supplied keystore needs a file and GOF2_ANDROID_KEYSTORE_ALIAS/PASSWORD")
    (settings / "editor_settings-4.7.tres").write_text(
        '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
        f'export/android/java_sdk_path = "{java}"\n'
        f'export/android/android_sdk_path = "{overlay}"\n'
        f'export/android/debug_keystore = "{key}"\n'
        f'export/android/debug_keystore_user = "{alias}"\n')
    env = os.environ.copy()
    env.update(XDG_CONFIG_HOME=str(work / "config"), XDG_DATA_HOME=str(work / "data"),
               XDG_CACHE_HOME=str(work / "cache"), JAVA_HOME=str(java),
               ANDROID_SDK_ROOT=str(overlay), ANDROID_HOME=str(overlay),
               ANDROID_USER_HOME=str(work / "android-user"),
               ADB_SERVER_PORT="5049", ADB_SERVER_SOCKET="tcp:127.0.0.1:5049",
               GRADLE_USER_HOME=str(work / "gradle"),
               GODOT_ANDROID_KEYSTORE_DEBUG_PATH=str(key),
               GODOT_ANDROID_KEYSTORE_DEBUG_USER=alias,
               GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=password)
    if release:
        env.update(GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(key),
                   GODOT_ANDROID_KEYSTORE_RELEASE_USER=alias,
                   GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=password)
    env["PATH"] = str(platform) + os.pathsep + env.get("PATH", "")
    return env


def verify_apk(output, abi):
    with zipfile.ZipFile(output) as archive:
        names = archive.namelist()
        if not any(name.startswith(f"lib/{abi}/") for name in names):
            raise ValueError("Target Android ABI libraries missing")
        if any(name.startswith("lib/") and not name.startswith(f"lib/{abi}/") for name in names):
            raise ValueError("Unexpected Android ABI in APK")
        if any(Path(name).suffix.lower() in {".dmg", ".ipa", ".aem", ".aei", ".gof2save"}
               or "installation.json" in name for name in names):
            raise ValueError("Original content or import receipt entered the APK")
        expected = {"assets/licenses/" + name for name in
                    ("LICENSE.md", "THIRD_PARTY_NOTICES.md", "Android-NDK-NOTICE.toolchain",
                     *RUNTIME_NOTICES)}
        if not expected.issubset(names):
            raise ValueError("Required third-party notices missing from APK")
        if not any(name.endswith(".dex") and b"AndroidImportPlugin" in archive.read(name)
                   for name in names):
            raise ValueError("Android import plugin missing from APK")
        try:
            with zipfile.ZipFile(io.BytesIO(archive.read("assets/chaquopy/app.imy"))) as python:
                if not {"android_import_worker.pyc", "import_game.pyc",
                        "gof2_content/game_install.pyc"}.issubset(python.namelist()):
                    raise ValueError("Shared Mac app ZIP importer missing from APK")
            with zipfile.ZipFile(io.BytesIO(archive.read("assets/chaquopy/requirements-common.imy"))) as packages:
                licenses = {"capstone-5.0.6.dist-info/licenses/LICENSE.TXT",
                            "capstone-5.0.6.dist-info/licenses/LICENSE_LLVM.TXT",
                            "texture2ddecoder-1.0.6.dist-info/licenses/LICENSE"}
                if not licenses.issubset(packages.namelist()):
                    raise ValueError("Android importer dependency licenses missing from APK")
                machine = {"arm64-v8a": 183, "x86_64": 62}[abi]
                for native in ("capstone/lib/libcapstone.so",
                               "texture2ddecoder/_texture2ddecoder.abi3.so"):
                    elf = packages.read(native)
                    if elf[:4] != b"\x7fELF" or int.from_bytes(elf[18:20], "little") != machine:
                        raise ValueError("Android importer native dependency has the wrong ABI: " + native)
        except (KeyError, zipfile.BadZipFile) as error:
            raise ValueError("Android Python importer missing from APK") from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--sdk", type=Path, required=True)
    parser.add_argument("--ndk", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--templates", type=Path, required=True,
                        help="Godot 4.7 android_source.zip")
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--abi", choices=ARCHES, default="arm64-v8a")
    parser.add_argument("--keystore", type=Path,
                        help="Reuse a private signing key for upgrade-compatible APKs")
    parser.add_argument("--release", action="store_true",
                        help="Export a release-mode APK with the supplied signing key")
    parser.add_argument("--version-name", help="Android versionName, required for release")
    parser.add_argument("--version-code", type=int,
                        help="Positive Android versionCode, required for release")
    args = parser.parse_args()
    if args.release and (args.keystore is None or args.version_name is None
                         or args.version_code is None):
        parser.error("Release export requires --keystore, --version-name and --version-code")
    if args.version_code is not None and not 1 <= args.version_code <= 2100000000:
        parser.error("Android versionCode must be between 1 and 2100000000")
    if args.version_name is not None and (len(args.version_name) > 64 or
                                         re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", args.version_name) is None):
        parser.error("Android versionName must use 1–64 letters, digits, dots, underscores or hyphens")
    work = args.work.resolve()
    output = args.output.resolve()
    if work.exists() or output.exists() or work.is_relative_to(ROOT) or output.is_relative_to(ROOT):
        parser.error("Use fresh, private work and output paths outside the source tree")
    if not args.ndk.joinpath("source.properties").is_file() or not args.templates.is_file():
        parser.error("Android NDK or Godot 4.7 Android source template is missing")
    if args.keystore is not None and args.keystore.resolve().is_relative_to(ROOT):
        parser.error("Keep the Android signing key outside the source tree")
    work.mkdir(parents=True)
    print("Building native importer dependencies", flush=True)
    wheels = native_wheels(work, args.ndk.resolve(), args.abi)
    print("Staging the engine-only Android Gradle project", flush=True)
    stage = stage_project(work, args.templates.resolve(), wheels, args.abi,
                          args.ndk.resolve(), release=args.release,
                          version_name=args.version_name, version_code=args.version_code)
    env = environment(work, args.sdk.resolve(), args.ndk.resolve(), args.java.resolve(),
                      args.templates.resolve(), args.keystore, args.release)
    print("Importing Godot project resources", flush=True)
    command([str(args.godot), "--headless", "--path", str(stage), "--editor", "--import"],
            env=env, log=work / "godot-editor.log", timeout=300)
    print("Exporting Android APK with direct ZIP importer", flush=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    command([str(args.godot), "--headless", "--path", str(stage),
             "--export-release" if args.release else "--export-debug",
             "Android Import", str(output)], env=env, log=work / "godot-export.log", timeout=1200)
    verify_apk(output, args.abi)
    print(output, output.stat().st_size, hashlib.sha256(output.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
