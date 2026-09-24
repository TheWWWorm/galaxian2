"""Optional Mac second-trip story data. No executable runtime is emitted."""
import copy
from .declaration_layouts import recognize
from .station_exterior import declaration_bytes

def extract_full_hold_story(mach,arrival,flight,briefing,objective):
    if mach.architecture!='x86_64':return {}
    try:
        if flight['scope']!='full_hold_mining_flight_construction':return {}
        if briefing['scope']!='first_mining_briefing' or objective['scope']!='first_mining_cargo_objective':return {}
        origin=arrival['provenance']['actor']
        if origin['bytes']!=315:return {}
        layouts=[{k:[v[2],v[0],v[1],v[3]] for k,v in rows.items()} for rows in [LAYOUTS,MAC_ALTERNATE]]
        proof=recognize(mach,origin['offset'],layouts,reader=declaration_bytes)
        if not proof:return {}
        values=MAC_VALUES if proof['mode0_counts']['offset']==origin['offset']+MAC_ALTERNATE['mode0_counts'][0] else VALUES
        result=copy.deepcopy(values);result['provenance']=proof
        return result
    except (KeyError,TypeError,ValueError,IndexError,OverflowError):return {}

VALUES = {'scope': 'full_hold_mining_story',
 'campaign_cursor': 4,
 'mission_kind': 154,
 'station_id': 78,
 'required_cargo': 25,
 'cursor_after_acknowledgement': 5,
 'next_kind': 11,
 'briefing_events': [{'speaker_id': 2, 'text_id': 1716, 'voice_event_id': 188}],
 'completion_events': [{'speaker_id': 0,
                        'text_id': 1717,
                        'voice_event_id': 431},
                       {'speaker_id': 2,
                        'text_id': 1718,
                        'voice_event_id': 432}]}

LAYOUTS = {'mode0_counts': [1554602, 20, '__const', '02000000000000000a0000000000000002000000'],
 'mode0_events': [1555962, 8, '__const', '02000000b4060000'],
 'mode1_counts': [1555258, 20, '__const', '0000000026000000060000000a00000004000000'],
 'mode1_events': [1546578, 16, '__const', '00000000b506000002000000b6060000'],
 'briefing_voice': [1560354, 8, '__const', 'b4060000bc000000'],
 'completion_voices': [1562298, 16, '__const', 'b5060000af010000b6060000b0010000'],
 'next_dispatch': [871422, 4, '__text', '04d6ffff'],
 'next_mission': [860658,
                  43,
                  '__text',
                  'bf98000000e830600a004889c34889dfbe0b00000031d2b94e000000e885f5f8ffe969ffffffe9a7290000'],
 'acknowledgement_cleanup': [352080,
                             4033,
                             '__text',
                             'sha256:e9c87f5f46995d42c94089562d1be9af2636e5e87116dd2e78558ad2753e1125'],
 'entry_controller': [150932,
                      435,
                      '__text',
                      '41f6452c010f84a8010000498b4520488b38be1e00000031d2e8d2990100488d05c9ed2200488b38e859120b004885c07438498b7d20e81950ffff4989c641833e00742631db498b46084c8b3cd84c89ffe82882fcff84c0740841c6877d0100000148ffc3413b1e72dc8b85c0d0ffff41014530498b7d20e8c94fffff4885c00f842d010000488d0561ed2200488b38e803ca0a0083f8020f8c1501000041817d30591b00000f8c0701000041c745300000000041c6452c0041c6452d01498b7d1831f6e803940b00498b7d20e8744fffff488b38be01000000e8a7e5050041c6451100498b7d20e8594fffff4889c7be01000000e87c3b0600488d0575f42200488b184885db7440488d05deec2200488b38e838c90a004889df4889c6e871b60a0084c07522498b7d20498b9d08010000e80f4fffff4889dfbe050000004889c231c9e803e8fbff488d05eef32200c60000488d0524f42200f6000175084c89efe867cbffff488d0580ec2200488b38e810110b004885c07438498b7d20e8d04effff4989c641833e00742631db498b46084c8b3cd84c89ffe8df80fcff84c0740841c6877d0100000048ffc3413b1e72dc']}

# Complete independently verified alternate Mac layout.
MAC_ALTERNATE = {'mode0_counts': [1529586, 20, '__const', '04000000000000000a0000000000000002000000'],
 'mode0_events': [1530954, 8, '__const', '02000000bf060000'],
 'mode1_counts': [1530242, 20, '__const', '0000000026000000060000000a00000004000000'],
 'mode1_events': [1521562, 16, '__const', '00000000c006000002000000c1060000'],
 'briefing_voice': [1535418, 8, '__const', 'bf060000bc000000'],
 'completion_voices': [1537362, 16, '__const', 'c0060000af010000c1060000b0010000'],
 'next_dispatch': [872054, 4, '__text', '04d6ffff'],
 'next_mission': [861290,
                  43,
                  '__text',
                  'bf98000000e804fc09004889c34889dfbe0b00000031d2b94e000000e811f5f8ffe969ffffffe9a7290000'],
 'acknowledgement_cleanup': [351794,
                             4033,
                             '__text',
                             'sha256:0eb982bef5a9a776cbf7ebe71bde77c4fe7e513a3310c088f0b00699a423f8a3'],
 'entry_controller': [150932,
                      435,
                      '__text',
                      '41f6452c010f84a8010000498b4520488b38be1e00000031d2e8de990100488d05a1952200488b38e8d1140b004885c07438498b7d20e81950ffff4989c641833e00742631db498b46084c8b3cd84c89ffe82882fcff84c0740841c6877d0100000148ffc3413b1e72dc8b85c0d0ffff41014530498b7d20e8c94fffff4885c00f842d010000488d0539952200488b38e87bcc0a0083f8020f8c1501000041817d30591b00000f8c0701000041c745300000000041c6452c0041c6452d01498b7d1831f6e87b960b00498b7d20e8744fffff488b38be01000000e8bfe7050041c6451100498b7d20e8594fffff4889c7be01000000e8943d0600488d05659c2200488b184885db7440488d05b6942200488b38e8b0cb0a004889df4889c6e8e9b80a0084c07522498b7d20498b9d08010000e80f4fffff4889dfbe050000004889c231c9e85fe6fbff488d05de9b2200c60000488d05149c2200f6000175084c89efe867cbffff488d0558942200488b38e888130b004885c07438498b7d20e8d04effff4989c641833e00742631db498b46084c8b3cd84c89ffe8df80fcff84c0740841c6877d0100000048ffc3413b1e72dc']}
MAC_VALUES = {'scope': 'full_hold_mining_story',
 'campaign_cursor': 4,
 'mission_kind': 154,
 'station_id': 78,
 'required_cargo': 25,
 'cursor_after_acknowledgement': 5,
 'next_kind': 11,
 'briefing_events': [{'speaker_id': 2, 'text_id': 1727, 'voice_event_id': 188}],
 'completion_events': [{'speaker_id': 0, 'text_id': 1728, 'voice_event_id': 431},
                       {'speaker_id': 2, 'text_id': 1729, 'voice_event_id': 432}]}
