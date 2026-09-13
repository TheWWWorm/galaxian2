"""Recover weapon property bindings and primary-weapon modifier declarations.

The importer emits numeric catalogue bindings and provenance, never source code.
Projectile construction, hit tests and weapon-kind behavior remain native work.
"""
import math
import struct
from .opening_loadout import template
from .ship_models import section_bytes
from .weapon_capacity import extract_weapon_capacity
from .ordinary_hit_policy import extract_ordinary_hit_policy
from .player_hit_policy import extract_player_hit_policy
from .weapon_collision_bounds import extract_weapon_collision_bounds


def extract_weapon_parameters(mach, vehicle, opening):
    if not vehicle or not opening or mach.architecture not in ('x86_64', 'armv7'): return {}
    import capstone
    mac = mach.architecture == 'x86_64'; prefix = 'MAC_' if mac else 'ARM_'
    text = mach.text; base = text['address']; file_base = mach.slice_offset + text['offset']
    code = mach.data[text['offset']:text['offset'] + text['length']]
    decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB); decoder.detail = True
    provenance = {}; constants = {}
    def require(value):
        if not value: raise ValueError('Unsupported weapon parameter declarations')
    def address(extent): return base + extent['offset'] - file_base
    def record(key, at, size):
        value = section_bytes(mach, at, size, b'__text'); require(value is not None)
        provenance[key] = {'offset':value[1], 'bytes':size}; return value[0]
    def instruction(m, field):
        rows = list(decoder.disasm(m[field], base+m.start(field)))
        require(len(rows)==1 and rows[0].size==len(m[field])); return rows[0]
    def match(key):
        rows = [m for m in template(globals()[prefix+key.upper()]).finditer(code) if mac or m.start()%2==0]
        require(len(rows)==1); m=rows[0]; record(key,base+m.start(),len(m[0]))
        if not mac:
            for field in m.groupdict():
                i=instruction(m,field)
                if field.startswith('call_'): require(i.mnemonic=='bl')
                elif field.startswith('ref_'): require(i.mnemonic=='vldr' and i.operands[1].mem.base==capstone.arm.ARM_REG_PC)
                elif field.endswith('_property'): require(i.mnemonic=='movs' and i.op_str.startswith('r1, #'))
                elif field=='low_damage_threshold': require(i.mnemonic=='cmp.w' and i.op_str.startswith('fp, #'))
                elif field.startswith('jump_'):
                    expected={('head','jump_32'):'cbz',('scale','jump_22'):'bpl',('scale','jump_28'):'bge'}.get((key,field),'b')
                    require(i.mnemonic==expected)
                    if expected=='cbz': require(i.reg_name(i.operands[0].reg)=='r0')
        return m
    def target(m, field):
        return base+m.end(field)+int.from_bytes(m[field],'little',signed=True) if mac else instruction(m,field).operands[-1].imm
    def scalar(m, field):
        return int.from_bytes(m[field],'little',signed=True) if mac else instruction(m,field).operands[-1].imm
    def helper(key, at, spec): require(record(key,at,len(bytes.fromhex(spec)))==bytes.fromhex(spec))
    def constant(key, m, field, register=None):
        if mac: at=target(m,field)
        else:
            i=instruction(m,field); require(i.reg_name(i.operands[0].reg)==register)
            at=((base+m.start(field)+4)&~3)+i.operands[1].mem.disp
        data=section_bytes(mach,at,4,b'__const' if mac else b'__text'); require(data is not None)
        value=struct.unpack('<f',data[0])[0];require(math.isfinite(value))
        constants[key]={'offset':data[1],'bytes':4};return value
    try:
        head=match('head');tail=match('tail');scale=match('scale');modifier=match('modifier');defaults=match('defaults')
        require(scale.start()==head.end())
        if mac:
            require(tail.start()==scale.end())
            require(target(head,'jump_43')==base+scale.start() and target(head,'jump_48')==base+tail.start())
            require(target(scale,'jump_1d')==base+scale.start()+0x24 and target(scale,'jump_22')==base+scale.start()+0x60 and target(scale,'jump_5e')==base+tail.start())
            properties=[target(head,k) for k in ['call_11','call_26']]+[target(tail,k) for k in ['call_30','call_45']]+[target(modifier,k) for k in ['call_11','call_5f']]
            categories=[target(head,'call_3c')]
            types=[target(tail,'call_1b')]
            getter_calls=[target(scale,k) for k in ['call_a','call_40','call_6d']]
            damage_getter=target(scale,'call_12');interval_getters=[target(scale,k) for k in ['call_48','call_75']]
            helper('category_getter',categories[0],'554889e58b47045dc3')
            helper('id_getter',target(tail,'call_b'),'554889e58b075dc3')
            helper('ship_getter',getter_calls[0],'554889e5488b87000200005dc3')
            helper('damage_getter',damage_getter,'554889e5f30f1047585dc3')
            helper('interval_getter',interval_getters[0],'554889e5f30f1047545dc3')
            divisor=constant('percent_divisor',modifier,'ref_1a')
            require(divisor==constant('damage_divisor',modifier,'ref_6b'))
            default=constant('default_multiplier',modifier,'ref_22')
            require(default==constant('damage_default',modifier,'ref_73')==1.0)
            sentinel=constant('missing_multiplier',modifier,'ref_31')
            require(sentinel==constant('damage_missing',modifier,'ref_81'))
            low_scale=constant('low_damage_interval_scale',scale,'ref_82')
            require(target(modifier,'jump_43')==base+modifier.start()+0x48)
            require(len({target(modifier,k) for k in ['jump_88','jump_8a','jump_94']})==1)
            factory=target(tail,'call_73')
        else:
            scale_tail=match('scale_tail');loads=match('constants');low_load=match('scale_load')
            require(scale_tail.start()==scale.end()+12 and tail.start()==scale_tail.end())
            require(low_load.end()==head.start()-0x3e)
            require(target(head,'jump_32')==base+scale.start() and target(head,'jump_3a')==base+tail.start())
            require(target(scale,'jump_22')==target(scale,'jump_28')==base+scale_tail.start() and target(scale,'jump_60')==base+scale_tail.end()-2)
            properties=[target(head,k) for k in ['call_c','call_1e']]+[target(tail,k) for k in ['call_2c','call_3c']]+[target(modifier,k) for k in ['call_8','call_36']]
            categories=[target(head,'call_2e')];types=[target(tail,'call_1c')]
            getter_calls=[target(scale,k) for k in ['call_a','call_36']]+[target(scale_tail,'call_1a')]
            damage_getter=target(scale,'call_12');interval_getters=[target(scale,'call_3e'),target(scale_tail,'call_22')]
            helper('category_getter',categories[0],'40687047')
            helper('id_getter',target(tail,'call_a'),'00687047')
            helper('ship_getter',getter_calls[0],'d0f87c017047')
            helper('damage_getter',damage_getter,'806d7047')
            helper('interval_getter',interval_getters[0],'406d7047')
            divisor=constant('percent_divisor',loads,'ref_8','s20')
            sentinel=constant('missing_multiplier',loads,'ref_10','s24')
            low_scale=constant('low_damage_interval_scale',low_load,'ref_0','s16')
            default=1.0 # Both reset stores and the modifier immediate are recognized above.
            require(0<address(vehicle['provenance']['equipment_selector'])-(base+loads.start())<128)
            factory=target(tail,'call_60')
        require(len(set(properties))==len(set(getter_calls))==len(set(interval_getters))==1)
        require(properties[0]==address(vehicle['provenance']['property_getter']))
        require(types[0]==address(vehicle['provenance']['type_getter']))
        require(categories[0]==address(opening['provenance']['category_getter']))
        # Recheck the shared helpers instead of trusting caller-supplied extents.
        helper('property_getter',properties[0],
               '554889e5488b4f388b3931d2eb044883c202b8257899c539fa730d488b410839349075ea8b4490045dc3' if mac else
               '026bd2f80090b9f1000f08d05268002352f82300884207d002334b45f8d347f62500ccf29950704702eb830040687047')
        helper('type_getter',types[0],'554889e58b47085dc3' if mac else '80687047')
        table=vehicle['provenance']['equipment_table'];table_address=address(table)
        raw=record('equipment_table',table_address,120 if mac else 30)
        require(all(provenance[k]==vehicle['provenance'][k] for k in ['property_getter','type_getter','equipment_table']))
        require(provenance['category_getter']==opening['provenance']['category_getter'])
        targets=[table_address+x for x in struct.unpack('<30i',raw)] if mac else [table_address+x*2 for x in raw]
        ids=[i for i,at in enumerate(targets) if at==base+modifier.start()];require(len(ids)==1)
        require(0<address(vehicle['provenance']['equipment_selector'])-(base+defaults.start())<256)
        require(section_bytes(mach,factory,4,b'__text') is not None)
        # All relationships above refer to the edition's own executable offsets.
        result={key:scalar(context,key) for context,keys in [(head,['damage_property','interval_property']),(tail,['lifetime_property','speed_property']),(modifier,['interval_percent_property','damage_percent_property']),(scale,['low_damage_threshold'])] for key in keys}
        require(all(0<=result[k]<=65535 for k in result) and len({result[k] for k in ['damage_property','interval_property','lifetime_property','speed_property']})==4)
        require(0<divisor<=10000 and 0<low_scale<=1 and sentinel<0)
        require(vehicle['item_type_value_index']==5 and opening['item_category_value_index']==3)
        spans=sorted((r['offset'],r['offset']+r['bytes']) for r in provenance.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        values=sorted(set((r['offset'],r['offset']+r['bytes']) for r in constants.values()))
        require(all(a[1]<=b[0] for a,b in zip(values,values[1:])))
        require(all(a>=d or b<=c for a,b in spans for c,d in values))
        result.update(item_type_value_index=5,item_category_value_index=3,primary_category=0,modifier_type=ids[0],
                      percent_divisor=divisor,default_multiplier=default,missing_multiplier=sentinel,
                      low_damage_interval_scale=low_scale,provenance=provenance,value_sources=constants)
        result['launch_modes'] = extract_launch_modes(mach, result)
        result['projectile_capacity'] = extract_weapon_capacity(mach, result, factory)
        result['ordinary_hit_policy'] = extract_ordinary_hit_policy(mach, result)
        result['player_hit_policy'] = extract_player_hit_policy(mach, result)
        result['collision_bounds'] = extract_weapon_collision_bounds(mach, result)
        return result
    except (ValueError,KeyError,IndexError,TypeError,OverflowError,struct.error): return {}


def extract_launch_modes(mach, weapon):
    """Item-specific alternate path selector; type zero alone is insufficient."""
    import capstone
    mac = mach.architecture == 'x86_64'
    text = mach.text; base = text['address']
    code = mach.data[text['offset']:text['offset']+text['length']]
    decoder = capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB); decoder.detail=True
    try:
        def one(spec):
            rows=[m for m in template(spec).finditer(code) if mac or m.start()%2==0]
            if len(rows)!=1: raise ValueError('Ambiguous launch mode')
            return rows[0]
        def inst(m,key,name,registers):
            rows=list(decoder.disasm(m[key],base+m.start(key)))
            if len(rows)!=1 or rows[0].mnemonic!=name or rows[0].size!=len(m[key]): raise ValueError('Unknown mode operand')
            i=rows[0]
            if not i.operands or i.operands[-1].type!=capstone.arm.ARM_OP_IMM: raise ValueError('Mode operand is not an immediate')
            if [i.reg_name(op.reg) for op in i.operands[:-1]]!=registers: raise ValueError('Unknown mode registers')
            return i.operands[-1].imm
        def extent(m): return {'offset':mach.slice_offset+text['offset']+m.start(),'bytes':len(m[0])}
        declaration=one(MAC_LAUNCH_MODE if mac else ARM_LAUNCH_MODE)
        selector=one('41f68760010000010f85 {branch:4}' if mac else '93f808010028 {branch:4} d96b0868')
        if mac:
            singleton=int.from_bytes(declaration['single'],'little')
            first=-int.from_bytes(declaration['first'],'little',signed=True)
            count=int.from_bytes(declaration['count'],'little')
            getter=base+declaration.end('getter')+int.from_bytes(declaration['getter'],'little',signed=True)
            target=base+selector.end('branch')+int.from_bytes(selector['branch'],'little',signed=True)
            target_spec='498b4f788339007e {branch:1}'
        else:
            first=inst(declaration,'first','sub.w',['r0','r4'])
            count=inst(declaration,'count','cmp',['r0'])
            singleton=inst(declaration,'single','cmp',['r4'])
            inst(declaration,'address_low','movw',['r1']);inst(declaration,'address_high','movt',['r1'])
            getter=inst(declaration,'getter','bl',[])
            target=inst(selector,'branch','beq.w',[])
            target_spec='98680028'
        origin=weapon['provenance']['property_getter']
        expected=base+origin['offset']-mach.slice_offset-text['offset']
        if getter!=expected or not 0<=first<=65535 or not 1<=count<=64 or first+count>65536 or not 0<=singleton<=65535: return {}
        ids=list(range(first,first+count))+[singleton]
        if len(set(ids))!=len(ids): return {}
        size=9 if mac else 4
        selected=section_bytes(mach,target,size,b'__text')
        if selected is None or template(target_spec).fullmatch(selected[0]) is None: return {}
        provenance={'classification':extent(declaration),'selector':extent(selector),
                    'selected_path':{'offset':selected[1],'bytes':size},'property_getter':dict(origin)}
        spans=sorted((r['offset'],r['offset']+r['bytes']) for r in provenance.values())
        if any(a[1]>b[0] for a,b in zip(spans,spans[1:])): return {}
        return {'alternate_item_ids':ids,'provenance':provenance}
    except (ValueError,KeyError,TypeError,IndexError,OverflowError): return {}


