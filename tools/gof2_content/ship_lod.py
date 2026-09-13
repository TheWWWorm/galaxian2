"""Read ordinary ship LOD declarations and bounded distance-selection contexts.

Only declarative mesh IDs, thresholds and provenance survive import. Special hull
factories and the owner of the source reference position/detail input are separate.
"""
import math
import struct
from .opening_loadout import template
from .ship_models import section_bytes


def extract_ship_lod(mach, models, lights):
    count = len(models.get('resource_ids', []))
    if not lights or not 1 <= count <= 64 or mach.architecture not in ['x86_64','armv7']: return {}
    import capstone
    mac = mach.architecture == 'x86_64'; prefix = 'MAC_' if mac else 'ARM_'
    text = mach.text; base = text['address']; file_base = text['offset'] + mach.slice_offset
    code = mach.data[text['offset']:text['offset']+text['length']]
    decoder = capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB); decoder.detail=True
    provenance = {}
    def require(ok):
        if not ok: raise ValueError('Unsupported ship LOD declaration')
    def instruction(m,key):
        rows=list(decoder.disasm(m[key],base+m.start(key)))
        require(len(rows)==1 and rows[0].size==len(m[key])); return rows[0]
    def find(key):
        name=prefix+key.upper(); matches=[m for m in template(globals()[name]).finditer(code) if mac or m.start()%2==0]
        if key in ['body','fill','step','child','child_copy','limit']:
            root=lights['provenance'][0]['offset']; matches=[m for m in matches if root<=file_base+m.start()<file_base+m.end()<=root+2400]
        require(len(matches)==1); m=matches[0]
        if not mac:
            for field,expected in ARM_FIELDS[name].items():
                i=instruction(m,field);require(i.mnemonic==expected['kind'])
                if 'register' in expected: require(i.reg_name(i.operands[0].reg)==expected['register'])
        provenance[key]={'offset':file_base+m.start(),'bytes':len(m[0])};return m
    def reference(m,key): return base+m.end(key)+int.from_bytes(m[key],'little',signed=True)
    def pair(m,low,high,pc):
        return instruction(m,low).operands[1].imm+(instruction(m,high).operands[1].imm<<16)+base+m.start()+pc+4
    def extent(key,address,size,section):
        found=section_bytes(mach,address,size,section);require(found is not None)
        provenance[key]={'offset':found[1],'bytes':size};return found[0]
    try:
        parts={key:find(key) for key in ['body','fill','step','child','child_copy','limit','select','cull','square']}
        root=lights['provenance'][0];begin=root['offset'];end=begin+2400
        ordered=[parts[k] for k in ['body','fill','step','child','child_copy','limit']]
        require(all(begin<=file_base+m.start()<file_base+m.end()<=end for m in ordered))
        require(all(a.end()<=b.start() for a,b in zip(ordered,ordered[1:])))
        body=parts['body'];fill=parts['fill'];step=parts['step'];child=parts['child'];copy=parts['child_copy'];limit=parts['limit']
        if mac:
            body_address=reference(body,'ref_b');require(body_address==reference(fill,'ref_0'))
            child_address=reference(child,'ref_0');require(child_address==reference(copy,'ref_0'))
            seed=int.from_bytes(fill['value'],'little',signed=True);increment=int.from_bytes(step['value'],'little',signed=True)
            maximum=int.from_bytes(limit['value'],'little',signed=True)
            helper=reference(step,'call_3d');setter=reference(limit,'call_8')
            expected=bytes.fromhex('554889e5480faff64889b7980000005dc3')
            detail=find('detail')
            require(parts['cull'].end()==detail.start() and detail.end()<=parts['select'].start())
            low=struct.unpack('<f',extent('detail_low',reference(detail,'ref_0'),4,b'__const'))[0]
            high=struct.unpack('<f',extent('detail_high',reference(detail,'ref_1f'),4,b'__const'))[0]
            first=struct.unpack('<f',extent('detail_first',reference(detail,'ref_15'),4,b'__const'))[0]
            last,middle=struct.unpack('<2f',extent('detail_pair',reference(detail,'ref_30'),8,b'__const'))
            boundaries=[low,high];factors=[first,middle,last]
        else:
            body_address=pair(body,'word_0','word_8',16)
            require(instruction(body,'word_c').operands[1].imm==65535)
            child_address=pair(child,'word_0','word_6',12)
            require(instruction(child,'word_e').operands[1].imm==65535)
            seed=instruction(fill,'word_c').operands[1].imm;increment=instruction(step,'word_6').operands[2].imm
            maximum=instruction(limit,'word_2').operands[1].imm+(instruction(limit,'word_a').operands[1].imm<<16)
            helper=instruction(step,'call_26').operands[0].imm;setter=instruction(limit,'call_14').operands[0].imm
            require(instruction(parts['select'],'call_10').operands[0].imm==instruction(parts['select'],'call_1a').operands[0].imm)
            expected=bytes.fromhex('b0b5a1fb014302af01fb023301fb0235c0e91c45b0bd')
            boundaries=[];factors=[1.0]
        require(helper<=base+parts['square'].start()<helper+512)
        require(parts['cull'].end()<=parts['select'].start()<=parts['cull'].end()+300)
        require(extent('limit_setter',setter,len(expected),b'__text')==expected)
        require(0<seed<seed+increment<maximum<=1000000)
        require(all(math.isfinite(v) and 0<v<=1 for v in factors+boundaries))
        require(boundaries==sorted(set(boundaries)) and factors==sorted(set(factors)))
        tables=[]
        for key,address in [('body_table',body_address),('child_table',child_address)]:
            raw=extent(key,address,count*12,b'__const');rows=[list(struct.unpack_from('<2I',raw,i*12)) for i in range(count)]
            require(all(0<=v<=65535 for row in rows for v in row))
            require(all(row[0]!=65535 or row[1]==65535 for row in rows));tables.append(rows)
        require(all(all(v==65535 for v in child_row) or sum(v!=65535 for v in child_row)==sum(v!=65535 for v in body_row) for body_row,child_row in zip(*tables)))
        return {'body_resource_ids':tables[0],'child_resource_ids':tables[1], 'distances':[seed,seed+increment],
                'maximum_distance':maximum,'detail_boundaries':boundaries,'squared_distance_factors':factors,
                'threshold_comparison':'greater','maximum_comparison':'greater_or_equal','provenance':provenance}
    except (ValueError,KeyError,IndexError,TypeError,OverflowError,struct.error): return {}

