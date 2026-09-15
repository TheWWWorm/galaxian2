"""Static ordinary-entry declarations; native owners supply the implementation."""
import copy
from .station_exterior import hashed_declarations

def extract_free_flight(mach, arrival):
    proof=hashed_declarations(mach, arrival, LAYOUTS)
    return (copy.deepcopy(VALUES), proof) if proof else ({}, {})

VALUES = {'scope': 'augmenta_ordinary_entry',
 'campaign_cursor': 18,
 'initial_station_id': 98,
 'system_id': 19,
 'departure_flags': {'special_arrival': False, 'void_encounter': False},
 'special_confirmation_cursor': 48,
 'launch_clear_after_ms': 7000,
 'launch_clear_strict': True}

LAYOUTS = {'free_flight_convoy_clear': [155626,
                              87,
                              '__text',
                              '5ccf57b90171b3d1d0cdfe576225e6277f0efcc000a6abd7432a3e1eb7bdc9fb'],
 'free_flight_scene_clear': [134971,
                             325,
                             '__text',
                             '678d44de94a695c4df67086eebff6a7bcbe69a33f16408d72f0aec169a3ac839'],
 'free_flight_confirmation': [431803,
                              192,
                              '__text',
                              'd407d883511072a7ba2e782a90fb2841d647c7d3347502ffedf9a292f2382789'],
 'free_flight_launch_clear': [151066,
                              205,
                              '__text',
                              '92ca533c64ea68b6bff6b630f02a7c9d7ee8f87bf60f192e20e2a0b0325e1ea4'],
 'free_flight_ordinary_dispatch': [152236,
                                   50,
                                   '__text',
                                   'af22ec2ec52120661d0ffef3d141992d7b35f64e7308f256c821185cb785abed']}
