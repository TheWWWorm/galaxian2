"""Import resource IDs for the verified location reflection selector.

Static contexts link to the existing location predicate and sky getter. Only
numeric resource IDs and provenance leave this reader, never executable bytes.
"""
from .opening_loadout import template
from .ship_models import section_bytes


def extract_reflection_selection(mach, projection, sky):
    if not projection or not sky or mach.architecture not in ['x86_64','armv7']: return {}
    import capstone
    mac=mach.architecture=='x86_64';prefix='MAC_' if mac else 'ARM_'
    text=mach.text;base=text['address'];file_base=mach.slice_offset+text['offset']
    code=mach.data[text['offset']:text['offset']+text['length']]
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    provenance={}
    def require(value):
        if not value:raise ValueError('Unsupported reflection selector')
    def instruction(m,key):
        rows=list(decoder.disasm(m[key],base+m.start(key)))
        require(len(rows)==1 and rows[0].size==len(m[key]));return rows[0]
    def target(m,key):
        return base+m.end(key)+int.from_bytes(m[key],'little',signed=True) if mac else instruction(m,key).operands[0].imm
    def match(key,address=None):
        name=prefix+key.upper();pattern=template(globals()[name])
        matches=([pattern.match(code,address-base)] if address is not None else [m for m in pattern.finditer(code) if mac or m.start()%2==0])
        require(len(matches)==1 and matches[0] is not None);m=matches[0]
        if not mac:
            for field,expected in ARM_FIELDS[name].items():
                i=instruction(m,field);require(i.mnemonic==expected['kind'])
                if 'register' in expected:require(i.reg_name(i.operands[0].reg)==expected['register'])
        for field in m.groupdict():
            if field.startswith('call_'):
                at=target(m,field)
                require(section_bytes(mach,at,2,b'__text') is not None or section_bytes(mach,at,6 if mac else 16,b'__stubs' if mac else b'__picsymbolstub4') is not None)
        provenance[key]={'offset':file_base+m.start(),'bytes':len(m[0])};return m
    def inherited(key,row):
        require(isinstance(row,dict) and row['bytes']>0)
        at=base+row['offset']-file_base
        require(section_bytes(mach,at,row['bytes'],b'__text') is not None)
        provenance[key]=dict(row);return at
    try:
        selection=match('select');binding=match('bind',target(selection,'call_59' if mac else 'call_5a'))
        require(target(selection,'call_a' if mac else 'call_14')==inherited('predicate',projection['provenance']['predicate']))
        require(target(selection,'call_2f' if mac else 'call_30')==inherited('system',sky['provenance']['system']))
        index=target(selection,'call_37' if mac else 'call_36')
        raw=bytes.fromhex('554889e58b473c5dc3' if mac else '006b7047')
        found=section_bytes(mach,index,len(raw),b'__text');require(found is not None and found[0]==raw)
        provenance['sky_index']={'offset':found[1],'bytes':len(raw)}
        context=inherited('load_context',sky['provenance']['texture'])
        raw=section_bytes(mach,context,7 if mac else 6,b'__text')[0]
        if mac:
            require(raw[:3]==bytes.fromhex('31c9e8'))
            loader=context+7+int.from_bytes(raw[3:],'little',signed=True)
            require(target(selection,'ref_0')==target(selection,'ref_25'))
            require(len({target(binding,k) for k in ['call_5e','call_8b','call_123']})==1)
            require(target(binding,'call_10d')==target(binding,'call_13f'))
        else:
            require(raw[:2]==bytes.fromhex('0023'))
            rows=list(decoder.disasm(raw[2:],context+2));require(len(rows)==1 and rows[0].mnemonic=='bl')
            loader=rows[0].operands[0].imm
            require(len({target(binding,k) for k in ['call_3c','call_50','call_c2']})==1)
            require(target(binding,'call_b8')==target(binding,'call_e8'))
        require(target(selection,'call_4d' if mac else 'call_4a')==loader)
        values={key:int.from_bytes(selection[key],'little') if mac else instruction(selection,key).operands[1].imm for key in ['texture_base','special_id']}
        require(all(0<=v<=65533 for v in values.values()))
        spans=sorted((r['offset'],r['offset']+r['bytes']) for r in provenance.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        return dict(values,provenance=provenance)
    except (ValueError,KeyError,IndexError,TypeError,OverflowError):return {}

MAC_SELECT = """
488d05
{ref_0:4}
488b38e8
{call_a:4}
498b5e0884c0740e488d55d44889dfbe
{special_id:4}
eb26488d05
{ref_25:4}
488b38e8
{call_2f:4}
4889c7e8
{call_37:4}
05
{texture_base:4}
488d55d40fb7f04889df31c9e8
{call_4d:4}
498b7e088b75d4e8
{call_59:4}
"""

MAC_BIND = """
554889e54883ec40488d05
{ref_8:4}
48897df88975f4488b7df8f6000148897dd80f8505000000e918010000817df4000000000f82100000008b45f4488b4dd83b41180f8205000000e9f6000000488b45d84805180000008b75f44889c7e8
{call_5e:4}
488b00f6401c010f857f000000488d3d
{ref_70:4}
488b45d84805180000008b75f448897dd04889c7e8
{call_8b:4}
488b004805080000004889c7e8
{call_9c:4}
488945e8488b75e88b55f4488b7dd0b000e8
{call_b2:4}
48817de8000000000f841d000000488b45e8483d00000000488945c80f8409000000488b7dc8e8
{call_dd:4}
48c745e800000000e955000000bfc0840000b813850000b9c7840000c605
{ref_fe:4}
01897dc489cf8945c0e8
{call_10d:4}
488b55d84881c2180000008b75f44889d7e8
{call_123:4}
488b000fb708894de48b75e48b7dc0e8
{call_137:4}
8b7dc4e8
{call_13f:4}
4883c4405dc3
"""

ARM_SELECT = """
{global_low:4}
4ff0ff36
{global_high:4}
7844056828680c96
{call_14:4}
d8f80440012805d10c9608aa2046
{special_id:4}
0de028680c96
{call_30:4}
0c96
{call_36:4}
{texture_base:4}
084408aa0c9681b220460023
{call_4a:4}
08994ff0ff36d8f804000c96
{call_5a:4}
"""

ARM_BIND = """
80b56f4688b0
{ref_6:4}
{ref_a:4}
7a441268079006910798117811f0010f039000d163e00698002804d3069803990a69904200d35ae0039810300699
{call_3c:4}
0068007c10f0010f2bd1039810300699
{call_50:4}
00680430
{call_58:4}
{ref_5c:4}
{ref_60:4}
794405900598069a029008460299
{call_72:4}
0020c0f20000059981420ad00020c0f2000005998142019102d00198
{call_92:4}
ffe70020c0f20000059024e048f2c740c0f20000
{ref_aa:4}
{ref_ae:4}
7944069a0a60
{call_b8:4}
039810300699
{call_c2:4}
48f21351c0f200010068006804900498009008460099
{call_dc:4}
48f2c040c0f20000
{call_e8:4}
08b080bd
"""

ARM_FIELDS = {'ARM_SELECT': {'global_low': {'kind': 'movw', 'register': 'r0'}, 'global_high': {'kind': 'movt', 'register': 'r0'}, 'call_14': {'kind': 'bl'}, 'special_id': {'kind': 'movw', 'register': 'r1'}, 'call_30': {'kind': 'bl'}, 'call_36': {'kind': 'bl'}, 'texture_base': {'kind': 'movw', 'register': 'r1'}, 'call_4a': {'kind': 'bl'}, 'call_5a': {'kind': 'bl'}}, 'ARM_BIND': {'ref_6': {'kind': 'movw', 'register': 'r2'}, 'ref_a': {'kind': 'movt', 'register': 'r2'}, 'call_3c': {'kind': 'blx'}, 'call_50': {'kind': 'blx'}, 'call_58': {'kind': 'bl'}, 'ref_5c': {'kind': 'movw', 'register': 'r1'}, 'ref_60': {'kind': 'movt', 'register': 'r1'}, 'call_72': {'kind': 'bl'}, 'call_92': {'kind': 'blx'}, 'ref_aa': {'kind': 'movw', 'register': 'r1'}, 'ref_ae': {'kind': 'movt', 'register': 'r1'}, 'call_b8': {'kind': 'blx'}, 'call_c2': {'kind': 'blx'}, 'call_dc': {'kind': 'blx'}, 'call_e8': {'kind': 'blx'}}}
