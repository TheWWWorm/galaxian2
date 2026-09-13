"""Bounded first-mining briefing declarations; original instructions never run."""
import copy
from .radio_audio import constant_bytes


def extract_mining_briefing(mach, arrival, flight, presentation, desktop):
    if mach.architecture != 'x86_64':
        return {}
    try:
        if flight['scope'] != 'first_mining_flight_construction' or presentation['scope'] != 'first_station_presentation':
            return {}
        if desktop.get('scope') != 'mac_desktop_text' or [1703, 1704] not in desktop.get('pairs', []):
            return {}
        origin = arrival['provenance']['actor']
        if origin['bytes'] != 315:
            return {}
        anchor = mach.text['address'] + origin['offset'] - mach.slice_offset - mach.text['offset']
        proof = {}
        for key, (delta, size, section, pattern) in LAYOUTS.items():
            found = constant_bytes(mach, anchor + delta, size, section.encode())
            if found is None or found[0] != bytes.fromhex(pattern):
                return {}
            proof[key] = {'offset': found[1], 'bytes': size}
        # The shared presentation reader verifies the entire voice lookup and
        # the fixed portraits. A missing text lookup has no mission actor here.
        result = copy.deepcopy(VALUES)
        result['provenance'] = proof
        return result
    except (KeyError, TypeError, ValueError, IndexError, OverflowError):
        return {}

VALUES = {'scope': 'first_mining_briefing',
 'campaign_cursor': 2,
 'mission_kind': 154,
 'mode': 0,
 'entry_release_ms': 7001,
 'briefing_minimum_ms': 5001,
 'max_frame_ms': 150,
 'briefing_before_controller_update': True,
 'modal_stops_simulation': True,
 'final_acknowledgement_clears_pending': True,
 'final_acknowledgement_completes_mission': False,
 'next_text_id': 179,
 'final_text_id': 180,
 'key_token': '#KEY_DOCK',
 'events': [{'speaker_id': 0, 'text_id': 1699, 'voice_event_id': 177},
            {'speaker_id': 2, 'text_id': 1700, 'voice_event_id': 178},
            {'speaker_id': 0, 'text_id': 1701, 'voice_event_id': 179},
            {'speaker_id': 2, 'text_id': 1702, 'voice_event_id': 180},
            {'speaker_id': 16, 'text_id': 1703, 'voice_event_id': -1}]}

