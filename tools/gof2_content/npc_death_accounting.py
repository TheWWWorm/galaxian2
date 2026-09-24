"""Static attribution and counter deltas for the opening hostile kind-8 deaths.

The declaration describes changes only. It does not invent initial world/save
counter values, achievement status, mission completion, cargo or rewards.
"""
import copy
from .opening_npc_guidance import LAYOUTS as GUIDANCE
from .declaration_layouts import recognize

VALUES = {
    'actor_kind':8, 'initial_nonplayer_kill':False,
    'nonplayer_flag_on_lethal_hit':True, 'credit_on_destruction_start':True,
    'requires_hostile':True, 'hostile_remaining_delta':-1,
    'hostile_deaths_delta':1, 'world_player_kills_delta':1,
    'world_other_kills_delta':1, 'player_kills_delta':1,
    'pirate_kills_delta':1,
}


def extract_npc_death_accounting(mach, actors, weapons):
    arch=mach.architecture
    if arch not in LAYOUTS:return {}
    try:
        npc=actors['npc_initialization']
        if not npc['destruction'] or not npc['hostility'] or not npc['primary_weapon']:return {}
        if [row['actor_kind'] for row in actors['actors']]!=[8,8,8]:return {}
        selection=npc['guidance']['provenance']['selection']
        _,relative,size,_=GUIDANCE[arch]['selection']
        if selection['bytes']!=size:return {}
        origin=selection['offset']-relative
        # Separate dependencies must point at the same hit and statistics owners.
        links={'hit_argument':weapons['ordinary_hit_policy']['provenance']['normal_hit']['offset'],
               'initial_attribution':npc['provenance']['stats_entry']['offset']+(0x2f9 if arch=='x86_64' else 0x20c)}
        layouts=[LAYOUTS[arch]]+([MAC_ALTERNATE] if arch=='x86_64' else [])
        proof=recognize(mach,origin,layouts,links)
        if not proof:return {}
        value=copy.deepcopy(VALUES);value['provenance']=proof
        return value
    except (KeyError,ValueError,TypeError,IndexError,OverflowError):return {}


# Compiler recognizers are import-time only; executable bytes never enter packs.
LAYOUTS = {'x86_64': {'initial_attribution': [-75841, 4, 'c6434800'],
            'hit_argument': [-71830,
                             82,
                             '554889e54157415641554154534883ec18894dd44189f64989fc41f68424ca000000010f84fe06000041f68424c8000000010f84ef0600004183bc2480000000000f8ee006000084d28955d00f858b040000'],
            'lethal_attribution': [-70390,
                                   38,
                                   '85d28b45d00f8ffe00000041c7842480000000000000003c01750b41c644244801e9e3000000'],
            'death_guard': [7251, 28, '4585e40f8fe1050000418b86bc00000083c0fd83f8020f82ce050000'],
            'hostile_kind': [7681, 32, '498b4608f64060010f84e0010000418b4e4483f909742783f9080f85b5000000'],
            'pirate_credit': [7713, 30, 'f64048010f85a7010000488d0582cb1b00488b38e804ef0300e993010000'],
            'world_call': [8146, 29, '418bb6e0000000498b4608498b7e780fb6504883e201e8532ef8ffeb20'],
            'world_counters': [-504241,
                               44,
                               '4989fe41ff8eb801000041ff86cc01000084d20f85db030000488d1d459b2300488b3be895be0b0041ff4628'],
            'other_counter': [-503229, 4, '41ff4624'],
            'player_counter': [265484, 26, '554889e5ff8750020000488d05c7dd1700488b385de9588de7ff'],
            'pirate_counter': [265534, 26, '554889e5ff8768020000488d0595dd1700488b385de93a8de7ff']},
 'armv7': {'initial_attribution': [-59644, 26, '002001214ff0ff35c6f8d00086f8701004acc6f80c1186f84400'],
           'hit_argument': [-56288,
                            66,
                            'f0b503af2de9000dadf1100424f00f04a54604f9ef8a84b00446984694f8c20092468b4600281cbf94f8c000002800f06682a06f0128c0f26282baf1000f40f08781'],
           'lethal_attribution': [-55290, 22, 'a16f002960dc0020baf1010fa0670cd1012084f84400'],
           'death_guard': [5132, 18, '002d00f3e382daf8840003380228c0f0dd82'],
           'hostile_kind': [5630, 24, 'daf8040090f85c10002956d0daf82410cdf8d480092968d1'],
           'pirate_credit': [5864, 32, '08290dd190f84400002840f0818037984ff0ff310068cdf8a0183ff047fd77e0'],
           'world_call': [6136, 28, 'daf804204ff0ff33daf85000daf8a81092f84420cdf8a03892f74efa'],
           'world_counters': [-443192,
                              66,
                              '0446002ad4f81801a0f10100c4f81801d4f82c0100f10100c4f82c0103d0206a0130206267e143f29a40c0f228007844d0f800b0dbf80000adf032fa606a01306062'],
           'player_counter': [266600, 28, '46f25001c0f21d01d0f8ac2179440132c0f8ac210968086832f6e6b9'],
           'pirate_counter': [266644, 28, '46f22401c0f21d01d0f8c42179440132c0f8c4210968086832f6d4b9']}}


# Independently verified alternate Mac compiler layout.
MAC_ALTERNATE = {'initial_attribution': [-75853, 4, 'c6434800'],
 'hit_argument': [-71842,
                  82,
                  '554889e54157415641554154534883ec18894dd44189f64989fc41f68424ca000000010f84fe06000041f68424c8000000010f84ef0600004183bc2480000000000f8ee006000084d28955d00f858b040000'],
 'lethal_attribution': [-70402, 38, '85d28b45d00f8ffe00000041c7842480000000000000003c01750b41c644244801e9e3000000'],
 'death_guard': [7251, 28, '4585e40f8fe1050000418b86bc00000083c0fd83f8020f82ce050000'],
 'hostile_kind': [7681, 32, '498b4608f64060010f84e0010000418b4e4483f909742783f9080f85b5000000'],
 'pirate_credit': [7713, 30, 'f64048010f85a7010000488d0536711b00488b38e858ef0300e993010000'],
 'world_call': [8146, 29, '418bb6e0000000498b4608498b7e780fb6504883e201e82f2cf8ffeb20'],
 'world_counters': [-504789,
                    44,
                    '4989fe41ff8eb801000041ff86cc01000084d20f85db030000488d1d1d432300488b3be80dc10b0041ff4628'],
 'other_counter': [-503777, 4, '41ff4624'],
 'player_counter': [265568, 26, '554889e5ff8750020000488d052f831700488b385de9d873e7ff'],
 'pirate_counter': [265618, 26, '554889e5ff8768020000488d05fd821700488b385de9ba73e7ff']}
