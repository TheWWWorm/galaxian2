"""Bounded ordinary NPC flight tuning; original code is never emitted."""
import math
import struct
from .opening_loadout import template
from .npc_initialization import MAC_ACTOR_WRAPPER, ARM_ACTOR_WRAPPER

LAYOUTS = {'x86_64': {'bank': ('constructor', 2272, 24, '41c78424fc020000 {bank_limit:4} 41c7842400030000 {bank_gain:4}'),
            'turn': ('update', 12248, 19, '416bc5 {turn_numerator:1} 0f57c0f30f2ac0f30f5905 {ref_b:4}'),
            'snap': ('update', 12480, 13, 'f30f100d {ref_0:4} 0f2ec8760f'),
            'sign': ('update', 12726, 13, 'f30f100d {ref_0:4} 0f2ec8770a'),
            'history': ('update',
                        12764,
                        222,
                        '49638618030000f3410f11948604030000418a861c030000240174280f57d231c9f3410f58948e0403000048ffc183f90575eef30f5e15 '
                        '{ref_33:4} '
                        '418b8e18030000eb3c418b8e1803000085c9750bffc141898e18030000eb4b0f57d27e160f57d231d2f3410f5894960403000048ffc239ca7cef0f57c0f30f2ac1f30f5ed0ffc141898e1803000083f9057c1741c786180300000000000084c0750841c6861c03000001f3410f1086fc020000f30f59d0f3410f599600030000f3410f1196740200000f2ed0770c0f5705 '
                        '{ref_c9:4} 0f2ec27609f3410f118674020000'),
            'reset': ('update', 13279, 30, '41c786740200000000000041c786180300000000000041c6861c03000000'),
            'slew': ('update', 13355, 21, 'f3410f2acdf30f590d {ref_5:4} f30f5e0d {ref_d:4}'),
            'radians': ('update', 13609, 16, 'f30f5915 {ref_0:4} f30f5915 {ref_8:4}'),
            'travel': ('update', 13723, 28, '0f57c0f3410f2ac5f3410f598650020000f30f2cc00f57c0f30f2ac0')},
 'armv7': {'bank': ('constructor',
                    1794,
                    52,
                    '{limit_low:4}  {limit_high:4} c2f8f4000020159ac2f80402159ac2f80802159ac2f80c02159ac2f88c32 '
                    '{gain_low:4} 159a {gain_high:4} c2f89032'),
           'turn': ('update', 11936, 28, '{ref_0:4} cdf8a05800eb4000000140ec300b2046fbff200600ff900d'),
           'snap': ('update', 12102, 32, '{ref_0:4} b5eec00af1ee10fad8bfb9ff800700ef800db4eec20af1ee10fa08d5'),
           'sign': ('update', 12324, 22, '{ref_0:4} 40ec110bb4eec01af1ee10fa48bfb9ff8887'),
           'history': ('update',
                       12346,
                       198,
                       'daf8a8020aeb800080eda58a9af8ac0220ef100198b180ef10000af5257100228b180432142a93ed001a00ef010df7d181ef141fdaf8a81280ee018a16e0daf8a81209b380ef1000012909db0af525720023b2ec011a013300ef010d8b42f8db41ec301bbbff201680ee018a4a1ccaf8a82204290bdb00210028caf8a81204bf01208af8ac0202e00120caf8a8029aeda30a34469aeda41a48ff100d00ff911db4eec01a8aed811af1ee10fa02dd8aed810a08e0b9ff8007b4eec01af1ee10fa48bf8aed810a'),
           'reset': ('update', 11832, 14, '0020caf80402caf8a8028af8ac02'),
           'slew': ('update',
                    12742,
                    32,
                    '44ec324b {ref_4:4} fbff2226 {slew_numerator:4} b4eec20af1ee10fa02ffb01d81ee041a'),
           'radians': ('update',
                       12916,
                       42,
                       '{ref_0:4} cfac {ref_6:4} '
                       'c0ef500040ff122d211d4ff07e50c0adcf90002241f98f0a04f1180102ff910d'),
           'travel': ('update',
                      13122,
                      40,
                      '9aed780a40ec300bfbff200640ff900d9eed550a0df5806e9eed561a0df5806efbff2007fbff2006')}}