LAYOUTS = {'count_prefix': [1554602, 12, '__const', '02000000000000000a000000'],
 'events': [1555922,
            40,
            '__const',
            '00000000a306000002000000a406000000000000a506000002000000a606000010000000a7060000'],
 'voice_events': [1560266, 32, '__const', 'a3060000b1000000a4060000b2000000a5060000b3000000a6060000b4000000'],
 'index_table': [-694459,
                 60,
                 '__text',
                 '31c031c9488d155a512200488d35e353220031ffeb11030411033c314883c104498b9d9000000089040b498b9d98000000893c0b81f98402000075da'],
 'dialogue_mode': [-693624,
                   144,
                   '__text',
                   '4d8967704189576883fa01743a83fa02754a4c89e7e8fcb410004889c34885db74164889dfe8c09affff84c0750a4889df31f6e82e9effff4c89e7be01000000e891b11000eb154c89e7e8c7b410004c89e7be01000000e88eb1100041c7476c000000004183feff7512488d0589d02f00488b38e82bad17004189c6458977204c89ff5b415c415e415f5de9f8030000'],
 'speaker_selection': [-692286,
                       155,
                       '__text',
                       '498b7f70e80dae1000418b4f6884c0751f83f9020f85b504000041837f202a0f85aa0400004d8d7768b810000000eb534d8d776883f9017429b81000000085c9754149634720498b9790000000418b4f6c01c9030c824863c1488d0da84d2200eb1e49634720498b9798000000418b4f6c01c9030c824863c1488d0d382822008b0481898560fcffff4863d8488d0505222f00488b04d849894738'],
 'text_selection': [-692078,
                    65,
                    '__text',
                    '418b0e85c90f859700000049634720498b8f90000000418b576c8d5c1201031c814863c3488d0d0d4d2200448b3481488d05d2ca2f00488b384489f6e8f7a61b00'],
 'line_count': [-686407,
                60,
                '__text',
                '488b7b704885ff7440e8119710003c0175378b4b6883f9017422b80100000085c9756e48634320488d0dc33122008b0c8189c8c1e81f01c8d1f8eb55'],
 'next_line': [-686457,
               41,
               '__text',
               '4889fb448b736ce81d000000ffc84139c67c0430c0eb0dff436c4889dfe867e8ffffb0015b415e5dc3'],
 'previous_line': [-685046,
                   45,
                   '__text',
                   '3c0175298bb3a0000000488d058fb52f00488b38e8c35b00008b436c85c07e0dffc889436c4889dfe8d9e2ffff'],
 'acknowledgement': [-685001,
                     56,
                     '__text',
                     '488b7b084489fe4489f2e84c7618003c0175258bb3a0000000488d0553b52f00488b38e8875b00004889dfe819faffff88c1b00184c97448'],
 'hud_initial': [338262,
                 51,
                 '__text',
                 'c6436900c6436b0048c7435000000000c6830c01000000c6830901000000c6830801000000c6830a01000000c6830d01000000'],
 'hud_modal_clock_gate': [364625, 11, '__text', '41f64569010f85410b0000'],
 'hud_clock': [365124, 19, '__text', '41f6456b010f85140400004963454849014550'],
 'hud_modal_dispatch': [368096,
                        39,
                        '__text',
                        '41f6456c010f85301e0000498b7d60e88eed020085c00f8e1f1e000041f64569010f8590210000'],
 'briefing_start': [385208,
                    516,
                    '__text',
                    '554889e54156534989fe498bbe98000000e8daaefdff3c010f85e1010000488d05a55a1f00488b38e84737070089c7e8e08defff84c0751f488d058b5a1f00488b38e84d3707004889c7e8d13c000084c00f85a8010000488d056c5a1f00488b38e82e3707004889c7e80e3b000084c00f8589010000488d054d5a1f00488b38e80f3707004889c7e8853b000083f8080f8469010000488d052d5a1f00488b38e8ef3607004889c7e8653b00003da60000000f8447010000488d050b5a1f00488b38e8cd3607004889c7e8433b000085c00f8428010000488d05ec591f00488b38e8ae3607004889c7e8243b00003db70000000f8406010000488d05ca591f00488b38e88c3607004889c7e8883a00003c010f85e7000000488d05ab591f00488b38e86d3607004889c7e8f13b000084c07520488d0590591f00488b38e8523607004889c7e8c83a000083f80b0f84ac0000004983beb8000000007537bfb0000000e80da011004889c3488d0559591f00488b38e81b360700498b96900000004889df4889c631c9e83584efff49899eb8000000498b7e6031f6e805a10200498bb690000000498bbe98000000e87ca8fdff498b7e6031f6e82f580300498bbe3801000031f6e895fd0700498b7e6031f6e8e651030041c6865901000001498b869800000048c740080000000041c64669014c89f7e88e51ffff41c6466a015b415e5dc3'],
 'controller_order': [377622, 24, '__text', '418a5d6b418b7548498bbd98000000e8965afcff4188456b'],
 'modal_update_dispatch': [376727,
                           41,
                           '__text',
                           '498bbdb00000004885ff0f84c701000041f6851a010000010f85b901000041f6456a010f85ae010000'],
 'modal_update': [377346,
                  51,
                  '__text',
                  '41f6456a010f84da090000418b7548488d05aa791f00488b38e8967cf9ff418b7548498bbdb8000000e87ec3efffe9b2090000'],
 'final_acknowledgement': [351489,
                           102,
                           '__text',
                           '41f644246a010f8404120000498bbc24b800000089de4489fae8032ef0ff3c010f852120000041c6442469004c89e7e86fd7ffff41c644246a004c8d3540de1f00498b3ee802bb07004889c7e816bf000088c3498b3ee8f0ba07004889c784db0f84e9010000'],
 'unfinished_mission': [352080,
                        40,
                        '__text',
                        'e827bd000084c0751f488d0522dc1f00488b38e8d0b807004889c7e80cbd00003c010f85710f0000'],
 'post_briefing': [356073,
                   40,
                   '__text',
                   '498bbc2498000000e8a020feff49c744243800000000498bbc2488000000e8de28f9ffe9afe5ffff'],
 'clear_pending': [233366, 18, '__text', '554889e5c6472d00c74730000000005dc390']}
