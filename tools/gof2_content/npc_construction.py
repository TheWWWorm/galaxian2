"""Bounded declarations for fresh opening NPC construction, never runtime code.

Spawn, route, generated cargo and preallocated breakup geometry share one stream.
The authored opening discards generated cargo after constructing each actor.
"""
import copy
import struct
from .opening_loadout import template
from .opening_npc_guidance import LAYOUTS as GUIDANCE_LAYOUTS

VALUES = {
    'spawn_origin':[-20000,-20000,-20000], 'spawn_bound':40000,
    'cargo_count_bound':3, 'cargo_attempts':100, 'chance_bound':100,
    'category_weights':[10,40,2,10,100], 'excluded_items':[164,175,217,218],
    'category_index':3, 'rank_index':7, 'chance_index':13,
    'price_low_index':15, 'price_high_index':17, 'maximum_rank':7,
    'commodity_category':4, 'quantity_minimum':1, 'quantity_bound':3,
    'commodity_quantity_bound':9, 'fallback_item_minimum':154, 'fallback_item_bound':10,
    'special_ship_ids':[37,38,40], 'special_equipment_type':18,
    'special_item':122, 'special_chance_maximum':9,
    'fragment_count_minimum':3, 'fragment_count_bound':7, 'fragment_resource':14292,
    'rotation_bound':360, 'rotation_divisor':180.0, 'rotation_multiplier':3.1415927410125732,
    'scale_minimum':50, 'scale_bound':50, 'scale_divisor':100.0,
    'opening_discards_cargo':True,
}


