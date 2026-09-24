"""Fresh ordinary player-frame declarations following the first cinematic cut.

Bounded static recognition only: native code owns movement, commands and firing.
"""
import copy
from .declaration_layouts import recognize

VALUES = {'ordinary_phase':4,'postcombat_after_event_finished':10,
          'initial_pitch_units':0,'initial_yaw_units':0,'initial_throttle':1.0,
          'primary_category':0,'primary_requires_living_hull':True,
          'primary_contacts_before_npc':True,'fire_after_camera':True,'response_after_camera':True}


def extract_opening_player_flight(mach, staging, actors, rotation, response):
    arch=mach.architecture
    if arch not in LAYOUTS:return {}
    try:
        if not staging['player_motion'] or staging['player_motion']['release_phase']!=4:return {}
        if not actors['player_initialization'] or not actors['npc_initialization']['initial_firing_allowed']:return {}
        origin=staging['provenance']['initial']['offset']
        layouts=[LAYOUTS[arch]]+([MAC_ALTERNATE] if arch=='x86_64' else [])
        proof=recognize(mach,origin,layouts,{'rotation_anchor':rotation['provenance'][0]['offset'],
                                           'response_anchor':response['provenance'][0]['offset']})
        if not proof:return {}
        result=copy.deepcopy(VALUES);result['provenance']=proof
        return result
    except (KeyError,IndexError,TypeError,ValueError,OverflowError):return {}


LAYOUTS = {'x86_64': {'initial_angular': [429398,
                                20,
                                'c7831803000000000000c7831403000000000000'],
            'ordinary_path': [456905,
                              90,
                              '0f57c041f6869501000001754d41f6861802000001750a41f6861902000001740d4c89f74489e6e88ec1ffffeb29418bb6840100004c89f7e86bc5ffff4c89f7e8f9cdffff0f57c084c0750e4c89f74489e6e86fc7ffff0f57c0'],
            'controller_result': [255595,
                                  24,
                                  '418a5d6b418b7548498bbd98000000e8965afcff4188456b'],
            'input_block': [256619,
                            39,
                            '41f6456c010f85a002000041f6456b010f8595020000498b7d60e839c4020084c00f8584020000'],
            'primary_input': [256713,
                              54,
                              '41f6456801751a41f68558010000017510498bbd88000000e8018df8ff3c017526498b7d60e8f82b030084c07519418b7548498b7d60'],
            'primary_route': [438223,
                              72,
                              '488b3be850a7ffff85c07e3c488b3b4183ff0175268b935c0100004963cebe010000004531c0e82dc1ffff84c07519c7835c010000ffffffffeb0d4963d64489fe31c9e864c0ffff'],
            'primary_call': [256759,
                             23,
                             '418b7548498b7d6031d2e8dfc3020041c685ad01000001'],
            'primary_permission': [420670,
                                   45,
                                   '498b074885c00f84b201000041f687cb000000010f84a401000039300f869c01000085f60f88940100004c63ee'],
            'steering_input': [256994,
                               51,
                               '498bbd88000000e80fd9f8fff30f118500fdffff498bbd88000000e8fbd8f8fff30f598500fdffff4889df4489f6e85a4d0300'],
            'input_release': [17845, 5, '41c6451100'],
            'postcombat_gate': [17889,
                                21,
                                '488b4308488b7850e8c74e080084c00f85b3290000'],
            'player_equipment_before_field': [-165110, 5, 'e85e160000'],
            'initial_normal_modes': [428741,
                                     14,
                                     'c6831802000000c6831902000000'],
            'weapon_groups': [-4221,
                              100,
                              '498b87500100004885c07426833800742131db488b4008488b3cd8488b074489f6ff502048ffc3498b87500100003b1872e1498b87580100004885c07426833800742131db488b4008488b3cd8488b074489f6ff502048ffc3498b87580100003b1872e1'],
            'primary_group': [-55066, 7, '498b9f50010000'],
            'npc_group': [-64431, 7, '498b8e58010000'],
            'rotation_anchor': [442786,
                                24,
                                'f30f10151d9c0f00f30f101d356a0f00f30f100d016a0f00'],
            'response_anchor': [473793,
                                16,
                                'f30f100d4e230f00f30f59c8f30f59cd']},
 'armv7': {'constructor_zero': [384198, 2, '0022'],
           'initial_angular': [384804, 8, 'c4f87822c4f87422'],
           'ordinary_path': [406570,
                             30,
                             '9bf8410170b99bf89c0120b99bf89d01002801f0aa804ff0ff303146ec90'],
           'ordinary_call': [411028,
                             40,
                             'dbf830114ff0ff345846ec94fcf751f95846ec94fcf767fc00287ef44eaf58463146ec94fcf733fa'],
           'controller_result': [264322,
                                 26,
                                 'dbf83c104ff0ff32dbf874009bf85b40b492c2f7cdfd8bf85b00'],
           'input_block': [265248,
                           40,
                           '9bf85c00002840f08f819bf85b00002840f08a81dbf854004ff0ff31b4911ef06aff002840f08081'],
           'primary_input': [265364,
                             44,
                             '9bf8580058b99bf8040140b9dbf86c004ff0ff31b49189f752fe012808d1dbf854004ff0ff34b49423f02dff'],
           'primary_call': [265494, 16, 'dbf83c100022dbf85400b4941ef008ff'],
           'primary_route': [392156,
                             74,
                             '2868fbf7fefc01281cdb2868012e11d1d5f80c214feae87400210094019101214346fcf748fe002804bf4ff0ff30c5f80c0107e000214feae873009131464246fcf7fbfd23b0bde8000d'],
           'primary_permission': [377892,
                                  36,
                                  '2068002800f0948094f8c31000291cbf0168b14240f28c80002ec0f28980406850f82600'],
           'steering_input': [265716,
                              44,
                              'b4948df7eaffdbf86c1040ec180bb49408468df7e2ff40ec300b40462946b49408ff300d10ee102a25f017fc'],
           'input_release': [51176, 4, '86f80da0'],
           'postcombat_gate': [39860,
                               34,
                               '2095042942f0c08560680df500554ff0ff36806ac5f824646ef099ff002803f06284'],
           'player_equipment_before_field': [-160366, 4, '01f058fa'],
           'initial_normal_modes': [384532, 8, '84f89c2184f89d21'],
           'weapon_groups': [-3304,
                             84,
                             'd5f8e40000281cbf016800290dd00024406850f8240001680a6959469047d5f8e400013401688c42f2d3d5f8e80000281cbf016800290dd00024406850f8240001680a6959469047d5f8e800013401688c42f2d3'],
           'primary_group': [-57418, 4, 'daf8e440'],
           'npc_group': [-65644, 4, 'daf8e810'],
           'rotation_anchor': [396128, 12, '9fed9f0a94ed9d1a94ed9e2a'],
           'response_anchor': [419772, 12, '9fed3c2a42f28301c8f20821']}}


