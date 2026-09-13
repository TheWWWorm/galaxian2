"""Static ordinary repair-device and fresh player hull declarations."""
import struct
from .opening_loadout import template
from .player_initialization import LAYOUTS as PLAYER_LAYOUTS
from .ship_models import section_bytes
from .scenery_population import import_symbol

VALUES={'equipment_type':15,'item_type_value_index':5,'item_id_value_index':1,'slow_item_id':75,'missing_device_mode':-1,
        'hull_periods_ms':[600,420],'armor_periods_ms':[1000,700],'hull_amount':1,'armor_amount':2,
        'initial_elapsed_ms':0,'base_hull_field':1,'upgrade_tag':0,'upgrade_bonus':40,
        'initial_upgrades':[],'after_shield_recharge':True,'requires_full_hull_for_armor':True,
        'discard_excess_time':True}


def extract_player_repair(mach,actors,vehicle,loadout):
    import capstone
    arch=mach.architecture
    if arch not in LAYOUTS:return {}
    mac=arch=='x86_64';text=mach.text;proof={};blocks={};positions={}
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    def require(ok):
        if not ok:raise ValueError('Unsupported ordinary player repair')
    def address(span):
        p=span['offset']-mach.slice_offset-text['offset']
        require(0<=p and p+span['bytes']<=text['length'])
        return text['address']+p
    def read(key,at,size,section=b'__text'):
        found=section_bytes(mach,at,size,section);require(found is not None and len(found[0])==size)
        proof[key]={'offset':found[1],'bytes':size};return found[0]
    def match(key,at):
        size,spec=LAYOUTS[arch][key];row=template(spec).fullmatch(read(key,at,size));require(row is not None)
        blocks[key]=row;positions[key]=at;return at
    def target(key,field,kind='bl'):
        row=blocks[key];at=positions[key]
        if mac:return at+row.end(field)+int.from_bytes(row[field],'little',signed=True)
        ins=list(decoder.disasm(row[field],at+row.start(field)))
        require(len(ins)==1 and ins[0].mnemonic==kind and ins[0].operands[-1].type==capstone.arm.ARM_OP_IMM)
        return ins[0].operands[-1].imm
    def branch_at(at):
        raw=section_bytes(mach,at,5 if mac else 4,b'__text');require(raw is not None)
        if mac:
            require(raw[0][0]==0xe8);return at+5+int.from_bytes(raw[0][1:],'little',signed=True)
        ins=list(decoder.disasm(raw[0],at));require(len(ins)==1 and ins[0].mnemonic=='bl')
        return ins[0].operands[0].imm
    def literal(key,field):
        if mac:return target(key,field)
        at=positions[key]+blocks[key].start(field);ins=list(decoder.disasm(blocks[key][field],at))
        require(len(ins)==1 and ins[0].mnemonic=='addw' and ins[0].reg_name(ins[0].operands[1].reg)=='pc' and ins[0].reg_name(ins[0].operands[0].reg)==('r2' if field=='ref_34' else 'r0'))
        return ((at+4)&~3)+ins[0].operands[2].imm
    try:
        player=actors['player_initialization'];recharge=player['recharge'];npc=actors['npc_initialization']
        require(recharge and vehicle['equipment_rule']=='last_matching')
        match('update',address(recharge['provenance']['recharge'])+recharge['provenance']['recharge']['bytes'])
        match('device_getter',target('update','call_12' if mac else 'call_c'))
        hull=address(recharge['provenance']['hull_getter'])
        for field in (['call_26','call_7b','call_c3'] if mac else ['call_22','call_86','call_e2']):require(target('update',field)==hull)
        maximum=match('hull_max',target('update','call_85' if mac else 'call_92'))
        require(target('update','call_cd' if mac else 'call_ee')==maximum)
        for key,field in [('hull_add','call_91' if mac else 'call_a0'),('armor_current','call_d9' if mac else 'call_fc'),
                          ('armor_max','call_e3' if mac else 'call_108'),('armor_add','call_ef' if mac else 'call_11a')]:match(key,target('update',field))
        require(target('hull_add','call_1e' if mac else 'call_10','b.w')==target('armor_add','call_24' if mac else 'call_10','b.w'))
        if not mac:
            helper=target('update','call_64','blx')
            require(helper==target('update','call_be','blx') and import_symbol(mach,helper)==b'___floatdisf')
        match('timers_zero',address(recharge['provenance']['clock_zero'])-(22 if mac else 8))
        table=address(player['provenance']['equipment_table']);raw=section_bytes(mach,table,120 if mac else 30,b'__text');require(raw is not None)
        entries=struct.unpack('<30i',raw[0]) if mac else raw[0]
        destination=table+entries[15]*(1 if mac else 2)
        require(sum(table+n*(1 if mac else 2)==destination for n in entries)==1)
        match('device_assignment',destination)
        match('item_id',target('device_assignment','call_c' if mac else 'call_6'))
        match('device_zero',address(player['provenance']['reset'])-(31 if mac else 40))
        factory=address(player['provenance']['factory']);size,spec=PLAYER_LAYOUTS[arch]['factory']
        raw=section_bytes(mach,factory,size,b'__text');require(raw is not None)
        blocks['factory']=template(spec).fullmatch(raw[0]);positions['factory']=factory;require(blocks['factory'] is not None)
        match('hull_source',target('factory','call_4' if mac else 'call_0'))
        match('stats_capacity',address(npc['provenance']['stats_entry'])+(173 if mac else 112))
        clone=address(loadout['provenance']['ship_clone'])
        match('ship_clone',branch_at(clone+(8 if mac else 6)))
        match('ship_ctor',target('ship_clone','call_5f' if mac else 'call_a6'))
        first=literal('update','ref_60' if mac else 'ref_34');second=literal('update','ref_a8')
        require(second==first+8)
        values=struct.unpack('<4f',read('periods',first,16,b'__const' if mac else b'__text'))
        require(values==(420.0,600.0,700.0,1000.0))
        spans=sorted((p['offset'],p['offset']+p['bytes']) for p in proof.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        return dict(VALUES,provenance=proof)
    except (KeyError,ValueError,TypeError,IndexError,OverflowError,struct.error):return {}


LAYOUTS = {'x86_64': {'update': [244,
                       '488d05 {ref_0:4} 488b38e8 {call_a:4} 4889c7e8 {call_12:4} '
                       '4189c74585ff0f88d1000000498b3ee8 {call_26:4} '
                       '85c00f8ec1000000498b8670010000488b8d48fbffff4801c84989867001000049018e78010000f3480f2ac04585ff0f94c00fb6c0488d0d '
                       '{ref_60:4} 0f2e0481762949c7867001000000000000498b3ee8 {call_7b:4} 89c3498b3ee8 '
                       '{call_85:4} 39c37d08498b3ee8 {call_91:4} f3490f2a86780100004585ff0f94c00fb6c0488d0d '
                       '{ref_a8:4} 0f2e0481763f49c7867801000000000000498b3ee8 {call_c3:4} 89c3498b3ee8 '
                       '{call_cd:4} 39c37c1e498b3ee8 {call_d9:4} 89c3498b3ee8 {call_e3:4} 39c37d08498b3ee8 '
                       '{call_ef:4}'],
            'device_getter': [9, '554889e58b474c5dc3'],
            'hull_max': [12, '554889e58b878c0000005dc3'],
            'hull_add': [35, '554889e58b87800000008b8f8c000000ffc039c80f4fc18987800000005de9 {call_1e:4}'],
            'armor_current': [12, '554889e58b87940000005dc3'],
            'armor_max': [12, '554889e58b87980000005dc3'],
            'armor_add': [41,
                          '554889e58b879400000083c0028987940000008b8f9800000039c87e06898f940000005de9 '
                          '{call_24:4}'],
            'timers_zero': [22, '48c783780100000000000048c7837001000000000000'],
            'device_assignment': [35,
                                  '498b4770488b40084a8b3c30e8 {call_c:4} 83f84b0f95c00fb6c04189474ce9 '
                                  '{call_1e:4}'],
            'device_zero': [8, '41c7474cffffffff'],
            'item_id': [8, '554889e58b075dc3'],
            'hull_source': [59,
                            '554889e5488b978800000031c04885d27424448b0231c04585c0741a488b520831c031f68d4828833cb2000f44c148ffc64439c672ee0347045dc3'],
            'stats_capacity': [12, '89938000000089938c000000'],
            'ship_clone': [148,
                           '554889e541574156534883ec184989ffbf98000000e8 {call_15:4} '
                           '4989c6498b7f688b470c412b8790000000458b4714418b4f0c418b37418b5704f3410f104718448b0f8b5f048b7f0889442410897c2408891c24f30f5905 '
                           '{ref_54:4} 4c89f7e8 {call_5f:4} '
                           '498b87880000004885c07424833800741f31db488b40088b34984c89f7e8 {call_81:4} '
                           '48ffc3498b87880000003b1872e3'],
            'ship_ctor': [240,
                          '554889e541574156415541545350f30f1145d44589ce4889fb8933895304894b0cc74310000000004489431444894308bf10000000e8 '
                          '{call_35:4} f30f1045d4f30f5e05 {ref_3f:4} '
                          '448b6d208b4d18448b7d1048894368448930448978048948084489680cf30f114318bf18000000e8 '
                          '{call_6e:4} 4989c4bf08000000e8 {call_7b:4} '
                          '498944240841c74424100100000048c7000000000041c70424000000004c8963704501f744037d184501ef4489ff4c89e6e8 '
                          '{call_b1:4} '
                          '48c7437800000000c743640000000048c7838800000000000000c78390000000000000004889df4883c4085b415c415d415e415f5de9 '
                          '{call_eb:4}']},
 'armv7': {'update': [286,
                      '08980068ec94 {call_6:4} ec94 {call_c:4} 0446002cc0f28380dbf800004ff0ff31ec91 '
                      '{call_22:4} 012879db00ee906b06980bf58e75 {ref_34:4} '
                      '65f98f2a002c08bf0432b24620ee900b01ee906b92ed008a21ee900b72efe00810ee900b30ee901b45f98f0a '
                      '{call_64:4} 40ec100bb4eec80af1ee10fa16dd00204ff0ff3628606860dbf80000ec96 {call_86:4} '
                      '0546dbf80000ec96 {call_92:4} 854204dadbf80000ec96 {call_a0:4} 0bf59275 {ref_a8:4} '
                      'd5e90023002c08bf0430194690ed008a1046 {call_be:4} '
                      '40ec100b5646b4eec80af1ee10fa25dd0020286068604ff0ff35dbf80000ec95 {call_e2:4} '
                      '0446dbf80000ec95 {call_ee:4} 844213dbdbf80000ec95 {call_fc:4} 0446dbf80000ec95 '
                      '{call_108:4} 844206dadbf800004ff0ff31ec91 {call_11a:4}'],
           'device_getter': [4, 'c06c7047'],
           'hull_max': [6, 'd0f884007047'],
           'hull_add': [20, '816fd0f8842001319142b8bf0a468267 {call_10:4}'],
           'armor_current': [6, 'd0f88c007047'],
           'armor_max': [6, 'd0f890007047'],
           'armor_add': [20, 'd0e92323911c9942c8bf1946c0f88c10 {call_10:4}'],
           'timers_zero': [8, '04f5907000f98f8a'],
           'device_assignment': [26, 'e06e40688059 {call_6:4} 4b284ff0000018bf0120e06457e0e06e'],
           'device_zero': [28, '4ff0ff31002284ed04ab04464df2b07004f13c03c0f21f00e1647844'],
           'item_id': [4, '00687047'],
           'hull_source': [50,
                           '816f00291cbfd1f80090b9f1000f01d100210be0d1f804c0002200215cf822300132002b08bf28314a45f7d3406808447047'],
           'stats_capacity': [18, 'b2670396d7f80c90bd68c6f8842080e82802'],
           'ship_clone': [216,
                          'f0b503af2de9000dadf1400424f00f04a54604f9ed8204f9efc29cb0054680200995 {call_22:4} '
                          '4cf61201c0f21f010e900e9879440d90a86e096800f1040b02680c929be81009d5f800a068680b90e8680a9032486e6995ed068a7844ed6f1591304916900fa841f0010117977944cdf864d0189101211091 '
                          '{call_78:4} abeb0500 {ref_80:4} '
                          '5146049008ff100d0c980b9a0a9b8ded050acdf80c80029401900d98009620ef1001 {call_a6:4} '
                          '0998816f064600291cbf086800280ed000244ff0ff350e98496851f824101095 {call_ca:4} '
                          'b16f013408688442f3d3'],
           'ship_ctor': [212,
                         'f0b503af2de9000dadf1400424f00f04a54604f9ed8204f9efc290b00446b868 {ref_20:4} '
                         '4ff0000997ed072a04f10805019484e8060082ee008a85e8090260611020 {call_42:4} '
                         '07f10c052ecda06680e82e000c2084ed068a20ef1001 {call_5c:4} '
                         '4df67e01c0f21f01029079442a4809687844099129490a9003a841f001010b977944cdf834d00c9101210491 '
                         '{call_8c:4} 0420 {call_92:4} '
                         '02990123029a00255060029a9360056002983a69019c0560f868e16610447a691044ba691044 '
                         '{call_bc:4} 4ff0ff3025676566a567e56704902046 {call_d0:4}']}}
