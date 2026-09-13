"""Fresh opening NPC hostility declarations, with linked constructor/update evidence."""
import copy
from .opening_loadout import template
from .ship_models import section_bytes

VALUES={'actor_kind':8,'initial_hostile':False,'updated_hostile':True,'updates_while_inactive':True}
GETTERS={'x86_64':{'special_getter':('call_41','554889e58a87ec00000024015dc3'),
                   'neutral_getter':('call_5e','554889e58a87f900000024015dc3')},
         'armv7':{'special_getter':('call_48','90f8e0007047'),
                  'neutral_getter':('call_64','90f8ed007047')}}


def extract_npc_hostility(mach,actors):
    import capstone
    if mach.architecture not in LAYOUTS:return {}
    mac=mach.architecture=='x86_64';proof={}
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    def require(ok):
        if not ok:raise ValueError('Unsupported fresh NPC hostility')
    def address(span):
        offset=span['offset']-mach.slice_offset
        sections=[s for s in mach.sections if s['offset']<=offset and offset+span['bytes']<=s['offset']+s['length']]
        require(len(sections)==1)
        return sections[0]['address']+offset-sections[0]['offset']
    def read(key,at,size,section=b'__text'):
        value=section_bytes(mach,at,size,section);require(value is not None and len(value[0])==size)
        proof[key]={'offset':value[1],'bytes':size};return value[0]
    def target(row,key,at):
        if mac:return at+row.end(key)+int.from_bytes(row[key],'little',signed=True)
        rows=list(decoder.disasm(row[key],at+row.start(key)))
        require(len(rows)==1 and rows[0].mnemonic=='bl' and rows[0].operands[0].type==capstone.arm.ARM_OP_IMM)
        return rows[0].operands[0].imm
    try:
        initial=actors['npc_initialization']
        require(initial['guidance'] and initial['holding'] and initial['activation'])
        require([r['actor_id'] for r in actors['actors']]==[0,1,2])
        require([r['actor_kind'] for r in actors['actors']]==[8,8,8])
        require([r['hull_catalogue_id'] for r in actors['actors']]==[2,23,2])
        slot=initial['flight']['provenance']['virtual_update']
        require(slot==initial['guidance']['provenance']['virtual_update'])
        at=address(slot);size=8 if mac else 4
        sections=[s for s in mach.sections if s['segment']==b'__DATA' and s['name']==b'__const' and s['address']<=at and at+size<=s['address']+s['length']]
        require(len(sections)==1)
        offset=sections[0]['offset']+at-sections[0]['address']
        raw=mach.data[offset:offset+size];require(len(raw)==size)
        proof['virtual_update']={'offset':offset+mach.slice_offset,'bytes':size}
        pointer=int.from_bytes(raw,'little')
        if not mac:require(pointer&1)
        bases={'stats':address(initial['provenance']['stats_entry']),
               'base':address(initial['provenance']['point_geometry'])-(0x21e if mac else 0x1a6),
               'fresh':address(initial['primary_weapon']['provenance']['fresh_level']),
               'update':pointer if mac else pointer&~1}
        blocks={};positions={}
        for key,(base,delta,size,pattern) in LAYOUTS[mach.architecture].items():
            at=bases[base]+delta;positions[key]=at
            blocks[key]=template(pattern).fullmatch(read(key,at,size));require(blocks[key] is not None)
        row=blocks['overrides'];at=positions['overrides']
        if mac:require(target(row,'ref_0',at)==target(row,'ref_13',at))
        else:
            # Live global-address construction must not overwrite flag registers.
            for block,field,mnemonic,register in [('base_flags','ref_6','movt','r1'),('overrides','ref_0','movw','r0'),('overrides','ref_8','movt','r0')]:
                match=blocks[block];rows=list(decoder.disasm(match[field],positions[block]+match.start(field)))
                require(len(rows)==1 and rows[0].mnemonic==mnemonic and rows[0].reg_name(rows[0].operands[0].reg)==register)
        for key,(field,pattern) in GETTERS[mach.architecture].items():
            raw=bytes.fromhex(pattern)
            require(read(key,target(row,field,at),len(raw))==raw)
        spans=sorted((s['offset'],s['offset']+s['bytes']) for s in proof.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        result=copy.deepcopy(VALUES);result['provenance']=proof;return result
    except (ValueError,KeyError,TypeError,IndexError,OverflowError):return {}


LAYOUTS = {'x86_64': {'stats_flags': ['stats',
                            814,
                            29,
                            'c6436100c6436000c683ec00000000c683f800000000c683f900000000'],
            'base_flags': ['base', 408, 8, 'c6435e00c6435f00'],
            'fresh_override': ['fresh', 66, 8, '41c6867001000000'],
            'kind': ['update',
                     192,
                     76,
                     '418a465fa8010f8584000000418b4e4483c1f8b00183f902722b4c89f7e8 {call_1d:4} '
                     '88c130c084c9751b488d05 {ref_2a:4} 488b38e8 {call_34:4} 418b76444889c7e8 '
                     '{call_40:4} 498b4e08884160'],
            'overrides': ['update',
                          560,
                          119,
                          '488d05 {ref_0:4} 488b38e8 {call_a:4} 3c01752a488d05 {ref_13:4} '
                          '488b00f6807001000001741741837e44087510498b4608c6406000498b4608c6406100498b7e08e8 '
                          '{call_41:4} 3c017510498b4608c6406001498b4608c6406100498b7e08e8 '
                          '{call_5e:4} 3c017510498b4608c6406101498b4608c6406000']},
 'armv7': {'stats_flags': ['stats',
                           524,
                           88,
                           '002001214ff0ff35c6f8d00086f8701004acc6f80c1186f8440086f8450086f8680086f8c01086f8c100c6f8b40086f8c210c6f8d40086f85d0086f85c0086f8e00086f8ec0086f8ed00706786f8540086f8550086f86900'],
           'base_flags': ['base',
                          290,
                          62,
                          '00204ff0ff32 {ref_6:4} '
                          'c6f82480f064794486f86e0086f8210086f8710086f8380086f8390086f83a0086f83e0086f83f0086f840007264012286f88820'],
           'fresh_override': ['fresh',
                              0,
                              74,
                              '00230124c0f888300a6800f5e071c0f89c31c0f8a031c0f8ac31c0f8b03101f98f8ac0f8d031c0f8b441c0f8b831c0f8bc31c0f8a831c0f8a431c0f8f830c0f8f430c0f8003180f80431'],
           'kind': ['update',
                    258,
                    90,
                    '9af83f0010b1daf8040051e0daf8240020f00100082801d101201ae04ff0ff345046cdf8a048 '
                    '{call_26:4} 08b1002010e0 {ref_30:4} {ref_34:4} 784400680068cdf8a048 '
                    '{call_42:4} daf82410cdf8a048 {call_4e:4} daf8041081f85c00'],
           'overrides': ['update',
                         648,
                         124,
                         '{ref_0:4} 4ff0ff34 {ref_8:4} 7844006837900068cdf8a048 {call_18:4} '
                         '01280fd13798006890f8040150b1daf82400082801bfdaf80400002180f85c1080f85d10daf80400cdf8a048 '
                         '{call_48:4} 0146daf80400012904bf0121a0f85c104ff0ff31cdf8a018 {call_64:4} '
                         '012807d1daf80400012180f85d10002180f85c10']}}
