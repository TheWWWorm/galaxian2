"""Static fresh-opening death timing and effect declarations.

Recognizers cover the two supported compiler layouts. They are import-time
validation only; packs contain constants and extents, never executable bytes.
Unknown layouts remain unsupported instead of receiving guessed death behavior.
"""
import copy
from .opening_npc_guidance import LAYOUTS as GUIDANCE_LAYOUTS
from .ship_models import section_bytes

VALUES = {
    'actor_kind':8, 'dying_mode':3, 'explosion_mode':4,
    'delay_base_ms':1500, 'delay_bound_ms':1500,
    'axis_bound':200, 'axis_offset':-100, 'spin_scale':0.05000000074505806,
    'rotation_order':'XYZ', 'rotation_per_update':True,
    'death_sound':20, 'breakup_sound_base':18, 'breakup_sound_bound':2,
    'drift_bound':50, 'drift_scale':0.009999999776482582, 'drift_base':50.0,
    'effect_type':0, 'model_ids':[16821,16820], 'fragment_model_id':14292,
    'cargo_absent':True, 'retire_on_following_update':True,
    'trigger_uses_pre_motion_position':True, 'discard_delay_overshoot':True,
}


def extract_npc_destruction_audio(mach, actors):
    """Bind audible death triggers separately from the older motion capability."""
    arch=mach.architecture
    if arch not in AUDIO_LAYOUTS:return {}
    try:
        npc=actors['npc_initialization']
        death=npc['destruction']
        if not death:return {}
        source=npc['guidance']['provenance']['selection']
        _,relative,size,_=GUIDANCE_LAYOUTS[arch]['selection']
        if source['bytes']!=size:return {}
        update=mach.text['address']+source['offset']-mach.slice_offset-mach.text['offset']-relative
        proof={}
        for key,(delta,size,pattern) in AUDIO_LAYOUTS[arch].items():
            found=section_bytes(mach,update+delta,size,b'__text')
            if found is None or found[0]!=bytes.fromhex(pattern):return {}
            proof[key]={'offset':found[1],'bytes':size}
        return {'initial_source_id':death['death_sound'],
                'breakup_source_ids':list(range(death['breakup_sound_base'],death['breakup_sound_base']+death['breakup_sound_bound'])),
                'position':'pre_motion','instance':'cached_event','provenance':proof}
    except (KeyError,ValueError,TypeError,IndexError,OverflowError):return {}


AUDIO_LAYOUTS = {
    'x86_64': {
        'initial': [8316,121,'4c8d8518fcfffff30f1005994f0e00498b46788b704c488bb888000000c78518fcffff00000000c7851cfcffff00000000c78520fcffff00000000488b9d90f5ffff4889da31c9e8305ffeff488d050dcf1b0031c9488d1540c91b00f6420f014889da480f44d1488b38be1400000031c90f57c0e88d71ecff'],
        'breakup_entry': [-1292588,10,'554889e54156534889f3'],
        'breakup_call': [-1292371,17,'4889da31c90f57c05b415e5de9c44a0000'],
    },
    'armv7': {
        'initial': [6248,98,'daf850000023cbf680730df5c062c16b406fcdf80086cdf80486cdf80886cdf8a068369ccde90023002322466df6fcfb45f616100023c0f2210045f67c11c0f2210178447944006809680068ca7b1421cdf8a068cdf80080002a18bf224681f665fa'],
        'breakup_entry': [-1576620,8,'b0b502af81b00c46'],
        'breakup_call': [-1576342,10,'22464ff0000303f090fd'],
    },
}


def extract_npc_destruction(mach, actors):
    arch=mach.architecture
    if arch not in LAYOUTS:return {}
    try:
        npc=actors['npc_initialization']
        if npc['guidance']['actor_kind']!=VALUES['actor_kind'] or not npc['construction']:return {}
        source=npc['guidance']['provenance']['selection']
        _,relative,size,_=GUIDANCE_LAYOUTS[arch]['selection']
        if source['bytes']!=size:return {}
        update=mach.text['address']+source['offset']-mach.slice_offset-mach.text['offset']-relative
        proof={}
        for key,(delta,size,pattern) in LAYOUTS[arch].items():
            # Relative positions bind each guard/callee to this verified actor
            # update. Renaming or repackaging either game does not affect this.
            found=section_bytes(mach,update+delta,size,b'__const' if key in ['spin_constant','drift_multiplier','drift_base'] and arch=='x86_64' else b'__text')
            if found is None or found[0]!=bytes.fromhex(pattern):return {}
            proof[key]={'offset':found[1],'bytes':size}
        value=copy.deepcopy(VALUES);value['provenance']=proof
        return value
    except (KeyError,ValueError,TypeError,IndexError,OverflowError):return {}


