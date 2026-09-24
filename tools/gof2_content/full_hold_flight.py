"""Second Mac mining flight construction; original code is never executed or emitted."""
import copy
from .declaration_layouts import recognize
from .station_exterior import declaration_bytes

def extract_full_hold_flight(mach, arrival, departure, first_flight, actors):
    if mach.architecture != 'x86_64': return {}
    try:
        if departure['scope'] != 'full_hold_station_departure' or first_flight['scope'] != 'first_mining_flight_construction': return {}
        initial=actors['npc_initialization']
        if not all(initial.get(k) for k in ['construction','routes','world_initialization']): return {}
        origin=arrival['provenance']['actor']
        if origin['bytes'] != 315: return {}
        layouts=[{k:[v[2],v[0],v[1],v[3]] for k,v in rows.items()} for rows in [LAYOUTS,MAC_ALTERNATE]]
        proof=recognize(mach,origin['offset'],layouts,reader=declaration_bytes)
        if not proof:return {}
        values=VALUES
        result=copy.deepcopy(values);result['provenance']=proof
        return result
    except (KeyError,TypeError,ValueError,IndexError,OverflowError):return {}

VALUES = {'scope': 'full_hold_mining_flight_construction',
 'campaign_cursor': 4,
 'world_type': 3,
 'mission_kind': 154,
 'station_id': 78,
 'system_id': 15,
 'requires_ordinary_location': True,
 'requires_empty_companions': True,
 'requires_default_placement': True,
 'environment_reseed_before_yaw': True,
 'environment_object_resource_id': 16994,
 'environment_object_position_bounds': [80000, 40000, 40000],
 'environment_object_position_offsets': [-40000, -20000, 40000],
 'player_position': [10, 10, 10000],
 'yaw_units': 1600,
 'angle_fraction': 1.52587890625e-05,
 'angle_tau': 6.2831854820251465,
 'yaw_zero_means_positive': True,
 'camera_axis_base': 500,
 'camera_axis_bound': 2000,
 'camera_z': 9000,
 'camera_zero_means_negative': True,
 'actor_count': 1,
 'weapon_item_sequence': [0, 19],
 'weapon_effect_sequence': [14600, 14605],
 'entry_release_ms': 7001,
 'briefing_minimum_ms': 5001,
 'briefing_requires_entry_release': True,
 'actor_kind': 8,
 'hull_catalogue_id': 2,
 'subtype': 0,
 'actor_position': [0, 0, -200000],
 'actor_mode': 5,
 'actor_active': False,
 'actor_targeting_blocked': True,
 'retains_generated_cargo': True,
 'retains_generated_route': True,
 'weapon_effect_capacity': 4,
 'weapon_effect_random_bound': 2,
 'zero_means_flipped': True}

LAYOUTS = {'actor_dispatch': [315,
                    256,
                    '__text',
                    '83f8060f8ff700000083f8044c89fa0f85f7c300004989d6bf18000000e8cf8017004889c3bf08000000e8bc80170048894308c743100100000048c70000000000c7030000000049899e78010000bf010000004889dee8a7d60100c70424000000004c89f7be0800000031d2b9020000004531c041b901000000e8be2e0100498b8e78010000488b4908488901498b8678010000488b4008488b3831f6e82fcafeff498b8678010000488b4008488b00488b7808be01000000e84f2a0800f30f1015a9071800498b8678010000488b4008488b38488b07660fefc0660fefc9ff9090000000498b8678010000488b4008488b38e89bc9feff4c89f2e90cc30000'],
 'actor_position_z': [1575338, 4, '__const', '005043c8'],
 'ordinary_field_center': [-35306,
                           796,
                           '__text',
                           'sha256:c2b2fba547ab45adb44a1d9786688c6e4f06a658b858b5b5a2f756c76d93a577'],
 'route_and_cargo': [605172,
                     2070,
                     '__text',
                     'sha256:5c736e8f5a1a01fba01080af14930276fe27daf62659649ba266bdc8e28b57e4'],
 'placement_virtual': [2399834, 8, '__const', 'e2cb140001000000'],
 'world_order': [-44096,
                 2458,
                 '__text',
                 'sha256:8e77d24e7a62a0ebd87fa6aba01be64f590ee82544d83b799c9666e9b551e64a'],
 'factory': [77944,
             3478,
             '__text',
             'sha256:9b9cfd3e564cc131a926a3f0704be2479fa2ee4dcf4c291e129e904aeb57b6cb'],
 'inactive_mode': [-78898,
                   44,
                   '__text',
                   '554889e553504889fbc783bc00000005000000488b7b0831f6e802750900c683e5000000014883c4085b5dc3'],
 'activity': [-78836,
              36,
              '__text',
              '554889e553504889fb488b7b08400fb6f6e8cc740900c683e6000000004883c4085b5dc3'],
 'activity_field': [540910, 14, '__text', '554889e54088b7c80000005dc390'],
 'hostile': [535624, 28, '__text', '554889e54088b7f8000000c6476001c6476100c687ec000000015dc3'],
 'position_setter': [609228,
                     176,
                     '__text',
                     '554889e54156534883ec20f30f1155d4f30f114dd8f30f1145dc4889fbf30f118380000000f30f118b84000000f30f119388000000488b7b10e894a7ebff4c8db3c0010000488d75e0f30f1045dcf30f1145e0f30f1045d8f30f1145e4f30f1045d4f30f1145e84c89f7e86fda0600488bbbb80100004885ff7410f3410f104e08f3410f7e06e8cdc704004c8b7308488b7b10e8b0a6ebff4983c6084c89f74889c6e8879609004883c4205b415e5dc3'],
 'weapons': [54772,
             4266,
             '__text',
             'sha256:93395d2357f50de1eae22eb2ec4b6f53cda4499231fe0110d2a04c1bd99c392d'],
 'extra_story': [51826,
                 1046,
                 '__text',
                 'sha256:f9888874fd48b47efc6738660c865a899430cfdd540c30372ca09d04e7a0443a']}

