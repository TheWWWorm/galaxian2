"""Recognize bounded fresh-opening NPC control declarations, never runtime code."""
import copy
import struct
from .opening_loadout import template

LAYOUTS = {'x86_64': {'tuning': ('constructor',
                       1371,
                       127,
                       '41c784240c0200000000004041c7842410020000f6fff93b41c784241402000000000040488db550ffffff41c7842418020000dc05000041c784247801000050c3000041c784241c0200000500000041c74424540000000041c684248d0100000041c78424900100000000000041c684247d0100000041c684247e01000000'),
            'speed_seed': ('constructor',
                           1772,
                           55,
                           '41c64424680141c684248d01000001f3410f10842414020000f3410f11842450020000f3410f1084240c020000f3410f11842458020000'),
            'hull_seed': ('constructor',
                          2118,
                          39,
                          '498b7c2408e8 {call_5:4} 418984244002000041c78424440200000000000041c684244802000000'),
            'selection': ('update',
                          2095,
                          119,
                          '4181be20020000891300000f8cfe0200004489ad80f5ffff30c041f6867d01000001751a488d05 '
                          '{ref_24:4} 488b38be64000000e8 {call_33:4} '
                          '83f8140f9cc04188867d01000041c7862002000000000000488d05 {ref_50:4} 488b38be64000000e8 '
                          '{call_5f:4} 83f81d0f8f3d01000041833f020f8233010000'),
            'boost_damage': ('update',
                             10661,
                             123,
                             '418b86400200004439e07e6f4429e041038644020000418986440200004589a640020000f30f2ac0f30f118580f5ffff498b7e08e8 '
                             '{call_34:4} 0f57c0f30f2ac0f30f108d80f5fffff30f5ec8f30f590d {ref_4c:4} 0f2e0d '
                             '{ref_54:4} 761e41c786440200000000000041c786280200001027000041c6864802000001'),
            'boost_start': ('update',
                            10784,
                            135,
                            '4181be28020000891300007c7a41f6865c02000001757041c786280200000000000041f6864802000001751d488d05 '
                            '{ref_2c:4} 488b38be64000000e8 {call_3b:4} 413b861c0200007d3e488d05 {ref_49:4} '
                            '488b38beb80b0000e8 {call_58:4} '
                            '05881300004189862c02000041c6865c0200000141c786540200000000b04041c786580200006666a63f'),
            'boost_response': ('update',
                               10919,
                               202,
                               '41f6865c020000010f84bc000000418b8628020000413b862c0200007f0bf3410f108654020000eb3741c786280200000000000041c6864802000000f3410f108614020000f3410f118654020000f3410f108e0c020000f3410f118e58020000660fefc90f2ec17661f3410f108e500200000f2ec10f97c00fb6c0488d0d '
                               '{ref_7b:4} f30f590c81f3410f118e50020000f3410f1096140200000f2e0d {ref_99:4} '
                               '73050f2ed17623f3410f1186500200000f2ec2750a7a0841c6865c0200000041c7865402000000000000'),
            'near': ('update',
                     11151,
                     62,
                     'b9401f0000f6406d017433498b7e78e8 {call_f:4} b9401f00004885c07420498b7e78e8 {call_22:4} '
                     '4889c7e8 {call_2a:4} bae02e000084c0b9401f00000f45ca'),
            'fire': ('update',
                     11635,
                     146,
                     'f3410f1086cc010000f3410f5c4648f30f100d {ref_f:4} 0f2ec80f86490100000f2e05 {ref_20:4} '
                     '0f863c010000f3410f1086d0010000f3410f5c464cf30f100d {ref_3c:4} 0f2ec80f861c0100000f2e05 '
                     '{ref_4d:4} 0f860f010000f3410f1086d4010000f3410f5c4650f30f100d {ref_69:4} '
                     '0f2ec80f86ef0000000f2e05 {ref_7a:4} 0f86e200000041f64641010f84a3000000'),
            'hull_level': ('factory',
                           166,
                           46,
                           'bb2c010000488d05 {ref_5:4} 488b38e8 {call_f:4} 83f8147f15488d05 {ref_19:4} 488b38e8 '
                           '{call_23:4} 6bd80e83c314'),
            'hull_difficulty': ('factory',
                                442,
                                37,
                                'f30f2ac3488d05 {ref_4:4} f30f10482cf30f580d {ref_10:4} '
                                'f30f59c8f30f58c8f3440f2cf1'),
            'membership': ('membership',
                           0,
                           37,
                           '488b4008488b3cd84c39f70f849e0000008b45c83947440f95c00a45c03c010f858a000000'),
            'player_first': ('membership',
                             512,
                             33,
                             '498b876801000031db4885c07413488b4db8488b4908488b00488901bb01000000')},
 'armv7': {'tuning': ('constructor',
                      1134,
                      132,
                      '15984ff0ff314ff6f672c0ef5000c3f6f93297ed030ac0f82c1120eff0811598c0f830111598c0f834114ff080411598c0f8a0111598c0f8a4211598c0f8a81140f2dc511598c0f8ac114cf250311598c0f8241105211598c0f8b01100201599159a01f5a2715063159a82f83901159a159b159cc4f83c01159c84f82901159c84f82a01'),
           'speed_seed': ('constructor',
                          1378,
                          38,
                          '159801231599159a82f84830159a82f83931159ad2f8a821c1f8e0211599d1f8a011c0f8e811'),
           'hull_seed': ('constructor',
                         1700,
                         30,
                         '159840681b91 {call_6:4} 1599c1f8d00100211598c0f8d411159880f8d811'),
           'selection': ('update',
                         2026,
                         132,
                         '41f28931caf84401daf8b4018842c0f2c4809af829010025cdf8ccb000284ff0000012d146f6be104ff0ff31c0f22100784400680068cdf8a0186421 '
                         '{call_3c:4} '
                         '14284ff00000b8bf0120cdf8d48046f69411c0f221018af829017944caf8b451d1f800b04ff0ff31dbf80000cdf8a0186421 '
                         '{call_72:4} 1d2800f3118120680228c0f00d81'),
           'boost_damage': ('update',
                            6712,
                            102,
                            'daf8d001a8422edddaf8d411401bcaf8d0514ff0ff320144caf8d411daf8040041ec181bcdf8a028 '
                            '{call_28:4} 40ec300b {ref_30:4} bbff0806bbff201680ee010a {ref_40:4} '
                            '00ff110db4eec20af1ee10fa09dd0020caf8d40142f21070caf8bc0101208af8d801'),
           'boost_start': ('update',
                           6814,
                           130,
                           'daf8bc0141f2893188423adb9af8ec01b8bb0020caf8bc019af8d80188b945f210704ff0ff31c0f22100784400680068cdf8a0186421 '
                           '{call_36:4} daf8b01188421fda45f2ec604ff0ff31c0f22100784400680068cdf8a01840f6b831 '
                           '{call_5c:4} 41f288310844caf8c001012046f266618af8ec010020c3f6a671c4f2b000cae97901'),
           'boost_return': ('update',
                            6944,
                            54,
                            '9af8ec01002800f06884dae96f01884240f32f840020caf8bc018af8d8019aed6a0a8aed790adaf8a001caf8e80120ef100100f020bc'),
           'boost_response': ('update',
                              9106,
                              104,
                              '9aed790ab5eec00af1ee10fa2cdd9aed781a {rates:4} '
                              '81ef163fb4eec10af1ee10fa20ef1001c8bf043090ed002a01ff121d8aed781ab4eec31a9aed6a2af1ee10fa04dab4eec21af1ee10fa0cd5b4eec20a8aed780af1ee10fa04bf00208af8ec010020caf8e401'),
           'near': ('update',
                    9210,
                    86,
                    'daf84401002800f00f829af82811002940f00a8290f86900002800f0c581daf850004ff0ff35cdf8a058 '
                    '{call_2a:4} 4ff4fa54002800f0ba81daf85000cdf8a058 {call_40:4} cdf8a058 {call_48:4} '
                    '002818bf42f6e064aae1'),
           'fire': ('update',
                    11374,
                    128,
                    '9aed0a1a9aed582a {ref_8:4} 22ef011db4eec01af1ee10fa40f1b180 {ref_1c:4} '
                    'b4eec21af1ee10fa40f3a9809aed0b1a9aed593a23ef011db4eec01af1ee10fa40f19d80b4eec21af1ee10fa40f397809aed0c1a9aed5a3a23ef011db4eec01af1ee10fa40f18b80b4eec21af1ee10fa40f385809af821105d465646002944d0'),
           'hull_level': ('factory',
                          254,
                          36,
                          '0846 {call_2:4} 142802dd4ff4967509e0d8f800003094 {call_16:4} c0ebc000142101eb4005'),
           'hull_difficulty': ('factory',
                               490,
                               44,
                               'c6ff102f784445ec305bfbff2006baf19a0f006890ed0b0a40ef222d40ffb22d40efa20dbbff200710ee105a'),
           'membership': ('membership', 0, 30, '406850f82500984250d0416a099a91424ff0000118bf0121089a114346d0'),
           'player_first': ('membership',
                            -360,
                            30,
                            'd6f8f0004ff0ff3a002806d000684ff0010b0d994968086001e04ff0000b')}}