# Complete alternate Mac layout, linked to the same native flight contract.
MAC_ALTERNATE = {'initial_angular': [429934, 20, 'c7831803000000000000c7831403000000000000'],
 'ordinary_path': [457441,
                   90,
                   '0f57c041f6869501000001754d41f6861802000001750a41f6861902000001740d4c89f74489e6e88ec1ffffeb29418bb6840100004c89f7e86bc5ffff4c89f7e8f9cdffff0f57c084c0750e4c89f74489e6e86fc7ffff0f57c0'],
 'controller_result': [256107, 24, '418a5d6b418b7548498bbd98000000e89658fcff4188456b'],
 'input_block': [257131,
                 39,
                 '41f6456c010f85a002000041f6456b010f8595020000498b7d60e851c4020084c00f8584020000'],
 'primary_input': [257225,
                   54,
                   '41f6456801751a41f68558010000017510498bbd88000000e85d89f8ff3c017526498b7d60e8102c030084c07519418b7548498b7d60'],
 'primary_route': [438759,
                   72,
                   '488b3be850a7ffff85c07e3c488b3b4183ff0175268b935c0100004963cebe010000004531c0e82dc1ffff84c07519c7835c010000ffffffffeb0d4963d64489fe31c9e864c0ffff'],
 'primary_call': [257271, 23, '418b7548498b7d6031d2e8f7c3020041c685ad01000001'],
 'primary_permission': [421206,
                        45,
                        '498b074885c00f84b201000041f687cb000000010f84a401000039300f869c01000085f60f88940100004c63ee'],
 'steering_input': [257506,
                    51,
                    '498bbd88000000e80fd7f8fff30f118580fcffff498bbd88000000e8fbd6f8fff30f598580fcffff4889df4489f6e87e4d0300'],
 'input_release': [17845, 5, '41c6451100'],
 'postcombat_gate': [17889, 21, '488b4308488b7850e8eb50080084c00f85b3290000'],
 'player_equipment_before_field': [-165110, 5, 'e85e160000'],
 'initial_normal_modes': [429277, 14, 'c6831802000000c6831902000000'],
 'weapon_groups': [-4221,
                   100,
                   '498b87500100004885c07426833800742131db488b4008488b3cd8488b074489f6ff502048ffc3498b87500100003b1872e1498b87580100004885c07426833800742131db488b4008488b3cd8488b074489f6ff502048ffc3498b87580100003b1872e1'],
 'primary_group': [-55066, 7, '498b9f50010000'],
 'npc_group': [-64431, 7, '498b8e58010000'],
 'rotation_anchor': [443322, 24, 'f30f10159d380f00f30f101db5060f00f30f100d81060f00'],
 'response_anchor': [474341, 16, 'f30f100dc2bf0e00f30f59c8f30f59cd']}