def extract_npc_flight(mach, actors):
    import capstone
    mac = mach.architecture == 'x86_64'
    if mach.architecture not in LAYOUTS: return {}
    decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
    decoder.detail = True
    proof = {}
    def require(ok):
        if not ok: raise ValueError('Unsupported ordinary NPC flight declaration')
    def address(span):
        offset = span['offset'] - mach.slice_offset
        sections = [s for s in mach.sections if s['offset'] <= offset and offset+span['bytes'] <= s['offset']+s['length']]
        require(len(sections)==1)
        return sections[0]['address']+offset-sections[0]['offset']
    def read(key, at, size, segment=b'__TEXT', name=b'__text'):
        sections = [s for s in mach.sections if s['name']==name and s['segment']==segment and s['address']<=at and at+size<=s['address']+s['length']]
        require(len(sections)==1)
        offset = sections[0]['offset']+at-sections[0]['address']
        raw = mach.data[offset:offset+size]
        require(len(raw)==size)
        proof[key] = {'offset':offset+mach.slice_offset,'bytes':size}
        return raw
    def match(key, at, size, pattern):
        row = template(pattern).fullmatch(read(key,at,size))
        require(row is not None)
        return row
    def instruction(row, key, at, mnemonic, register=None):
        rows = list(decoder.disasm(row[key],at+row.start(key)))
        require(len(rows)==1 and rows[0].size==len(row[key]) and rows[0].mnemonic==mnemonic)
        i = rows[0]
        if register: require(i.reg_name(i.operands[0].reg)==register)
        return i
    def immediate(row, key, at, mnemonic, register):
        i = instruction(row,key,at,mnemonic,register)
        require(i.operands[-1].type==capstone.arm.ARM_OP_IMM)
        return i.operands[-1].imm
    def target(row, key, at):
        return at+row.end(key)+int.from_bytes(row[key],'little',signed=True) if mac else immediate(row,key,at,'bl',None)
    try:
        initial = actors['npc_initialization']
        require(initial and initial['activation'])
        wrapper_at = address(initial['provenance']['actor_wrapper'])
        wrapper = match('actor_wrapper',wrapper_at,14 if mac else 60,MAC_ACTOR_WRAPPER if mac else ARM_ACTOR_WRAPPER)
        constructor = target(wrapper,'constructor',wrapper_at)
        slot = address(initial['activation']['provenance']['virtual_activation'])+(80 if mac else 40)
        pointer = int.from_bytes(read('virtual_update',slot,8 if mac else 4,b'__DATA',b'__const'),'little')
        if not mac: require(pointer&1==1)
        update = pointer if mac else pointer&~1
        bases = {'constructor':constructor,'update':update}
        positions = {}; rows = {}
        for key,(base,delta,size,pattern) in LAYOUTS[mach.architecture].items():
            positions[key] = bases[base]+delta
            rows[key] = match(key,positions[key],size,pattern)
        def literal(block, field, key):
            row = rows[block]; at = positions[block]
            if mac: location = target(row,field,at)
            else:
                register = {'turn':'s0','snap':'s4','sign':'s0','slew':'s8','radians':'s4' if field=='ref_0' else 's2'}[block]
                i = instruction(row,field,at,'vldr',register)
                op = i.operands[-1]
                require(op.type==capstone.arm.ARM_OP_MEM and i.reg_name(op.mem.base)=='pc')
                location = ((i.address+4)&~3)+op.mem.disp
            return struct.unpack('<f',read(key,location,4,name=b'__const' if mac else b'__text'))[0]
        bank = rows['bank']; bank_at = positions['bank']
        def bank_value(key):
            if mac: raw = bank['bank_'+key]
            else:
                stem = 'limit' if key=='limit' else 'gain'
                low = immediate(bank,stem+'_low',bank_at,'movw','r3')
                high = immediate(bank,stem+'_high',bank_at,'movt','r3')
                raw = struct.pack('<I',low+(high<<16))
            return struct.unpack('<f',raw)[0]
        if mac:
            numerator = int.from_bytes(rows['turn']['turn_numerator'],'little',signed=True)
            slew_numerator = literal('slew','ref_5','slew_numerator')
            require(literal('history','ref_33','history_divisor')==5)
            sign_at = target(rows['history'],'ref_c9',positions['history'])
            require(read('sign_mask',sign_at,16,name=b'__const')==struct.pack('<4I',*[0x80000000]*4))
        else:
            numerator = 48  # The recognized integer add/shift expression is 3*16.
            i = instruction(rows['slew'],'slew_numerator',positions['slew'],'vmov.f32','d16')
            require(i.operands[-1].type==capstone.arm.ARM_OP_FP)
            slew_numerator = i.operands[-1].fp
        result = {'turn_numerator':numerator,
                  'turn_scale':literal('turn','ref_b' if mac else 'ref_0','turn_scale'),
                  'heading_snap_l1':literal('snap','ref_0','heading_snap_l1'),
                  'bank_sign_angle':literal('sign','ref_0','bank_sign_angle'),
                  'bank_samples':5,'bank_limit':bank_value('limit'),'bank_gain':bank_value('gain'),
                  'bank_slew_numerator':slew_numerator,
                  'bank_slew_divisor':literal('slew','ref_d' if mac else 'ref_4','bank_slew_divisor'),
                  'bank_angle_scale':literal('radians','ref_0','bank_angle_scale'),
                  'pi':literal('radians','ref_8' if mac else 'ref_6','pi')}
        require(1<=numerator<=127)
        for key,value in result.items(): require(math.isfinite(value) and 0<value<=100000)
        require(result['heading_snap_l1']<=1 and result['turn_scale']<=1 and result['bank_angle_scale']<=1)
        require(result['pi']==struct.unpack('<f',struct.pack('<f',math.pi))[0])
        require(result['bank_sign_angle']==struct.unpack('<f',struct.pack('<f',math.pi/2))[0])
        spans = sorted((r['offset'],r['offset']+r['bytes']) for r in proof.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        result['provenance'] = proof
        return result
    except (ValueError,TypeError,KeyError,IndexError,OverflowError,struct.error): return {}
