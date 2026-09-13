"""Recover ordinary environment material constants from linked static setters.

This import-time recognizer emits only numeric data and file extents. Setter
prefixes identify the destination fields; no original runtime code is emitted.
"""
import math
import struct
from .opening_loadout import template
from .ship_models import section_bytes
from . import environment_colors

ROLES = ('ambient', 'diffuse', 'specular', 'power')


def extract_surface_material(mach, colors):
    if not colors or mach.architecture not in ['x86_64', 'armv7']: return {}
    import capstone
    mac = mach.architecture == 'x86_64'; prefix = 'MAC_' if mac else 'ARM_'
    text = mach.text; base = text['address']; file_base = mach.slice_offset + text['offset']
    code = mach.data[text['offset']:text['offset'] + text['length']]
    decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB); decoder.detail = True
    provenance = {}; value_sources = {}
    def require(value):
        if not value: raise ValueError('Unsupported surface material setup')
    def instruction(m, key):
        rows = list(decoder.disasm(m[key], base + m.start(key)))
        require(len(rows) == 1 and rows[0].size == len(m[key])); return rows[0]
    def match(key, at=None):
        spec = getattr(environment_colors, prefix+'RIM') if key == 'rim' else globals()[prefix+key.upper()]
        pattern = template(spec)
        matches = [pattern.match(code, at-base)] if at is not None else [m for m in pattern.finditer(code) if mac or m.start()%2 == 0]
        require(len(matches) == 1 and matches[0] is not None); m = matches[0]
        # A declared extent must remain inside the Mach-O code section.
        require(section_bytes(mach, base+m.start(), len(m[0]), b'__text') is not None)
        if not mac and key != 'rim':
            fields = ARM_FIELDS if key == 'setup' else {k:(k.removeprefix('global_'), 'r1') for k in m.groupdict()}
            for field, (kind, register) in fields.items():
                i = instruction(m, field); require(i.mnemonic == kind)
                if register: require(i.reg_name(i.operands[0].reg) == register and i.operands[1].type == capstone.arm.ARM_OP_IMM)
        provenance[key] = {'offset':file_base+m.start(), 'bytes':len(m[0])}; return m
    def target(m, key):
        return base+m.end(key)+int.from_bytes(m[key], 'little', signed=True) if mac else instruction(m, key).operands[0].imm
    try:
        rim = colors['provenance']['rim']
        match('rim', base+rim['offset']-file_base)
        require(provenance['rim'] == rim)
        setup = match('setup')
        require(provenance['setup']['offset'] == rim['offset']+rim['bytes'])
        renderers = {target(setup, 'renderer_'+str(i)) for i in range(4)}
        require(len(renderers) == 1); match('renderer', renderers.pop())
        result = {}
        for role in ROLES:
            match(role, target(setup, role+'_call'))
            if mac:
                value = section_bytes(mach, target(setup, role+'_value'), 4, b'__const')
                require(value is not None)
                numbers = [struct.unpack('<f', value[0])[0]] * (1 if role == 'power' else 3)
                value_sources[role] = {'offset':value[1], 'bytes':4}
            else:
                if role == 'power':
                    bits = instruction(setup, 'power_0').operands[1].imm | (instruction(setup, 'power_1').operands[1].imm << 16)
                    numbers = [struct.unpack('<f', struct.pack('<I', bits))[0]]
                else:
                    numbers = [struct.unpack('<f', struct.pack('<I', instruction(setup, role+'_'+str(i)).operands[1].imm & 0xffffffff))[0] for i in range(3)]
                value_sources[role] = {'offset':file_base+setup.start(role+'_0'), 'bytes':6 if role == 'power' else 12}
            require(all(math.isfinite(v) and (0 < v <= 1024 if role == 'power' else 0 <= v <= 16) for v in numbers))
            result['specular_power' if role == 'power' else role+'_rgb'] = numbers[0] if role == 'power' else numbers
        spans = sorted((r['offset'], r['offset']+r['bytes']) for r in provenance.values())
        require(all(a[1] <= b[0] for a,b in zip(spans, spans[1:])))
        if mac:
            # Compilers may pool equal constants. Exact aliases are valid; partial overlaps aren't.
            constants = sorted(set((r['offset'], r['offset']+4) for r in value_sources.values()))
            require(all(a[1] <= b[0] for a,b in zip(constants, constants[1:])))
            require(all(b <= c or a >= d for a,b in constants for c,d in spans))
        return dict(result, provenance=provenance, value_sources=value_sources)
    except (ValueError, KeyError, IndexError, TypeError, OverflowError, struct.error): return {}

