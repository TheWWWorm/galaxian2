"""Prepare a player-selected Mac app ZIP with the shared private Mac importer.

The Android bridge copies the SAF document to a private, bounded file before
calling this module. The original executable is only read as static input.
"""
from pathlib import Path
import os
import shutil
import time

from gof2_content.bundle import Bundle, CHUNK
from gof2_content.formats import ContentError
from gof2_content.game_install import prepare
from import_game import write_status


MAX_SOURCE = 8 * 1024 * 1024 * 1024
MAX_SELECTED = 8 * 1024 * 1024 * 1024
MAX_FILE = 256 * 1024 * 1024
HEADROOM = 512 * 1024 * 1024


def _available(path):
    stat = os.statvfs(path)
    return stat.f_bavail * stat.f_frsize


def verify_native_decoders():
    """Fail early if the two Android wheels cannot load their native libraries."""
    try:
        import capstone
        import texture2ddecoder
        instructions = list(capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64).disasm(b"\x90", 0))
        pixels = texture2ddecoder.decode_bc1(b"\x00" * 8, 4, 4)
        if len(instructions) != 1 or instructions[0].mnemonic != "nop" or len(pixels) != 64:
            raise ValueError("unexpected native decoder result")
    except Exception as error:
        raise ContentError("Android native importer libraries failed to load: " + str(error)) from error


def extract_app(source, destination, checkpoint):
    """Extract only resources consumed by Bundle and the static declaration reader."""
    source = Path(source)
    if source.suffix.lower() != ".zip" or source.is_symlink() or not source.is_file():
        raise ContentError("Choose a readable ZIP containing your Mac .app")
    if not 0 < source.stat().st_size <= MAX_SOURCE:
        raise ContentError("The Mac app ZIP exceeds the 8 GiB import limit")
    with Bundle(source) as bundle:
        if bundle.profile["edition"] != "mac-full-hd":
            raise ContentError("Choose Galaxy on Fire 2 Full HD for Mac")
        prefix = bundle.info_path.removesuffix("/Contents/Info.plist")
        if not prefix.endswith(".app"):
            raise ContentError("The ZIP does not contain a Mac .app")
        resources = bundle.resources()
        names = sorted({bundle.info_path, bundle.executable()}
                       | {bundle.root + name for name in resources})
        sizes = {name: bundle.entries[name][0] for name in names}
        if (any(size <= 0 or size > MAX_FILE for size in sizes.values())
                or sum(sizes.values()) > MAX_SELECTED):
            raise ContentError("The Mac app ZIP exceeds the import size limit")
        # Source ZIP is already on private storage. The app, base cache, and
        # decoded textures coexist until activation, so budget for all three.
        needed = sum(sizes.values()) * 3 + HEADROOM
        if _available(destination.parent) < needed:
            raise ContentError("Import needs more free device storage; keep at least "
                               + str((needed + 1024**3 - 1) // 1024**3) + " GiB available")
        app = destination / prefix.rsplit("/", 1)[-1]
        app.mkdir(parents=True)
        copied = 0
        total = sum(sizes.values())
        for name in names:
            if not name.startswith(prefix + "/"):
                raise ContentError("Mac app ZIP has an inconsistent bundle root")
            relative = name[len(prefix) + 1:]
            target = app / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            count = 0
            with bundle.open(name) as reader, target.open("xb") as writer:
                while block := reader.read(CHUNK):
                    checkpoint("Unpacking the Mac application", copied / total)
                    count += len(block)
                    if count > sizes[name]:
                        raise ContentError("A Mac app ZIP entry changed while unpacking")
                    writer.write(block)
                    copied += len(block)
            if count != sizes[name]:
                raise ContentError("An original Mac resource is incomplete: " + relative)
        checkpoint("Mac application unpacked", 1.0)
        return app


def run(source, data_directory, status_path, cancel_path):
    """Chaquopy entry point. Always write the same status contract as import_game.py."""
    source = Path(source)
    data_directory = Path(data_directory)
    status_path = Path(status_path)
    cancel_path = Path(cancel_path)
    last = 0.0

    def checkpoint(message, ratio):
        nonlocal last
        if cancel_path.exists():
            raise InterruptedError("Import cancelled; the previous game and saves are unchanged")
        if _available(data_directory) < HEADROOM:
            raise ContentError("Import stopped because device storage is nearly full")
        now = time.monotonic()
        if now - last >= 0.2:
            last = now
            write_status(status_path, {"state": "working", "message": message,
                                       "progress": float(ratio)})

    extracted = source.parent / "extracted"
    try:
        checkpoint("Checking Android native importer", 0.0)
        verify_native_decoders()
        extracted.mkdir()
        app = extract_app(source, extracted, checkpoint)
        receipt, _ = prepare(app, data_directory / "imports", checkpoint)
        checkpoint("Mac game is ready", 1.0)
        write_status(status_path, {"state": "ready", "message": "Mac game is ready",
                                   "receipt": str(receipt)})
    except Exception as error:
        stopped = isinstance(error, InterruptedError)
        write_status(status_path, {"state": "cancelled" if stopped else "failed",
                                   "message": str(error)})
    finally:
        if extracted.exists():
            shutil.rmtree(extracted)