LITERALS = {'x86_64': {'boost_damage.ref_4c': (None, 100.0),
            'boost_damage.ref_54': (None, 40.0),
            'boost_response.ref_7b': (None, [0.949999988079071, 1.0499999523162842]),
            'boost_response.ref_99': (None, 5.5),
            'fire.ref_f': (None, 35000.0),
            'fire.ref_20': (None, -35000.0),
            'fire.ref_3c': (None, 35000.0),
            'fire.ref_4d': (None, -35000.0),
            'fire.ref_69': (None, 35000.0),
            'fire.ref_7a': (None, -35000.0),
            'hull_difficulty.ref_10': (None, -0.5)},
 'armv7': {'boost_damage.ref_30': ('s4', 40.0),
           'boost_damage.ref_40': ('s2', 100.0),
           'boost_response.rates': ('r0', [0.949999988079071, 1.0499999523162842]),
           'fire.ref_8': ('s0', 35000.0),
           'fire.ref_1c': ('s4', -35000.0)}}

# These immediate declarations are recognized by the bounded layouts above.
# Later mission/cursor, companion, hull-family and level branches are excluded.
VALUES = {'actor_kind':8,'target_kind':'player','selection_period_ms':5000,
          'straight_roll_bound':100,'straight_chance':20,'selection_roll_bound':100,
          'cruise_speed':2.0,'boost_period_ms':5000,'boost_chance':5,'boost_roll_bound':100,'damage_boost_elapsed_ms':10000,
          'boost_duration_base_ms':5000,'boost_duration_bound_ms':3000,
          'boost_speed':5.5,'speed_decrease':0.949999988079071,'speed_increase':1.0499999523162842,
          'damage_percent_scale':100.0,'boost_damage_percent':40.0,
          'close_half_extent':8000,'special_close_half_extent':12000,
          'fire_half_extent':35000.0,'fire_alignment':struct.unpack('<f',bytes.fromhex('f6fff93b'))[0],
          'fresh_hull_base':34,'difficulty_offset':-0.5}