# Bounded compiler-layout signatures; these never enter runtime data.
LAYOUTS = {'x86_64': {'early_retirement': [40,
                                 61,
                                 '4183bebc000000047533498bbe70010000e82e4fecff84c0752341f6466801740d4181be2001000061ea00007c0f4c89f731f6e8cc79f5ffe93c420000'],
            'death_guard': [7251, 28, '4585e40f8fe1050000418b86bc00000083c0fd83f8020f82ce050000'],
            'initial_delay': [8207,
                              109,
                              '41c686a30000000041c786bc000000030000004c8d2dbbc91b00498b7d00bedc050000e845a9070005dc05000041898660020000498b7e10e87c80ebff498dbefc010000488db528fcfffff30f118d30fcfffff30f118528fcffff660f70c001f30f11852cfcffffe860b40600'],
            'initial_spin': [8437,
                             196,
                             '498b7d00bec8000000e879a807004c8dbdf8fbffff83c09c0f57c0f30f2ac0f30f11856cf5ffff498b7d00bec8000000e852a8070089c3498b7d00bec8000000e842a80700f30f10856cf5fffff30f1185f8fbffff83c39c0f57c0f30f2ac3f30f1185fcfbffff83c09c0f57c0f30f2ac0f30f118500fcffff4c89ffe826be0600498d9ef0010000488db508fcfffff30f118d10fcfffff30f118508fcffff660f70c001f30f11850cfcffff4889dfe833b30600f30f100517900e004889dfe823b40600'],
            'tumble': [15113,
                       436,
                       '4989d441c6868e0100000041c6864d01000000c78558f7ffff0000803f48c78564f7ffff0000000048c7855cf7ffff00000000c7856cf7ffff0000803f48c78578f7ffff0000000048c78570f7ffff00000000488dbd18f7ffff488db558f7ffffc78580f7ffff0000803fc78584f7ffff00000000c78588f7ffff0000803fc7858cf7ffff0000803fc78590f7ffff0000803ff3410f1096f8010000f3410f1086f0010000f3410f108ef4010000e8406809004585ed7e30498b5e104889dfe87965ebff4c8dbdd8f6ffff488d9558f7ffff4c89ff4889c6e8765909004889df4c89fee86765ebff498b5e10498dbefc0100000f57c0f3410f2ac5e8639d0600f30f118dc0f6fffff30f1185b8f6ffff660f70c001f30f1185bcf6ffff488dbdb8f6fffff3410f108650020000e8319d0600488db5c8f6fffff30f118dd0f6fffff30f1185c8f6ffff660f70c001f30f1185ccf6ffff4889dfe8dd69ebff498b7e10e8e86bebff418b86600200004429e84189866002000085c04c89e60f8915060000498bbe70010000c785a8f6ffff00000000c785acf6ffff00000000c785b0f6ffff00000000488d95a8f6ffffe8df0becff'],
            'breakup_draws': [15645,
                              255,
                              '498b5e084c8d25bcac1b00498b3c24be32000000e8468c07000f57c0f30f2ac0f30f59059f320e00f30f58053b330e004889dfe823a5feff498b3c24bec8000000e8198c07004c8dbd88f6ffff83c09c0f57c0f30f2ac0f30f118590f5ffff498b3c24bec8000000e8f28b070089c3498b3c24bec8000000e8e28b0700f30f108590f5fffff30f118588f6ffff83c39c0f57c0f30f2ac3f30f11858cf6ffff83c09c0f57c0f30f2ac0f30f118590f6ffff4c89ffe8c6a10600498dbee4010000488db598f6fffff30f118da0f6fffff30f118598f6ffff660f70c001f30f11859cf6ffffe8d696060041c786bc0000000400000041c7866002000000000000'],
            'explosion_mode': [16020, 34, '418b86600200004401e84189866002000085c07e0d41c686a300000000e954010000'],
            'cleanup': [16963,
                        75,
                        '498bbe70010000e81d0decff84c0754e41f6861801000001741241f6869100000001750841c68690000000014181be2001000061ea00007c0a4c89f731f6e8a637f5ff41c6864d01000001'],
            'cargo_predicate': [-687786,
                                46,
                                '554889e5488b4f7030c04885c9741d8b1131f6eb044883c60230c039d6730d488b7908b001837cb704007ee95dc3'],
            'sound_choice': [-1292354,
                             79,
                             '8b078d48fe83f904724585c07573488d0509a82f004c8b30488d0507a22f00488b38be02000000e892811b00488d0d27a22f008a510f31c9f6c201480f44d985c00f95c00fb6f083ce124c89f7eba0'],
            'type_zero_models': [-1295321,
                                 122,
                                 'bfe8000000e82df421004889c3488d0589ad2f00488b104889dfbeb541000031c9e81360ffff49891c24bfe8000000e803f421004889c3488d055fad2f00488b104889dfbeb441000031c9e8e95fffff8b7314498b3c24e89b63ffff4885db0f84640100004889dfe8f662ffff4889dfe8b6f32100e94f010000'],
            'effect_update': [-1291224,
                              538,
                              '554889e54157415641554154534883ec384989d64189f74989fc41f6442430010f84e4010000488d056f9d2f00488b38498b4424088b7014e8572c1c004d63ff4889c74c89fe31d2e8a7ad1a00498b4424088b701c83feff741c488d053b9d2f00488b38e82b2c1c004889c74c89fe31d2e87ead1a00498b4424104885c0741f8b7014488d05129d2f00488b38e8022c1c004889c74c89fe31d2e855ad1a00498b4424184885c0743b833800743631db4c8d2de59c2f00488b4008488b04d88b7014498b7d00e8c92b1c004889c74c89fe31d2e81cad1a0048ffc3498b4424183b1872d34d85f60f84f100000041833c24010f87e6000000498b7c2408e88453fffff30f114dc0f30f1145b8660f70c001f30f1145bc4c8d2d7f9c2f00498b5d004889dfe85b311c004889df89c6e8812d1c004889c7e809521d00488d7db8488d75a8f30f114db0f30f1145a8660f70c001f30f1145ace8d88a1a00488d7dc8f30f114dd0f30f1145c8660f70c001f30f1145cce80b931a00f30f1145a4498b7d00498b4424088b7014e8052b1c008b80300100003dd00700007f42f30f1005d8f52100f30f1055a4f30f5dd0f30f5ed0f30f2ac8f30f5e0dc3f52100f30f1005e7f12100f30f58c8f30f5cc2f30f59c14c89f7be32000000e8e24018004d037c24284d897c24284d3b7c24207e1b4c89e7e87bf4ffff4d85f6740e4c89f7660fefc031f6e8b64018004883c4385b415c415d415e415f5dc390'],
            'retire': [-689620, 18, '554889e5488b7f08400fb6f65de9e2740900'],
            'active_setter': [-69856, 14, '554889e54088b7c80000005dc390'],
            'spin_constant': [963016, 4, 'cdcc4c3d'],
            'drift_multiplier': [946148, 4, '0ad7233c'],
            'drift_base': [946312, 4, '00004842']},
 'armv7': {'early_retirement': [114,
                                60,
                                '042c1bd1daf820014ff0ff31cdf8a0187ff6a7fb90b99af8480028b1daf8d4004ef66121884209db4ff0ff300021cdf8a008504667f755fe03f038bb'],
           'death_guard': [5132, 18, '002d00f3e382daf8840003380228c0f0dd82'],
           'initial_delay': [6164,
                             84,
                             '45f6b4104ff00008c0f221008af86f8078444ff0ff3640f2dc5105680320caf884002868cdf8a06844f130ff00f2dc50caf8f001daf808100df20c64cdf8a068204672f67df80af5c8702146cdf8a0683df1d8fd'],
           'initial_spin': [6346,
                            150,
                            '2868c821cdf8a06844f1e5fe29686438cdf8a06840ec300b0846c821bbff208644f1d9fe29686438cdf8a06840ec300b0846c821bbff209644f1cdfe64380df580680df2f4540df5bd6140ec300b88ed7a8abbff20060df58068204688ed7b9a0df5806888ed7c0acdf8a06820ef10013ef12df80af5c2752146cdf8a06828463df165fd4cf6cd412846c3f64c51cdf8a0683df1b8fd'],
           'tumble': [7008,
                      268,
                      '8da9c0ef50000b1d00204ff07e528af83a018af8fd0044468d924ff0ff3843f98f0a01f11803929243f98f0a979298907ea899929a929b92dae961239aed630acdf8ccb0cdf8a0888ded000a20ef100156f10efe2646012c14dbdaf80840cdf8a088204671f6fcfe6fad8daa0146cdf8a088284656f1d4f820462946cdf8a08871f6f2feb34669ad4bec30bb0af5c871bbff20062846daf80840cdf8a08810ee102a3df175fddaf8e0216cae2946cdf8a08830463df16cfd20463146cdf8a08872f648f8daf80800cdf8a08872f606f9daf8f001a0eb0b00ddf8ccb0caf8f001b0f1ff3f01f36b854ff000084ff0ff35daf8200166aacdf89881cdf89c81cdf8a081cdf8a05836997df610fb'],
           'breakup_draws': [7338,
                             192,
                             '45f220503221c0f22100daf80440784406683068cdf8a05844f1edfc40ec300b9fed470afbff20069fed461a2046cdf8a05840ff900d00ef810d10ee101af0f73cfa3068c821cdf8a05844f1d4fc31686438cdf8a05840ec300b0846c821bbff208644f1c8fc31686438cdf8a05840ec300b0846c821bbff209644f1bcfc643863ac60a940ec300b61a8bbff200600ed018a80ed009a80ed010a2046cdf8a05820ef10013df123fe0af5bc702146cdf8a0583df15cfb0420caf88400caf8f081'],
           'explosion_mode': [7624, 24, 'daf8f0014044caf8f0010128c0f23c8300208af86f00a4e3'],
           'cleanup': [10066,
                       80,
                       'daf820014ff0ff31cdf8a0187df639f8002840f0db879af8cc0030b19af86500002804bf01208af86400daf8d4004ef66121884207db4ff0ff300021cdf8a008504665f7defa01208af8fd0000f0bebf'],
           'cargo_predicate': [-621716,
                               40,
                               'c16c00291cbf086800280bd049680022043151f82230012ba4bf0120704702328242f6d300207047'],
           'sound_choice': [-1576468,
                            78,
                            '002841d147f6c070c0f2390047f6d671c0f239017844794400680968056808680221c7f247fa48f20a010028c0f23901284679440968ca7b4ff0000100914ff0130108bf1221002a08bf144617e0'],
           'type_zero_models': [-1579526,
                                128,
                                '4ff0ff3001951490c0200df344ec48f69231c0f23901029079440968009102980a680121149144f2b5110023f5f7c1f80298019948604ff0ff301490c0200df32aec0390039800990a680221149144f2b4110023f5f7adf8039c4ff0ff32019840680399c9681492f5f739f9032014902046f5f72cf903980df3feeb019e87e1'],
           'effect_update': [-1575644,
                             424,
                             'f0b503af2de9000d8ab00546934695f820000e46002800f0bf8047f65c40c0f2390069687844d0f80080c968d8f80000ccf2e6fd4feae67a314652460023c1f26ffb68684169b1f1ff3f08d0d8f80000ccf2d6fd314652460023c1f261fba86848b1c168d8f80000ccf2cafd314652460023c1f255fbe86800281cbf0168002912d00024406850f82410d8f80000c968ccf2b6fd314652460023c1f241fbe868013401688c42edd3bbf1000f53d02868012850d8696804a8f4f7acf9cdf800b0d8f800b05846cdf22ff801465846ccf289fe0df1040b01465846d8f2cbfe07ac04a95a46ddf800b02046c0f21ff82046c0f22efa69680446d8f80000c968ccf27ffdd0f80c01b0f5fa6f24dc40ec300b9fed232abbff20169fed224a44ec104b5846c7ef100f322280ee023a81ee041ab4eec20af1ee10fa20ef833d41ef200d80ef104048bfb0ee434a04ff300d10ee101ac8f103fea869e96980194ff0000641eb0a01c5e906012a696b6990424ff0000098bf01209942d8bf012608bf064656b92846fff7f8fabbf1000f04d0584600210022c8f1e2fd0ab0bde8000df0bd0060ea460000fac4'],
           'retire': [-623276, 8, '40688af015be00bf'],
           'active_setter': [-54908, 8, '80f8c010704700bf'],
           'drift_multiplier': [7656, 4, '0ad7233c'],
           'drift_base': [7660, 4, '00004842']}}
