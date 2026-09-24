"""Bounded declarations for fresh-opening smoke/fire ownership.

Instruction contexts identify supported layouts at import time. The result is
only parameters and file extents; no instructions enter a content pack.
"""
import math
import struct
from .ship_models import section_bytes
from .declaration_layouts import recognize


def extract_damage_particle_owners(mach, actors, staging):
    if mach.architecture not in LAYOUTS:return {}
    try:
        npc=actors['npc_initialization']
        if npc['world_initialization']['campaign_cursor']!=0 or len(actors['actors'])!=3:return {}
        if not npc.get('hull') or not npc.get('flight') or not npc.get('destruction'):return {}
        if not staging.get('escape'):return {}
        anchor=npc['provenance']['factory_entry']
        if anchor['bytes']!=4:return {}
        at=mach.text['address']+anchor['offset']-mach.slice_offset-mach.text['offset']
        layouts=[LAYOUTS[mach.architecture]]+([MAC_ALTERNATE] if mach.architecture=='x86_64' else [])
        proof=recognize(mach,anchor['offset'],[{k:v for k,v in row.items() if k!='hull_fraction'} for row in layouts])
        if not proof:return {}
        delta=LAYOUTS[mach.architecture]['hull_fraction'][0]
        if mach.architecture=='x86_64' and proof['npc_registration']['offset']==anchor['offset']+MAC_ALTERNATE['npc_registration'][0]:
            delta=MAC_ALTERNATE['hull_fraction'][0]
        section=b'__const' if mach.architecture=='x86_64' else b'__text'
        found=section_bytes(mach,at+delta,4,section)
        if found is None:return {}
        fraction=struct.unpack('<f',found[0])[0]
        if not math.isfinite(fraction) or not 0<fraction<1:return {}
        proof['hull_fraction']={'offset':found[1],'bytes':4}
        return {'scope':'fresh_opening_damage_emitters','npc_hull_fraction':fraction,
                'npc_suppressed_mode':9,'active_mode':1,'player_max_campaign_cursor':1,
                'npc_uses_detail_gate':mach.architecture=='x86_64',
                'initially_damaged':False,'provenance':proof}
    except (KeyError,TypeError,IndexError,ValueError,OverflowError,struct.error):return {}


