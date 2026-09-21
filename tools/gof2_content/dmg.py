"""Read a local Mac disk image through 7-Zip without mounting or running it."""
from pathlib import Path
import os
import shutil
import stat
import subprocess
import tempfile
import time

from .formats import ContentError

MAX_LISTING = 32 * 1024 * 1024
MAX_ENTRIES = 20000
MAX_TOTAL = 8 * 1024 * 1024 * 1024
MAX_FILE = 256 * 1024 * 1024


def app_files(listing):
    """Select one regular app subtree; never extract volume links or helpers."""
    from .bundle import safe_name
    rows = []
    seen = set()
    for block in listing.split('\n\n'):
        if not block.strip():
            continue
        row = {}
        for line in block.splitlines():
            if ' = ' not in line:
                raise ContentError('Unsupported DMG archive listing')
            key, value = line.split(' = ', 1)
            if key in row:
                raise ContentError('Ambiguous DMG archive metadata')
            row[key] = value.replace(os.sep, '/') if key == 'Path' else value
        name = safe_name(row.get('Path', ''))
        if name.casefold() in seen:
            raise ContentError('Duplicate or ambiguous DMG path: ' + name)
        seen.add(name.casefold())
        rows.append(row)
        if len(rows) > MAX_ENTRIES:
            raise ContentError('Too many DMG entries')
    infos = [r['Path'] for r in rows if r['Path'].endswith('.app/Contents/Info.plist')]
    if len(infos) != 1:
        raise ContentError('Expected exactly one Mac application in the DMG')
    app = infos[0].removesuffix('/Contents/Info.plist')
    selected = {}
    for row in rows:
        name = row['Path']
        if name != app and not name.startswith(app + '/'):
            continue
        mode = row.get('Mode', '')
        folder = row.get('Folder') == '+'
        if (row.get('Encrypted', '-') != '-' or row.get('Alternate Stream', '-') != '-'
                or row.get('Symbolic Link') or row.get('Hard Link')
                or not mode.startswith('d' if folder else '-')):
            raise ContentError('Unsupported link, encrypted or special file in Mac app: ' + name)
        if folder:
            continue
        try:
            size = int(row['Size'])
        except (ValueError, KeyError) as error:
            raise ContentError('Invalid DMG file size: ' + name) from error
        if not 0 <= size <= MAX_FILE:
            raise ContentError('Mac app file exceeds the import limit: ' + name)
        selected[name] = size
    if sum(selected.values()) > MAX_TOTAL:
        raise ContentError('Mac app exceeds the import size limit')
    return app, selected


class DmgApp:
    def __init__(self, source, checkpoint=lambda *_: None, work=None):
        self.source = Path(source).absolute()
        self.checkpoint = checkpoint
        self.work = work
        self.stage = None

    def __enter__(self):
        try:
            return self.extract()
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *_):
        if self.stage is not None:
            self.stage.cleanup()
            self.stage = None

    def run_tool(self, tool, arguments, report, message):
        with report.open('wb') as output:
            child = subprocess.Popen([tool, *arguments], stdin=subprocess.DEVNULL,
                                     stdout=output, stderr=subprocess.STDOUT)
            started = time.monotonic()
            try:
                while child.poll() is None:
                    self.checkpoint(message, 0.0)
                    if report.stat().st_size > MAX_LISTING or time.monotonic() - started > 600:
                        raise ContentError('DMG extraction exceeded its output or time limit')
                    time.sleep(0.1)
            except BaseException:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill(); child.wait()
                raise
        if report.stat().st_size > MAX_LISTING:
            raise ContentError('DMG listing exceeds the import limit')
        result = report.read_text('utf-8', errors='replace')
        if child.returncode:
            raise ContentError('Could not read this Mac DMG: ' + result[-1600:])
        return result.replace('\r\n', '\n')

    def extract(self):
        if (self.source.suffix.lower() != '.dmg' or self.source.is_symlink()
                or not self.source.is_file()):
            raise ContentError('Choose a readable Mac .dmg file')
        before = self.source.stat()
        with self.source.open('rb') as source:
            if before.st_size < 512:
                raise ContentError('The Mac DMG is truncated')
            source.seek(-512, 2)
            if source.read(4) != b'koly':
                raise ContentError('Unsupported Mac disk image; expected a UDIF DMG')
        bundled = Path(__file__).resolve().parents[2] / '7zip' / ('7z.exe' if os.name == 'nt' else '7zz')
        tool = (os.environ.get('GOF2_7ZIP') or (str(bundled) if bundled.is_file() else None)
                or shutil.which('7zz') or shutil.which('7z'))
        if not tool:
            raise ContentError('The DMG importer needs 7-Zip (7zz or 7z). Install the importer dependencies before playing.')
        self.stage = tempfile.TemporaryDirectory(prefix='gof2-dmg-', dir=self.work)
        root = Path(self.stage.name)
        listing = self.run_tool(tool, ['l', '-slt', '-ba', '-sns-', '-sccUTF-8', '-p-', '--', str(self.source)],
                                root / 'listing.txt', 'Reading the Mac disk image')
        app, files = app_files(listing)
        names = root / 'files.txt'
        names.write_text('\n'.join(files) + '\n', encoding='utf-8')
        destination = root / 'app'
        destination.mkdir()
        # HFS extended attributes are not content. Without this explicit switch,
        # 7-Zip may extract unlisted :com.apple.quarantine streams alongside files.
        self.run_tool(tool, ['x', '-y', '-spd', '-sns-', '-scsUTF-8', '-sccUTF-8', '-p-', '-bd', '-bb0',
                             '-o' + str(destination), '-i@' + str(names), '--', str(self.source)],
                      root / 'extraction.txt', 'Unpacking the original Mac content')
        after = self.source.stat()
        if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
            raise ContentError('The DMG changed during import')
        for name, size in files.items():
            path = destination / name
            if path.is_symlink() or not path.is_file() or not stat.S_ISREG(path.lstat().st_mode) or path.stat().st_size != size:
                raise ContentError('The extracted Mac file is incomplete or unsupported: ' + name)
            parent = path.parent
            while parent != destination:
                if parent.is_symlink():
                    raise ContentError('The Mac app contains a directory link')
                parent = parent.parent
        self.checkpoint('Mac disk image unpacked', 1.0)
        return destination / app
