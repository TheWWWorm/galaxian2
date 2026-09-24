"""Recover a bounded character-alias declaration from each language loader.

Recognizes a finite compiler layout and its constant switch table. Emits only
Unicode pairs and provenance. No source instruction is executed or translated.
"""
import struct
from .opening_loadout import template
from .ship_models import section_bytes

MAC = """
0fb775c681fea900000089b574ffffff0f8f19000000e9000000008b8574ffffff83f8600f846f010000e92b0200008b8574ffffff3db90000000f8f1b000000e9000000008b8574ffffff3daa0000000f84c7010000e9ff0100008b8574ffffff3d0f0400000f8f1b000000e9000000008b8574ffffff3dba0000000f84bc010000e9d30100008b8574ffffff3d440400000f8feb000000e9000000008b8574ffffff3d3d0400000f8f93000000e9000000008b8574ffffff3d340400000f8f67000000e9000000008b8574ffffff3d2f0400000f8f3b000000e9000000008b8574ffffff8d88f0fbffff89ca83f91548899568ffffff0f875d010000488d05
{table:4}
488b8d68ffffff48630c88488d0401ffe08b8574ffffff3d300400000f84f7000000e92f0100008b8574ffffff3d350400000f84f7000000e9190100008b8574ffffff3d3e0400000f84ec000000e9000000008b8574ffffff3d400400000f84e1000000e9000000008b8574ffffff3d410400000f84aa000000e9d70000008b8574ffffff3d450400000f84c0000000e9c100000066c745c6
{value0:2}
e9b600000066c745c6
{value1:2}
e9ab00000066c745c6
{value2:2}
e9a000000066c745c6
{value3:2}
e99500000066c745c6
{value4:2}
e98a00000066c745c6
{value5:2}
e97f00000066c745c6
{value6:2}
e97400000066c745c6
{value7:2}
e96900000066c745c6
{value8:2}
e95e00000066c745c6
{value9:2}
e95300000066c745c6
{value10:2}
e94800000066c745c6
{value11:2}
e93d00000066c745c6
{value12:2}
e93200000066c745c6
{value13:2}
e92700000066c745c6
{value14:2}
e91c00000066c745c6
{value15:2}
e91100000066c745c6
{value16:2}
e90600000066c745c6
{value17:2}
"""
ARM = """
bdf87800a9280c9005dcffe70c98602800f06680cfe00c98b92805dcffe70c98aa2800f0a580c6e00c98b0f5826f05daffe70c98ba2800f0ad80bce040f244400c99814246dcffe740f23d400c9981422ddcffe740f234400c99814220dcffe70c98b0f5866f16daffe70c98a0f582610a4615290b9200f29e800b99dfe801f0
{table:22}
0c98b0f5866f68d08ae040f235400c99814200f06e8083e040f23e400c99814200f06d80ffe70c98b0f5886f00f06d80ffe740f241400c99814254d070e040f245400c99814266d06ae0
{value0:1}
20c0f20000adf8780064e0
{value1:1}
20c0f20000adf878005ee0
{value2:1}
20c0f20000adf8780058e0
{value3:1}
20c0f20000adf8780052e0
{value4:1}
20c0f20000adf878004ce0
{value5:1}
20c0f20000adf8780046e0
{value6:1}
20c0f20000adf8780040e0
{value7:1}
20c0f20000adf878003ae0
{value8:1}
20c0f20000adf8780034e0
{value9:1}
20c0f20000adf878002ee0
{value10:1}
20c0f20000adf8780028e0
{value11:1}
20c0f20000adf8780022e0
{value12:1}
20c0f20000adf878001ce0
{value13:1}
20c0f20000adf8780016e0
{value14:1}
20c0f20000adf8780010e0
{value15:1}
20c0f20000adf878000ae0
{value16:1}
20c0f20000adf8780004e0
{value17:1}
20c0f20000adf87800
"""

MAC_CASES = [409, 420, 431, 442, 453, 464, 475, 486, 497, 508, 519, 530, 541, 552, 563, 574, 585, 596]
ARM_CASES = [224, 236, 248, 260, 272, 284, 296, 308, 320, 332, 344, 356, 368, 380, 392, 404, 416, 428]

# Same finite alias dispatch with compact stack operands and a different jump
# register. The eighteen assignment leaves retain their complete original shape.
MAC_ALTERNATE = '''
0fb775c681fea900000089758c0f8f16000000e9000000008b458c83f8600f843a010000e9f60100008b458c3db90000000f8f18000000e9000000008b458c3daa0000000f8498010000e9d00100008b458c3d0f0400000f8f18000000e9000000008b458c3dba0000000f8493010000e9aa0100008b458c3d440400000f8fc8000000e9000000008b458c3d3d0400000f8f7c000000e9000000008b458c3d340400000f8f56000000e9000000008b458c3d2f0400000f8f30000000e9000000008b458c05f0fbffff89c183f81548894d800f8747010000488d05
{table:4}
488b4d80486314884801c2ffe28b458c3d300400000f84e8000000e9200100008b458c3d350400000f84eb000000e90d0100008b458c3d3e0400000f84e3000000e9000000008b458c3d400400000f84db000000e9000000008b458c3d410400000f84a7000000e9d40000008b458c3d450400000f84c0000000e9c100000066c745c6
{value0:2}
''' + MAC.split('{value0:2}', 1)[1]
MAC_ALTERNATE_CASES = [case - 59 for case in MAC_CASES]

def extract_text_aliases(mach):
    mac = mach.architecture == 'x86_64'
    if not mac and mach.architecture != 'armv7': return {}
    section = mach.text
    code = mach.data[section['offset']:section['offset'] + section['length']]
    matches = [m for m in template((MAC, MAC_ALTERNATE) if mac else ARM).finditer(code) if mac or m.start() % 2 == 0]
    if len(matches) != 1: return {}
    match = matches[0]
    address = section['address'] + match.start()
    merge = address + len(match[0])
    cases = [match.start('value%d' % i) - match.start() - 4 for i in range(18)] if mac else ARM_CASES
    values = [int.from_bytes(match['value%d' % i], 'little') for i in range(18)]
    # This declaration maps characters, never control/whitespace or glyph logic.
    if any(not 33 <= value <= 65535 or 0xd800 <= value <= 0xdfff for value in values): return {}
    destinations = {address + at: value for at, value in zip(cases, values)}
    if mac:
        table = address + match.end('table') - match.start() + struct.unpack('<i', match['table'])[0]
        found = section_bytes(mach, table, 88, b'__text')
        if found is None or len(found[0]) != 88: return {}
        targets = [table + delta for delta in struct.unpack('<22i', found[0])]
        table_extent = {'offset': found[1], 'bytes': 88}
    else:
        table = address + match.start('table') - match.start()
        targets = [table + delta * 2 for delta in match['table']]
        table_extent = {'offset': mach.slice_offset + section['offset'] + match.start('table'), 'bytes': 22}
    if any(target != merge and target not in destinations for target in targets): return {}
    aliases = [[0x410 + index, destinations[target]] for index, target in enumerate(targets) if target != merge]
    # Fixed equality leaves in the recognized declaration share constant cases.
    for source, case in [(0x60, 0), (0xaa, 12), (0xba, 15), (0x430, 12),
                         (0x435, 14), (0x43e, 15), (0x440, 16), (0x441, 13), (0x445, 17)]:
        aliases.append([source, values[case]])
    if len(aliases) != 20: return {}
    return {'aliases': sorted(aliases), 'provenance': {
        'declaration': {'offset': mach.slice_offset + section['offset'] + match.start(), 'bytes': len(match[0])},
        'switch_table': table_extent}}
