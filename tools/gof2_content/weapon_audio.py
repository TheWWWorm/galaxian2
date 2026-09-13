"""Read per-edition weapon sound bindings and ordinary firing declarations.

Static compiler-layout recognition only. The runtime receives tables, parameters
and provenance; original instructions never enter a content pack.
"""
import copy
import struct
from .ship_models import section_bytes

VALUES = {
    'player_sound_limit': 2, 'npc_sound_limit': 1, 'initial_enabled': True,
    'disabled_world_type': 2, 'price_low_index': 15, 'price_high_index': 17,
    'sort': 'descending_midpoint_price', 'enabled_index': 'sorted_copy_index',
    'duplicates': 'first_item_id', 'position': 'firing_owner',
    'instance': 'cached_event', 'requires_successful_launch': True,
    'player_pitch': 'nonnegative_one_minus_interval_multiplier', 'npc_pitch': 0.0,
    'continuous_kinds': [2, 3, 8], 'npc_default_event_id': 61,
}
NPC_EVENTS = [52, 55, 54, 53, 61, 61, 61, 61, 61, 62, 2276]


def extract_weapon_audio(mach, weapons, actors, staging):
    arch = mach.architecture
    if arch not in LAYOUTS:
        return {}
    try:
        npc = actors['npc_initialization']
        construction = npc['construction']
        if (not weapons or not staging['player_flight'] or
                npc['world_initialization']['world_type'] == VALUES['disabled_world_type'] or
                construction['price_low_index'] != VALUES['price_low_index'] or
                construction['price_high_index'] != VALUES['price_high_index']):
            return {}
        origin = staging['provenance']['initial']['offset']
        address = mach.text['address'] + origin - mach.slice_offset - mach.text['offset']
        proof = {}
        for key, (delta, size, pattern) in LAYOUTS[arch].items():
            found = section_bytes(mach, address + delta, size, b'__text')
            if found is None or found[0] != bytes.fromhex(pattern):
                return {}
            proof[key] = {'offset': found[1], 'bytes': size}
        for key, expected in [('price_layout', construction['provenance']['item_layout']),
                              ('price_getter', construction['provenance']['price']),
                              ('interval_getter', weapons['provenance']['interval_getter'])]:
            if proof[key] != expected:
                return {}
        # Both layouts index this complete 233-row catalogue table. A missing
        # entry stays -1. Edition tables are read independently, never replaced.
        table_delta = 1464783 if arch == 'x86_64' else 2351530
        found = section_bytes(mach, address + table_delta, 233 * 4, b'__const')
        if found is None:
            return {}
        ids = list(struct.unpack('<233i', found[0]))
        if any(x < -1 or x > 19999 for x in ids):
            return {}
        proof['player_table'] = {'offset': found[1], 'bytes': 233 * 4}
        npc_events = list(NPC_EVENTS)
        if arch == 'armv7':
            found = section_bytes(mach, address + 2352474, 44, b'__const')
            if found is None:
                return {}
            npc_events = list(struct.unpack('<11i', found[0]))
            if npc_events != NPC_EVENTS:
                return {}
            proof['npc_table'] = {'offset': found[1], 'bytes': 44}
        result = copy.deepcopy(VALUES)
        result.update(player_event_ids=ids, npc_event_ids=npc_events, provenance=proof)
        return result
    except (KeyError, ValueError, TypeError, IndexError, OverflowError, struct.error):
        return {}