MAC_LAUNCH_MODE = '''4189b79c00000081fe {single:4} 0f94c08d4e {first:1} 83f9 {count:1} 0f92c108c141888f600100004863de488d05 {address:4} 488b00488b4008488b3cd8be0a000000e8 {getter:4} '''
ARM_LAUNCH_MODE = ''' {first:4}  {count:2} 01d2012003e00020 {single:2} 08bf0120 {address_low:4} 4ff0ff35 {address_high:4} 86f808017944096808680a21406850f824000895 {getter:4} '''

MAC_HEAD = """
894d8c498b4424084a8b3c28be
{damage_property:4}
e8
{call_11:4}
89c3498b4424084a8b3c28be
{interval_property:4}
e8
{call_26:4}
4c89e14189c4488b41084989ce4a8b3c28e8
{call_3c:4}
85c074
{jump_43:1}
895dc0e9
{jump_48:4}
"""

MAC_TAIL = """
4c89f3488b43084a8b3c28e8
{call_b:4}
894588488b43084a8b3c28e8
{call_1b:4}
4189c7488b43084a8b3c28be
{lifetime_property:4}
e8
{call_30:4}
4189c6488b43084a8b3c28be
{speed_property:4}
e8
{call_45:4}
894424104489742408448924244989dc4c8b75a04c89f78b7588488b55a84489f9448b458c448b4dc0e8
{call_73:4}
"""

