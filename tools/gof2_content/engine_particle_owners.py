"""Optional normal player-exhaust ownership declarations.

The original nozzle art and emitter presets remain in engine_particles. This
reader recognizes bounded manager and flag declarations; only data and source
extents leave the reader, never executable bytes or a boost implementation.
"""
import copy

from .declaration_layouts import recognize
from .engine_particles import VALUES as NOZZLES, OPENING_SHIP, OPENING_SPANS
from .station_exterior import declaration_bytes


VALUES = {
    'scope': 'mac_betty_normal_engine_owner',
    'ship_id': 0,
    'nozzle_count': 4,
    'first_preset': 29,
    'pose': 'player_statistics',
    'manager_velocity_interval_ms': 10,
    'initial_engine_enabled': True,
    'initial_player_hidden': False,
    'initial_draw_enabled': True,
    'manager_updates_when_hidden': True,
    'engine_flag_controls_emission': True,
    'engine_flag_controls_draw': True,
    'hidden_flag_controls_emission': False,
    'manager_hide_resets_emitters': False,
    'entry_engine_enabled': False,
    'mining_capture_engine_enabled': False,
    'mining_release_engine_enabled': True,
    'death_engine_enabled': False,
    'revive_engine_enabled': True,
    'boost_available': False,
}

# Complete, independently reviewed source layouts. All values are relative to
# the existing arrival actor declaration in the same executable.
LAYOUTS = {'manager_initial_flags': [509330,
                           46,
                           '__text',
                           'sha256:91ee7282ac16a8103c2b2563577d8cf721dc44f0eb38b72e6bcc16063c75d6bd'],
 'player_initial_flags': [551167,
                          14,
                          '__text',
                          'sha256:6e90138b59ebc6d5ecdf13f18e3ae9e11a04a20675e3e0f308a9761097b397fe'],
 'world_update': [118201,
                  82,
                  '__text',
                  'sha256:519dbb2e6b217ddf204845927e3246d336783f979e91e1e4461b4d5b751fa867'],
 'world_draw': [110499,
                17,
                '__text',
                'sha256:5c235837a4c4a9e888c0b332f65d2d663bf090449175c10490bbfe84806d9edd'],
 'manager_update': [510392,
                    314,
                    '__text',
                    'sha256:a36aab1e7e2f45e8823fa495c7fcb14ead393622a6d0f698ad5dc2ac53b6eccc'],
 'manager_draw': [512192,
                  56,
                  '__text',
                  'sha256:bb2bc79515512c7199c7623bb2e95432112569133d5a985616e2e47b5439d671'],
 'engine_enable': [555592,
                   112,
                   '__text',
                   'sha256:ecd9c44318fca15a398aeafeed4e4774c67020b9012aca2dd2855533e7cb72d3'],
 'manager_emitting': [511634,
                      52,
                      '__text',
                      'sha256:b32c63ae03ff1f1affcfe67c599b1bf9bc6709cef81208038459d32ba6a2103c'],
 'emitting_flag': [514238,
                   32,
                   '__text',
                   'sha256:4ce2bcd7bcb2d89038e1c0ebff7bf12818cc1b1a6b117d6c9b8a05ab6f70c553'],
 'player_hidden': [603252,
                   54,
                   '__text',
                   'sha256:91d1d1092bf66dba09777c69209726c46545a0a9b6adf5db1825ff6f8c95fb7a'],
 'entry_disable': [122627,
                   15,
                   '__text',
                   'sha256:72a4909a86e371c5fdcb873a4dfa51286124dcaa428de71450651ab0f1eda7aa'],
 'arrival_disable': [380838,
                     16,
                     '__text',
                     'sha256:d5fc672cc3fe6060945a2d038eab92b0287c446b76beb502386136ee13fa3c73'],
 'mining_cancel_enable': [586859,
                          23,
                          '__text',
                          'sha256:195ff9a43d6c8ea6f63ff3ba624257d6c1008a7cbff8f20ee039ca971cc591cb'],
 'mining_capture_disable': [587571,
                            15,
                            '__text',
                            'sha256:a4d7517af63bdd6f357f0ebc10beeabf5d1f7fdc4a82168ef0312c98ebb10a1b'],
 'mining_release_enable0': [589591,
                            21,
                            '__text',
                            'sha256:a907dc0b1e8f2bd2125027f9570d1ed49a156c05477ff6c9fbfb58518f0887a7'],
 'mining_release_enable1': [589894,
                            25,
                            '__text',
                            'sha256:acfee01e240820276c683c221c9a7dc68888e27b65705d1e3b48624fc01f9db4'],
 'death_disable': [600188,
                   19,
                   '__text',
                   'sha256:bac83a67eac7e6b1bad1850f013c33e4846f3da8218c678426633161cdd20289'],
 'revive_enable': [600403,
                   18,
                   '__text',
                   'sha256:98b08b25d07580ee9b2519905df03e0333d79175fc01a04829a6b8250edd96a4'],
 'drill_stop_enable': [602054,
                       18,
                       '__text',
                       'sha256:a35427dec5069c34105fa327135149ed1d3d92902b3ddfcf199e60f1ed69692b']}
