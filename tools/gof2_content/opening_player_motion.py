"""Recognize the fresh opening scripted player-flight declarations.

Static bounded readers emit constants/extents only. This motion precedes weapon
contacts and scripted placement; the first ordinary handoff is its scope limit.
"""
import copy
from .declaration_layouts import recognize

VALUES = {'initial_scripted_flight':True,'scripted_ignores_throttle':True,
          'ordinary_motion_suppressed':True,'initial_update_enabled':True,
          'release_after_event_finished':8,'release_phase':4,
          'motion_before_controller':True}


def extract_opening_player_motion(mach, staging, camera, cruise, actors):
    arch=mach.architecture
    if arch not in LAYOUTS:return {}
    try:
        if not actors['player_initialization'] or not camera or cruise['speed_units_per_millisecond']!=2.0 or cruise['forward_axis']!=[0,0,1]:return {}
        if camera['pan']['follow_player_after_event_finished']!=VALUES['release_after_event_finished']:return {}
        initial=staging['provenance']['initial']
        if initial['bytes']!=(366 if arch=='x86_64' else 320):return {}
        origin=initial['offset']
        layouts=[LAYOUTS[arch]]+([MAC_ALTERNATE] if arch=='x86_64' else [])
        proof=recognize(mach,origin,layouts,{'speed':cruise['provenance'][0]['offset'],
                                           'forward_helper':cruise['provenance'][3]['offset']})
        if not proof:return {}
        result=copy.deepcopy(VALUES);result['provenance']=proof
        return result
    except (KeyError,ValueError,TypeError,IndexError,OverflowError):return {}


LAYOUTS = {'x86_64': {'player_before_weapons': [244328,
                                      40,
                                      'e804200300498b7d60e875ef020088c349637548498bbd90000000410fb6556b83e201e89933fcff'],
            'controller_call': [255610, 5, 'e8965afcff'],
            'player_delta': [449268, 7, '4589a684010000'],
            'initial_scripted': [65, 18, 'e8e9c0ffff4889c7be01000000e8f2b70600'],
            'scripted_setter': [440389, 13, '554889e54088b7880200005dc3'],
            'initial_update_enabled': [428577, 4, 'c6434000'],
            'update_gate': [449205, 11, '41f64640010f8579350000'],
            'scripted_gate': [454099,
                              68,
                              '418a868202000041f68688020000017512a801750e41f68681020000010f848e0000004c89ad60fbffff41c6869501000001a801740e418b868401000041018684020000'],
            'scripted_travel': [454167, 23, 'f3410f2ac4f3410f5986f8000000498b7e10e8192eecff'],
            'ordinary_suppression': [456905, 13, '0f57c041f6869501000001754d'],
            'release': [17756,
                        46,
                        '488b7840e8504f08003c010f856e2b000049c785a00000000000000041c74528040000004c89ff31f6e8bb720600'],
            'speed': [429564, 27, 'c783f8000000000000404c8d35cad01c00c783fc0000000000803f'],
            'forward_helper': [-844729,
                               42,
                               '554889e54156534881ec80000000f30f1145804889fb8b7314488b7b38e8a6cb1c004889c7e8bef71d00']},
 'armv7': {'player_before_weapons': [253418,
                                     40,
                                     '23f096fedbf854004ff0ff36b49621f095fcdbf83c1005469bf85b30dbf87000ca17b496c1f7e0f9'],
           'controller_call': [264340, 4, 'c2f7cdfd'],
           'player_delta': [400308, 4, 'cbf83061'],
           'initial_scripted': [26, 16, 'fcf7c0ff0121cdf85068012560f0cef9'],
           'scripted_setter': [394182, 6, '80f8f0117047'],
           'constructor_zero': [384198, 2, '0022'],
           'initial_update_enabled': [384452, 4, '84f82420'],
           'update_gate': [400264, 10, '9bf82400002842f0f384'],
           'scripted_gate': [404284,
                             60,
                             '9bf8ea019bf8f011002907d0cdf828a0c2468bf84141002809d10fe0002800f08b810120cdf828a0c2468bf84101dbf83001dbf8ec110844cbf8ec01'],
           'scripted_travel': [404344, 36, '46ec306b9bed2e0afbff2006dbf8080009964ff0ff36ec9600ff900d10ee101a7af641fb'],
           'ordinary_suppression': [406570, 6, '9bf8410170b9'],
           'release': [51082,
                       48,
                       '006ac4f824546cf0b7f9012877f45da8219e0df5005b04200021c6f88ca0c6f890a0b061cbf824541d9c204653f006fe'],
           'speed': [384956, 20, '4ff07e50d1f800a04ff08041c4f8b810c4f8bc00'],
           'forward_helper': [-1191394,
                              36,
                              'f0b503af2ded028b99b004460d46e168e06ad8f297f904ae01463046e4f2f2fa07a83146']}}


# One coherent Mac compiler layout; all frame/flag links retain the same contract.
MAC_ALTERNATE = {'player_before_weapons': [244051,
                           40,
                           'e831230300498b7d60e8a2f2020088c349637548498bbd90000000410fb6556b83e201e8ae34fcff'],
 'controller_call': [256122, 5, 'e89658fcff'],
 'player_delta': [449804, 7, '4589a684010000'],
 'initial_scripted': [65, 18, 'e8e9c0ffff4889c7be01000000e80aba0600'],
 'scripted_setter': [440925, 13, '554889e54088b7880200005dc3'],
 'initial_update_enabled': [429113, 4, 'c6434000'],
 'update_gate': [449741, 11, '41f64640010f8579350000'],
 'scripted_gate': [454635,
                   68,
                   '418a868202000041f68688020000017512a801750e41f68681020000010f848e0000004c89ad60fbffff41c6869501000001a801740e418b868401000041018684020000'],
 'scripted_travel': [454703, 23, 'f3410f2ac4f3410f5986f8000000498b7e10e8f914ecff'],
 'ordinary_suppression': [457441, 13, '0f57c041f6869501000001754d'],
 'release': [17756,
             46,
             '488b7840e8745108003c010f856e2b000049c785a00000000000000041c74528040000004c89ff31f6e8d3740600'],
 'speed': [430100, 27, 'c783f8000000000000404c8d358a761c00c783fc0000000000803f'],
 'forward_helper': [-850625,
                    42,
                    '554889e54156534881ec80000000f30f1145804889fb8b7314488b7b38e816d81c004889c7e89ef21d00']}