MAC_BODY = """
4b8d0c7648898d88feffff488d05
{ref_b:4}
488d04884531f631c94589f58b1c8881fbffff00000f95c2440fb6f24501ee48ffc183f90275e2
"""

MAC_FILL = """
488d05
{ref_0:4}
488b8d88feffff488d0488488985a0feffff8b859cfeffff05c87d00004531ffbb
{value:4}
0fb7c089859cfeffff488b85a0feffff66428b04b8664289047a43891cb8
"""

MAC_STEP = """
81c3
{value:4}
4983c40449ffc74539fd488b95b0feffff4c8b85a8feffff75948b85bcfeffff3c01751a4c8bad90feffff4c89ef4889d64c89c24489f1e8
{call_3d:4}
"""

MAC_CHILD = """
488d05
{ref_0:4}
488b8d88feffff488d0c8831c031d24189c78b1c9181fbffff00000f95c00fb6c04401f848ffc283fa0275e3
"""

MAC_CHILD_COPY = """
488d05
{ref_0:4}
81fbffff0000488b8d88feffff4c8d24880f95c00fb6c04101c731db66418b049c664189045e4c89ef4c89f6e8
{call_33:4}
48ffc34139df75e3
"""

MAC_LIMIT = """
4c89efbe
{value:4}
e8
{call_8:4}
"""

