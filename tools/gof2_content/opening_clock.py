"""Read a fresh-opening clock seed and its ordinary millisecond increment."""
import struct
from .opening_loadout import template
from .ship_models import section_bytes


def extract_opening_clock(mach, drift, opening):
    if not drift or not opening or mach.architecture not in ['x86_64','armv7']: return {}
    import capstone
    mac = mach.architecture == 'x86_64'; prefix = 'MAC_' if mac else 'ARM_'
    text = mach.text; base = text['address']
    code = mach.data[text['offset']:text['offset']+text['length']]
    decoder = capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB); decoder.detail = True
    provenance = {}
    def require(ok):
        if not ok: raise ValueError('Unsupported opening clock context')
    def ins(m,key):
        rows = list(decoder.disasm(m[key],base+m.start(key)))
        require(len(rows)==1 and rows[0].size==len(m[key])); return rows[0]
    def find(key):
        name = prefix+key.upper()
        matches = [m for m in template(globals()[name]).finditer(code) if mac or m.start()%2==0]
        require(len(matches)==1); m=matches[0]
        if not mac:
            for field, expected in ARM_FIELDS[name].items():
                i=ins(m,field); require(i.mnemonic==expected['kind'])
                if 'register' in expected: require(i.reg_name(i.operands[0].reg)==expected['register'])
        provenance[key]={'offset':mach.slice_offset+text['offset']+m.start(),'bytes':len(m[0])}
        return m
    try:
        reset=find('reset'); frame=find('frame')
        if mac:
            seed=int.from_bytes(reset['seed'],'little',signed=True)
            target=base+frame.end('call_e')+int.from_bytes(frame['call_e'],'little',signed=True)
        else:
            value=ins(reset,'seed').operands[1].imm
            seed=value | (value<<32)  # The same immediate supplies both words.
            call=ins(frame,'call_1e'); require(call.operands[0].type==2)
            target=call.operands[0].imm
        raw=globals()[prefix+'ADD']; found=section_bytes(mach,target,len(raw),b'__text')
        require(found is not None and found[0]==raw)
        provenance['increment']={'offset':found[1],'bytes':len(raw)}
        getter=drift['provenance']['elapsed_getter']
        expected=bytes.fromhex('554889e5488b87480200005dc3' if mac else 'd0e969017047')
        offset=getter['offset']-mach.slice_offset
        require(getter['bytes']==len(expected) and offset>=0 and mach.data[offset:offset+len(expected)]==expected)
        provenance['getter']=dict(getter)
        require(0<=seed<=2147483647)
        return {'initial_elapsed_ms':seed,'time_unit':'milliseconds','advance_before_controller':True,'provenance':provenance}
    except (ValueError,KeyError,IndexError,TypeError,OverflowError,struct.error): return {}

MAC_RESET = """
488d05
{ref_0:4}
41c786580200000100000041c7865c0200000000000041c786600200000000000049c78648020000
{seed:4}
"""

ARM_RESET = """
0890
{word_2:4}
{word_6:4}
80ef50807944
{seed:2}
0124c0f888300a6800f5e071c0f89c31c0f8a031c0f8ac31c0f8b03101f98f8ac0f8d031c0f8b441c0f8b831c0f8bc31c0f8a831c0f8a431
"""

MAC_FRAME = """
49633424488d05
{ref_4:4}
488b38e8
{call_e:4}
498b85a0000000f6809c00000001
"""

ARM_FRAME = """
{word_0:4}
4ff0ff34
{word_8:4}
dbf83c107844d0f800a0ca17daf80000b494
{call_1e:4}
"""

ARM_FIELDS = {'ARM_RESET': {'word_2': {'kind': 'movw', 'register': 'r1'}, 'word_6': {'kind': 'movt', 'register': 'r1'}, 'seed': {'kind': 'movs', 'register': 'r3'}}, 'ARM_FRAME': {'word_0': {'kind': 'movw', 'register': 'r0'}, 'word_8': {'kind': 'movt', 'register': 'r0'}, 'call_1e': {'kind': 'bl'}}}

MAC_ADD = bytes.fromhex('554889e54801b7480200005dc3')
ARM_ADD = bytes.fromhex('b0b5d0e9694502af64185541c0e96945b0bd')