MAC_ALTERNATE = {'manager_initial_flags': [509866,
                           46,
                           '__text',
                           'sha256:91ee7282ac16a8103c2b2563577d8cf721dc44f0eb38b72e6bcc16063c75d6bd'],
 'player_initial_flags': [551703,
                          14,
                          '__text',
                          'sha256:6e90138b59ebc6d5ecdf13f18e3ae9e11a04a20675e3e0f308a9761097b397fe'],
 'world_update': [118201,
                  82,
                  '__text',
                  'sha256:c094cbfc66b1250fadb3f4019ea19bc1ef850a97b638735fc4441db4cf6db434'],
 'world_draw': [110499,
                17,
                '__text',
                'sha256:9ab745328574937cdb834696884ebba122263da7b2d4b103170cc148efe3ab2e'],
 'manager_update': [510928,
                    314,
                    '__text',
                    'sha256:48edbda444b73b15f91816545e547c3363672e38dd5b83ee2e8a661c126e255b'],
 'manager_draw': [512728,
                  56,
                  '__text',
                  'sha256:bb2bc79515512c7199c7623bb2e95432112569133d5a985616e2e47b5439d671'],
 'engine_enable': [556128,
                   112,
                   '__text',
                   'sha256:ecd9c44318fca15a398aeafeed4e4774c67020b9012aca2dd2855533e7cb72d3'],
 'manager_emitting': [512170,
                      52,
                      '__text',
                      'sha256:b32c63ae03ff1f1affcfe67c599b1bf9bc6709cef81208038459d32ba6a2103c'],
 'emitting_flag': [514774,
                   32,
                   '__text',
                   'sha256:4ce2bcd7bcb2d89038e1c0ebff7bf12818cc1b1a6b117d6c9b8a05ab6f70c553'],
 'player_hidden': [603800,
                   54,
                   '__text',
                   'sha256:91d1d1092bf66dba09777c69209726c46545a0a9b6adf5db1825ff6f8c95fb7a'],
 'entry_disable': [122627,
                   15,
                   '__text',
                   'sha256:19d4923960465a5e5489bb6fc9602f91c64fb50dd8635734c48587830c61225a'],
 'arrival_disable': [381354,
                     16,
                     '__text',
                     'sha256:69a308af1b7f15ad154a7aaffb4983c8930a08beeb1b766ffcb75969475110dc'],
 'mining_cancel_enable': [587395,
                          23,
                          '__text',
                          'sha256:195ff9a43d6c8ea6f63ff3ba624257d6c1008a7cbff8f20ee039ca971cc591cb'],
 'mining_capture_disable': [588107,
                            15,
                            '__text',
                            'sha256:a4d7517af63bdd6f357f0ebc10beeabf5d1f7fdc4a82168ef0312c98ebb10a1b'],
 'mining_release_enable0': [590139,
                            21,
                            '__text',
                            'sha256:c6b63b84b4e1501be60742ca3712a16d5640ef241a5b7b9d394e4d8fcaaaef88'],
 'mining_release_enable1': [590442,
                            25,
                            '__text',
                            'sha256:b43fa060b08738f6dc7604139e4b5d9f627cdf3b54967f5405008f831289c81c'],
 'death_disable': [600736,
                   19,
                   '__text',
                   'sha256:dfc942bf2a84bbecb00f94b865f480ce6c99de75e2d89cf0d2e210dbd8f3dda1'],
 'revive_enable': [600951,
                   18,
                   '__text',
                   'sha256:8ab0246acadb82df30a1d306a269a13fe6db53be54affbb5e712b4e70267f7ab'],
 'drill_stop_enable': [602602,
                       18,
                       '__text',
                       'sha256:a6ffe348b0c17d2416b9202f69c1f1eaf678ea3697b81987abb1ce7ab87a0e88']}


def extract_engine_particle_owners(mach, arrival, engines):
    if mach.architecture != 'x86_64':
        return {}
    try:
        opening = engines.get('opening_ship') == OPENING_SHIP
        if len(engines) != len(NOZZLES) + 1 + int(opening) or not isinstance(engines.get('provenance'), dict):
            return {}
        if opening and not set(OPENING_SPANS) <= engines['provenance'].keys():
            return {}
        if any(engines.get(key) != value for key, value in NOZZLES.items()):
            return {}
        origin = arrival['provenance']['actor']
        if origin['bytes'] != 315:
            return {}
        layouts = [{key: [row[2], row[0], row[1], row[3]] for key, row in layout.items()}
                   for layout in (LAYOUTS, MAC_ALTERNATE)]
        proof = recognize(mach, origin['offset'], layouts, reader=declaration_bytes)
        if not proof:
            return {}
        result = copy.deepcopy(VALUES)
        if opening:
            result['opening_ship'] = {
                'ship_id': OPENING_SHIP['ship_id'],
                'nozzle_count': OPENING_SHIP['nozzle_count'],
                'first_preset': OPENING_SHIP['first_preset'],
            }
        result['provenance'] = proof
        return result
    except (AttributeError, KeyError, TypeError, ValueError, IndexError, OverflowError):
        return {}