# Bounded compiler-layout signatures stay in the import tool.
LAYOUTS = {'x86_64': {'owner_defaults': [412873, 25, '48c783d800000000000000c6437401c7832001000001000000'],
            'owner_setter': [413737, 26, '554889e5408877748997200100005dc3554889e58977445dc390'],
            'player_limit': [429491, 21, '4889334889f7be01000000ba02000000e861c2ffff'],
            'npc_backlink_call': [-202971, 12, '488b7b084889dee812690900'],
            'npc_backlink_setter': [413763, 14, '554889e54889b7d80000005dc390'],
            'npc_world_gate': [-66553, 26, '4183bf14010000027510488b7f0831f6ba02000000e808540700'],
            'weapon_defaults': [-311196, 25, 'c683cd0000000048c7430800000000c783f800000000000000'],
            'primary_select': [419113,
                               457,
                               '554889e54157415641554154534883ec284189f4448965c448897dc84c8b374d85f60f84cb010000498b46084c8b384d85ff0f849101000049631f48895db8b9040000004889d848f7e148c7c7ffffffff480f41f8e8f83f0f004889df4889c389f94885ff7f0648894db0eb2a8d41ff48894db031c9eb0a48ffc1498b56084c8b3a498b5708488b14ca8b929c00000089148b39c875e141be0100000041b701eb66418d46ff4c63e84a6304ab488d0d1afa1c00488b09488b4908488b3cc1e8c872f6ff8945d44d63e64a6304a3488d0df9f91c00488b09488b4908488b3cc1e8a772f6ff3945d47d13428b04ab428b0ca342890cab428904a34530ff41ffc6448b65c4488b7db84139fe7c9541be0100000041f6c70141b70174ec4531ed85ff4c8b75b07e3231c04889c14531ed4889c239d1740f8b348b3b34937507c70493ffffffff48ffc239d775e648ffc14439f175dbeb0349ffc54539f57d5e42833cab007852488b55c8488b02488b4008488b00488b40084a8b04e8c680cd00000001488d055df81c00488d0d16f30f00488b12488b5208488b12488b52084a8b14ea4863929c0000008b3491488b38e8fe6ff4ff41ffcc4585e4759a4885db74084889dfe87d3e0f00'],
            'single_install_gate': [419053, 17, '41f644247401751c5b415c415e415f5dc3'],
            'single_install_select': [419089, 24, '418bb424200100004c89e75b415c415e415f5de900000000'],
            'bulk_install_gate': [419915, 22, '41f646740175224883c4085b415c415d415e415f5dc3'],
            'bulk_install_select': [419956, 29, '418bb6200100004c89f74883c4085b415c415d415e415f5de998fcffff'],
            'player_install': [440229, 17, '554889e553504889fb488b3be8c1afffff'],
            'player_install_call': [-157396, 5, 'e8741e0900'],
            'npc_install': [-199451, 14, '554889e5488b7f085de96c6f0900'],
            'npc_install_call': [-64368, 29, '498b8778010000488b40084c8b75a04a8b3c304c89e631d2e838f0fdff'],
            'dispatch': [420317,
                         280,
                         '554889e54156534883ec10f30f1145ec4989ce488b87d80000004885c0750f4863c6488d0dc9ef0f008b1c81eb468b40444883f80a7738bb3e000000488d0dd7000000486304814801c8ffe0bb36000000eb21bb34000000eb1abb35000000eb13bb37000000eb0cbbe4080000eb05bb3d000000488d05a7fa1c00488b388d42fe83f802720583fa08755889dee8fe9bedff84c0751f488d05c1f41c008a480f31c0f6c1014c0f44f0488d0572fa1c00488b38eb41488d05a2f41c00f6400f01744d488d0559fa1c00488b3889de4c89f231c94531c04883c4105b415e5de9b7a0edff488d0574f41c008a480f31c0f6c1014c0f44f089de4c89f231c9f30f1045ec4883c4105b415e5de9b99cedff4883c4105b415e5dc3'],
            'fire_success': [420917,
                             176,
                             'e885d9f4ff3c010f85a3000000f3410f104764f30f58050bdd0f00f3410f114764498b07488b40084a8b04e8488b40084a8b04f0c780b00000000000000041f6477401746b498b07488b40084a8b04e8488b40084a8b04f0f680cd00000001744f4889dfe8f1a70a00f30f114d90f30f114588660f70c001f30f11458c498b07488b40084a8b04e8488b40084a8b04f0f30f1080f80000008bb09c0000008b90a00000004c89ff488d4d88e8f8fcffff'],
            'pitch_update': [215010,
                             55,
                             '488d05ee162000488b38e872f307004889c7e878fd05000f28c80f57d2f30f1005f06c1200f30f5cc10f2ec27209498b7e60e818160400'],
            'pitch_wrapper': [482865, 13, '554889e5488b3f5de9c517ffff'],
            'pitch_setter': [423427,
                             66,
                             '554889e5488b074885c07434488b4008488b004885c07428833800742331c9488b4008488b04c8f30f1180f800000048ffc1488b07488b4008488b003b0872df5dc3'],
            'price_layout': [-206893,
                             140,
                             '554889e5488b47384885c0747d488b48088b4904890f488b48088b490c894f04488b48088b4914894f08488b48088b491c894f0c488b48088b4934894f1c488b48088b493c894f20488b50088b5244895724488b70088b7624897710488b40088b402c89471429ca89d0c1e81f01d0d1f801c8894718c647500048c747480000000048c74740000000005dc3'],
            'price_getter': [-206667, 10, '554889e58b47185dc390'],
            'interval_getter': [607601, 11, '554889e5f30f1047545dc3'],
            'npc_dispatch_table': [420599,
                                   44,
                                   '39ffffff47ffffff32ffffff40ffffff55ffffff55ffffff55ffffff55ffffff55ffffff5affffff4effffff']},
 'armv7': {'owner_defaults': [371646, 22, '002001214ff0ff35c6f8d00086f8701004acc6f80c11'],
           'owner_setter': [372386, 16, '80f87010c0f80c21704700bf01647047'],
           'player_limit': [384836, 18, '022200f98f8a0846216001210294fcf7a6ff'],
           'npc_backlink_call': [-193898, 8, '486808928af00afa'],
           'npc_backlink_setter': [372402, 6, 'c0f8d0107047'],
           'npc_world_gate': [-67352, 20, 'daf8c010022905d140680021022230966bf0d3fa'],
           'weapon_zero_register': [-294266, 2, '0024'],
           'weapon_defaults': [-294070, 18, '119880f889401198446011981199c1f8b040'],
           'primary_select': [376678,
                              348,
                              'f0b503af2de9000d83b004680090002c00f0cb8060680068002800f09f80056804200191a5fb0001002918bf0121002918bf4ff0ff3099f1cee90646012d0bdb6068294632460068406850f8043b01399b6d42f8043bf8d101204ff0010801e008f10108a84529da029044f29260c0f22200a8f1010a784456f82a10d0f800b0dbf80000406850f8210073f7a7ff0446dbf8000056f82810406850f8210073f79dff84420298dbda56f82a0056f8281046f82a1046f828000020d1e710f0010f4ff001084ff00100ccd0012d41db00204ff0ff310022904207d056f8223056f820409c4208bf46f8221001329542f2d10130a842eed1002d2bdd44f208600024c0f2220042f2321a7844c0f21e0afa444ff00108d0f800b056f82400002812db0098006840680068406850f8240080f88980816ddbf800005af8211055f762fb0198013800e00198019010b10134ac42e2db304699f12ee900980468'],
           'single_install_select': [376586, 22, '95f8700038b1d5f80c114ff0ff300890284600f023f8'],
           'bulk_install_select': [377338, 22, '98f8700038b1d8f80c114ff0ff3008904046fff7abfe'],
           'player_install': [394066, 12, '90b5044601af2068fbf7defe'],
           'player_install_call': [-153370, 16, '169e22460d98d0f8f0001c9585f02efd'],
           'npc_install': [-190846, 6, '40688af0e3bb'],
           'npc_install_call': [-65544, 24, '26994ff0ff36daf8f80000221b9d406840593096e1f739fb'],
           'dispatch': [377614,
                        192,
                        'f0b503af81b0d0f8d0001c4600280ad0406a0a280fd842f22a21c0f21e01794451f8205008e041f66a60c0f21e00784450f8215000e03d2544f22a30082ac0f222007844066830681bd80121914011f4867f16d029468ff605ff00281cd044f26e30c0f2220078440068c07b38b130680021009129462246002390f6a1f801b0f0bd44f24a31c0f2220179440968c97b002908bf0c460ae044f23430c0f2220078440068c07b002808bf04463068294622464ff0000301b0bde8f0408ff640bf'],
           'fire_success': [378068,
                            110,
                            '5cf7cbf9012832d194ed180a002100ef080d84ed180a2068406850f82600406850f82800c16694f87010002920ef10011cbf90f88900002819d017ad1aa9284665f19df92068406850f82600406850f82800d0e9162390ed2c0a204611461a462b468ded000a20ef1001fff7e6fe'],
           'pitch_update': [226382,
                            52,
                            'dbf800000c966ef009fc0c964bf0dcffc7ef100f40ec320b20efa20db5eec00af1ee10fa06db10ee101adaf854000c9630f074fe'],
           'pitch_wrapper': [426346, 6, '0068f4f771bd'],
           'pitch_setter': [379986,
                            50,
                            '0068002808bf704740680268002a1cbf106800280cd041ec101b5168002251f822300132824283ed2c0a20ef1001f6d37047'],
           'price_layout': [-196950,
                            84,
                            '016b002908bf70474968c0ef50004a680260ca6842604a698260ca69c2604a6bc261ca6b02624b6c4362d1f82490c0f81090c96a4161991a01ebd17102eb6101816100f1340141f98f0a002180f84410704700bf'],
           'price_getter': [-196798, 4, '80697047'],
           'interval_getter': [537622, 4, '406d7047']}}