MAC_SETUP = """
498b3c24
e8
{renderer_0:4}
f30f1015
{ambient_value:4}
4889c7
0f28c2
0f28ca
e8
{ambient_call:4}
498b3c24
e8
{renderer_1:4}
4889c7
f30f1015
{diffuse_value:4}
0f28c2
0f28ca
e8
{diffuse_call:4}
498b3c24
e8
{renderer_2:4}
4889c7
f30f1015
{specular_value:4}
0f28c2
0f28ca
e8
{specular_call:4}
498b3c24
e8
{renderer_3:4}
f30f1005
{power_value:4}
4889c7
e8
{power_call:4}
"""

MAC_AMBIENT = """
55
4889e5
4883ec20
48897df8
f30f1145f4
f30f114df0
f30f1155ec
488b7df8
f30f1045f4
f30f1187a0020000
f30f1045f0
f30f1187a4020000
f30f1045ec
f30f1187a8020000
"""

MAC_DIFFUSE = """
55
4889e5
4883ec20
48897df8
f30f1145f4
f30f114df0
f30f1155ec
488b7df8
f30f1045f4
f30f118790020000
f30f1045f0
f30f118794020000
f30f1045ec
f30f118798020000
"""

MAC_SPECULAR = """
55
4889e5
4883ec20
48897df8
f30f1145f4
f30f114df0
f30f1155ec
488b7df8
f30f1045f4
f30f1187b0020000
f30f1045f0
f30f1187b4020000
f30f1045ec
f30f1187b8020000
"""

MAC_POWER = """
55
4889e5
4883ec20
48897df8
f30f1145f4
488b7df8
f30f1045f4
f30f1187c0020000
"""

MAC_RENDERER = """
55
4889e5
48897df8
488b7df8
488b8700010000
5d
c3
"""

ARM_SETUP = """
daf80000
{renderer_0:4}
{ambient_0:4}
{ambient_1:4}
{ambient_2:4}
{ambient_call:4}
daf80000
{renderer_1:4}
{diffuse_0:4}
{diffuse_1:4}
{diffuse_2:4}
{diffuse_call:4}
daf80000
{renderer_2:4}
{specular_0:4}
{specular_1:4}
{specular_2:4}
{specular_call:4}
daf80000
{renderer_3:4}
{power_0:2}
{power_1:4}
{power_call:4}
"""

ARM_AMBIENT = """
80b5
6f46
86b0
43ec103b
b0ee402a
42ec102b
b0ee404a
41ec101b
b0ee406a
{global_movw:4}
{global_movt:4}
7944
0590
8ded046a
8ded034a
8ded022a
0598
9ded042a
00f52672
82ed002a
9ded032a
00f52772
82ed002a
9ded022a
00f52872
82ed002a
"""

ARM_DIFFUSE = """
80b5
6f46
86b0
43ec103b
b0ee402a
42ec102b
b0ee404a
41ec101b
b0ee406a
{global_movw:4}
{global_movt:4}
7944
0590
8ded046a
8ded034a
8ded022a
0598
9ded042a
00f52272
82ed002a
9ded032a
00f52372
82ed002a
9ded022a
00f52472
82ed002a
"""

ARM_SPECULAR = """
80b5
6f46
86b0
43ec103b
b0ee402a
42ec102b
b0ee404a
41ec101b
b0ee406a
{global_movw:4}
{global_movt:4}
7944
0590
8ded046a
8ded034a
8ded022a
0598
9ded042a
00f52a72
82ed002a
9ded032a
00f52b72
82ed002a
9ded022a
00f52c72
82ed002a
"""

ARM_POWER = """
80b5
6f46
83b0
41ec101b
b0ee402a
{global_movw:4}
{global_movt:4}
7944
0290
8ded012a
0298
9ded012a
00f52e72
82ed002a
"""

ARM_RENDERER = """
81b0
0090
0098
d0f8a000
01b0
7047
"""

ARM_FIELDS = {'renderer_0': ('bl', None), 'ambient_0': ('mov.w', 'r1'), 'ambient_1': ('mov.w', 'r2'), 'ambient_2': ('mov.w', 'r3'), 'ambient_call': ('bl', None), 'renderer_1': ('bl', None), 'diffuse_0': ('mov.w', 'r1'), 'diffuse_1': ('mov.w', 'r2'), 'diffuse_2': ('mov.w', 'r3'), 'diffuse_call': ('bl', None), 'renderer_2': ('bl', None), 'specular_0': ('mov.w', 'r1'), 'specular_1': ('mov.w', 'r2'), 'specular_2': ('mov.w', 'r3'), 'specular_call': ('bl', None), 'renderer_3': ('bl', None), 'power_0': ('movs', 'r1'), 'power_1': ('movt', 'r1'), 'power_call': ('bl', None)}
