"""Mac second-trip pirate combat data; executable bytes never enter the runtime."""
import copy, hashlib
from .station_exterior import declaration_bytes

def extract_full_hold_pirate(mach, arrival, flight, actors, handoff):
    if mach.architecture!='x86_64':return {}
    try:
        if flight['scope']!='full_hold_mining_flight_construction' or not handoff:return {}
        npc=actors['npc_initialization']
        if not all(npc.get(key) for key in ['hull','guidance','holding','hostility','primary_weapon']):return {}
        if npc['hull']['rank']!=0:return {}
        origin=arrival['provenance']['actor']
        if origin['bytes']!=315:return {}
        anchor=mach.text['address']+origin['offset']-mach.slice_offset-mach.text['offset'];proof={}
        for key,(delta,size,section,pattern) in LAYOUTS.items():
            found=declaration_bytes(mach,anchor+delta,size,section.encode())
            if found is None:return {}
            if pattern.startswith('sha256:'):
                if hashlib.sha256(found[0]).hexdigest()!=pattern[7:]:return {}
            elif found[0]!=bytes.fromhex(pattern):return {}
            proof[key]={'offset':found[1],'bytes':size}
        result=copy.deepcopy(VALUES);result['provenance']=proof;return result
    except (KeyError,TypeError,ValueError,IndexError,OverflowError):return {}

VALUES = {'scope': 'full_hold_pirate_combat',
 'campaign_cursor': 4,
 'actor_id': 0,
 'actor_kind': 8,
 'hull_catalogue_id': 2,
 'subtype': 0,
 'rank_base': 20,
 'rank_multiplier': 14,
 'cursor_multiplier': 4,
 'difficulty_offset': -0.5,
 'percentage_scale': 100.0,
 'initial_hostile': True,
 'current_hull_is_factory_hull': True,
 'primary_weapon': {'actor_ids': [0],
                    'actor_kind': 8,
                    'category': 0,
                    'damage': 1,
                    'interval_ms': 592,
                    'item_id': 19,
                    'kind': 1,
                    'launch_mode': 'ordinary',
                    'lifetime_ms': 3000,
                    'local_muzzle': [0.0, 0.0, 0.0],
                    'model_resource_id': 6795,
                    'projectile_capacity': 4,
                    'speed_units_per_millisecond': 16.0},
 'activation_cursor': 5,
 'activation_phase_before': 0,
 'activation_phase_after': 1,
 'activation_offset': [5000, 0, 30000],
 'activation_yaw_radians': 3.1415927410125732,
 'activation_mode': 1,
 'proximity_half_extent': 25000,
 'target_activation_half_extent': 50000}

