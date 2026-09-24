"""Synthetic relocated extents for import-only declaration readers."""
import hashlib
import copy
from types import SimpleNamespace
from unittest.mock import patch


def literal_fixture(architecture, layouts, shift=0, constants=()):
    """Build bounded text/constant sections from complete literal proof layouts."""
    low=min(value[0] for value in layouts.values())-32
    high=max(value[0]+value[1] for value in layouts.values())+32
    offset=128;bias=4096;base=0x400000+shift-low
    data=bytearray(offset+high-low);groups={b'__text':[],b'__const':[]}
    for key,(delta,size,raw) in layouts.items():
        value=bytes.fromhex(raw)
        if len(value)!=size:raise ValueError('Literal proof size does not match its bytes')
        data[offset+delta-low:offset+delta-low+size]=value
        groups[b'__const' if key in constants else b'__text'].append((delta,size))
    sections=[]
    for name,spans in groups.items():
        if not spans:continue
        lo=min(v[0] for v in spans)-16;hi=max(v[0]+v[1] for v in spans)+16
        sections.append({'segment':b'__TEXT','name':name,'address':base+lo,
                         'offset':offset+lo-low,'length':hi-lo})
    mach=SimpleNamespace(architecture=architecture,slice_offset=bias,data=bytes(data),
                         text=sections[0],sections=sections)
    return mach,bias+offset-low,offset,low


def declaration_fixture(layouts, shift=0, hash_prefix=''):
    low=min(0,min(value[0] for value in layouts.values()))-16
    high=max(value[0]+value[1] for value in layouts.values())+16
    offset=128;bias=4096;anchor=0x800000+shift
    raw=bytearray(offset+high-low);sections=[];patched={}
    for index,(key,(delta,size,name,_)) in enumerate(layouts.items()):
        value=bytes([index+1])*size
        at=offset+delta-low;raw[at:at+size]=value
        patched[key]=[delta,size,name,hash_prefix+hashlib.sha256(value).hexdigest()]
        sections.append({'segment':b'__TEXT','name':name.encode(),
            'address':anchor+delta,'offset':at,'length':size})
    # Some proofs deliberately nest a small table inside its enclosing owner.
    # Hash the final synthetic bytes after every overlapping span was written.
    for key,(delta,size,_,_) in layouts.items():
        at=offset+delta-low
        patched[key][3]=hash_prefix+hashlib.sha256(raw[at:at+size]).hexdigest()
    mach=SimpleNamespace(architecture='x86_64',
        text={'address':anchor+low,'offset':offset,'length':high-low},
        sections=sections,data=bytes(raw),slice_offset=bias)
    arrival={'provenance':{'actor':{'offset':bias+offset-low,'bytes':315}}}
    return mach,arrival,patched


def verify_hashed_declarations(test, reader, extract, mutable_key):
    """Exercise relocation, ownership and every proof's corruption boundary."""
    for relocation in (0, 0x800000):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS, relocation)
        with patch.object(reader, 'LAYOUTS', layouts):
            values, proof = extract(mach, arrival)
            test.assertEqual(values, reader.VALUES)
            test.assertEqual(set(proof), set(layouts))
            values[mutable_key].clear()
            test.assertEqual(extract(mach, arrival)[0], reader.VALUES)
            for name, (delta, _, _, _) in layouts.items():
                changed = copy.copy(mach)
                raw = bytearray(mach.data)
                raw[arrival['provenance']['actor']['offset']-mach.slice_offset+delta] ^= 255
                changed.data = bytes(raw)
                test.assertEqual(extract(changed, arrival), ({}, {}), name)
            mach.architecture = 'armv7'
            test.assertEqual(extract(mach, arrival), ({}, {}))
