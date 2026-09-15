#!/usr/bin/env python3
"""Build allowlisted desktop previews with pinned, offline Mac DMG import tools."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile

from source_checks import manifest_files, source_closure

ROOT = Path(__file__).resolve().parents[1]
PLATFORMS = {'linux-x64': 'Linux', 'windows-x64': 'Windows Desktop',
             'macos-arm64': 'macOS'}


def fetch(record, cache):
    path = cache / record['sha256']
    if not path.is_file():
        with urllib.request.urlopen(record['url'], timeout=60) as response:
            data = response.read(256 * 1024 * 1024 + 1)
        if len(data) > 256 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != record['sha256']:
            raise ValueError('Dependency checksum mismatch: ' + record['name'])
        temporary = path.with_suffix('.partial')
        temporary.write_bytes(data)
        temporary.replace(path)
    if hashlib.sha256(path.read_bytes()).hexdigest() != record['sha256']:
        raise ValueError('Cached dependency checksum mismatch: ' + record['name'])
    return path


def unpack_tar(path, destination):
    with tarfile.open(path) as archive:
        archive.extractall(destination, filter='data')


def stage_importer(destination, platform, cache, extractor):
    destination.mkdir(parents=True)
    records = json.loads((ROOT / 'tools/desktop-dependencies.json').read_text())['files']
    selected = [r for r in records if r['platform'] in [platform, 'all'] or
                (r['platform'] == 'macos' and platform.startswith('macos'))]
    for record in selected:
        archive = fetch(record, cache)
        if record['kind'] == 'license':
            target = destination / 'licenses/python' / record['name']
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(archive, target)
        elif record['kind'] == 'python':
            unpack_tar(archive, destination)
        elif record['kind'] == '7zip':
            target = destination / '7zip'
            target.mkdir()
            if platform == 'windows-x64':
                subprocess.run([extractor, 'x', '-y', '-o' + str(target), str(archive)], check=True,
                               stdout=subprocess.DEVNULL)
                keep = {'7z.exe', '7z.dll', 'License.txt', 'readme.txt', 'History.txt'}
                for child in target.iterdir():
                    if child.name not in keep:
                        shutil.rmtree(child) if child.is_dir() else child.unlink()
            else:
                unpack_tar(archive, target)
    site = destination / ('python/Lib/site-packages' if platform == 'windows-x64'
                          else 'python/lib/python3.12/site-packages')
    for record in selected:
        if record['kind'] != 'wheel':
            continue
        with zipfile.ZipFile(fetch(record, cache)) as archive:
            for name in archive.namelist():
                if Path(name).is_absolute() or '..' in Path(name).parts:
                    raise ValueError('Unsafe wheel entry')
            archive.extractall(site)
    for name in manifest_files(ROOT):
        if name.startswith('tools/') and (name.endswith('.py') or name.endswith('.txt')):
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
    shutil.copyfile(ROOT / 'tools/desktop-dependencies.json', destination / 'dependencies.json')
    # Python's relocatable archives use internal links. Resolve only links inside
    # this staged importer so Windows ZIP extraction requires no symlink support.
    for path in sorted(destination.rglob('*')):
        if path.is_symlink():
            resolved = path.resolve()
            if not resolved.is_relative_to(destination.resolve()) or not resolved.is_file():
                raise ValueError('Unexpected dependency link: ' + str(path))
            data, mode = resolved.read_bytes(), resolved.stat().st_mode
            path.unlink(); path.write_bytes(data); path.chmod(mode)


def stage_project(stage, names, platform, version):
    for name in names:
        if not name.startswith('game/') or name.startswith('game/tests/'):
            continue
        target = stage / Path(name).relative_to('game')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, target)
    settings = stage / 'project.godot'
    text = settings.read_text().replace('config/name="GoF2 Remake"', 'config/name="Galaxian2"\nconfig/version=' + json.dumps(version))
    if platform.startswith('macos'):
        text = text.replace('[rendering]', '[rendering]\ntextures/vram_compression/import_etc2_astc=true')
    settings.write_text(text)
    options = {'binary_format/architecture': '"x86_64"', 'binary_format/embed_pck': 'true',
               'texture_format/s3tc_bptc': 'true', 'texture_format/etc2_astc': 'false'}
    if platform.startswith('macos'):
        options = {'application/bundle_identifier': '"io.github.thewwworm.galaxian2"',
                   'application/short_version': '"0.1.0"', 'application/version': '"0.1.0"',
                   'application/copyright': '"WWWorm"',
                   'binary_format/architecture': '"universal"', 'codesign/codesign': '0',
                   'notarization/notarization': '0', 'texture_format/s3tc_bptc': 'true',
                   'texture_format/etc2_astc': 'true'}
    elif platform == 'windows-x64':
        options['codesign/enable'] = 'false'
        options['application/product_name'] = '"Galaxian2"'
        options['application/file_description'] = '"Galaxy on Fire 2 native remake"'
    preset = ('[preset.0]\nname="desktop"\nplatform=' + json.dumps(PLATFORMS[platform]) +
              '\nrunnable=true\nexport_filter="all_resources"\ninclude_filter=""\n'
              'exclude_filter="tests/*"\nexport_path=""\nscript_export_mode=2\n\n[preset.0.options]\n')
    (stage / 'export_presets.cfg').write_text(preset + '\n'.join(k + '=' + v for k, v in options.items()) + '\n')


def archive_package(folder, output, platform):
    files = sorted(p for p in folder.rglob('*') if p.is_file())
    for path in files:
        if path.is_symlink() or path.suffix.lower() in {'.dmg', '.ipa', '.gof2save', '.aem', '.aei'}:
            raise ValueError('Private content or link in package: ' + str(path))
    if platform == 'linux-x64':
        with tarfile.open(output, 'w:gz') as archive:
            for path in files:
                archive.add(path, arcname='Galaxian2/' + path.relative_to(folder).as_posix(), recursive=False)
    else:
        with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
            for path in files:
                archive.write(path, path.relative_to(folder).as_posix())


def thin_apple_silicon(folder):
    """Retain the complete arm64 Mach-O slice of universal executables/libraries."""
    for path in folder.rglob('*'):
        if not path.is_file():
            continue
        with path.open('rb') as stream:
            header = stream.read(8)
        if len(header) != 8:
            continue
        magic, count = struct.unpack('>II', header)
        if magic not in (0xCAFEBABE, 0xCAFEBABF):
            continue
        if not 1 <= count <= 32:
            raise ValueError('Invalid universal executable: ' + str(path))
        data = path.read_bytes()
        width = 32 if magic == 0xCAFEBABF else 20
        for index in range(count):
            cpu, _, offset, size = struct.unpack_from('>IIQQ' if width == 32 else '>IIII', data, 8 + index * width)
            if cpu != 0x0100000C:
                continue
            if offset + size > len(data):
                raise ValueError('Invalid arm64 slice')
            path.write_bytes(data[offset:offset + size])
            break
        else:
            raise ValueError('No Apple Silicon slice: ' + str(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=PLATFORMS, required=True)
    parser.add_argument('--output', type=Path, required=True, help='Private build/output folder outside this checkout')
    parser.add_argument('--cache', type=Path, required=True, help='External dependency download cache')
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--extractor', default='7z', help='Build-host 7-Zip for the Windows helper')
    parser.add_argument('--version', default='0.1.0-preview.1')
    args = parser.parse_args()
    for path in (args.output, args.cache):
        if path.resolve().is_relative_to(ROOT):
            parser.error('Build output and dependency caches must be outside the repository')
        path.mkdir(parents=True, exist_ok=True)
    source_closure(ROOT)
    names = manifest_files(ROOT)
    folder = (args.output / args.platform).resolve()
    if folder.exists():
        parser.error('Use a fresh platform output folder: ' + str(folder))
    folder.mkdir()
    with tempfile.TemporaryDirectory(prefix='galaxian2-export-', dir=args.output) as temporary:
        stage = Path(temporary)
        stage_project(stage, names, args.platform, args.version)
        executable = folder / ('Galaxian2.exe' if args.platform == 'windows-x64' else
                               'Galaxian2.zip' if args.platform.startswith('macos') else 'Galaxian2')
        subprocess.run([args.godot, '--headless', '--path', str(stage), '--editor', '--import'], check=True, timeout=180)
        subprocess.run([args.godot, '--headless', '--path', str(stage), '--export-release', 'desktop', str(executable)], check=True, timeout=240)
    resource_root = folder
    if args.platform.startswith('macos'):
        with zipfile.ZipFile(executable) as archive:
            archive.extractall(folder)
            for info in archive.infolist():
                path = folder / info.filename
                if path.is_file() and info.external_attr >> 16:
                    path.chmod(info.external_attr >> 16)
        executable.unlink()
        resource_root = folder / 'Galaxian2.app/Contents/Resources'
    stage_importer(resource_root / 'importer', args.platform, args.cache.resolve(), args.extractor)
    if args.platform == 'macos-arm64':
        thin_apple_silicon(folder)
    for name in ('README.md', 'LICENSE.md', 'THIRD_PARTY_NOTICES.md'):
        shutil.copyfile(ROOT / name, folder / name)
    (folder / 'screenshots').mkdir()
    for path in (ROOT / 'screenshots').glob('*.png'):
        shutil.copyfile(path, folder / 'screenshots' / path.name)
    subprocess.run([args.godot, '--headless', '--script', str(ROOT / 'tools/export_notices.gd'),
                    '--', str(folder / 'GODOT_LICENSES.txt')], check=True, timeout=30)
    extension = '.tar.gz' if args.platform == 'linux-x64' else '.zip'
    output = args.output / ('Galaxian2-' + args.version + '-' + args.platform + extension)
    archive_package(folder, output, args.platform)
    print(str(output), hashlib.sha256(output.read_bytes()).hexdigest())


if __name__ == '__main__':
    main()
