"""Read-only IPA/app ZIP and extracted app access, with bounded streaming."""
from contextlib import contextmanager
from pathlib import Path, PurePosixPath
import os
import plistlib
import stat
import zipfile

from .formats import ContentError

MAX_ENTRIES = 20000
MAX_RESOURCE = 256 * 1024 * 1024
MAX_TOTAL = 8 * 1024 * 1024 * 1024
CHUNK = 1024 * 1024
LANGUAGES = {'de', 'es', 'fr', 'gb', 'it', 'ja', 'ko', 'pl', 'ptl', 'ru', 'zs', 'zt'}
CATALOGUES = {'agents', 'collision', 'collision_test', 'docks', 'docks_hd', 'items',
              'shipparts', 'ships', 'static_collisions', 'stationparts', 'stations',
              'systems', 'ticker', 'wanted', 'weapons_hd', 'weapons_sd', 'wreck_collisions',
              'names_bobolan_0', 'names_bobolan_1', 'names_cyborg_0', 'names_grey_0',
              'names_multipod_0', 'names_multipod_1', 'names_nivelian_0', 'names_nivelian_1',
              'names_terran_0_m', 'names_terran_0_w', 'names_terran_1', 'names_vossk_0', 'names_vossk_1'}


def safe_name(name: str) -> str:
    parts = name.split('/')
    if (not name or len(name) > 1024 or '\\' in name or ':' in name
            or any(p in ('', '.', '..') for p in parts)
            or any(ord(c) < 32 for c in name)):
        raise ContentError(f'Unsafe resource path: {name!r}')
    return name


def selected(name: str) -> bool:
    p = PurePosixPath(name)
    if len(p.parts) == 1:
        return ((p.suffix == '.lang' and p.stem in LANGUAGES)
                or (p.name.startswith('FMOD_GOF2') and p.suffix in ('.fsb', '.fev')))
    if p.parent.as_posix() == 'data/bin':
        return p.suffix == '.bin' and p.stem in CATALOGUES
    if p.parent.as_posix() in ('data/meshes', 'data/textures'):
        return ((p.parent.name == 'meshes' and p.suffix == '.aem')
                or (p.parent.name == 'textures' and p.suffix == '.aei'))
    return (len(p.parts) >= 5 and p.parts[:2] == ('data', 'assets')
            and p.parts[2] in ('main', 'valkyrie', 'supernova') and p.suffix in ('.aem', '.aei'))


