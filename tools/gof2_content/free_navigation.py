"""Source-bound system routes and pending destination guidance."""
import copy
from .station_exterior import hashed_variants

def extract_free_navigation(mach, arrival):
    variant, proof = hashed_variants(mach, arrival, [LAYOUTS, MAC_ALTERNATE])
    return (copy.deepcopy(VALUES), proof) if proof else ({}, {})

VALUES = {'scope': 'base_system_navigation',
 'gate_station_field': 6,
 'gate_environment_object_index': 1,
 'route_available_neighbors_only': True,
 'route_order': 'fewest_links_catalogue_order',
 'same_station_clears_course': True,
 'pending_story_requires_station_match': True}

LAYOUTS = {'free_navigation_gate_helpers': [735008,
                                  198,
                                  '__text',
                                  '11e02e40be6249192debcba9aa59f983a8cf9d602f2a8fa752167bd6ab280d20'],
 'free_navigation_route_graph': [901582,
                                 608,
                                 '__text',
                                 'bb55274ada1a8550129b329b7ea6c83698e2b3a0e8aef1f0a2b07eb89d3b1363'],
 'free_navigation_route_search': [902190,
                                  430,
                                  '__text',
                                  'e0dfeeaf97af09233927cb7fef8c15440c74ab02e97acef6bc7d7bf85e6ef695'],
 'free_navigation_route_predecessors': [902620,
                                        288,
                                        '__text',
                                        '5f75671173c7b74f220969db6cffd5e39f765417bf856064f25dce7a5af23ff7'],
 'free_navigation_queue_removal': [903154,
                                   98,
                                   '__text',
                                   'e40422fa43431cfcbf0be57cdf4c6f07935d6c2083f05daeaf63247b01a1f234'],
 'free_navigation_course': [137826,
                            368,
                            '__text',
                            '8ebe230813cc8cd35296aae90dfc504736da2d1b626cbe974c863294da00ab1b'],
 'free_navigation_story_selection': [856965,
                                     661,
                                     '__text',
                                     '828a3b7e9c015c71b471542042217d7df0990c47c21c49a3314e9f70e12ce9de']}

# Complete alternate source declarations; no executable payloads.
MAC_ALTERNATE = {'free_navigation_gate_helpers': [735640,
                                  198,
                                  '__text',
                                  'cc29162820c83932b402ad8b45db33e1e8cd78b87a8578f356790dac30e96776'],
 'free_navigation_route_graph': [902214,
                                 608,
                                 '__text',
                                 'b5dbfd8e168182661d5d3684bc9dd7456c60e3dc2371a3d83421b172c9ed3385'],
 'free_navigation_route_search': [902822,
                                  430,
                                  '__text',
                                  'bc835be708a2d2c093da3f829bb79e07097a8dde7b071a76f341bc16869a9106'],
 'free_navigation_route_predecessors': [903252,
                                        288,
                                        '__text',
                                        'f25ecac8dd7e8d7c029bb2e4d0081a7273bbaf510f6a4a45865d56c7f60b7b0b'],
 'free_navigation_queue_removal': [903786,
                                   98,
                                   '__text',
                                   'b812061bca38ffbe01825fc16cf1a7c87efa07b8db5c91da78e9d6a94fbfb7f9'],
 'free_navigation_course': [137826, 368, '__text', '81b37149c3c031ea38ba1364cb4a3cb29c3c32f8fc272912cd2221d95d14c49b'],
 'free_navigation_story_selection': [857597,
                                     661,
                                     '__text',
                                     'c3727ce85e04d68c724295933ac5cc3716f4cdcf350e18558bfd59ee11ea006c']}
