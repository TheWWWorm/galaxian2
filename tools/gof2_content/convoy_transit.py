"""Verified ordinary travel before the convoy story target is selected."""
import copy
from .station_exterior import hashed_declarations

def extract_convoy_transit(mach,arrival):
    proof=hashed_declarations(mach,arrival,LAYOUTS)
    return (copy.deepcopy(VALUES),proof) if proof else ({},{})

VALUES = {'scope': 'mido_convoy_transit',
 'campaign_cursor': 14,
 'system_id': 15,
 'story_kind': 4,
 'story_station_id': 79,
 'story_reward': 0,
 'requires_target_match': True,
 'story_precedes_side_mission': True,
 'retains_side_mission': True,
 'npc_weapon_interval_ms': 572}

LAYOUTS = {'convoy_transit_selection': [856506,
                              1129,
                              '__text',
                              'e3f766995d67858baf291908dc9367266796ae96e6c29cb8c7ff1d87c2bc9f04'],
 'convoy_transit_story_factory': [861385,
                                  38,
                                  '__text',
                                  'ab51b26abc9a675cc574485fe1edef14243bb716e31d08f17fb5734e43518749'],
 'convoy_transit_story_slot': [859544,
                               122,
                               '__text',
                               '0e1548dc4236b4a447747ac3453da996a0e60f5019e81f51aa757bd81957dbcb'],
 'convoy_transit_departure_selection': [428158,
                                        29,
                                        '__text',
                                        '5454c8eb6d87758d902f2748251c82abad08fa1715b891304c4b1ba3bc6d423e'],
 'convoy_transit_departure_state': [431869,
                                    126,
                                    '__text',
                                    'faf79612974e31946653c4d52efa1d5977ea201dc5e3e86d8a07d688248fa066'],
 'convoy_transit_weapon_interval': [57315,
                                    107,
                                    '__text',
                                    '6353c882b18462d64aecbfe0935f84872953e14fbf57c81810fda3a832246ceb']}
