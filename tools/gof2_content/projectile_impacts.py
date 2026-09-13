"""Recover fresh ordinary impact model and playback declarations statically."""
import copy
from .ship_models import section_bytes

VALUES = {'item_ids': [2, 19], 'model_ids': [14600, 14605], 'kinds': [0, 1], 'initial_playing': False, 'animation_speed': 1.0, 'animation_loop': False, 'camera_basis_copy': True, 'position_is_projectile': True, 'sample_before_contacts': True, 'restart_preserves_sample': True, 'render_type': 2}

def extract_projectile_impacts(mach,staging,actors,weapons):
    arch=mach.architecture
    if arch not in LAYOUTS:return {}
    try:
        if not weapons['ordinary_hit_policy'] or not weapons['player_hit_policy']:return {}
        if not staging['projectile_visuals'] or actors['npc_initialization']['primary_weapon']['item_id']!=19:return {}
        origin=staging['provenance']['initial']['offset']
        at=mach.text['address']+origin-mach.slice_offset-mach.text['offset']
        proof={}
        for key,(delta,size,raw) in LAYOUTS[arch].items():
            found=section_bytes(mach,at+delta,size,b'__const' if key in ['model_2','model_19'] else b'__text')
            if found is None or found[0]!=bytes.fromhex(raw):return {}
            proof[key]={'offset':found[1],'bytes':size}
        result=copy.deepcopy(VALUES);result['provenance']=proof
        return result
    except (KeyError,TypeError,IndexError,ValueError,OverflowError):return {}

