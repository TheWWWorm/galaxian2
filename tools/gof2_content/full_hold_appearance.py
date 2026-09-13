"""Optional Mac mission placement declarations, without executable runtime code."""
import copy,hashlib
from .station_exterior import declaration_bytes

def extract_full_hold_appearance(mach,arrival,story,death):
    if mach.architecture!='x86_64':return {}
    try:
        if story['scope']!='full_hold_mining_story' or death['scope']!='full_hold_pirate_destruction':return {}
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

VALUES = {'scope': 'full_hold_pirate_appearance',
 'campaign_cursor': 4,
 'trigger_cursor': 5,
 'actor_id': 0,
 'actor_kind': 8,
 'hull_catalogue_id': 2,
 'subtype': 0,
 'once_per_flight': True,
 'offset': [5000, 0, 30000],
 'offset_space': 'world',
 'yaw_radians': 3.1415927410125732,
 'actor_mode': 1,
 'active': True,
 'model_draw_enabled': True,
 'node_draw_requested': True,
 'bank_child': True,
 'statistics_before_yaw': True,
 'preserve_hull': True,
 'preserve_cargo': True,
 'preserve_guidance': True,
 'preserve_bank_history': True,
 'preserve_effect_clocks': True,
 'preserve_cleanup_clock': True,
 'dead_actor_reenters_death': True,
 'repeat_death_counters': True}

LAYOUTS = {'mission_controller': [138688,
                        93478,
                        '__text',
                        'sha256:7d5903c3306c9e77eda72db8f17ae7b1b91b9dac866c4610cab470406bf7cd5e'],
 'activation': [630538,
                82,
                '__text',
                '554889e553504889fbc783bc00000001000000488b7b08be01000000e8c3a1feff4889dfbe01000000e8eaaeffffc6834101000001488b7b184885ff7504488b7b10be010000004883c4085b5de9805aebff'],
 'placement': [609228,
               176,
               '__text',
               '554889e54156534883ec20f30f1155d4f30f114dd8f30f1145dc4889fbf30f118380000000f30f118b84000000f30f119388000000488b7b10e894a7ebff4c8db3c0010000488d75e0f30f1045dcf30f1145e0f30f1045d8f30f1145e4f30f1045d4f30f1145e84c89f7e86fda0600488bbbb80100004885ff7410f3410f104e08f3410f7e06e8cdc704004c8b7308488b7b10e8b0a6ebff4983c6084c89f74889c6e8879609004883c4205b415e5dc3'],
 'visibility': [609826,
                78,
                '__text',
                '554889e5535089f3488b47104885c07436488b4f184885c974288b711c83feff7425488d0547ed1b00488b38e8377c08000fb6f34889c74883c4085b5de926ad07008b701cebd64883c4085b5dc3'],
 'model_install': [-79336,
                   272,
                   '__text',
                   '554889e54156534889fb8993b00000004885f6746980f10184c97562488973184c8b73104d85f67527bfe8000000e8e1b718004989c6488d053d712600488b304c89f7e88a25f6ff4c897310488b73188b76144c89f7e87927f6ff488b4b10488b43188b491489482ceb384889c34c89f7e892b718004889dfe8c6b71800488973104c8b73184d85f674104c89f7e8ad26f6ff4c89f7e86db7180048c7431800000000f30f109388000000f30f108b84000000f30f108380000000488b7b10e8c228f6ff4c8b7308488b7b10e82b28f6ff4983c6084c89f74889c6e802181400488b7b184885ff750a5b415e5dc3e978ffffff488b5b084883c308e8fc27f6ff4889df4889c65b415e5de9c318140090'],
 'actor_factory': [77944,
                   3478,
                   '__text',
                   'sha256:9b9cfd3e564cc131a926a3f0704be2479fa2ee4dcf4c291e129e904aeb57b6cb'],
 'matrix_setter': [-724186, 24, '__text', '554889e54889f08b7714488b7f384889c25de95dcf1c0090'],
 'position_setter': [-724066,
                     68,
                     '__text',
                     '554889e54883ec50f30f1155bcf30f114db8f30f1145b48b7714488b7f38e8f9d01c00488d7dc04889c6f30f1045b4f30f104db8f30f1055bce81e101e004883c4505dc3'],
 'euler_addition': [-723090,
                    140,
                    '__text',
                    '554889e5534881ec880000004889fbf30f584340f30f114340f30f584b44f30f114b44f30f585348f30f1153488b7314488b7b38e813cd1c00488d7db88b535cf30f105348f30f104340f30f104b444889c6e8e5ff1d008b7314488b7b38e8e9cc1c00488dbd78fffffff30f105354f30f10434cf30f104b504889c6e8ab0a1e004881c4880000005b5dc390'],
 'effect_trigger': [-681366,
                    484,
                    '__text',
                    '554889e54157415641554154534883ec784989d74989f64989fc498b7c2408e8be58ffff488d05fda02f00488b38498b4424088b7014e8e52f1c00c6800d01000001498b4424088b701c83feff7416488d05d2a02f00488b38e8c22f1c00c6800d01000001498b7c24104885ff74264c89f6e86b58ffff488d05aaa02f00488b38498b4424108b7014e8922f1c00c6800d01000001418b042483f80b746e83c0f883f8020f87b7000000488d1d97a02f00488b3bbe450c0000e822801b00f30f2ad0f30f5e158e262200498d74243c488d7d980f57c00f57c9e8825a1d00488b3bbe28000000e8f57f1b000f57c0f30f2ac0f30f59054e262200f30f58055a2622004c89e7e88ef7ffffeb55498b7c2408c7458800000000c7458c0000803fc7459000000000488d55884c89fee84658ffff488d9578ffffff498b7c2410c78578ffffff00000000c7857cffffff0000803fc74580000000004c89fee81758ffff498b4424184885c07441833800743c31db4c8d2daf9f2f00488b40084c8b3cd84c89ff4c89f6e85657ffff418b7714498b7d00e8872e1c0048ffc3c6800d01000001498b4424183b1872cd41c644243001418b4608898570ffffff498b0648898568ffffff488db568ffffff4c89e7e863fcffff4883c4785b415c415d415e415f5dc3'],
 'activation_virtual': [2399714, 8, '__const', '201f150001000000'],
 'model_install_virtual': [2399706, 8, '__const', '98cb140001000000'],
 'offset_x': [1545990, 4, '__const', '00409c45'],
 'offset_z': [1545586, 4, '__const', '0060ea46'],
 'yaw': [1546070, 4, '__const', 'db0f4940']}
