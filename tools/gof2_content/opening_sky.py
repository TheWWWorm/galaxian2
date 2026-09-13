"""Read opening sky resource declarations and the linked system star alternatives.

The emitted data is a small resource selector, never executable instructions.
Other mission/location overrides are deliberately outside this selector's scope.
"""
from .opening_loadout import template
from .ship_models import section_bytes


def extract_opening_sky(mach, projection):
    if not projection or mach.architecture not in ['x86_64', 'armv7']: return {}
    import capstone
    mac=mach.architecture=='x86_64'; prefix='MAC_' if mac else 'ARM_'
    text=mach.text; base=text['address']; file_base=mach.slice_offset+text['offset']
    code=mach.data[text['offset']:text['offset']+text['length']]
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB); decoder.detail=True
    provenance={}
    def require(ok):
        if not ok: raise ValueError('Unsupported opening sky context')
    def instruction(m,key):
        rows=list(decoder.disasm(m[key],base+m.start(key)))
        require(len(rows)==1 and rows[0].size==len(m[key])); return rows[0]
    def match(key,address=None):
        name=prefix+key.upper(); pattern=template(globals()[name])
        matches=([pattern.match(code,address-base)] if address is not None else
                 [m for m in pattern.finditer(code) if mac or m.start()%2==0])
        require(len(matches)==1 and matches[0] is not None); m=matches[0]
        if not mac:
            for field,expected in ARM_FIELDS[name].items():
                i=instruction(m,field); require(i.mnemonic==expected['kind'])
                if 'register' in expected: require(i.reg_name(i.operands[0].reg)==expected['register'])
        provenance[key]={'offset':file_base+m.start(),'bytes':len(m[0])}; return m
    def target(m,key):
        return base+m.end(key)+int.from_bytes(m[key],'little',signed=True) if mac else instruction(m,key).operands[0].imm
    def identifier(m,key):
        value=int.from_bytes(m[key],'little') if mac else instruction(m,key).operands[1].imm
        require(0<=value<=65533); return value
    def getter(key,address,raw):
        found=section_bytes(mach,address,len(raw),b'__text')
        require(found is not None and found[0]==raw)
        provenance[key]={'offset':found[1],'bytes':len(raw)}
    try:
        stars=match('stars'); opening=match('opening')
        require(stars.end()==opening.start())
        texture=match('texture',target(opening,'jump_42' if mac else 'jump_3c'))
        require(opening.end()<=texture.start()<opening.end()+2048)
        cursor=projection['provenance']['cursor']
        require(target(opening,'call_4' if mac else 'call_6')==base+cursor['offset']-file_base)
        getter('cursor',base+cursor['offset']-file_base,bytes.fromhex('554889e58b87780200005dc3' if mac else 'd0f8d4017047'))
        system=target(stars,'call_b' if mac else 'call_8')
        system_id=target(stars,'call_13' if mac else 'call_10')
        require(system==target(stars,'call_5a' if mac else 'call_50'))
        require(system_id==target(stars,'call_62' if mac else 'call_58'))
        getter('system',system,bytes.fromhex('554889e5488b87280200005dc3' if mac else 'd0f890017047'))
        getter('system_id',system_id,bytes.fromhex('554889e58b47205dc3' if mac else '40697047'))
        require(target(stars,'call_47' if mac else 'call_42')==target(opening,'call_2e' if mac else 'call_2a'))
        require(target(stars,'call_99' if mac else 'call_82')==target(texture,'call_2'))
        if not mac:
            require(instruction(stars,'word_18').operands[1].imm==0x5556 and instruction(stars,'word_20').operands[1].imm==0x5555)
        return {'world_type':3,'campaign_cursor':0,'location_match':False,'star_variants':3,
                'star_mesh_base':identifier(stars,'id_38' if mac else 'word_38'),
                'star_texture_base':identifier(stars,'id_8a' if mac else 'word_78'),
                'sky_mesh_id':identifier(opening,'id_24' if mac else 'word_1e'),
                'sky_texture_id':identifier(opening,'id_3d' if mac else 'word_38'),
                'provenance':provenance}
    except (ValueError,KeyError,IndexError,TypeError,OverflowError): return {}

MAC_STARS = """
4c8d25
{ref_0:4}
498b3c24e8
{call_b:4}
4889c7e8
{call_13:4}
4863c0488d530c4869c8565555554889ce48c1ee3f48c1e92001f18d0c49f7d98d8408
{id_38:4}
0fb7f04c89ff31c9e8
{call_47:4}
488d05
{ref_4c:4}
4c8b38498b3c24e8
{call_5a:4}
4889c7e8
{call_62:4}
488d93400200004863c04869c8565555554889ce48c1ee3f48c1e92001f18d0c49f7d98d8408
{id_8a:4}
0fb7f04c89ff31c9e8
{call_99:4}
"""

MAC_OPENING = """
498b3c24e8
{call_4:4}
85c04989df75374183bf1401000003752d488d1d
{ref_1a:4}
488b3bbe
{id_24:4}
4c89f231c9e8
{call_2e:4}
488b3b498d973c020000be
{id_3d:4}
e9
{jump_42:4}
"""

MAC_TEXTURE = """
31c9e8
{call_2:4}
"""

ARM_STARS = """
30681594cdf85481
{call_8:4}
cdf85481
{call_10:4}
34465e46
{word_18:4}
06f10802
{word_20:4}
002350fb0bf1cdf8548101ebd17101eb4101401a
{word_38:4}
084481b22846
{call_42:4}
2068daf80050cdf85481
{call_50:4}
cdf85481
{call_58:4}
50fb0bf1b3460bf5ce7200232646cdf8548101ebd17101eb4101401a
{word_78:4}
084481b22846
{call_82:4}
"""

ARM_OPENING = """
3068cdf85481
{call_6:4}
c0b9dbf8c000032814d1d0464ff0ff35d8f80000
{word_1e:4}
55950023159c2246
{call_2a:4}
d8f800000bf5cc725595
{word_38:4}
{jump_3c:2}
"""

ARM_TEXTURE = """
0023
{call_2:4}
"""

ARM_FIELDS = {'ARM_STARS': {'call_8': {'kind': 'bl'}, 'call_10': {'kind': 'bl'}, 'word_18': {'kind': 'movw', 'register': 'fp'}, 'word_20': {'kind': 'movt', 'register': 'fp'}, 'word_38': {'kind': 'movw', 'register': 'r1'}, 'call_42': {'kind': 'bl'}, 'call_50': {'kind': 'bl'}, 'call_58': {'kind': 'bl'}, 'word_78': {'kind': 'movw', 'register': 'r1'}, 'call_82': {'kind': 'bl'}}, 'ARM_OPENING': {'call_6': {'kind': 'bl'}, 'word_1e': {'kind': 'movw', 'register': 'r1'}, 'call_2a': {'kind': 'bl'}, 'word_38': {'kind': 'movw', 'register': 'r1'}, 'jump_3c': {'kind': 'b'}}, 'ARM_TEXTURE': {'call_2': {'kind': 'bl'}}}
