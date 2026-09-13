"""Mac second-trip NPC control declarations; no original runtime code is emitted."""
import copy,hashlib
from .station_exterior import declaration_bytes

def extract_full_hold_control(mach,arrival,pirate,actors):
    if mach.architecture!='x86_64':return {}
    try:
        if pirate['scope']!='full_hold_pirate_combat':return {}
        npc=actors['npc_initialization']
        if not all(npc.get(k) for k in ['guidance','flight','holding','routes','construction','hostility']):return {}
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

VALUES = {'scope': 'full_hold_pirate_control',
 'campaign_cursor': 4,
 'actor_id': 0,
 'actor_kind': 8,
 'hull_catalogue_id': 2,
 'player_ship_id': 0,
 'player_target_count': 1,
 'retains_generated_route': True,
 'holding_selects_player': True,
 'initial_model_draw_enabled': True,
 'initial_node_draw_requested': True,
 'held_node_draw_requested': False,
 'active_node_draw_requested': True,
 'activation_world_flag': False,
 'proximity_before_mode_dispatch': True,
 'target_activation_defers_flight': True,
 'alternate_player_position_for_proximity': True,
 'proximity_replaces_same_pass_steering_vector': True,
 'firing_range_uses_target_statistics': True}

LAYOUTS = {'npc_update': [610766,
                17180,
                '__text',
                'sha256:ebf68b2b6ca047e083dacda1f7f7b6c9bd44140189540f8b670a9489112ee495'],
 'npc_constructor': [605172,
                     2562,
                     '__text',
                     'sha256:9872cce6e7b565f4b3dbeb762598ade1997e62a1d03100f33cfc538edab0800b'],
 'membership': [59038,
                2050,
                '__text',
                'sha256:4833480cd77d57fc971f51b26224e7efefb74b6b8a57d1c39189d721590857b4'],
 'merge_targets': [536398,
                   334,
                   '__text',
                   '554889e5415741564155415453504989f74989fe49837e78000f8415010000bf18000000e8b5520f004989c4bf08000000e8a2520f00498944240841c74424100100000048c7000000000041c7042400000000498b4e7831f6833900743e31db488b49084c8b2cd9ffc6418974241048c1e6034889c7e877530f00498944240848ffc3418b0c244c892cc8418b74241041893424498b4e783b1972c441833f00743b31db498b4f084c8b2cd9ffc6418974241048c1e6034889c7e833530f00498944240848ffc3418b0c244c892cc8418b74241041893424413b1f72c74c89f74c89e6e878fdffff4d85e47425498b7c24084885ff7405e8d0510f004c89e74883c4085b415c415d415e415f5de9c0510f004883c4085b415c415d415e415f5dc34989c64c89e7e8a6510f004c89f7e8da510f004c89f74c89fe4883c4085b415c415d415e415f5de913fdffff90'],
 'assign_targets': [535982,
                    246,
                    '__text',
                    '554889e5415741564154534989f64989fc4d8b7c24784d85ff7416498b7f084885ff7405e843540f004c89ffe841540f0049c7442478000000004d85f67441bf18000000e835540f004989c7bf08000000e822540f004989470841c747100100000048c7000000000041c707000000004d897c24784c89f74c89fee8b4250000498b04244885c07451833800744c4531f64d63fe488b48084a8b0cf94885c9743131db833900742a488b4908488b3cd94885ff740e498b742478e8fbf2f4ff498b0424488b48084a8b0cf948ffc33b1972d641ffc6443b3072b75b415c415e415f5dc34889c34c89ffe884530f004889dfe8b8530f00'],
 'player_constructor': [549940,
                        3862,
                        '__text',
                        'sha256:371a2b68bd0f8fe679486e63a980898adec8d0747b424f98de0bb63ee2b525db'],
 'alternate_body_test': [558742, 18, '__text', '554889e54883bf00020000000f95c05dc390'],
 'alternate_body': [604878, 14, '__text', '554889e5488b87b80000005dc390'],
 'alternate_model': [905094, 10, '__text', '554889e5488b47085dc3'],
 'model_position': [-724356, 26, '__text', '554889e58b7714488b7f38e82ed21c004889c75de9a5fe1d0090'],
 'model_constructor': [-725444,
                       430,
                       '__text',
                       '554889e5415741564154534189cc4989d64189f74889fbc783a000000000000000c783a400000000000000c783a800000000000000c783ac0000000000803f48c783b80000000000000048c783b000000000000000c783c00000000000803f488d732048c783cc0000000000000048c783c400000000000000c783d40000000000803fc783d800000000000000c783dc0000000000803fc783e00000000000803fc783e40000000000803f6644897b104c897338c7431400000000c74320000000004c89f7e824cd1c00488d5324410fb6cc4c89f74489fee8d1991c008b73208b53244c89f7e8c3d01c00c7434800000000c7434400000000c7434000000000c743540000803fc743500000803fc7434c0000803fc6435801c6435901c7435c0000000048c7839800000000000000c743300000000048c783880000000000000048c783800000000000000048c743780000000048c743700000000048c74368000000008b7320897314c74328ffffffffc7431cffffffffc74318ffffffffc7432cffffffff4c89f7e8f0d41c00488dbbac0000004889c6e821f31d0048c74308000000005b415c415e415f5dc3'],
 'model_request': [-722468, 14, '__text', '554889e540887758408877595dc3'],
 'model_submission': [-722442, 28, '__text', '554889e5f647580175025dc38b7714488b7f3831d25de9a9801c0090'],
 'target_alive': [540880, 16, '__text', '554889e583bf80000000000f9ec05dc3'],
 'target_activity': [540924, 14, '__text', '554889e58a87c800000024015dc3'],
 'force_route': [535610, 14, '__text', '554889e58a87fa00000024015dc3']}
