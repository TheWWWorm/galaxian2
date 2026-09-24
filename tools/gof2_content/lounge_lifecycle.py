"""Original station contact retention declarations; no executable payloads."""
import copy
from .station_exterior import hashed_variants

def extract_lounge_lifecycle(mach, arrival):
    variant, proof = hashed_variants(mach, arrival, [LAYOUTS, MAC_ALTERNATE])
    return (copy.deepcopy(VALUES), proof) if proof else ({}, {})

VALUES = {'scope': 'mido_station_contact_retention',
 'capacity': 3,
 'replacement_order': 'oldest_insertion',
 'revisit_changes_order': False,
 'cached_quotes_repriced': False}

LAYOUTS = {'lounge_lifecycle_lookup': [855620,
                             94,
                             '__text',
                             'c0d3d6470d2a216e541fa40be17cf149457ed934732ab86fcd178706999a9c71'],
 'lounge_lifecycle_insert': [855396,
                             204,
                             '__text',
                             '0ce00eb70d5f06a74ae433d45fe868450495fbf297b6f11e21d6f9ab7f17c156'],
 'lounge_lifecycle_identity': [853288,
                               22,
                               '__text',
                               '88fd654fbe9f154dc3b1abf97b31858eb99c0710a7cb258faaef2c2e729145e5'],
 'lounge_lifecycle_current': [855731,
                              20,
                              '__text',
                              '78e1d8a7f54623b2f8a5e2dfd47a2f42e0914eb00da9b459f0e006eece7e8f3d'],
 'lounge_lifecycle_arrival': [856712,
                              38,
                              '__text',
                              'ccd6d97ab4b1eadfad7e96be2be4423bbd2b875d36f0862c2fbc56e0545a5840'],
 'lounge_lifecycle_generation': [856903,
                                 62,
                                 '__text',
                                 'a919260095d71f8c4534bb53e3b48ef710a6345b9655e88be7837f16de662f75'],
 'lounge_lifecycle_ordinary_stock': [857285,
                                     83,
                                     '__text',
                                     'c8e00ef311f21c2bf0afdb53e2d4bd92963160b40f4f0b826111220625142833']}

# Complete alternate source declarations; no executable payloads.
MAC_ALTERNATE = {'lounge_lifecycle_lookup': [856252,
                             94,
                             '__text',
                             'c0d3d6470d2a216e541fa40be17cf149457ed934732ab86fcd178706999a9c71'],
 'lounge_lifecycle_insert': [856028,
                             204,
                             '__text',
                             '67faa79fa1691433c82f19d43f6fa76bcd0226ad76621ea47a97a8f2fb7069ad'],
 'lounge_lifecycle_identity': [853920,
                               22,
                               '__text',
                               '88fd654fbe9f154dc3b1abf97b31858eb99c0710a7cb258faaef2c2e729145e5'],
 'lounge_lifecycle_current': [856363,
                              20,
                              '__text',
                              '78e1d8a7f54623b2f8a5e2dfd47a2f42e0914eb00da9b459f0e006eece7e8f3d'],
 'lounge_lifecycle_arrival': [857344,
                              38,
                              '__text',
                              'ccd6d97ab4b1eadfad7e96be2be4423bbd2b875d36f0862c2fbc56e0545a5840'],
 'lounge_lifecycle_generation': [857535,
                                 62,
                                 '__text',
                                 '4d8edfd57b9e8badda8bda8e09314b55db4ffb799695355ba499a61328209980'],
 'lounge_lifecycle_ordinary_stock': [857917,
                                     83,
                                     '__text',
                                     '62a30a490ae85b9b327ecb4b6dc76b36f4410f874d64e62009ff5051d839ffe4']}