MAC_MODIFIER = """
498b4770488b40084a8b3c30be
{interval_percent_property:4}
e8
{call_11:4}
f30f2ac8f30f5e0d
{ref_1a:4}
f30f1015
{ref_22:4}
0f28c2f30f5cc10f2e05
{ref_31:4}
0f9bc00f94c184c80f28ca75
{jump_43:1}
0f28c8f3410f114f54498b4770488b40084a8b3c30be
{damage_percent_property:4}
e8
{call_5f:4}
0f57c0f30f2ac0f30f5e05
{ref_6b:4}
f30f5805
{ref_73:4}
f3410f1147580f2e05
{ref_81:4}
75
{jump_88:1}
7a
{jump_8a:1}
41c747580000803feb
{jump_94:1}
"""

MAC_DEFAULTS = """
41c747540000803f41c747580000803f
"""

MAC_SCALE = """
488d05
{ref_0:4}
488b38e8
{call_a:4}
4889c7e8
{call_12:4}
0f57c90f2ec876
{jump_1d:1}
83fb
{low_damage_threshold:1}
7c
{jump_22:1}
0f57c9f30f2acbf30f59c8488d05
{ref_2f:4}
488b38f30f2cc18945c0e8
{call_40:4}
4889c7e8
{call_48:4}
0f57c9f3410f2accf30f59c8f3440f2ce1eb
{jump_5e:1}
895dc0488d05
{ref_63:4}
488b38e8
{call_6d:4}
4889c7e8
{call_75:4}
0f57c9f3410f2accf30f5905
{ref_82:4}
f30f59c1f3440f2ce0
"""

