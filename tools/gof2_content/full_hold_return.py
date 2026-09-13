"""Optional Mac full-hold station return and cargo-lifetime declarations."""
import copy,hashlib
from .station_exterior import declaration_bytes

def extract_full_hold_return(mach,arrival,first,story):
    if mach.architecture!='x86_64':return {}
    try:
        if first['scope']!='first_mining_station_return' or story['scope']!='full_hold_mining_story':return {}
        origin=arrival['provenance']['actor']
        if origin['bytes']!=315:return {}
        anchor=mach.text['address']+origin['offset']-mach.slice_offset-mach.text['offset'];proof={}
        for key,(delta,size,section,pattern) in LAYOUTS.items():
            found=declaration_bytes(mach,anchor+delta,size,section.encode())
            if found is None:return {}
            if pattern.startswith('sha256:'):
                if hashlib.sha256(found[0]).hexdigest()!=pattern[7:]:return {}
            elif found[0]!=bytes.fromhex(pattern):return {}
            proof[key]={'offset':found[1],'bytes':size}
        result=copy.deepcopy(VALUES);result['provenance']=proof;return result
    except (KeyError,TypeError,ValueError,IndexError,OverflowError):return {}

VALUES = {'scope': 'full_hold_station_return',
 'station_id': 78,
 'system_id': 15,
 'departing_cursor': 4,
 'campaign_cursor': 5,
 'source_state': 5,
 'contact_radius': 16000.0,
 'contact_before_motion': True,
 'volume_after_motion': True,
 'requires_station_target': True,
 'mission_kind': 11,
 'restricted_mission_kind': 154,
 'restricted_notice': 21,
 'minimum_delivered_cargo': 25,
 'cache_pools': ['hull', 'armor', 'shield', 'gamma'],
 'cache_truncates': ['shield', 'gamma'],
 'cargo_preserved_on_arrival': True,
 'clear_cargo_after_acknowledgement': True,
 'mode': 1,
 'next_text_id': 179,
 'final_text_id': 180,
 'cursor_after_acknowledgement': 6,
 'next_mission_kind': 158,
 'next_mission_parameter': 0,
 'reward_credits': 0,
 'bonus_credits': 0,
 'events': [{'speaker_id': 2, 'text_id': 1719, 'voice_event_id': 433},
            {'speaker_id': 0, 'text_id': 1720, 'voice_event_id': 434},
            {'speaker_id': 2, 'text_id': 1721, 'voice_event_id': 435},
            {'speaker_id': 0, 'text_id': 1722, 'voice_event_id': 436},
            {'speaker_id': 2, 'text_id': 1723, 'voice_event_id': 437},
            {'speaker_id': 16, 'text_id': 1724, 'voice_event_id': -1}],
 'refresh_cargo_after_acknowledgement': False}

LAYOUTS = {'mode1_counts': [1555258, 24, '__const', '0000000026000000060000000a000000040000000c000000'],
 'mode1_return_events': [1546594,
                         48,
                         '__const',
                         '02000000b706000000000000b806000002000000b906000000000000ba06000002000000bb06000010000000bc060000'],
 'voice_table': [1560154,
                 12032,
                 '__const',
                 'sha256:9d6c95a1f5be7db67e20b62e913d94d275f8f743dc943cd685af361d96684be7'],
 'cursor6_dispatch': [871426, 4, '__text', '2fd6ffff'],
 'cursor6_factory': [860701,
                     50,
                     '__text',
                     '498bbe00020000e8bf04feffbf98000000e8f95f0a004889c34889dfbe9e00000031d2b94e000000e84ef5f8ffe932ffffff'],
 'factory_install': [860545, 16, '__text', '4c89f74889dee80cfcffffe9242a0000'],
 'cargo_list_dispose': [730856,
                        54,
                        '__text',
                        '554889e54156534989fe498b5e784885db7416488b7b084885ff7405e8115b0c004889dfe80f5b0c0049c74678000000005b415e5dc3'],
 'mission_constructor': [399266,
                         448,
                         '__text',
                         '554889e54157415641554154534883ec384189ce4189d74189f44889fb488d7b1848897da8e8beba0e00488d7b2848897da0e8b1ba0e00488d7b5848897db0e8a4ba0e004c8d6b684c89efe898ba0e004489631044897b444489735048c743380000000048c74308000000004585f67826488d0560231f00488b384489f6e863daefff488d7dc84889c6e84de5060041b6014530ffeb18488d7dc8488d35c29c150031d2e8dfbc0e004530f641b701488d75c8488b7db0e8bcc30e004180ff017509488d7dc8e8fdb90e004180fe017509488d7dc8e8eeb90e00488d7db8488d357f9c150031d2e89cbc0e00488d75b84c89efe880c30e00488d7db8e8c7b90e00c7838400000001000000c6839400000001c60300c6430100c6437c00c7839000000000000000c7434c000000004883c4385b415c415d415e415f5dc34889c3eb624889c3eb544889c3eb464889c3eb394889c34584f6751aeb2f4889c34180ff017509488d7dc8e85bb90e004180fe017517488d7dc8e84cb90e00eb0c4889c3488d7db8e83eb90e004c89efe836b90e00488b7db0e82db90e00488b7da0e824b90e00488b7da8e81bb90e004889dfe805691100e8b86811004889c3ebcb90'],
 'station_acknowledgement': [429803,
                             1908,
                             '__text',
                             'sha256:3ac1adb5069204f99145694aab530df1110ea076aa33b21cb049e6e18e2850a4'],
 'station_dialogue_selection': [447318,
                                69,
                                '__text',
                                '488b9de0feffff4885db0f848400000049899d00010000bfb0000000e8b5ae10004989c64c89f74889de31d2b901000000e8ee92eeff4d89b5d800000041c685a500000001'],
 'dialogue_mission_binding': [-693644,
                              28,
                              '__text',
                              '554889e5415741564154534189ce4989f44989ff4d89677041895768'],
 'mission_voice_actor': [401310, 10, '__text', '554889e5488b47085dc3'],
 'silent_voice_lookup': [-215216,
                         68,
                         '__text',
                         '554889e5415741564154534989d689f331c0488d0df1161b00eb044883c0023dbf0b00007f15391c8175f0488d0dd8161b008b448104e9d50800004d85f60f84c7080000'],
 'silent_voice_return': [-212901, 14, '__text', 'b8ffffffff5b415c415e415f5dc3'],
 'next_mission_equipment': [874532,
                            126,
                            '__text',
                            '498bbd00020000e88acbfdff4989c641833e000f845201000030db4531e44530ed498b46084a8b3ce04885ff742be8eb5cf1ff85c0750541b501eb1d498b46084a8b3ce04885ff7410e8e45cf1ffb10183f80a740288d988cb49ffc4453b2672c041f6c5014c8b6db00f84fc000000f6c301e9eb000000418b9d64020000']}
