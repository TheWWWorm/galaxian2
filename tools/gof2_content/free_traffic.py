"""Verified ordinary ship setup declarations, independent of travel permission."""
import copy
from .station_exterior import hashed_declarations

def extract_free_traffic(mach, arrival):
    proof=hashed_declarations(mach, arrival, LAYOUTS)
    return (copy.deepcopy(VALUES), proof) if proof else ({}, {})

VALUES = {'scope': 'augmenta_ordinary_ship_setup',
 'campaign_cursor': 18,
 'opposition': {'exclusive_factions': [8, 9, 10], 'pairs': [[0, 1], [2, 3]]},
 'nivelian_boxes': [{'offset': [0, -85, 24], 'half_extents': [2167.5, 622.5, 5440]},
                    {'offset': [0, 710, 292], 'half_extents': [1495, 467.5, 5725]},
                    {'offset': [0, 1510, -2886], 'half_extents': [1375, 505, 1375]}]}

LAYOUTS = {'free_traffic_nivelian_boxes': [80500,
                                 278,
                                 '__text',
                                 '3f39eead7833aafc377395e5e9d332e0fc6d64d35efd1616ae9e81de803e5b1e'],
 'free_traffic_box_values': [1575482,
                             48,
                             '__const',
                             '61005225e16dba67c95d8c35984042cdcb6dcd0f7aa44a275b19ceefc6439e92'],
 'free_traffic_opposition': [614052,
                             268,
                             '__text',
                             'f0cef08b7978855b3ee22bba5d5a57afc0ee7e8dee6bc4d433771050e68717af']}