def extract_npc_construction(mach,actors,vehicle):
    import capstone
    arch=mach.architecture;mac=arch=='x86_64'
    if arch not in LAYOUTS:return {}
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    proof={};matched={}
    def require(value):
        if not value:raise ValueError('Unsupported NPC construction declaration')
    def address(span):
        offset=span['offset']-mach.slice_offset
        rows=[s for s in mach.sections if s['offset']<=offset and offset+span['bytes']<=s['offset']+s['length']]
        require(len(rows)==1)
        return rows[0]['address']+offset-rows[0]['offset']
    def read(key,at,size,section=b'__text'):
        rows=[s for s in mach.sections if s['segment']==b'__TEXT' and s['name']==section and s['address']<=at and at+size<=s['address']+s['length']]
        require(len(rows)==1);offset=rows[0]['offset']+at-rows[0]['address']
        raw=mach.data[offset:offset+size];require(len(raw)==size)
        proof[key]={'offset':offset+mach.slice_offset,'bytes':size};return raw
    def target(key,field):
        row,at=matched[key]
        if mac:return at+row.end(field)+int.from_bytes(row[field],'little',signed=True)
        instructions=list(decoder.disasm(row[field],at+row.start(field)))
        require(len(instructions)==1 and instructions[0].mnemonic in ['bl','blx','b.w'])
        require(instructions[0].operands[-1].type==capstone.arm.ARM_OP_IMM)
        return instructions[0].operands[-1].imm
    try:
        initial=actors['npc_initialization']
        require(initial['routes'] and initial['holding'])
        require([a['actor_kind'] for a in actors['actors']]==[8,8,8] and [a['hull_catalogue_id'] for a in actors['actors']]==[2,23,2])
        bases={'factory':address(initial['provenance']['factory_entry']),
               'constructor':address(initial['flight']['provenance']['bank'])-(2272 if mac else 1794),
               'item_layout':address(vehicle['provenance']['item_type_layout'])}
        for key,(base,delta,size,pattern) in LAYOUTS[arch].items():
            if base not in bases:bases[base]=target(*LINKS[arch][base])
            at=bases[base]+delta;row=template(pattern).fullmatch(read(key,at,size));require(row is not None)
            matched[key]=(row,at)
        wrapper=target('tail','call_101' if mac else 'call_94')
        row=template('554889e55de9 {inner:4}' if mac else '90b5044601af {inner:4} 204690bd').fullmatch(read('effect_wrapper',wrapper,10 if mac else 14))
        require(row is not None);matched['effect_wrapper']=(row,wrapper)
        constructor=target('effect_wrapper','inner')
        require(read('effect_zero',constructor+(121 if mac else 76),8 if mac else 22)==bytes.fromhex('49c7461800000000' if mac else '002300686a65ab65ea652a666a666a626b60ab60eb60'))
        # Tie every constructor draw to the already recognized shared generator.
        selection=initial['guidance']['provenance']['selection'];at=address(selection)
        row=template(GUIDANCE_LAYOUTS[arch]['selection'][3]).fullmatch(read('selection',at,selection['bytes']));require(row is not None)
        matched['selection']=(row,at)
        require(target('selection','call_33' if mac else 'call_3c')==target('spawn','call_72' if mac else 'call_86'))
        # The source equipment dispatch maps type 18 to the special-drop flag.
        table=vehicle['provenance']['equipment_table'];at=address(table)
        raw=read('equipment_table',at,120 if mac else 30)
        case=at+(struct.unpack_from('<i',raw,18*4)[0] if mac else raw[18]*2)
        require(read('special_equipment_case',case,5 if mac else 4)==bytes.fromhex('41c6475001' if mac else '84f85080'))
        require(target('item_arrays','call_18' if mac else 'call_14')==bases['item_layout'])
        for fields in SAME_TARGETS[arch]:require(len({target(*f.split('.')) for f in fields})==1)
        if mac:
            weights=target('cargo','ref_300')
            for name,field,value in [('rotation_divisor','ref_244',180.0),('rotation_multiplier','ref_276',VALUES['rotation_multiplier']),('scale_divisor','ref_329',100.0)]:
                require(struct.unpack('<f',read(name,target('fragments',field),4,b'__const'))[0]==value)
        else:
            row,at=matched['cargo'];parts=[]
            for name,op in [('weights_low','movw'),('weights_high','movt')]:
                ins=list(decoder.disasm(row[name],at+row.start(name)))
                require(len(ins)==1 and ins[0].mnemonic==op and ins[0].reg_name(ins[0].operands[0].reg)=='r1')
                parts.append(ins[0].operands[-1].imm)
            weights=(parts[0]|parts[1]<<16)+at+278
            # PC-relative VFP literals in the independently recovered fragment setup.
            raw,at=matched['fragments']
            for name,delta,value in [('rotation_divisor',64,180.0),('rotation_multiplier',72,VALUES['rotation_multiplier']),('scale_divisor',78,100.0)]:
                ins=list(decoder.disasm(raw[0][delta:delta+4],at+delta));require(len(ins)==1 and ins[0].mnemonic=='vldr')
                require(ins[0].reg_name(ins[0].operands[-1].mem.base)=='pc')
                literal=((ins[0].address+4)&~3)+ins[0].operands[-1].mem.disp
                require(struct.unpack('<f',read(name,literal,4))[0]==value)
        require(list(struct.unpack('<5i',read('category_weights',weights,20,b'__const')))==VALUES['category_weights'])
        # The authored opening clears the generated cargo after the factory.
        opening=address(actors['provenance']['declaration'])
        if not mac:require(read('cargo_zero',opening+94,4)==bytes.fromhex('4ff0000b'))
        require(read('cargo_discard',opening+(272 if mac else 240),8 if mac else 4)==bytes.fromhex('48c7407000000000' if mac else 'c1f84cb0'))
        spans=sorted((s['offset'],s['offset']+s['bytes']) for s in proof.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        result=copy.deepcopy(VALUES);result['provenance']=proof;return result
    except (ValueError,KeyError,TypeError,IndexError,OverflowError,struct.error):return {}

LAYOUTS = {'x86_64': {'spawn': ['factory',
                      55,
                      111,
                      'b9e0b1ffff4885dbb8e0b1ffffbae0b1ffff741bb8e0b1ffff8b937801000001c28b8b7401000001c10383700100008955d4894dd08945cc488d1d '
                      '{ref_59:4} 488b3bbe409c0000e8 {call_72:4} 4189c6488b3bbe409c0000e8 {call_88:4} '
                      '4189c7488b3bbe409c0000e8 {call_104:4} 4189c5'],
            'tail': ['constructor',
                     1988,
                     121,
                     '4889dfbeffffffffbaffffffffe8 {call_14:4} 49894424704885db74104889dfe8 {call_32:4} '
                     '4889dfe8 {call_40:4} 488d05 {ref_47:4} 488b38e8 {call_55:4} '
                     'b9a086010084c0b850c300000f45c14189842478010000bf78000000e8 {call_88:4} '
                     '4889c34889df31f6e8 {call_101:4} 49899c24700100004889dfe8 {call_117:4}'],
            'cargo': ['cargo',
                      183,
                      723,
                      '488d05 {ref_3:4} 488b00488945c8488d05 {ref_17:4} 488b38be03000000e8 {call_30:4} '
                      '4189c64585f67525488d05 {ref_45:4} 488b38be03000000e8 {call_58:4} '
                      '41be010000004531e485c00f8484020000bf18000000e8 {call_85:4} 4989c44c8965b0bf04000000e8 '
                      '{call_102:4} '
                      '498944240841c744241001000000c7000000000041c70424000000004501f64489f74c89e6e8 '
                      '{call_144:4} 41833c24000f84d0010000488d05 {ref_162:4} '
                      '4c8b2831db4531ff48895db84530e4c745d4ffffffff31c04189c6488d1d {ref_196:4} '
                      '4488e024018b4dd4ffc1894dd483f9630f8ff700000084c00f851d010000488b45c88b30488b3be8 '
                      '{call_240:4} 4c63f0498b45084a8b3cf0e8 {call_256:4} 4189c7498b45084a8b3cf0e8 '
                      '{call_272:4} 4885c075af488b3bbe64000000e8 {call_290:4} 4963cf488d15 {ref_300:4} '
                      '3b048a7d93488b3bbe64000000e8 {call_318:4} '
                      '448865c04589fc4d89ef4989dd89c3488b45c8488b40084a8b3cf0e8 {call_350:4} '
                      '39c34c89eb4d89fd4589e7448a65c00f8d51ffffff498b45084a8b3cf0e8 {call_384:4} '
                      '85c00f8e3cffffff418d865cffffff83f836771448b90108000000006000480fa3c10f821cffffff4183ff047416498b45084a8b3cf0e8 '
                      '{call_443:4} 83f8070f8f00ffffff41b401e9f8feffffe918feffff84c0752a488b3bbe0a000000e8 '
                      '{call_482:4} '
                      '059a0000004c8b65b0498b4c24084889da488b5db8890499488b3aeb204c8b65b0498b442408488b4db8448934884889d84889cb488b384183ff047523be09000000e8 '
                      '{call_553:4} ffc04889d94883c901498b54240889048a41bf04000000eb1bbe03000000e8 '
                      '{call_588:4} ffc04889d94883c901498b54240889048a4883c302413b1c240f823ffeffff488d05 '
                      '{ref_626:4} 488b38e8 {call_634:4} 4889c7e8 {call_642:4} 84c07449488d05 {ref_653:4} '
                      '488b38e8 {call_661:4} 4889c7be7a000000ba01000000e8 {call_679:4} 84c07524488d05 '
                      '{ref_690:4} 488b38be64000000e8 {call_703:4} 83f8097f0b498b442408c7007a000000'],
            'category': ['category', 0, 10, '554889e58b47045dc390'],
            'rank': ['rank', 0, 10, '554889e58b470c5dc390'],
            'price': ['price', 0, 10, '554889e58b47185dc390'],
            'chance': ['chance', 0, 10, '554889e58b471c5dc390'],
            'requirements': ['requirements', 0, 10, '554889e5488b47285dc3'],
            'item_layout': ['item_layout',
                            0,
                            140,
                            '554889e5488b47384885c0747d488b48088b4904890f488b48088b490c894f04488b48088b4914894f08488b48088b491c894f0c488b48088b4934894f1c488b48088b493c894f20488b50088b5244895724488b70088b7624897710488b40088b402c89471429ca89d0c1e81f01d0d1f801c8894718c647500048c747480000000048c74740000000005dc3'],
            'item_arrays': ['item_layout', -44, 22, '554889e5488977284889573048894f385de9 {call_18:4}'],
            'fragments': ['fragments',
                          82,
                          364,
                          '4c8d25 {ref_3:4} 498b3c24be07000000e8 {call_17:4} 8d7803498b7618e8 {call_29:4} '
                          '4531ed498b4618443b280f8350010000bfe8000000e8 {call_55:4} 4889c34c8d3d {ref_65:4} '
                          '498b174889dfbed437000031c9e8 {call_83:4} '
                          '498b4618488b40084a891ce8498b4618488b40084a8b04e88b7014498b3fe8 {call_118:4} '
                          '4889c7be0100000031d2e8 {call_133:4} 498b4618488b40084a8b04e88b7014498b3fe8 '
                          '{call_156:4} '
                          'c7800001000000401c46498b4618488b40084a8b04e8488945d0498b3c24be68010000e8 '
                          '{call_196:4} 4d89f74189c6498b3c24be68010000e8 {call_216:4} '
                          '89c3498b3c24be68010000e8 {call_232:4} f30f2ad0f30f101d {ref_244:4} '
                          'f30f5ed3f30f2acbf30f5ecbf3410f2ac64d89fef30f5ec3f30f101d {ref_276:4} '
                          'f30f59c3f30f59cbf30f59d3488b7dd0e8 {call_297:4} 498b3c24be32000000e8 {call_311:4} '
                          '83c0320f57d2f30f2ad0f30f5e15 {ref_329:4} 498b4618488b40084a8b3ce80f28c20f28cae8 '
                          '{call_352:4} 49ffc5e9b8feffff'],
            'fragment_gate': ['fragments',
                              0,
                              31,
                              '554889e54157415641554154534883ec184989fe49837e18000f85b4010000'],
            'predicate': ['predicate',
                          0,
                          42,
                          '554889e5b001f6475001751c8b0f4883f9287712b00148ba0000000060010000480fa3ca720230c05dc3']},
 'armv7': {'spawn': ['factory',
                     104,
                     150,
                     'b868002810d0d0f8201144f62063d0f82421d0f82801a1eb030aa2eb030b1295c01a0f940c9008e04bf2e01b1295cff6ff7b0f94cdf830b0da464bf6ce104ff0ff34c0f2280049f640417844d0f80080d8f800003094 '
                     '{call_86:4} 0546d8f8000049f640413094 {call_102:4} 0646d8f8000049f640413094 '
                     '{call_118:4} ddf838800aeb0502d8f8001030940b920beb06020a920c9a10440990'],
           'tail': ['constructor',
                    1576,
                    114,
                    '18981c211b914ff0ff314ff0ff32 {call_14:4} 1899159ad0641d201b900846 {call_30:4} 1898 '
                    '{call_36:4} 10981e2100681b91 {call_48:4} '
                    '15994cf2503200281cbf48f2a062c0f201021f20c1f824211b906820 {call_80:4} '
                    '2021199019981b910021 {call_94:4} 19981599c1f8200121211b91 {call_110:4}'],
           'cargo': ['cargo',
                     190,
                     570,
                     '44f20c004ff0ff38c0f22d000321784405682868cdf82080 {call_24:4} 48b928680321cdf82080 '
                     '{call_38:4} 002800f00381012003900c200194cdf808a00495cdf82080 {call_66:4} '
                     '0690022008900420 {call_78:4} 06990123069a5060069a936000220260069c039822604000 '
                     '{call_106:4} '
                     'ddf808b02068002800f0ac8001980024d0f80080cdf80c801ae006980299406840f821400c460498006809e00698042d0299406840f821400c460498006802d14ff0ff357de04ff0ff31089103217ae04ff0ff3a029404984ff0ff36dbf8001000680896 '
                     '{call_210:4} 0446d8f8040050f824000896 {call_226:4} 0546d8f8040050f8240008964ff0ff36 '
                     '{call_246:4} 002844d10498642100680896 {call_262:4} {weights_low:4} {weights_high:4} '
                     '794451f82510884235da04984ff0ff3864210068cdf82080 {call_298:4} '
                     '0646dbf8040050f82400cdf82080 {call_316:4} ddf80c8086421fdad8f804004ff0ff3150f824000891 '
                     '{call_342:4} '
                     '012814dba4f1d900022810d3a42c18bfaf2c0cd0042d8ad0d8f804004ff0ff3150f824000891 '
                     '{call_384:4} 072888dd0af1010abaf1630f98db049e4ff0ff350a2130680895 {call_414:4} '
                     '06999a30029c496841f82400306808950921 {call_436:4} '
                     '069944f0010201300234496841f82200069800688442fff476af049c43f6f250c0f22d00ddf8188078444ff0ff35066830680895 '
                     '{call_492:4} 0895 {call_498:4} 01281fd1ddf8188030680895 {call_514:4} 7a2101220895 '
                     '{call_524:4} 98b9ddf818804ff0ff31206808916421 {call_544:4} '
                     '092808dcddf818807a2106984068016001e04ff00008'],
           'category': ['category', 0, 4, '40687047'],
           'rank': ['rank', 0, 4, 'c0687047'],
           'price': ['price', 0, 4, '80697047'],
           'chance': ['chance', 0, 4, 'c0697047'],
           'requirements': ['requirements', 0, 4, '806a7047'],
           'item_layout': ['item_layout',
                           0,
                           84,
                           '016b002908bf70474968c0ef50004a680260ca6842604a698260ca69c2604a6bc261ca6b02624b6c4362d1f82490c0f81090c96a4161991a01ebd17102eb6101816100f1340141f98f0a002180f84410704700bf'],
           'item_arrays': ['item_layout', 84, 22, '90b5044604f1280901af89e80e00 {call_14:4} 204690bd'],
           'fragments': ['fragments',
                         114,
                         398,
                         '48f26a23c0f239037b449660002606600598039c1a680660e1604ff0ff311068029208910721 '
                         '{call_38:4} e1680330 {call_46:4} '
                         'e0680068002800f0a98048f2f2109fed668ac0f239009fed659a78449fed64aa4ff0ff35d0f800b0cdf804b0c02004960895 '
                         '{call_100:4} 022106900698dbf80020089143f2d4710023 {call_122:4} '
                         '06984ff0ff35ddf80ca0049eddf804b0daf80c10496841f82600daf80c00406850f82610dbf80000c9680895 '
                         '{call_170:4} 012100220895 {call_180:4} daf80c00406850f82610dbf80000c9680895 '
                         '{call_202:4} 44f20001029cc4f21c61c0f8e010daf80c004168206851f826804ff4b4710895 '
                         '{call_238:4} 40ec300b20684ff4b4710895bbff20b6 {call_258:4} '
                         '216840ec1c0b089508464ff4b471 {call_276:4} '
                         '40ec300b4046bbff0c060895bbff20168bee082a80ee080a81ee081a02ff192d00ff190d01ff191d12ee101a10ee102a11ee103a '
                         '{call_332:4} 206832210895 {call_342:4} '
                         '323040ec300bdaf80c00bbff2006406880ee0a0a50f82600089510ee101a0a460b46 {call_380:4} '
                         'daf80c00013600688642fff468af'],
           'fragment_gate': ['fragments',
                             28,
                             52,
                             '039048f25022c0f2390288497a44c468794410680d9007a80e9188490f9741f00101cdf844d079441091 '
                             '{call_42:4} 002c40f0d880'],
           'predicate': ['predicate',
                         0,
                         40,
                         '90f8501000291cbf0120704700682538032884bf0020704700f00f000b2121fa00f000f001007047']}}
LINKS = {'armv7': {'cargo': ['tail', 'call_14'],
           'category': ['cargo', 'call_226'],
           'chance': ['cargo', 'call_316'],
           'fragments': ['tail', 'call_110'],
           'predicate': ['cargo', 'call_498'],
           'price': ['cargo', 'call_342'],
           'rank': ['cargo', 'call_384'],
           'requirements': ['cargo', 'call_246']},
 'x86_64': {'cargo': ['tail', 'call_14'],
            'category': ['cargo', 'call_256'],
            'chance': ['cargo', 'call_350'],
            'fragments': ['tail', 'call_117'],
            'predicate': ['cargo', 'call_642'],
            'price': ['cargo', 'call_384'],
            'rank': ['cargo', 'call_443'],
            'requirements': ['cargo', 'call_272']}}
SAME_TARGETS = {'armv7': [['spawn.call_86',
            'spawn.call_102',
            'spawn.call_118',
            'cargo.call_24',
            'cargo.call_38',
            'cargo.call_210',
            'cargo.call_262',
            'cargo.call_298',
            'cargo.call_414',
            'cargo.call_436',
            'cargo.call_544',
            'fragments.call_38',
            'fragments.call_238',
            'fragments.call_258',
            'fragments.call_276',
            'fragments.call_342'],
           ['tail.call_80', 'cargo.call_66', 'fragments.call_100'],
           ['cargo.call_492', 'cargo.call_514'],
           ['fragments.call_170', 'fragments.call_202']],
 'x86_64': [['spawn.ref_59',
             'cargo.ref_17',
             'cargo.ref_45',
             'cargo.ref_196',
             'cargo.ref_690',
             'fragments.ref_3'],
            ['spawn.call_72',
             'spawn.call_88',
             'spawn.call_104',
             'cargo.call_30',
             'cargo.call_58',
             'cargo.call_240',
             'cargo.call_290',
             'cargo.call_318',
             'cargo.call_482',
             'cargo.call_553',
             'cargo.call_588',
             'cargo.call_703',
             'fragments.call_17',
             'fragments.call_196',
             'fragments.call_216',
             'fragments.call_232',
             'fragments.call_311'],
            ['tail.ref_47', 'cargo.ref_626', 'cargo.ref_653'],
            ['tail.call_88', 'cargo.call_85', 'fragments.call_55'],
            ['cargo.ref_3', 'cargo.ref_162'],
            ['cargo.call_634', 'cargo.call_661'],
            ['fragments.call_118', 'fragments.call_156']]}
