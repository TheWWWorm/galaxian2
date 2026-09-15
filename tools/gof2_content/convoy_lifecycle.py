"""Convoy-specific ordinary ship lifecycle declarations, import only."""
import copy
from .station_exterior import hashed_declarations

def extract_convoy_lifecycle(mach,arrival):
    proof=hashed_declarations(mach,arrival,LAYOUTS)
    return (copy.deepcopy(VALUES),proof) if proof else ({},{})

VALUES = {'scope': 'mido_convoy_ship_lifecycle',
 'campaign_cursor': 14,
 'terran_hostility': {'actor_kind': 0,
                      'axis': 0,
                      'hostile_below': -70,
                      'friendly_above': 70},
 'capital_death': {'model_id': 18304,
                   'model_resource': 'resources/data/assets/main/3d/meshes/ships/battleship_terran_explosion_anim.aem',
                   'initial_material_id': 34716,
                   'wreck_material_id': 33356,
                   'wreck_layout_id': 0,
                   'capital_kills_delta': 1,
                   'medal_id': 39,
                   'attached_damage': 9999999,
                   'attached_actor_ids': []}}

LAYOUTS = {'convoy_lifecycle_factory_death_model': [79935,
                                          13,
                                          '__text',
                                          'c186282b99e10a72c52674b261cfb64da1970de2f9456f9c0cf094d0b93b3f03'],
 'convoy_lifecycle_death_model_context': [633586,
                                          336,
                                          '__text',
                                          '60031382ce306285da9f4ea5978465bf1295001c511d16e7ae77f2e8c9d07fe7'],
 'convoy_lifecycle_capital_death_effects': [634134,
                                            4064,
                                            '__text',
                                            '1e9e3720758477dd246383e87b80ea89bc8a9cdba7cd5e597538605c9f146449'],
 'convoy_lifecycle_default_attachment': [-81548,
                                         948,
                                         '__text',
                                         'f12861749d41ef2ca9eac32cd4814ba5a3e3e9b12d3d34206d636457a5c0835e'],
 'convoy_lifecycle_small_ship_constructor': [605172,
                                             2562,
                                             '__text',
                                             '9872cce6e7b565f4b3dbeb762598ade1997e62a1d03100f33cfc538edab0800b'],
 'convoy_lifecycle_large_ship_constructor': [631244,
                                             1108,
                                             '__text',
                                             '39596638f6c7393a8e4af981e4162d2f1ffeb8e3f51bf20045112a50014d0da6'],
 'convoy_lifecycle_hostility': [807440,
                                128,
                                '__text',
                                '209daf40d4ec5e88c1313c37445ee4a0ef33d73404653b3a058a617a037fae4d'],
 'convoy_lifecycle_friendliness': [807568,
                                   128,
                                   '__text',
                                   'a32c7ef7f73abed32663bdf810d8affba26b4f3c3dccb168afc7abfaa939f8ed']}