# Complete independently verified alternate Mac layout.
MAC_ALTERNATE = {'actor_dispatch': [315,
                    256,
                    '__text',
                    '83f8060f8ff700000083f8044c89fa0f85f7c300004989d6bf18000000e81b1f17004889c3bf08000000e8081f170048894308c743100100000048c70000000000c7030000000049899e78010000bf010000004889dee8a7d60100c70424000000004c89f7be0800000031d2b9020000004531c041b901000000e8be2e0100498b8e78010000488b4908488901498b8678010000488b4008488b3831f6e82fcafeff498b8678010000488b4008488b00488b7808be01000000e8672c0800f30f101541a61700498b8678010000488b4008488b38488b07660fefc0660fefc9ff9090000000498b8678010000488b4008488b38e89bc9feff4c89f2e90cc30000'],
 'actor_position_z': [1550402, 4, '__const', '005043c8'],
 'ordinary_field_center': [-35306,
                           796,
                           '__text',
                           'sha256:a80c99c4eb73cda383cd71055857e8d4ac476aabafa20fbcd1d5eb73d72d3ed5'],
 'route_and_cargo': [605720, 2070, '__text', 'sha256:9465ec13dc3e42a12689abc652190347dad3912ec48a58a6f9e15f23b769849d'],
 'placement_virtual': [2377266, 8, '__const', '2ee6140001000000'],
 'world_order': [-44096, 2458, '__text', 'sha256:0cdaa357638444d69604f1f9989b89fcce3e2f2fcd894351d0e3b5e94608f7d6'],
 'factory': [77944, 3478, '__text', 'sha256:1edb599619eeabcc4601e757d01307eba28fc1a7bfb5ea74ea86ef4b365fcbf3'],
 'inactive_mode': [-78898,
                   44,
                   '__text',
                   '554889e553504889fbc783bc00000005000000488b7b0831f6e81a770900c683e5000000014883c4085b5dc3'],
 'activity': [-78836, 36, '__text', '554889e553504889fb488b7b08400fb6f6e8e4760900c683e6000000004883c4085b5dc3'],
 'activity_field': [541446, 14, '__text', '554889e54088b7c80000005dc390'],
 'hostile': [536160, 28, '__text', '554889e54088b7f8000000c6476001c6476100c687ec000000015dc3'],
 'position_setter': [609776,
                     176,
                     '__text',
                     '554889e54156534883ec20f30f1155d4f30f114dd8f30f1145dc4889fbf30f118380000000f30f118b84000000f30f119388000000488b7b10e8688eebff4c8db3c0010000488d75e0f30f1045dcf30f1145e0f30f1045d8f30f1145e4f30f1045d4f30f1145e84c89f7e823db0600488bbbb80100004885ff7410f3410f104e08f3410f7e06e87dc804004c8b7308488b7b10e8848debff4983c6084c89f74889c6e8db7709004883c4205b415e5dc3'],
 'weapons': [54772, 4266, '__text', 'sha256:3f2a1241cc0c6a3b727f4b1e1e83eb9328004ecc7ee2d56d85d10163057bf0d3'],
 'extra_story': [51826, 1046, '__text', 'sha256:1335a39e49f4f68f662e67e9c0a9ff1687c9138f7de54ec091cee8875401c351']}
