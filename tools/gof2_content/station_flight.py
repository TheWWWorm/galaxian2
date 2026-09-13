"""Recover bounded live station flight parameters; emit no executable payload."""
import copy
from .station_exterior import declaration_bytes

def extract_station_flight(mach, arrival, flight):
    if mach.architecture!='x86_64' or flight.get('scope')!='first_mining_flight_construction':return {}
    try:
        origin=arrival['provenance']['actor']
        if origin['bytes']!=315:return {}
        anchor=mach.text['address']+origin['offset']-mach.slice_offset-mach.text['offset']
        proof={}
        for key,(delta,size,section,pattern) in LAYOUTS.items():
            found=declaration_bytes(mach,anchor+delta,size,section.encode())
            if found is None or found[0]!=bytes.fromhex(pattern):return {}
            proof[key]={'offset':found[1],'bytes':size}
        result=copy.deepcopy(VALUES);result['provenance']=proof
        return result
    except (KeyError,TypeError,ValueError,IndexError,OverflowError):return {}

VALUES = {'scope': 'first_mining_station_flight',
 'station_id': 78,
 'system_id': 15,
 'input_mode': 'elapsed',
 'mining_shares_guidance_history': True,
 'manual_commands_during_guidance': False,
 'manual_sample_before_neutral': True,
 'guidance_retains_preceding_command_flags': True,
 'target_notice': {'source_id': 10,
                   'prefix_text_id': 535,
                   'separator': ': ',
                   'suffix_separator': ' ',
                   'suffix_text_id': 135,
                   'rgb': [255, 255, 255]},
 'restricted_notice': {'source_id': 21, 'text_id': 514, 'rgb': [255, 255, 255]},
 'docking_transition_supported': False}

LAYOUTS = {'mining_guidance_history': [587316,
                             29,
                             '__text',
                             '4c89e7660f6f8570fefffff30f108d8cfeffffbe01000000e805b5ffff'],
 'mining_visual_gate': [579171,
                        40,
                        '__text',
                        '41f6864802000001f30f109560fbffff0f85ed030000418b864c020000ffc883f8020f82db030000'],
 'manual_response_sample': [565055,
                            32,
                            '__text',
                            '488d7da0f3410f10842418030000f3410f1184241c0300004c89f6e88b440a00'],
 'manual_command_clear': [565902,
                          48,
                          '__text',
                          '41c78424f80200000000000041c78424f40200000000000041c78424540100000000000041c784245001000000000000'],
 'visual_neutral_return': [579664,
                           534,
                           '__text',
                           'f3410f108618030000488d0522651c00833800448ba55cfbffff0f57c974710f2ec14c8bad60fbffff762c4183be54010000007522f30f590529e90e00f3410f1186180300000f57c90f2ec80f87c1000000e9c70000000f2ec80f86be0000004183be54010000000f85b0000000f30f5905f0e80e00f3410f1186180300000f57c90f2ec10f8788000000e98e0000000f2ec14c8bad60fbffff763a4183be540100000075300f57c9f3410f2accf3410f598ea4010000f30f5e0d97610f000f57d2f30f58c1f3410f1186180300000f2ed0773feb480f2ec876434183be540100000075390f57c9f3410f2accf3410f598ea4010000f30f5e0d54610f000f57d2f30f58c1f3410f1186180300000f2ec2760b41c7861803000000000000f3410f1086140300000f57c90f2ec1763a4183be500100000075300f57c9f3410f2accf3410f598ea4010000f30f5e0d04610f000f57d2f30f58c1f3410f1186140300000f2ed0773feb480f2ec876434183be500100000075390f57c9f3410f2accf3410f598ea4010000f30f5e0dc1600f000f57d2f30f58c1f3410f1186140300000f2ec2760b41c78614030000000000004983be00020000007419498bbeb8000000f30f100554bb0e00be46000000e89206050041c786f80200000000000041c786f40200000000000041c786540100000000000041c786500100000000000041c7860c0300000000000041c7860403000000000000'],
 'yaw_negative_gate': [595613,
                       45,
                       '__text',
                       'f683a8010000010f8587010000f683f203000001740d83bb4c020000010f8571010000c78354010000ffffffff'],
 'yaw_positive_gate': [596309,
                       45,
                       '__text',
                       'f683a8010000010f8580010000f683f203000001740d83bb4c020000010f856a010000c7835401000001000000'],
 'pitch_negative_gate': [597426,
                         45,
                         '__text',
                         'f683a8010000010f8575010000f683f203000001740d83bb4c020000010f855f010000c78350010000ffffffff'],
 'pitch_positive_gate': [598385,
                         45,
                         '__text',
                         'f683a8010000010f8571010000f683f203000001740d83bb4c020000010f855b010000c7835001000001000000'],
 'neutral_divisors': [1587874, 8, '__const', '0000fc420000fcc2'],
 'station_menu': [358266,
                  73,
                  '__text',
                  'a9000080007442498b5c2460498bbc2490000000e86326fcff488b4008488b304889dfe8661d0300498b542460498bbc2488000000be0a00000031c9e825bff8ff418b842440010000'],
 'notice_dispatch': [-116996, 29, '__text', '418d46ff83f82e0f8706120000488d0db6130000486304814801c8ffe0'],
 'target_message': [-114776,
                    324,
                    '__text',
                    '488d05ebfb2600488b38be17020000e80ed812004889c34c8dbde8fdffff488d35686b1b004c89ff31d2e853951600488dbdf8fdffff4889de4c89fae851ad1600488d0592fb2600488b38e8ecd70e00488dbdc8fdffff4889c6e877bd0e00488dbdd8fdffff488db5c8fdffff31d2e8de971600488dbd08feffff488db5f8fdffff488d95d8fdffffe804ad1600488d0545fb2600488b38e89fd70e004889c7e84bbd0e004d8dbd4002000083f8657524488dbdb8fdffff488d359f741d0031d2e8bc941600b3014530e4eb4e4989c6e957010000488dbda8fdffff488d35ad6a1b0031d2e898941600488d0501fb2600488b3830dbbe87000000e822d7120041b40130db488dbdb8fdffff488db5a8fdffff4889c2e877ac1600488dbd18feffff488db508feffff488d95b8fdffffe85dac1600488db518feffff4c89ffe82e9b1600'],
 'restricted_message': [-113624, 20, '__text', '488d056bf72600488b38be02020000e9bf040000'],
 'current_station': [858084, 14, '__text', '554889e5488b87180200005dc390'],
 'station_name': [851326, 26, '__text', '554889e553504889fb31d2e86cda07004889d84883c4085b5dc3'],
 'station_id': [851352, 10, '__text', '554889e58b47105dc390'],
 'separators': [1682229, 5, '__cstring', '3a20002000'],
 'notice_10_entry': [-111894, 4, '__text', 'e2f4ffff'],
 'notice_21_entry': [-111850, 4, '__text', '62f9ffff']}
