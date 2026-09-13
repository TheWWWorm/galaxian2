"""Source first-mining session declarations; original code is never a runtime."""
import copy
from .ship_models import section_bytes

def extract_mining_session(mach, arrival, approach, drill):
    if mach.architecture!='x86_64' or approach.get('scope')!='first_mining_approach' or drill.get('scope')!='ordinary_mining_drill':return {}
    try:
        origin=arrival['provenance']['actor']
        if origin['bytes']!=315:return {}
        anchor=mach.text['address']+origin['offset']-mach.slice_offset-mach.text['offset']
        proof={}
        for key,(delta,size,pattern) in LAYOUTS.items():
            found=section_bytes(mach,anchor+delta,size,b'__text')
            if found is None or found[0]!=bytes.fromhex(pattern):return {}
            proof[key]={'offset':found[1],'bytes':size}
        result=copy.deepcopy(VALUES);result['provenance']=proof
        return result
    except (KeyError,TypeError,ValueError,IndexError,OverflowError):return {}

VALUES = {'scope': 'first_mining_session',
 'campaign_cursor': 2,
 'max_frame_ms': 150,
 'failure_notification': 8,
 'failure_text_id': 528,
 'stop_audio_events': [1, 3],
 'automatic_finish_resumes_motion': True,
 'commands_after_update': True,
 'creation_frame_advances_drill': False,
 'cancelled_target_grants_ore': False}

LAYOUTS = {'ongoing_drill': [588551,
                   179,
                   '418bb42484010000e8040afdff84c0754c498bbc2470020000e87509fdff84c0751b498bbc2470020000e87209fdff85c07e0a4c89e7e808320000eb74498bbc2470020000e84909fdff88c1b00184c9746141c684244304000001eb26498bbc2440020000e891d4f5ff84c07515498bbc2440020000e870d4f5ff88c130c084c97430488d05f13f1c00488b00c78084010000000000004c89e7e8a43100004c89f7be080000004c89e231c9e8283bf5ffb001'],
 'finish_release': [602148,
                    84,
                    '49c7877002000000000000498b57284c89ff31f6e875c3ffff488d1d66111c00488b3bbe01000000e895b7ecff488b3bbe03000000e888b7ecff418b7738488b3b4883c4185b415c415d415e415f5de9f6beecff'],
 'stop_dispatch': [344857,
                   48,
                   '498b7d60e8624303003c010f8596010000488d0551f81f00488b08c7818401000000000000488b38e8e6d4070083f802'],
 'stop_finish': [345173, 9, '498b7d60e8ece80300'],
 'active_drill': [558724, 17, '554889e54883bf70020000000f95c05dc3'],
 'player_frame_dispatch': [366274,
                           86,
                           '498d454c4183bdbc01000000490f4ec48b304d8b8d980000004d8b85a8000000498b8d88000000498b95a0000000498b7d60458b951c010000410fb65d6b418b45208944241083e301895c240844891424e804200300'],
 'frame_delta': [363155,
                 72,
                 '498b7d10e8be050f003d960000007f12498b7d10e8ae050f004889c131c085c97822498b7d10e89c050f004889c1b89600000081f9960000007f09498b7d10e883050f0041894548'],
 'hud_drill_input': [378881,
                     448,
                     '498bbd88000000e89bd9f8ff0f57c90f2ec8764c498d454c4183bdbc01000000490f4ec4448b30498b5d60498bbd88000000e870d9f8fff30f118500fdffff498bbd88000000e85cd9f8fff30f598500fdffff4889df4489f6e873500300eb5f498bbd88000000e83bd9f8ff0f2e059afc1100764a498d454c4183bdbc01000000490f4ec4448b30498b5d60498bbd88000000e80fd9f8fff30f118500fdffff498bbd88000000e8fbd8f8fff30f598500fdffff4889df4489f6e85a4d0300488d051f731f008a5810498bbd88000000e8f8d8f8ff0f57c9f6c3010f84b70000000f2ec87650498d454c4183bdbc010000004c0f4fe0458b3424498b5d60498bbd88000000e8c3d8f8fff30f118500fdffff498bbd88000000e8afd8f8fff30f598500fdffff4889df4489f6e858520300e98a000000498bbd88000000e88bd8f8ff0f2e05c4fb11007675498d454c4183bdbc010000004c0f4fe0458b3424498b5d60498bbd88000000e85ed8f8fff30f118500fdffff498bbd88000000e84ad8f8fff30f598500fdffff4889df4489f6e8ab550300eb280f2ec877ae498bbd88000000e824d8f8ff0f2e055dfb11000f8730ffffffeb084c89efe80361ffff'],
 'failure_text': [-115464, 20, '488d059bfe2600488b38be10020000e9ef0b0000'],
 'notification_dispatch': [-116996, 29, '418d46ff83f82e0f8706120000488d0db6130000486304814801c8ffe0'],
 'failure_jump_entry': [-111902, 4, '32f2ffff']}