LAYOUTS = {'x86_64': {'npc_registration': (530685,
                                 128,
                                 '488b7b10488b43784c8bb090000000e8b5a9ebff4c89f74889c6ba0f00000031c9e85781feff8983b4000000488b4b78488bb99000000089c631d2e8dd84feff488b7b10488b43784c8bb0a8000000e875a9ebff4c89f74889c6ba2a00000031c9e81781feff8983b8000000488b4b78488bb9a800000089c631d2e89d84feff'),
            'npc_initial_flag': (528759, 18, '41c684247f0100000041c684246402000000'),
            'npc_threshold': (539722,
                              351,
                              '498b7e08e807c7feff4189c4418a8664020000a801753c498b7e080f57c0f3410f2ac4f30f118580f5ffffe8ecc6feff0f57c0f30f2ac0f30f59058d240e000f2e8580f5ffff0f878e000000418a86640200004c89bd90f5ffffa8010f84fd000000498b7e080f57c0f3410f2ac4f30f118580f5ffffe8a1c6feff0f57c0f30f2ac0f30f590542240e00f30f108d80f5ffff0f2ec80f82c400000041c6866402000000418bb6b4000000498b4678488bb89000000031d2e81461feff418bb6b8000000498b4678488bb8a800000031d2e8fb60feffe9850000004c89bd90f5ffff488d053cce1b00f30f104028660fefc90f2ec176614c89f7e81a64f5ff418bb6b4000000498b4e78488bb99000000084c07523ba01000000e8b260feff418bb6b8000000498b4678488bb8a8000000ba01000000eb1b31d2e89260feff418bb6b8000000498b4678488bb8a800000031d2e87960feff41c6866402000001'),
            'hull_fraction': (1466646, 4, ''),
            'npc_release': (542362,
                            77,
                            '41c786bc0000000100000041f68664020000017438418bb6b4000000498b4678488bb890000000ba01000000e84f57feff418bb6b8000000498b4678488bb8a8000000ba01000000e83357feff'),
            'npc_holding': (543381,
                            75,
                            '41c786bc0000000900000041f68664020000010f8449190000418bb6b4000000498b4678488bb89000000031d2e85353feff418bb6b8000000498b4678488bb8a800000031d2e83a53feff'),
            'npc_breakup': (548294,
                            173,
                            '418b86600200004429e84189866002000085c04c89e60f8915060000498bbe70010000c785a8f6ffff00000000c785acf6ffff00000000c785b0f6ffff00000000488d95a8f6ffffe8df0becff418bb608020000498b4678488bb88800000031d2e8ee3ffeff660fefc0488d0537ad1b00f30f1048280f2ec87632418bb6b4000000498b4678488bb89000000031d2e8c03ffeff418bb6b8000000498b4678488bb8a800000031d2e8a73ffeff'),
            'player_registration': (481770,
                                    157,
                                    '488d0519b11c00488b38e8bb8d040083f8017e055b415e5dc3488b7b10488b43184c8bb090000000e88568ecff4c89f74889c6ba0f00000031c9e85140ffff89839c030000488b4b18488bb99000000089c631d2e8d743ffff488b7b10488b43184c8bb0a8000000e84568ecff4c89f74889c6ba2a00000031c9e81140ffff8983a0030000488b4b18488bb9a800000089c631d25b415e5de99343ffff'),
            'player_enable': (522652,
                              80,
                              '554889e553504889fb8bb39c03000085f679074883c4085b5dc3488b4318488bb890000000ba01000000e84fa4feff8bb3a0030000488b4318488bb8a8000000ba010000004883c4085b5de92ea4feff'),
            'restore_cue': (64447, 5, 'e8d8fd0600'),
            'relocation_reset': (63657, 28, '488bb8a8000000e839a80500498b4520488bb890000000e829a80500'),
            'world_smoke_update': (40359, 20, '498bbf900000004885ff74084c89f6e885fb0500'),
            'world_fire_update': (40472, 20, '498bbfa80000004885ff74084c89f6e814fb0500'),
            'npc_root_getter': (-802106, 13, '554889e5488d87ac0000005dc3'),
            'npc_root_capture': (-800338,
                                 45,
                                 '554889e553504889fb8b7314488b7b38e87fca1c004881c3ac0000004889df4889c64883c4085b5de9a7e81d00'),
            'player_root_getter': (-802148, 17, '554889e58b7714488b7f385de995d11c00')},
 'armv7': {'npc_registration': (475554,
                                84,
                                '406f6ff672faa068216d8d6f74f665f8014628460f2200236ff64df801460022e167206d806f6ff660faa068216dd1f8845074f652f8014628462a2200236ff63af801460022c4f88010206dd0f884006ff64bfa'),
           'npc_initial_flag': (473902,
                                70,
                                '00201599159a01f5a2715063159a82f83901159a159b159cc4f83c01159c84f82901159c84f82a01159c84f83a01159cc4f8f001159cc4f8d400159c84f82b01159c84f8f401'),
           'npc_threshold': (482212,
                             272,
                             'daf804004ff0ff340af5b676cdf8a048f0f70aff05469af8f40145ec305bbbff2086a0bbdaf80400cdf8a048f0f7fefe40ec300b9fed790afbff200600ff900db4eec08af1ee10fa1dd54ff0ff345046cdf8a04866f74eff0246daf85000daf87c10002a806f40d00022cdf8a0486df63bfddaf850000022daf88010d0f88400cdf8a0483fe09af8f401002840d0daf80400cdf8a048f0f7c9fe40ec300b9fed5f0afbff200600ff900db4eec08af1ee10fa2ddb00204ff0ff348af8f4010022daf85000daf87c10806fcdf8a0486df60bfddaf850000022daf88010d0f88400cdf8a0486df600fd12e00122cdf8a0486df6fafcdaf850000122daf88010d0f88400cdf8a0486df6effc01208af8f401'),
           'hull_fraction': (482752, 4, ''),
           'npc_release': (486122,
                           78,
                           '4ff00108fdf749fdb46ecdf8a058204616f0a9f901462046cdf8a05816f0a5f9c6f8848096f8f40188b1306d0122f16f806fcdf8a0586cf6b4fd306d0122d6f88010d0f88400cdf8a0586cf6aafd'),
           'npc_holding': (485720,
                           70,
                           '0920c8f8b442c8f8b842c8f8840098f8f401002801f02b83d8f850004ff0ff34d8f87c100022806fcdf8a0486cf682fed8f850000022d8f88010d0f88400cdf8a0486cf677fe'),
           'npc_breakup': (484568,
                           122,
                           'daf8f001a0eb0b00ddf8ccb0caf8f001b0f1ff3f01f36b854ff000084ff0ff35daf8200166aacdf89881cdf89c81cdf8a081cdf8a05836997df610fbdaf850000022daf89c11406fcdf8a0586df6b2f8daf850000022daf87c10806fcdf8a0586df6a8f8daf850000022daf88010d0f88400cdf8a0586df69df8'),
           'player_registration': (437712,
                                   108,
                                   '40f66040c0f2220078440068006846f047f90128c8bfb0bdd4e902018d6f7df63bfa014628460f22002378f62dfa01460022c4f8fc12e068806f78f63ffcd4e90201d1f884507df627fa014628462a22002378f619fa01460022c4f80013e068d0f88400bde8b04078f628bc'),
           'player_enable': (469144,
                             48,
                             '90b5044601afd4f8fc120029b8bf90bde0680122806f70f6edfee0680122d4f80013d0f88400bde8904070f6e3be00bf'),
           'restore_cue': (114570, 4, '56f085fc'),
           'relocation_reset': (113718,
                                34,
                                '0df50054d0f88400c4f82464c7f657fedaf814000df50054806fc4f82464c7f64efe'),
           'world_smoke_update': (43094, 12, 'a86f18b159465246d8f687fc'),
           'world_fire_update': (43158, 14, 'd5f8840018b159465246d8f666fc'),
           'npc_root_getter': (-1146244, 4, '84307047'),
           'npc_root_capture': (-1145116, 30, '90b5c26a00f18404c16801af1046d8f22df901462046bde89040e3f2b7bd'),
           'player_root_getter': (-1146264, 8, 'c168c06ad8f270bb')}}


