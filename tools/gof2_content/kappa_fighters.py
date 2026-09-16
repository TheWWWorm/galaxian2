"""Original common fighter systems and target rules for Kappa. Constant declarations only."""
import copy
from .station_exterior import hashed_declarations

def extract_kappa_fighters(mach, arrival):
    proof = hashed_declarations(mach, arrival, LAYOUTS)
    return (copy.deepcopy(VALUES), proof) if proof else ({}, {})

VALUES = {'scope': 'kappa_shared_fighters',
 'campaign_cursor': 21,
 'systems': {'capacity_base': 40,
             'capacity_rank_multiplier': 5,
             'capacity_rank_limit': 20,
             'capacity_limit': 140,
             'recovery_ms': 15000,
             'subtype': 0},
 'frame': {'recover_before_guidance': True,
           'disabled_root_commit': False,
           'disabled_bank_commit': True,
           'disabled_fire_permission_unchanged': True},
 'player_weapon_targets': [0, 1, 2, 3],
 'npc_target_memberships': [[-1], [-1], [-1], [-1]],
 'initial_permanent_friendly': False,
 'holding_proximity_requires_hostile': True,
 'holding_target_requires_hostile': False}

LAYOUTS = {'kappa_fighters_shared_factory': [77944,
                                   3478,
                                   '__text',
                                   '9b9cfd3e564cc131a926a3f0704be2479fa2ee4dcf4c291e129e904aeb57b6cb'],
 'kappa_fighters_systems_initializer': [535708,
                                        56,
                                        '__text',
                                        '7c85d69e72f18b7e78f0404ce332caeaca256f015bf3a86f9d14b7960ddcd565'],
 'kappa_fighters_systems_update': [612681,
                                   60,
                                   '__text',
                                   '585d38a86569b81d4cab6b125481de2a8749e359230c58262972701a4a539f31'],
 'kappa_fighters_disabled_motion': [624443,
                                    343,
                                    '__text',
                                    '629675ac35d3387047990cf413f3627ee0ce94ded5469b9a708dc0a3cdc1fffa'],
 'kappa_fighters_target_membership': [59038,
                                      2050,
                                      '__text',
                                      '4833480cd77d57fc971f51b26224e7efefb74b6b8a57d1c39189d721590857b4'],
 'kappa_fighters_fire_gate': [542670,
                              494,
                              '__text',
                              '1524de7b46cd99cf11da37ba8789e0a9af95817673b0a97ccb833cfd9056b98a'],
 'kappa_fighters_holding_activation': [617194,
                                       408,
                                       '__text',
                                       'f5a02ad7d2dfc307d9503438c215abf4fdcc367aeec409d5348950ce348e9af2'],
 'kappa_fighters_target_activation': [619682,
                                      255,
                                      '__text',
                                      '309bfefc706d25eff4b1682ced9c37c2de44c1388ded4870ccf316538bfa261d']}
