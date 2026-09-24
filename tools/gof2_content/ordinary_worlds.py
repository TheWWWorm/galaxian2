"""Original special-planet selection guard; no executable payload."""
import copy
from .station_exterior import hashed_variants

def extract_ordinary_worlds(mach, arrival):
    variant, proof = hashed_variants(mach, arrival, [LAYOUTS, MAC_ALTERNATE])
    return (copy.deepcopy(VALUES), proof) if proof else ({}, {})

VALUES = {'scope': 'ordinary_world_planet_guard',
 'special_planets': {'station_ids': [120, 126, 130, 132], 'size_units': 26000}}

LAYOUTS = {'ordinary_world_special_planet': [872426,
                                   80,
                                   '__text',
                                   '1a698012e1d64fe9f8b90dc3981140a3db6c10f9d9e30979020a9bcf1aa84051'],
 'ordinary_world_station_equality': [853288,
                                     22,
                                     '__text',
                                     '88fd654fbe9f154dc3b1abf97b31858eb99c0710a7cb258faaef2c2e729145e5'],
 'ordinary_world_station_id': [851352,
                               10,
                               '__text',
                               'eba6838af910ef1073f4aee9812ff89c920b16bd09dfcad38577c3aa80965a9c'],
 'ordinary_world_special_size': [843373,
                                 59,
                                 '__text',
                                 '2d207244eadace0eff8dea57bcd9b618a200450435b70a6f5d28d9cf38a094a9']}

# Complete alternate source declarations; no executable payloads.
MAC_ALTERNATE = {'ordinary_world_special_planet': [873058,
                                   80,
                                   '__text',
                                   '1a698012e1d64fe9f8b90dc3981140a3db6c10f9d9e30979020a9bcf1aa84051'],
 'ordinary_world_station_equality': [853920,
                                     22,
                                     '__text',
                                     '88fd654fbe9f154dc3b1abf97b31858eb99c0710a7cb258faaef2c2e729145e5'],
 'ordinary_world_station_id': [851984,
                               10,
                               '__text',
                               'eba6838af910ef1073f4aee9812ff89c920b16bd09dfcad38577c3aa80965a9c'],
 'ordinary_world_special_size': [844005,
                                 59,
                                 '__text',
                                 '4cd7326a3141bf7a8127f4b343b8172a2ee6033ec0a645a6bdbb5962ac34e1fe']}