MAC_DETAIL = """
f30f1005
{ref_0:4}
f30f108d50ffffff0f2ec1720af30f1005
{ref_15:4}
eb1df30f1005
{ref_1f:4}
0f2ec10f93c00fb6c0488d0d
{ref_30:4}
f30f100481f30f118550ffffff
"""

MAC_SELECT = """
498b8d880000004801c1488b0cd94885c979184889ca48d1ea4883e1014809d1f3480f2ac1f30f58c0eb05f3480f2ac1498b8d90000000f30f598550ffffff4885c979184889ca48d1ea4883e1014809d1f3480f2ac9f30f58c9eb05f3480f2ac94c8d73ff0f2ec876874a8d04a500000000490345688b7498fc
"""

MAC_CULL = """
49898590000000498b8d980000004885c974194839c80f92c041884558720d41c74530ffffffffe9d3010000
"""

MAC_SQUARE = """
498b8688000000488b0c58480fafc948890c58
"""

ARM_BODY = """
{word_0:4}
0aeb4a02
{word_8:4}
{word_c:4}
7844002600eb82030020cdf814a053f82040b2460af1010501308c4218bf2e460228f4d10793
"""

ARM_FILL = """
05990346
{word_4:4}
079a0844
{word_c:4}
4546069380b20590099852f82b1043f82b4020f81b10
"""

ARM_STEP = """
0bf1010b0435
{word_6:4}
da45d4d10a98012840f0a3804ff0ff3149984b911a4609999a463346
{call_26:4}
"""

ARM_CHILD = """
{word_0:4}
0023
{word_6:4}
04997844
{word_e:4}
00eb8105002155f823200e46701c0133a24218bf0146022bf5d1
"""

ARM_CHILD_COPY = """
55f8240028f814000134a642f8d149984ff0ff314b914146
{call_18:4}
"""

ARM_LIMIT = """
499c
{word_2:4}
4ff0ff30
{word_a:4}
4b9000222046
{call_14:4}
"""

ARM_SELECT = """
dbf86400013e00eb080150f808004968
{call_10:4}
0546d4e90001
{call_1a:4}
40ec100ba8f1080845ec115bb4eec10af1ee10fae3dd
"""

ARM_CULL = """
cbe91a01dbe91c2352ea030610d090424ff000004ff0000638bf0120994238bf012608bf06468bf84860002e00f07e80
"""

ARM_SQUARE = """
706e00eb080250f808105368a1fb015401fb034440f8085001fb03415160
"""

ARM_FIELDS = {'ARM_BODY': {'word_0': {'kind': 'movw', 'register': 'r0'}, 'word_8': {'kind': 'movt', 'register': 'r0'}, 'word_c': {'kind': 'movw', 'register': 'r1'}}, 'ARM_FILL': {'word_4': {'kind': 'movw', 'register': 'r0'}, 'word_c': {'kind': 'movw', 'register': 'r4'}}, 'ARM_STEP': {'word_6': {'kind': 'add.w', 'register': 'r4'}, 'call_26': {'kind': 'bl'}}, 'ARM_CHILD': {'word_0': {'kind': 'movw', 'register': 'r0'}, 'word_6': {'kind': 'movt', 'register': 'r0'}, 'word_e': {'kind': 'movw', 'register': 'r4'}}, 'ARM_CHILD_COPY': {'call_18': {'kind': 'bl'}}, 'ARM_LIMIT': {'word_2': {'kind': 'movw', 'register': 'r1'}, 'word_a': {'kind': 'movt', 'register': 'r1'}, 'call_14': {'kind': 'bl'}}, 'ARM_SELECT': {'call_10': {'kind': 'blx'}, 'call_1a': {'kind': 'blx'}}, 'ARM_CULL': {}, 'ARM_SQUARE': {}}