ARM_HEAD = """
7068
{damage_property:2}
50f80a00cdf87080
{call_c:4}
83467068
{interval_property:2}
50f80a00cdf87080
{call_1e:4}
1090706850f80a00cdf87080
{call_2e:4}
{jump_32:2}
cdf828b00b95
{jump_3a:2}
"""

ARM_TAIL = """
706850f80a00cdf87080
{call_a:4}
09904ff0ff35706850f80a001c95
{call_1c:4}
83467068
{lifetime_property:2}
50f80a001c95
{call_2c:4}
80467068
{speed_property:2}
50f80a001c95
{call_3c:4}
1c9522460b995b4600910a99019110990291cdf80c804ff0ff3804900d980999
{call_60:4}
"""

ARM_MODIFIER = """
e06e
{interval_percent_property:2}
40688059
{call_8:4}
40ec300b
{damage_percent_property:2}
bbff200680ee0a0a29ef000db4eecc0af1ee10fa08bfb0ee490a84ed150ae06e40688059
{call_36:4}
40ec300bbbff200680ee0a0a00ef090db4eecc0a84ed160af1ee10fa08bfc4f858a0
{jump_5c:2}
"""

ARM_DEFAULTS = """
4ff07e5021666065a065
"""

ARM_CONSTANTS = """
87ef109f
{ref_4:4}
{ref_8:4}
4ff00108
{ref_10:4}
4ff07e5a0025
"""

ARM_SCALE = """
08980b950068cdf87080
{call_a:4}
cdf87080
{call_12:4}
40ec190bb5eec09af1ee10fa
{jump_22:2}
{low_damage_threshold:4}
{jump_28:2}
0898cdf828b00068cdf87080
{call_36:4}
cdf87080
{call_3e:4}
109940ec320b42ff982d41ec301bfbff200640ffb20dbbff200710ee100a
{jump_60:2}
"""

ARM_SCALE_TAIL = """
10984bec32bbbbff22c640ec300b0898bbff20a60068cdf87080
{call_1a:4}
cdf87080
{call_22:4}
4cff192d40ec300b4aff300dbbff2207bbff201710ee100a0a9011ee100a1090
"""

ARM_SCALE_LOAD = """
{ref_0:4}
4ff0000a4ff0ff380024
"""