LAYOUTS = {'factory_hull': [78110,
                  433,
                  '__text',
                  'bb2c010000488d05580a2400488b38e80c2e0c0083f8147f15488d05440a2400488b38e8f82d0c006bd80e83c314440175cc44017dd044016dd4488d05230a2400488b38e8b5e60b00428d0ca50000000084c0b8b40000000f44c101d8448b75b84183fe3374284183fe3174144183fe2c752cf30f2ac0f30f590549d81600eb1af30f2ac0f30f590537d81600eb0cf30f2ac0f30f5905c5901600f30f2cc04183fc380f94c1418d5424cf83fa040f92c208cabb0e0100000f44d8488d05a2092400488b38e8562d0c0041bd8c00000083f8147f14488d0588092400488b38e83c2d0c00448d6c802841bf983a0000837db401751f478d6c6d004183fe0e740b41bfc8af00008d1c9beb096bdb1941bfc8af0000f30f2ac3488d05a9092400f30f10482cf30f580d48d11600f30f59c8f30f58c8f3440f2cf14181fc9a000000751b488d051b092400488b38e85be50b00837dbc090f94c120c141d3e6488d0500092400488b38e808200c00b98a02000084c0bbe80300000f45d9bf28010000e8894f16004989c44c89e789de4489f2b90100000041b8010000004531c9e8c9f306004c89e74489ee4489fae8cdf90600'],
 'factory_no_override': [78713,
                         244,
                         '__text',
                         'bf60030000e8a94e16004989c6f30f2a45ccf30f2a4dd0f30f2a55d48b45b0440fb6f84c89f78b5db889de448b6dbc4489ea4c89e141b8000000004589f9e82a080800498b064c8b6010488d05f0072400488b380fb64d1089de4489eae88773fbff4c89f74889c689da4489f941ffd4488b45c08b801401000083f8014d89f5741e83f8177419488b45c0488b38498b75184885f67504498b7510e8b9b202004189de4183fe3374414183fe31740a4183fe2c0f857e090000498b5d704885db7416488b7b084885ff7405e8d14d16004889dfe8cf4d160049c74570000000004183fe330f854d09000041c6454100e943090000'],
 'ordinary_vtable': [2399706,
                     32,
                     '__const',
                     '98cb140001000000201f15000100000092cc1400010000003cc9140001000000'],
 'initial_pools': [534334,
                   138,
                   '__text',
                   '89734489938000000089938c0000004489bba40000004489aba80000004489b3ac000000c783c00000000000c842c7838400000000000000c7838800000000000000c7437000000000c643620048c783980000000000000048c7839000000000000000c683cb00000001c7436400000000c783e400000000000000c783e000000000000000e8a0020000'],
 'previous_hull_sample': [607290,
                          39,
                          '__text',
                          '498b7c2408e88eeffeff418984244002000041c78424440200000000000041c684244802000000'],
 'weapon_damage': [55284,
                   51,
                   '__text',
                   'b8010000008b8d74ffffff83f9044189d4440f44e04489a57cffffff83f9380f94c08d49cf83f9040f92c108c1888d63ffffff'],
 'weapon_postpass': [54772,
                     4266,
                     '__text',
                     'sha256:93395d2357f50de1eae22eb2ec4b6f53cda4499231fe0110d2a04c1bd99c392d'],
 'weapon_constructor': [-190034,
                        1052,
                        '__text',
                        'sha256:4b0208493df049fbb0bfd01ecc5256fb626a03224588905359578b21399d347d'],
 'scripted_activation': [151367,
                         208,
                         '__text',
                         '488d0534ec2200488b38e8d6c80a0083f8050f85bd00000041837d28004c8bb5c8d0ffff488b9db0d0ffff0f850c0200004c89f7e850450600f30f118dd8fbfffff30f1185d0fbffff660f70c001f30f1185d4fbffff498d7d34488db5d0fbffffe8fdd60d00498b442408488b38488b07f3410f10553cf3410f104534f3410f104d38f30f580534471500f30f581598451500ff9090000000f30f100d6e471500498b442408488b00488b7810660fefc0660fefd2e86da7f2ff498b442408488b38488b07ff501841c7452801000000'],
 'proximity_activation': [617194,
                          408,
                          '__text',
                          '498b4608f64060010f848a0100004183bebc00000005741c41f68624010000010f84720100004183be2c010000010f85640100004183be78010000000f8e560100004d89fc498b7e78e8a232f8ff4889c7e8561bffff88c3498b7e784d8dbec4000000e88832f8ff84db743e4889c7e870cfffff4889c7e8206404004889c7e80e87ebfff30f118d50fcffff488db548fcfffff30f118548fcffff660f70c001f30f11854cfcffffeb2c488b38e862bffefff30f118d40fcfffff30f118538fcffff660f70c001f30f11853cfcffff488db538fcffff4c89ffe8e2ba0600f3410f10174d89e7f3410f5c17488b8578f5fffff30f1110f3410f108ec8000000f3410f5c4e4cf3410f118edc010000f3410f1086cc000000f3410f5c4650f3410f1186e0010000f30f101d829c0e000f2eda76650f2e15aad00e00765cf30f10156c9c0e000f2ed1764f0f2e0d94d00e007646f30f100d569c0e000f2ec876390f2e057ed00e00763041c786bc00000001000000498b7e184885ff7504498b7e10be01000000e8688debff498b7e08be01000000e86cd4feff'],
 'holding_activation': [619682,
                        255,
                        '__text',
                        '498b4608f64060017428488d05cfc61b00488b38e871a3030083f8027c14498b7e184885ff7504498b7e1031f6e80885ebff498b86a00100004885c00f848b1f0000f64062010f85811f0000f3410f1096d8010000418b8678010000f30f2ac00f2ec20f86641f0000f7d8f30f2ac80f2ed10f86551f0000f3410f1096dc0100000f2ec20f86431f00000f2ed10f863a1f0000f3410f1096e00100000f2ec20f86281f00000f2ed10f861f1f000041c786bc00000001000000498b7e184885ff7504498b7e10be01000000e86a84ebff498b7e08be01000000e86ecbfeff41f6867f010000010f84e11e0000498b7e78be01000000e8f859f8ffe9ce1e0000'],
 'mode_dispatch': [627906,
                   40,
                   '__text',
                   'dfe0ffff9be6ffffadffffff15f8ffffa0fbffffe0dfffff86dfffff9be6ffffc2e2ffffefe0ffff'],
 'proximity_positive': [1575066, 4, '__const', '0050c346'],
 'proximity_negative': [1588430, 4, '__const', '0050c3c6'],
 'activation_x': [1545990, 4, '__const', '00409c45'],
 'activation_z': [1545586, 4, '__const', '0060ea46'],
 'activation_yaw': [1546070, 4, '__const', 'db0f4940'],
 'projectile_speed': [1575350, 4, '__const', '00008041'],
 'hull_getter': [537554, 12, '__text', '554889e58b87800000005dc3'],
 'hull_percent': [535144,
                  150,
                  '__text',
                  '554889e5f30f2a878c000000f30f2a8f80000000f30f5ec8f30f100536970f00f30f59c8f30f2cc18987a0000000f30f2a979c000000f30f108f90000000f30f5ecaf30f59c8f30f2cc18987b0000000f30f2a9798000000f30f2a8f94000000f30f5ecaf30f59c8f30f2cc18987b4000000f30f2a9788000000f30f2a8f84000000f30f5ecaf30f59c8f30f2cc18987b80000005dc3'],
 'model_assignment': [-79336,
                      272,
                      '__text',
                      '554889e54156534889fb8993b00000004885f6746980f10184c97562488973184c8b73104d85f67527bfe8000000e8e1b718004989c6488d053d712600488b304c89f7e88a25f6ff4c897310488b73188b76144c89f7e87927f6ff488b4b10488b43188b491489482ceb384889c34c89f7e892b718004889dfe8c6b71800488973104c8b73184d85f674104c89f7e8ad26f6ff4c89f7e86db7180048c7431800000000f30f109388000000f30f108b84000000f30f108380000000488b7b10e8c228f6ff4c8b7308488b7b10e82b28f6ff4983c6084c89f74889c6e802181400488b7b184885ff750a5b415e5dc3e978ffffff488b5b084883c308e8fc27f6ff4889df4889c65b415e5de9c318140090'],
 'world_assignment': [608550,
                      340,
                      '__text',
                      '554889e54156534889fbe83987f5ff488b7b10488b43784c8bb088000000e8f5a9ebff4c89f74889c6ba0900000031c9e89781feff898308020000488b4b78488bb98800000089c631d2e81d85feff488b7b10488b43784c8bb090000000e8b5a9ebff4c89f74889c6ba0f00000031c9e85781feff8983b4000000488b4b78488bb99000000089c631d2e8dd84feff488b7b10488b43784c8bb0a8000000e875a9ebff4c89f74889c6ba2a00000031c9e81781feff8983b8000000488b4b78488bb9a800000089c631d2e89d84feff488b7b10488b43784c8bb0b8000000e835a9ebff4c89f74889c6ba1100000031c9e8d780feff898384010000488b4b78488bb9b800000089c631d2e85d84feff488b7b10488b43784c8bb0b8000000e8f5a8ebff4c89f74889c6ba1200000031c9e89780feff898388010000488b4b78488bb9b800000089c631d25b415e5de91984feff90'],
 'activate': [630538,
              82,
              '__text',
              '554889e553504889fbc783bc00000001000000488b7b08be01000000e8c3a1feff4889dfbe01000000e8eaaeffffc6834101000001488b7b184885ff7504488b7b10be010000004883c4085b5de9805aebff'],
 'world_player': [105946, 14, '__text', '554889e5488b87680100005dc390']}