# Independently verified complete alternate Mac compiler layout.
MAC_ALTERNATE = {'npc_registration': [531233,
                      128,
                      '488b7b10488b43784c8bb090000000e88990ebff4c89f74889c6ba0f00000031c9e84b81feff8983b4000000488b4b78488bb99000000089c631d2e8d184feff488b7b10488b43784c8bb0a8000000e84990ebff4c89f74889c6ba2a00000031c9e80b81feff8983b8000000488b4b78488bb9a800000089c631d2e89184feff'],
 'npc_initial_flag': [529307, 18, '41c684247f0100000041c684246402000000'],
 'npc_threshold': [540270,
                   351,
                   '498b7e08e8fbc6feff4189c4418a8664020000a801753c498b7e080f57c0f3410f2ac4f30f118580f5ffffe8e0c6feff0f57c0f30f2ac0f30f5905b1c00d000f2e8580f5ffff0f878e000000418a86640200004c89bd90f5ffffa8010f84fd000000498b7e080f57c0f3410f2ac4f30f118580f5ffffe895c6feff0f57c0f30f2ac0f30f590566c00d00f30f108d80f5ffff0f2ec80f82c400000041c6866402000000418bb6b4000000498b4678488bb89000000031d2e80861feff418bb6b8000000498b4678488bb8a800000031d2e8ef60feffe9850000004c89bd90f5ffff488d05f0731b00f30f104028660fefc90f2ec176614c89f7e8f661f5ff418bb6b4000000498b4e78488bb99000000084c07523ba01000000e8a660feff418bb6b8000000498b4678488bb8a8000000ba01000000eb1b31d2e88660feff418bb6b8000000498b4678488bb8a800000031d2e86d60feff41c6866402000001'],
 'npc_release': [542910,
                 77,
                 '41c786bc0000000100000041f68664020000017438418bb6b4000000498b4678488bb890000000ba01000000e84357feff418bb6b8000000498b4678488bb8a8000000ba01000000e82757feff'],
 'npc_holding': [543929,
                 75,
                 '41c786bc0000000900000041f68664020000010f8449190000418bb6b4000000498b4678488bb89000000031d2e84753feff418bb6b8000000498b4678488bb8a800000031d2e82e53feff'],
 'npc_breakup': [548842,
                 173,
                 '418b86600200004429e84189866002000085c04c89e60f8915060000498bbe70010000c785a8f6ffff00000000c785acf6ffff00000000c785b0f6ffff00000000488d95a8f6ffffe8bbf2ebff418bb608020000498b4678488bb88800000031d2e8e23ffeff660fefc0488d05eb521b00f30f1048280f2ec87632418bb6b4000000498b4678488bb89000000031d2e8b43ffeff418bb6b8000000498b4678488bb8a800000031d2e89b3ffeff'],
 'player_registration': [482306,
                         157,
                         '488d05d9561c00488b38e81b8e040083f8017e055b415e5dc3488b7b10488b43184c8bb090000000e8654fecff4c89f74889c6ba0f00000031c9e85140ffff89839c030000488b4b18488bb99000000089c631d2e8d743ffff488b7b10488b43184c8bb0a8000000e8254fecff4c89f74889c6ba2a00000031c9e81140ffff8983a0030000488b4b18488bb9a800000089c631d25b415e5de99343ffff'],
 'player_enable': [523200,
                   80,
                   '554889e553504889fb8bb39c03000085f679074883c4085b5dc3488b4318488bb890000000ba01000000e843a4feff8bb3a0030000488b4318488bb8a8000000ba010000004883c4085b5de922a4feff'],
 'restore_cue': [64447, 5, 'e8fcff0600'],
 'relocation_reset': [63657, 28, '488bb8a8000000e851aa0500498b4520488bb890000000e841aa0500'],
 'world_smoke_update': [40359, 20, '498bbf900000004885ff74084c89f6e89dfd0500'],
 'world_fire_update': [40472, 20, '498bbfa80000004885ff74084c89f6e82cfd0500'],
 'npc_root_getter': [-808002, 13, '554889e5488d87ac0000005dc3'],
 'npc_root_capture': [-806234,
                      45,
                      '554889e553504889fb8b7314488b7b38e8efd61c004881c3ac0000004889df4889c64883c4085b5de927e31d00'],
 'player_root_getter': [-808044, 17, '554889e58b7714488b7f385de905de1c00'],
 'hull_fraction': [1441630, 4, '']}
