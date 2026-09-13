"""Fresh opening world ordering and NPC weapon-effect declarations.

Original executable code is inspected statically and discarded. Only the fresh
source context is supported; these are not generic mission-construction rules.
"""
import copy
import struct
from .opening_loadout import template
from .opening_npc_weapons import LAYOUTS as WEAPON_LAYOUTS
from .opening_npc_guidance import LAYOUTS as GUIDANCE_LAYOUTS
from .npc_initialization import MAC_BASE_CALL, ARM_BASE_CALL

VALUES = {'world_type':3,'campaign_cursor':0,'initial_companions_empty':True,
          'absent_equipment_types':[33,39],'absent_hull_ids':[45,51],
          'weapon_item_sequence':[0,19],'weapon_effect_sequence':[14600,14605],
          'weapon_effect_capacity':4,'weapon_effect_random_bound':2,'zero_means_flipped':True}


def extract_opening_world_initialization(mach,actors,opening,scenery):
    import capstone
    arch=mach.architecture;mac=arch=='x86_64'
    if arch not in LAYOUTS:return {}
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    proof={};matched={}
    def require(value):
        if not value:raise ValueError('Unsupported opening world initialization')
    def address(span):
        o=span['offset']-mach.slice_offset
        rows=[s for s in mach.sections if s['offset']<=o and o+span['bytes']<=s['offset']+s['length']]
        require(len(rows)==1)
        return rows[0]['address']+o-rows[0]['offset']
    def read(key,at,size,section=b'__text'):
        rows=[s for s in mach.sections if s['segment']==b'__TEXT' and s['name']==section and s['address']<=at and at+size<=s['address']+s['length']]
        require(len(rows)==1);o=rows[0]['offset']+at-rows[0]['address'];raw=mach.data[o:o+size];require(len(raw)==size)
        proof[key]={'offset':o+mach.slice_offset,'bytes':size};return raw
    def target(key,field):
        row,at=matched[key]
        if mac:return at+row.end(field)+int.from_bytes(row[field],'little',signed=True)
        ins=list(decoder.disasm(row[field],at+row.start(field)))
        require(len(ins)==1 and ins[0].mnemonic in ['bl','blx','b.w'] and ins[0].operands[-1].type==capstone.arm.ARM_OP_IMM)
        return ins[0].operands[-1].imm
    try:
        initial=actors['npc_initialization'];weapon=initial['primary_weapon']
        require(initial['construction'] and initial['guidance'] and weapon['item_id']==19 and weapon['projectile_capacity']==4)
        require([r['hull_catalogue_id'] for r in actors['actors']]==[2,23,2] and [r['actor_kind'] for r in actors['actors']]==[8,8,8])
        require([r['actor_id'] for r in actors['actors']]==[0,1,2])
        require(opening['ship_id']==10 and opening['station_id']==78)
        main=weapon['provenance']['main'];at=address(main)
        row=template(WEAPON_LAYOUTS[arch]['main'][2]).fullmatch(read('weapon_main',at,main['bytes']));require(row is not None)
        matched['weapon_main']=(row,at)
        selection=initial['guidance']['provenance']['selection'];at=address(selection)
        row=template(GUIDANCE_LAYOUTS[arch]['selection'][3]).fullmatch(read('selection',at,selection['bytes']));require(row is not None)
        matched['selection']=(row,at)
        base_call=initial['provenance']['base_call'];at=address(base_call)
        row=template(MAC_BASE_CALL if mac else ARM_BASE_CALL).fullmatch(read('base_call',at,base_call['bytes']));require(row is not None)
        matched['base_call']=(row,at)
        code=mach.data[mach.text['offset']:mach.text['offset']+mach.text['length']]
        found=[r for r in template(LAYOUTS[arch]['before'][3]).finditer(code) if mac or r.start()%2==0]
        require(len(found)==1)
        bases={'world':mach.text['address']+found[0].start(),'loadout':address(opening['provenance']['declaration']),
               'weapon':address(main),'effect_setter':target('weapon_main','call_77' if mac else 'call_78'),
               'base_actor':target('base_call','base')}
        def match_layout(key):
            if key in matched:return
            base,delta,size,pattern=LAYOUTS[arch][key]
            if base not in bases:
                owner,field=LINKS[arch][base];match_layout(owner);bases[base]=target(owner,field)
            at=bases[base]+delta;row=template(pattern).fullmatch(read(key,at,size));require(row is not None);matched[key]=(row,at)
        for key in LAYOUTS[arch]:match_layout(key)
        require(target('before','call_37' if mac else 'call_30')+(206 if mac else 246)==address(scenery['provenance']['count']))
        require(target('after','call_4' if mac else 'call_2')+(2814 if mac else 168)==address(actors['provenance']['declaration']))
        require(target('after','call_86' if mac else 'call_102')+(2560 if mac else 1244)==bases['weapon'])
        require(target('station_gate','call_42' if mac else 'call_20')==address(scenery['provenance']['station_id']))
        require(target('effect_setter','call_158' if mac else 'call_166')==target('selection','call_33' if mac else 'call_3c'))
        for group in SAME_TARGETS[arch]:require(len({target(*name.split('.')) for name in group})==1)
        if mac:table=target('effect_setter','ref_3')
        else:
            row,at=matched['effect_setter'];parts=[]
            for name,op in [('models_low','movw'),('models_high','movt')]:
                ins=list(decoder.disasm(row[name],at+row.start(name)))
                require(len(ins)==1 and ins[0].mnemonic==op and ins[0].reg_name(ins[0].operands[0].reg)=='r1')
                parts.append(ins[0].operands[-1].imm)
            table=(parts[0]|parts[1]<<16)+at+14
        for index,item in enumerate(VALUES['weapon_item_sequence']):
            require(struct.unpack('<i',read('effect_model_'+str(item),table+item*4,4,b'__const'))[0]==VALUES['weapon_effect_sequence'][index])
        spans=sorted((s['offset'],s['offset']+s['bytes']) for s in proof.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        result=copy.deepcopy(VALUES);result['provenance']=proof;return result
    except (ValueError,KeyError,TypeError,IndexError,OverflowError,struct.error):return {}

LAYOUTS = {'x86_64': {'before': ['world',
                       0,
                       49,
                       '418b86d401000083f8010f85fd020000418b861401000083f804741583f81774104c89f7e8 '
                       '{call_37:4} 4c89f7e8 {call_45:4}'],
            'after': ['world',
                      408,
                      119,
                      '4c89f7e8 {call_4:4} 4c89f7e8 {call_12:4} '
                      '418b861401000083f817743683f804743183f8027514488d05 {ref_41:4} 488b38e8 {call_49:4} '
                      '83f82b74184c89f7e8 {call_62:4} 4c89f7e8 {call_70:4} 4c89f7e8 {call_78:4} 4c89f7e8 '
                      '{call_86:4} 4183be1401000003740b41c78614010000030000004c89f7e8 {call_115:4}'],
            'equipment33': ['pre_group',
                            64,
                            30,
                            '498b3ee8 {call_4:4} 4889c7be21000000e8 {call_17:4} 4885c00f84e3020000'],
            'station_gate': ['special',
                             16,
                             55,
                             '488d05 {ref_3:4} 488b38e8 {call_11:4} 84c00f85e6010000488d05 {ref_26:4} '
                             '488b38e8 {call_34:4} 4889c7e8 {call_42:4} 83f8700f85c6010000'],
            'cursor_gate': ['special', 525, 24, '488d05 {ref_3:4} 488b38e8 {call_11:4} 83f8550f8c37010000'],
            'equipment39': ['equipment_group',
                            18,
                            37,
                            '488d05 {ref_3:4} 488b38e8 {call_11:4} 4889c7be27000000e8 {call_24:4} '
                            '4885c00f843c010000'],
            'companion_gate': ['companions',
                               72,
                               24,
                               '488d05 {ref_3:4} 488b38e8 {call_11:4} 4885c00f847f030000'],
            'companion_getter': ['companion_getter', 0, 10, '554889e5488b47385dc3'],
            'companion_reset': ['loadout', -2073, 8, '49c7463800000000'],
            'effect_setter': ['effect_setter',
                              82,
                              238,
                              '488d0d {ref_3:4} '
                              '448b34994585f6418987a80000000f88e8000000418b5f10488d3c9d00000000e8 '
                              '{call_40:4} 498987680100004889dfe8 {call_55:4} 4531e4498987700100004c8d2d '
                              '{ref_72:4} 450fb7f6eb07418b5f1049ffc44139dc0f83a1000000bfe8000000e8 '
                              '{call_104:4} 4889c3498b55004889df4489f631c9e8 {call_124:4} '
                              '498b87680100008b4b1442890ca0488d05 {ref_145:4} 488b38be02000000e8 '
                              '{call_158:4} 498b8f7001000085c0420f940421498b8768010000428b34a0498b7d00e8 '
                              '{call_192:4} 4889c731f631d2e8 {call_204:4} 4885db0f8479ffffff4889dfe8 '
                              '{call_221:4} 4889dfe8 {call_229:4} e964ffffff'],
            'hull_gate': ['hull_group', 68, 25, '418b85b000000083f82d0f848000000083f8330f8516010000'],
            'base_flags': ['base_actor', 400, 20, 'c6435900c6435a00c6435e00c6435f00c6436000'],
            'base_secondary': ['base_actor', 470, 7, 'c6832401000000'],
            'secondary_getter': ['secondary_getter', 0, 13, '554889e58a872401000024015d'],
            'weapon_wrapper_call': ['weapon',
                                    1237,
                                    32,
                                    '4889c34889df31f64c89e24489f941b8112700004c8b7d984d89f9e8 {call_28:4}'],
            'weapon_wrapper': ['weapon_wrapper', 0, 10, '554889e55de9 {call_6:4}'],
            'weapon_effect_gate': ['weapon_inner', 462, 17, '418b86a000000083f819744383f80b751b'],
            'weapon_overrides': ['weapon',
                                 -1192,
                                 41,
                                 '498b7d00e8 {call_5:4} '
                                 '89458c488b4598488b8078010000488b40084a8b3c30f6475a010f84fd020000'],
            'weapon_overrides_tail': ['weapon',
                                      -386,
                                      345,
                                      '837d8c467538488b4598488b8078010000488b40084a8b3c30e8 {call_26:4} '
                                      '84c0751c4c8975a04c89e7beb7000000e8 {call_47:4} '
                                      '41bfd9370000e901010000488b4598488b8078010000488b40084a8b04308b88b000000083f9317539817d8c9100000075304c8975a041c78424a0000000280000004c89e7bed6000000e8 '
                                      '{call_126:4} '
                                      '41d1a424a400000041bfa0370000e9aa00000083f93175448b4d8c8d8963ffffff83f90177364c8975a041c78424a0000000000000004c89e7be07000000e8 '
                                      '{call_193:4} '
                                      '416b8424a40000000341898424a400000041bf6c1a0000eb614c8975a0f6405e01745748837d80007450488b7d80e8 '
                                      '{call_244:4} 89c34c89e789dee8 {call_256:4} 4863db488d05 {ref_266:4} '
                                      '488b00488b4008488b3cd8be02000000e8 {call_287:4} '
                                      '41898424a0000000488d05 {ref_302:4} '
                                      '448b3c9841c1a424a400000002418b9c24a000000083fb050f84f100000083fb280f85f4040000'],
            'weapon_extra': ['weapon',
                             414,
                             49,
                             'f6475e01488d1d {ref_7:4} '
                             '4989dd0f846001000048837d80000f84550100008b87b000000083c0d383f8030f8743010000'],
            'weapon_extra_hull': ['weapon',
                                  786,
                                  30,
                                  '83bfb0000000310f8529f5ffff8b458c0563ffffff83f8010f8718f5ffff'],
            'weapon_secondary': ['weapon',
                                 -1976,
                                 56,
                                 '488b4590ffc0488945904885ff448ba57cffffff7429e8 {call_23:4} '
                                 '3c017520498b8778010000488b40084a8b0430f64041010f85ac0c0000']},
 'armv7': {'before': ['world',
                      0,
                      42,
                      'd5f83441012c40f08f80d5f8c000042818bf172809d04ff0ff3428463094 {call_30:4} 28463094 '
                      '{call_38:4}'],
           'after': ['world',
                     440,
                     132,
                     '2846 {call_2:4} 07e04ff0ff3030902846 {call_16:4} c5f8c0604ff0ff3428463094 {call_32:4} '
                     'd5f8c000172818bf042818d0022808d1d8f800004ff0ff313091 {call_62:4} '
                     '2b280dd04ff0ff3628463096 {call_78:4} 28463096 {call_86:4} 28463096 {call_94:4} '
                     '28463094 {call_102:4} d5f8c0004ff0ff3403281cbf0320c5f8c00028463094 {call_128:4}'],
           'equipment33': ['pre_group',
                           72,
                           62,
                           '3068 {call_2:4} 2121 {call_8:4} '
                           '044645f2f430c0f22a00cc497844794400681d9017a81e91cc491f9741f00101cdf884d079442091 '
                           '{call_52:4} 002c00f05c81'],
           'station_gate': ['special',
                            92,
                            30,
                            '002c40f0e78030684ff0ff341094 {call_14:4} 1094 {call_20:4} 702840f0db80'],
           'cursor_gate': ['special', 560, 18, '30684ff0ff341094 {call_8:4} 5528c0f2a580'],
           'equipment39': ['equipment_group',
                           42,
                           62,
                           '0068 {call_2:4} 2721 {call_8:4} '
                           '044641f2ea60c0f229006949784479440068099003a80a9167490b9741f00101cdf834d079440c91 '
                           '{call_52:4} 002c00f09b80'],
           'companion_gate': ['companions', 116, 22, '30682494 {call_4:4} 00281cbfd5f8f000002800f06481'],
           'companion_getter': ['companion_getter', 0, 4, '406a7047'],
           'companion_reset': ['loadout', -1542, 4, '00206062'],
           'effect_setter': ['effect_setter',
                             134,
                             248,
                             '{models_low:4} {models_high:4} '
                             '7066794451f824100291002970dbb46804200895a4fb0001002918bf0121002918bf4ff0ff30 '
                             '{call_46:4} c6f80c0120460895 {call_58:4} '
                             'c6f81001002c58d048f25e000021c0f22c004ff0ff3278440468039448f28400c0f22c00784400680190c02005910892 '
                             '{call_110:4} 012106900698226808910299002389b2 {call_130:4} '
                             'ddf818804ff0ff340698049e059dc068d6f80c1141f825000221019800680894 {call_166:4} '
                             '00284ff0000008bf0120d6f810114855d6f80c11039851f8251000680894 {call_200:4} '
                             '002100220894 {call_210:4} 022008904046 {call_220:4} 0698 {call_226:4} '
                             '04984ff0ff320599039c013180688142b7d3'],
           'hull_gate': ['hull_group', 46, 6, 'b06f2d282bd1'],
           'hull_gate_tail': ['hull_group', 140, 4, '33283ad1'],
           'base_flags': ['base_actor',
                          290,
                          98,
                          '00204ff0ff32c0f22401c6f82480f064794486f86e0086f8210086f8710086f8380086f8390086f83a0086f83e0086f83f0086f840007264012286f8882086f83b0086f8480086f8cc0086f8640086f8650086f8660086f8d80086f8e80086f8f000'],
           'secondary_getter': ['secondary_getter', 0, 6, '90f8d8007047'],
           'weapon_wrapper_call': ['weapon',
                                   1342,
                                   26,
                                   '062128902898309142f211712a468de8020100215346 {call_22:4}'],
           'weapon_wrapper': ['weapon_wrapper',
                              0,
                              24,
                              '90b501af82b00446f86801902046 {call_14:4} 204602b090bd'],
           'weapon_effect_gate': ['weapon_inner',
                                  268,
                                  116,
                                  '0198c06d40f00201032901d1012103e00021082808bf012147f28252c0f22202029b7a44126883f84c10117899b118281edc0a2811dc082800f276800121814011f4857f70d0029a49f69a11c3f61971d1631164516419280cd00b2864d1029943f23330c3f63370c863086448645be0192859d1'],
           'weapon_overrides': ['weapon',
                                212,
                                34,
                                '189c2068cdf8c0b0 {call_8:4} 0646d8f8f8001b994068405890f83a10002900f06381'],
           'weapon_overrides_tail': ['weapon',
                                     956,
                                     90,
                                     '462e11d1d8f8f8001b9940684058cdf8c0b0 {call_18:4} 00bb2698b721cdf8c0b0 '
                                     '{call_32:4} '
                                     '43f2d97a072e16d1d8f8f8001b9940684058406a08280ed12698c6ef102f90ed180afbff000640ffb20dbbff200780ed180a20ef1001'],
           'weapon_mission': ['weapon',
                              1046,
                              130,
                              '2068cdf8c0b0 {call_6:4} 88b32068cdf8c0b0 {call_18:4} cdf8c0b0 {call_26:4} '
                              '012826d10d98149605682068cdf8c0b0 {call_46:4} '
                              '854237d10c980068032833dbd8f8f8001b9940684058cdf8c0b0 {call_76:4} '
                              '012828d1269890ed180afbff000640ff9e0dbbff200780ed180a20ef10011ae0d8f8f8001b9940684058816f312908bf912e'],
           'weapon_hull': ['weapon',
                           -582,
                           66,
                           '312915d1a6f19d01012911d81496002226982699ca650721cdf8c0b0 {call_28:4} '
                           '269841f66c2a016e01eb4101016668e390f83e00149600281cbf1298002800f06083'],
           'weapon_kind': ['weapon', 1212, 12, '2698c66d052e18bf282e34d1'],
           'weapon_extra': ['weapon', 1452, 12, '90f83e1000291cbf12990029'],
           'weapon_extra_branch': ['weapon', 1464, 4, '00f08280'],
           'weapon_extra_hull': ['weapon', 1728, 10, '169c816f312940f0ae80'],
           'weapon_secondary': ['weapon',
                                2086,
                                42,
                                '1799002801f10101179100f088803096 {call_16:4} '
                                '012840f08280daf8f8004068405990f82100002879d0']}}
LINKS = {'armv7': {'companion_getter': ['companion_gate', 'call_4'],
           'companions': ['after', 'call_94'],
           'equipment_group': ['after', 'call_78'],
           'pre_group': ['before', 'call_38'],
           'special': ['after', 'call_32'],
           'hull_group': ['after', 'call_86'],
           'secondary_getter': ['weapon_secondary', 'call_16'],
           'weapon_wrapper': ['weapon_wrapper_call', 'call_22'],
           'weapon_inner': ['weapon_wrapper', 'call_14']},
 'x86_64': {'companion_getter': ['companion_gate', 'call_11'],
            'companions': ['after', 'call_78'],
            'equipment_group': ['after', 'call_62'],
            'pre_group': ['before', 'call_45'],
            'special': ['after', 'call_12'],
            'hull_group': ['after', 'call_70'],
            'secondary_getter': ['weapon_secondary', 'call_23'],
            'weapon_wrapper': ['weapon_wrapper_call', 'call_28'],
            'weapon_inner': ['weapon_wrapper', 'call_6']}}
SAME_TARGETS = {'armv7': [['after.call_62', 'cursor_gate.call_8'],
           ['equipment33.call_2', 'equipment39.call_2'],
           ['equipment33.call_8', 'equipment39.call_8'],
           ['equipment33.call_52', 'equipment39.call_52'],
           ['effect_setter.call_46', 'effect_setter.call_58'],
           ['weapon_overrides.call_8', 'cursor_gate.call_8'],
           ['weapon_overrides_tail.call_18', 'weapon_secondary.call_16'],
           ['weapon_overrides_tail.call_32', 'weapon_main.call_78']],
 'x86_64': [['after.ref_41',
             'station_gate.ref_3',
             'station_gate.ref_26',
             'cursor_gate.ref_3',
             'equipment39.ref_3',
             'companion_gate.ref_3',
             'weapon_extra.ref_7'],
            ['after.call_49', 'cursor_gate.call_11', 'weapon_overrides.call_5'],
            ['equipment33.call_4', 'equipment39.call_11'],
            ['equipment33.call_17', 'equipment39.call_24'],
            ['effect_setter.call_40', 'effect_setter.call_55'],
            ['weapon_overrides_tail.call_26', 'weapon_secondary.call_23'],
            ['weapon_overrides_tail.call_47',
             'weapon_overrides_tail.call_126',
             'weapon_overrides_tail.call_193',
             'weapon_overrides_tail.call_256',
             'weapon_main.call_77']]}