LAYOUTS = {'x86_64': {'player_setter': [-57023,
                              35,
                              '4c89f7488b75d0e8ec20fcff8b45ac418986a00000004c89f7be01000000e83f24fcff'],
            'effect_table': [-310645, 27, '488d0dade01a00448b34994585f6418987a80000000f88e8000000'],
            'allocation': [-310618,
                           42,
                           '418b5f10488d3c9d00000000e8c4621a00498987680100004889dfe8b5621a004531e449898770010000'],
            'initial_disabled': [-310469,
                                 32,
                                 '498b8768010000428b34a0498b7d00e890aa14004889c731f631d2e8042a1300'],
            'update_before_contacts': [-302299,
                                       113,
                                       '498b86680100004885c0744141837e1000743a4c637da44531e44c8d2da1fb2700eb07498b8668010000428b34a0498b7d00e8838a14004889c74c89fe31d2e8d60b130049ffc4453b661072d641f68690000000010f84fd0100004183bea0000000270f84ef0100004c89f7e89bf4ffff'],
            'contact_restart': [-304271,
                                84,
                                '498b87680100004885c00f84e9000000428b34a84c8d355b032800498b3ee84b9214004889c7be0300000031d2e8bc111300498b8768010000428b34a8498b3ee8299214004889c7be0100000031d2e89a111300'],
            'contact_position': [-304187,
                                 165,
                                 '498b1e4889dfe8ff9714004889df89c6e825941400488b4820488b5028488b70308b783889bd40ffffff4889b538ffffff48899530ffffff48898d28ffffff488b481848898d20ffffff488b481048898d18ffffff488b08488b400848898510ffffff48898d08fffffff30f1055d0f30f1045c8f30f104dcc488dbdc8feffff488d9d08ffffff4889dee8fbca1500498b8768010000428b34a8498b3e4889dae885891400'],
            'position_load': [-303620,
                              48,
                              '498b47184863d1488995b0feffff898da8feffff488d0c95000000004c8d2c49428b4c2808894dd04a8b0428488945c8'],
            'draw': [-301683,
                     394,
                     '554889e54157415641554154534881ec980000004989fe498bbe080100004885ff7405e81a080f00498b86680100004885c00f844001000041837e10000f8435010000498d8e3001000048898d40ffffff4531e44c8d2dfff82700488d5d98eb07498b8668010000428b34a0498b7d00e8dd871400f6800d010000010f84e90000004d8b7d004c89ffe8b48d14004c89ff89c6e8da891400488b4820488b5028488b70308b7838897dd0488975c8488955c048894db8488b481848894db0488b481048894da8488b08488b4008488945a048894d98498b8668010000428b34a0498b7d00e8998114004889c7e811ae1500f30f114d90f30f114588660f70c001f30f11458c4c8bbd40ffffff4c89ff488d7588e85ae31200f3410f108e34010000f3410f109638010000f3410f1007488dbd48ffffff4889dee884c01500498b8668010000428b34a0498b7d004889dae80d7f1400498b8668010000428b34a0498b7d0031d2e81737140049ffc4453b66100f82e9feffff4881c4980000005b415c415d415e415f5dc3'],
            'wrapper_draw': [355864, 9, '498b7f10e86cf7f5ff'],
            'restart_mode': [945503,
                             112,
                             '554889e548897df88975f4488955e8488b55f88b75f485f6488955e08975dc0f8434000000e9000000008b45dc83f8030f852e000000e900000000488b45e0488b882001000048898830010000c6800d01000001e915000000488b45e0c6800d010000008b45f4488b4de08941785dc3'],
            'end_sample': [946259,
                           59,
                           '488b8548ffffffc6800d01000000488b882801000048898830010000488b8548ffffff488bb0300100008a4def80e1014889c70fb6d1e891070000'],
            'npc_setter': [-65918, 31, '41c78424a0000000010000004c89e7be13000000e89e43fcff41bf8b1a0000'],
            'model_2': [1450823, 4, '08390000'],
            'model_19': [1450891, 4, '0d390000']},
 'armv7': {'player_setter': [-58548, 32, '4ff0ff35119c28950d992046c6f7e5fc11980c99c165204601212895c6f779fe'],
           'effect_table': [-293460, 22, '42f6a061c0f228017066794451f824100291002970db'],
           'allocation': [-293438,
                          44,
                          'b46804200895a4fb0001002918bf0121002918bf4ff0ff303cf2aeeec6f80c01204608953cf2a8eec6f81001'],
           'initial_disabled': [-293274, 28, 'd6f80c11039851f8251000680894fcf1b3ff002100220894f1f104fd'],
           'update_before_contacts': [-287508,
                                      92,
                                      'd5f80c0100281cbfa968002919d046f656114feaea78c0f22c01002479440e6801e0d5f80c0150f824103068fbf161fc514642460023f0f1ecf90134a8688442efd395f84c00cdf808a000281cbfe86d272800f0af802846fff7abfb'],
           'contact_restart': [-288462,
                               52,
                               'dbf80c01002850d0b246079e50f824103068fbf14bfe03210022f0f19dfbdbf80c11306851f82410fbf140fe01210022f0f192fb'],
           'contact_position': [-288410,
                                118,
                                '35682846fcf1ccf8014628464ff00108fbf124ff00f1200160f98f0a22ad61f98f2a00f110012c3060f98f6a05f12c0061f98f4a294645f98f0a40f98f6a05f1200040f98f2a05f110004a9b499a40f98f4a13a89ded4b0a8ded000a20ef100108f22affdbf80c112a463068564651f82410fbf123fd'],
           'position_load': [-289392, 28, 'dbf80c0001eb41040f91311d00eb8400d0ed000b80684b90cded490b'],
           'draw': [-287042,
                    276,
                    'f0b503af2de9000da3b00446d4f8b800002818bfe0f0a0f9d4f80c0100281cbfa168002972d004f1d801019146f2667114aec0f22c010df1440b79444ff0000ad1f8008001e0d4f80c0150f82a10d8f80000fbf165fb90f8ed00002851d0d8f800502846fbf1f0fd01462846fbf14afc00f1200160f98f0a61f98f2a00f110012c3060f98f6a06f12c0061f98f4a46f98f0a40f98f6a06f1200040f98f2a06f1100040f98f4ad4f80c11d8f8000051f82a10fbf1f7fa0146584607f26bfc01985946eef1a7fcd4e9362302a894ed380a31468ded000a20ef100108f241fcd4f80c113246d8f8000051f82a10fbf13afad4f80c110022d8f8000051f82a10f8f18dfb0af1010aa06882459cd323b0bde8000df0bd'],
           'wrapper_draw': [367462, 8, 'dbf8080060f7a8f9'],
           'restart_mode': [1745034,
                            82,
                            '85b00490039102920498039900290190009113d0ffe70098032815d1ffe70120c0f200000199d1f8fc20d1f80031c1f81031c1f80c2181f8ed0008e00020c0f20000019981f8ed0003980199886505b07047'],
           'end_sample': [1745468,
                          48,
                          '00200e9981f8ed00d1f80401d1f80821c1f81021c1f80c01ffe70e98d0f80c11d0f810219df8ac3003f0010300f009fa'],
           'npc_setter': [-66740, 22, '269801222699ca651321cdf8c0b0c8f7e4fc41f68b2a'],
           'model_2': [2339938, 4, '08390000'],
           'model_19': [2340006, 4, '0d390000']}}