class Bundle:
    def __init__(self, source: Path, checkpoint=lambda *_: None):
        self.source = source.absolute()
        self.zip = None
        self.entries = {}
        self.root = ''
        self.profile = {}
        self.info_path = ''
        self.executable_name = None
        self.dmg = None
        self.checkpoint = checkpoint

    def __enter__(self):
        try:
            self._discover()
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *_):
        if self.zip:
            self.zip.close()
        if self.dmg:
            self.dmg.__exit__(None, None, None)

    def _discover(self):
        if self.source.is_symlink():
            raise ContentError('Choose a regular archive or extracted .app, not a symbolic link')
        if self.source.suffix.lower() == '.dmg':
            from .dmg import DmgApp
            self.dmg = DmgApp(self.source, self.checkpoint)
            self.source = self.dmg.__enter__()
            self._discover()
            if self.profile.get('edition') != 'mac-full-hd':
                raise ContentError('The DMG must contain Galaxy on Fire 2 Full HD for Mac')
            return
        if self.source.is_dir():
            if self.source.suffix != '.app':
                raise ContentError('Choose the extracted .app directory itself')
            seen = set()
            for base, dirs, files in os.walk(self.source, followlinks=False):
                for name in dirs + files:
                    path = Path(base) / name
                    rel = safe_name(path.relative_to(self.source).as_posix())
                    if rel.casefold() in seen:
                        raise ContentError(f'Ambiguous case-insensitive path: {rel}')
                    seen.add(rel.casefold())
                    if len(seen) > MAX_ENTRIES:
                        raise ContentError('Too many bundle entries')
                    mode = path.lstat().st_mode
                    if stat.S_ISLNK(mode) or not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                        raise ContentError(f'Unsupported link or special file in app: {rel}')
                    if stat.S_ISREG(mode):
                        self.entries[rel] = (path.stat().st_size, path)
            candidates = [n for n in ('Info.plist', 'Contents/Info.plist') if n in self.entries]
        else:
            try:
                self.zip = zipfile.ZipFile(self.source)
            except (zipfile.BadZipFile, OSError) as error:
                raise ContentError('Choose a readable IPA or ZIP containing one .app') from error
            infos = self.zip.infolist()
            if len(infos) > MAX_ENTRIES:
                raise ContentError('Too many archive entries')
            seen = set()
            for info in infos:
                name = safe_name(info.filename[:-1] if info.is_dir() else info.filename)
                if name.casefold() in seen:
                    raise ContentError(f'Duplicate or ambiguous archive path: {name}')
                seen.add(name.casefold())
                mode = info.external_attr >> 16
                if stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
                    raise ContentError(f'Unsupported archive link or special file: {name}')
                if info.flag_bits & 1:
                    raise ContentError(f'Encrypted archive entry: {name}')
                if not info.is_dir():
                    self.entries[name] = (info.file_size, info)
            candidates = [n for n in self.entries if n.endswith('.app/Info.plist') or n.endswith('.app/Contents/Info.plist')]
        if len(candidates) != 1:
            raise ContentError('Expected exactly one application bundle with Info.plist')
        info_path = candidates[0]
        try:
            info = plistlib.loads(self.read(info_path, 1024 * 1024))
        except (plistlib.InvalidFileException, ValueError, TypeError) as error:
            raise ContentError('Invalid bundle Info.plist') from error
        if not isinstance(info, dict):
            raise ContentError('Bundle Info.plist must be a dictionary')
        bundle_id = info.get('CFBundleIdentifier')
        if bundle_id == 'www.fishlabs.net.gof2hd' and not info_path.endswith('Contents/Info.plist'):
            edition = 'ios-hd'
            self.root = info_path.removesuffix('Info.plist')
        elif bundle_id == 'www.fishlabs.net.gof2mac' and info_path.endswith('Contents/Info.plist'):
            edition = 'mac-full-hd'
            self.root = info_path.removesuffix('Info.plist') + 'Resources/'
        else:
            raise ContentError('Unsupported bundle identity or layout; expected GoF2 iOS HD or Mac Full HD')
        self.profile = {'edition': edition, 'bundle_identifier': bundle_id,
                        'bundle_version': str(info.get('CFBundleShortVersionString', info.get('CFBundleVersion', 'unknown')))}
        self.info_path = info_path
        self.executable_name = info.get('CFBundleExecutable')

    def executable(self):
        """Locate optional import-time static input; never open or execute it here."""
        name = self.executable_name
        if not isinstance(name, str) or '/' in name:
            raise ContentError('Missing or invalid CFBundleExecutable for declaration extraction')
        safe_name(name)
        prefix = self.info_path.removesuffix('Info.plist')
        path = prefix + ('MacOS/' if self.profile['edition'] == 'mac-full-hd' else '') + name
        if path not in self.entries:
            raise ContentError('Bundle executable named by Info.plist is missing')
        return path

    def resources(self) -> dict[str, int]:
        resources = {n[len(self.root):]: v[0] for n, v in self.entries.items()
                     if n.startswith(self.root) and selected(n[len(self.root):])}
        if any(size <= 0 or size > MAX_RESOURCE for size in resources.values()):
            raise ContentError('Empty resource or resource exceeds the 256 MiB import limit')
        if sum(resources.values()) > MAX_TOTAL:
            raise ContentError('Resource set exceeds the 8 GiB import limit')
        required = {f'data/bin/{n}.bin' for n in ('ships', 'items', 'systems', 'stations')}
        required |= {'gb.lang'}
        missing = required - resources.keys()
        if missing:
            raise ContentError('Missing required resources: ' + ', '.join(sorted(missing)))
        for suffix in ('.aem', '.aei'):
            if not any(n.startswith('data/assets/main/') and n.endswith(suffix) for n in resources):
                raise ContentError(f'Missing main asset family: {suffix}')
        return dict(sorted(resources.items()))

    @contextmanager
    def open(self, name):
        size, entry = self.entries[name]
        if self.zip:
            with self.zip.open(entry) as stream:
                yield stream
        else:
            # Refuse a link substituted since discovery, including parent directories.
            path = entry
            while path != self.source.parent:
                if path.is_symlink():
                    raise ContentError(f'Bundle changed to a symbolic link: {name}')
                path = path.parent
            with entry.open('rb') as stream:
                if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                    raise ContentError(f'Not a regular resource: {name}')
                yield stream

    def read(self, name, limit):
        if self.entries[name][0] > limit:
            raise ContentError(f'Oversized metadata: {name}')
        with self.open(name) as stream:
            data = stream.read(limit + 1)
        if len(data) > limit or len(data) != self.entries[name][0]:
            raise ContentError(f'Resource size changed: {name}')
        return data