def extract_opening_npc_guidance(mach, actors):
    import capstone
    mac=mach.architecture=='x86_64'
    if mach.architecture not in LAYOUTS:return {}
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    proof={}
    def require(ok):
        if not ok:raise ValueError('Unsupported fresh NPC control declaration')
    def address(span):
        offset=span['offset']-mach.slice_offset
        matches=[s for s in mach.sections if s['offset']<=offset and offset+span['bytes']<=s['offset']+s['length']]
        require(len(matches)==1)
        return matches[0]['address']+offset-matches[0]['offset']
    def read(key,at,size,segment=b'__TEXT',section=b'__text'):
        matches=[s for s in mach.sections if s['segment']==segment and s['name']==section and s['address']<=at and at+size<=s['address']+s['length']]
        require(len(matches)==1)
        offset=matches[0]['offset']+at-matches[0]['address']
        raw=mach.data[offset:offset+size];require(len(raw)==size)
        span={'offset':offset+mach.slice_offset,'bytes':size}
        if span not in proof.values():proof[key]=span
        return raw
    try:
        initial=actors['npc_initialization'];flight=initial['flight'];weapon=initial['primary_weapon']
        require(flight and weapon and weapon['provenance']['fresh_level'])
        require([r['actor_id'] for r in actors['actors']]==[0,1,2])
        require([r['actor_kind'] for r in actors['actors']]==[8,8,8])
        require([r['hull_catalogue_id'] for r in actors['actors']]==[2,23,2])
        update_at=address(flight['provenance']['virtual_update'])
        pointer=int.from_bytes(read('virtual_update',update_at,8 if mac else 4,b'__DATA',b'__const'),'little')
        if not mac:require(pointer&1==1)
        bases={'constructor':address(flight['provenance']['bank'])-(2272 if mac else 1794),
               'factory':address(initial['provenance']['factory_entry']),
               'update':pointer if mac else pointer&~1}
        layout=LAYOUTS[mach.architecture]
        code=mach.data[mach.text['offset']:mach.text['offset']+mach.text['length']]
        found=[m for m in template(layout['membership'][3]).finditer(code) if mac or m.start()%2==0]
        require(len(found)==1)
        bases['membership']=mach.text['address']+found[0].start()
        rows={};positions={}
        for key,(base,delta,size,pattern) in layout.items():
            at=bases[base]+delta;positions[key]=at
            row=template(pattern).fullmatch(read(key,at,size));require(row is not None);rows[key]=row
        literal_index=0
        for name,(register,expected) in LITERALS[mach.architecture].items():
            block,field=name.split('.');row=rows[block];at=positions[block]
            if mac:location=at+row.end(field)+int.from_bytes(row[field],'little',signed=True)
            else:
                instructions=list(decoder.disasm(row[field],at+row.start(field)))
                require(len(instructions)==1 and instructions[0].size==4)
                i=instructions[0];require(i.reg_name(i.operands[0].reg)==register)
                if field=='rates':
                    require(i.mnemonic=='subw' and i.reg_name(i.operands[1].reg)=='pc' and i.operands[-1].type==capstone.arm.ARM_OP_IMM)
                    location=i.address+4-i.operands[-1].imm
                else:
                    require(i.mnemonic=='vldr' and i.operands[-1].type==capstone.arm.ARM_OP_MEM and i.reg_name(i.operands[-1].mem.base)=='pc')
                    location=((i.address+4)&~3)+i.operands[-1].mem.disp
            values=expected if isinstance(expected,list) else [expected]
            raw=read('literal_'+str(literal_index),location,4*len(values),section=b'__const' if mac else b'__text')
            require(list(struct.unpack('<'+'f'*len(values),raw))==values)
            if 'literal_'+str(literal_index) in proof:literal_index+=1
        spans=sorted((s['offset'],s['offset']+s['bytes']) for s in proof.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        result=copy.deepcopy(VALUES);result['provenance']=proof
        return result
    except (ValueError,KeyError,TypeError,IndexError,OverflowError,struct.error):return {}
