"""Match a complete set of bounded source proofs, never mixed compiler layouts."""
import hashlib
from .ship_models import section_bytes


def recognize(mach, origin, layouts, links=None, *, constants=(), reader=section_bytes):
    """Return provenance for exactly one matching layout relative to a file offset.

    Entries are (delta, size, hex) in text, or (section, delta, size, hex).
    Names in constants use the constant-data section for three-field entries.
    Links tie named entries to offsets established by independent readers.
    A bounded reader can support additional sections; sha256: proofs cover large
    constant tables without embedding their bytes in the importer.
    Only source extents leave this helper; matched executable bytes are discarded.
    """
    anchor = mach.text['address'] + origin - mach.slice_offset - mach.text['offset']
    accepted = []
    for layout in layouts:
        proof = {}
        for key, rule in layout.items():
            section, delta, size, expected = ('__const' if key in constants else '__text', *rule) if len(rule) == 3 else rule
            if links and key in links and links[key] != origin + delta:
                break
            hashed = expected.startswith('sha256:')
            raw = bytes.fromhex(expected[7:] if hashed else expected)
            if size <= 0 or len(raw) != (32 if hashed else size):
                break
            found = reader(mach, anchor + delta, size, section.encode('ascii'))
            if found is None or len(found[0]) != size:
                break
            if (hashlib.sha256(found[0]).digest() if hashed else found[0]) != raw:
                break
            proof[key] = {'offset': found[1], 'bytes': size}
        else:
            if proof and (not links or set(links) <= proof.keys()):
                accepted.append(proof)
    return accepted[0] if len(accepted) == 1 else {}
