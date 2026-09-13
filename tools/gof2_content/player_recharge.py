"""Static equipment-bound shield recharge and ordinary player-pass declarations."""
import struct
from .opening_loadout import template
from .ship_models import section_bytes

VALUES={'equipment_property':19,'period_ms':100,'capacity_divisor':100.0,
        'initial_elapsed_ms':0,'discard_excess_time':True,'pulses_per_update':1,
        'requires_living_hull':True,'before_world_weapons':True}


def extract_player_recharge(mach,actors,vehicle,clock):
    import capstone
    arch=mach.architecture
    if arch not in LAYOUTS:return {}
    mac=arch=='x86_64';proof={};blocks={};positions={}
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    text=mach.text;code=mach.data[text['offset']:text['offset']+text['length']]
    def require(ok):
        if not ok:raise ValueError('Unsupported player shield recharge')
    def address(span):
        offset=span['offset']-mach.slice_offset-text['offset']
        require(0<=offset and offset+span['bytes']<=len(code))
        return text['address']+offset
    def read(key,at,size,section=b'__text'):
        result=section_bytes(mach,at,size,section);require(result is not None and len(result[0])==size)
        proof[key]={'offset':result[1],'bytes':size};return result[0]
    def match(key,at=None):
        size,spec=LAYOUTS[arch][key]
        if at is None:
            found=[m for m in template(spec).finditer(code) if mac or m.start()%2==0]
            require(len(found)==1);at=text['address']+found[0].start()
        row=template(spec).fullmatch(read(key,at,size));require(row is not None)
        blocks[key]=row;positions[key]=at;return at
    def target(key,field,kind='bl'):
        row=blocks[key];at=positions[key]
        if mac:return at+row.end(field)+int.from_bytes(row[field],'little',signed=True)
        rows=list(decoder.disasm(row[field],at+row.start(field)))
        require(len(rows)==1 and rows[0].mnemonic==kind and rows[0].operands[0].type==capstone.arm.ARM_OP_IMM)
        return rows[0].operands[0].imm
    try:
        player=actors['player_initialization'];require(player and vehicle['equipment_rule']=='last_matching')
        pulse=match('pulse');update=match('recharge')
        match('application_order',address(clock['provenance']['frame'])+(0x547 if mac else 0x2cc))
        match('world_pass',target('application_order','call_7e' if mac else 'call_74'))
        require(target('pulse','call_c')==address(player['provenance']['shield_getter']))
        require(target('pulse','call_4' if mac else 'call_6')==target('pulse','call_18'))
        getter=match('getter',target('pulse','call_20' if mac else 'call_1e'))
        require(target('recharge','call_12' if mac else 'call_10')==getter)
        require(target('recharge','call_a')==target('pulse','call_4' if mac else 'call_6'))
        match('hull_getter',target('recharge','call_1e'))
        match('adder',target('recharge','call_59' if mac else 'call_6a'))
        assignment=address(player['provenance']['shield_assignment'])+(26 if mac else 14)
        match('assignment',assignment)
        require(target('assignment','call_11' if mac else 'call_8')==address(vehicle['provenance']['property_getter']))
        match('equipment_zero',address(player['provenance']['reset'])+(-8 if mac else 0))
        ctor=pulse-(0x92e if mac else 0x51a)
        match('clock_zero',ctor+(0x302 if mac else 0x152))
        match('blocked_zero',ctor+(0x298 if mac else 0x12a))
        require(target('application_order','call_5b' if mac else 'call_50')==update-(0x234a if mac else 0x1d00))
        if mac:divisor_at=target('pulse','ref_2c')
        else:
            match('zero_vector',ctor+0x1c);match('zero_integer',ctor+0x2c)
            at=match('divisor_load',ctor+0x35e)
            rows=list(decoder.disasm(blocks['divisor_load']['ref_0'],at))
            require(len(rows)==1 and rows[0].mnemonic=='vldr' and rows[0].reg_name(rows[0].operands[0].reg)=='s20')
            op=rows[0].operands[1];require(op.type==capstone.arm.ARM_OP_MEM and rows[0].reg_name(op.mem.base)=='pc')
            divisor_at=((at+4)&~3)+op.mem.disp
        divisor=struct.unpack('<f',read('divisor',divisor_at,4,b'__const' if mac else b'__text'))[0]
        require(divisor==100.0)
        spans=sorted((p['offset'],p['offset']+p['bytes']) for p in proof.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        return dict(VALUES,provenance=proof)
    except (ValueError,KeyError,TypeError,IndexError,OverflowError,struct.error):return {}


LAYOUTS = {'x86_64': {'pulse': [69,
                      '498b7d00e8 {call_4:4} 4889c7e8 {call_c:4} 4189c6498b7d00e8 {call_18:4} '
                      '4889c7e8 {call_20:4} 0f57c0f30f2ac0f30f5e05 {ref_2c:4} '
                      'f3410f2acef30f5ec8f30f118bac020000'],
            'recharge': [94,
                         '488d05 {ref_0:4} 488b38e8 {call_a:4} 4889c7e8 {call_12:4} '
                         '85c07e43498b3ee8 {call_1e:4} '
                         '85c07e37498b866801000048038548fbffff498986680100004883f8657c1c49c7866801000000000000f3410f1086ac020000498b3ee8 '
                         '{call_59:4}'],
            'assignment': [26, '498b4770488b40084a8b3c30be13000000e8 {call_11:4} 41894724'],
            'getter': [9, '554889e58b47245dc3'],
            'hull_getter': [12, '554889e58b87800000005dc3'],
            'adder': [38,
                      '554889e5f30f588790000000f30f2a8f9c000000f30f5dc1f30f1187900000005de9 '
                      '{call_21:4}'],
            'clock_zero': [11, '48c7836801000000000000'],
            'blocked_zero': [4, 'c6434000'],
            'equipment_zero': [8, '49c7472400000000'],
            'application_order': [131,
                                  '41817d589f0f00007f56498d454c4183bdbc01000000490f4ec48b304d8b8d980000004d8b85a8000000498b8d88000000498b95a0000000498b7d60458b951c010000410fb65d6b418b45208944241083e301895c240844891424e8 '
                                  '{call_5b:4} 498b7d60e8 {call_64:4} '
                                  '88c349637548498bbd90000000410fb6556b83e201e8 {call_7e:4}'],
            'world_pass': [40,
                           '554889e54157415641554154534883ec288955b04989f64989ff41f687f8010000010f84b2000000']},
 'armv7': {'pulse': [62,
                     'daf800000896 {call_6:4} 0896 {call_c:4} 0446daf800000896 {call_18:4} 0896 '
                     '{call_1e:4} 40ec300bbbff200644ec304bbbff201680ee0a0a81ee000a85ed850a'],
           'recharge': [110,
                        '08984ff0ff340068ec94 {call_a:4} ec94 {call_10:4} 01282adbdbf80000ec94 '
                        '{call_1e:4} '
                        '012823dbdbe945018219069841eb0003652a4ff000014ff00000cbe945234ff0000238bf0121002bb8bf012208bf0a4662b90bf58a714ff0ff3208604860dbf81412dbf80000ec92 '
                        '{call_6a:4}'],
           'assignment': [14, '1321e06e40688059 {call_8:4} 6062'],
           'getter': [4, '406a7047'],
           'hull_getter': [4, '806f7047'],
           'adder': [42,
                     '90ed251a41ec301b90ed220abbff011600ef200db4eec10af1ee10fa48bfb0ee401a80ed221a '
                     '{call_26:4}'],
           'clock_zero': [8, '04f5887000f98f8a'],
           'blocked_zero': [4, '84f82420'],
           'equipment_zero': [12, '04f11c0084f85c2040f98f0a'],
           'zero_vector': [6, '80ef50800446'],
           'zero_integer': [2, '0022'],
           'divisor_load': [4, '{ref_0:4}'],
           'application_order': [120,
                                 'dbf84c00b0f57a6f24dadbf860014ff0ff34dbf86c3000280c98dbf87490dbf87cc0dbf87820dbf8d0e0c8bf0bf140000168dbf854009bf85b60dbf81450b494cdf800c0cdf80490cdf808e003960495 '
                                 '{call_50:4} dbf854004ff0ff36b496 {call_5e:4} '
                                 'dbf83c1005469bf85b30dbf87000ca17b496 {call_74:4}'],
           'world_pass': [30, 'f0b503af2de9000d2ded028b87b00546924695f858018b460093002865d0']}}
