"""Read ordinary rescue sky/planet declarations; emit no executable bytes."""
import copy
from .declaration_layouts import recognize

def extract_arrival_environment(mach, sky, actors, arrival):
    arch=mach.architecture
    if arch not in LAYOUTS:return {}
    try:
        if arrival['campaign_cursor']!=1 or not actors['player_initialization']['flight_cache'] or not sky['planet_resources']:return {}
        origin=sky['provenance']['opening']
        if origin['bytes']!=(71 if arch=='x86_64' else 62):return {}
        proof=recognize(mach,origin['offset'],[LAYOUTS[arch]] + ([MAC_ALTERNATE] if arch == 'x86_64' else []))
        if not proof:return {}
        result=copy.deepcopy(VALUES);result['provenance']=proof
        return result
    except (KeyError,TypeError,IndexError,ValueError,OverflowError):return {}

VALUES = {'scope': 'fresh_rescue_environment',
 'campaign_cursor': 1,
 'world_type': 3,
 'special_system_id': 27,
 'maximum_sky_index': 14,
 'supported_planet_type': 0,
 'sky_mesh_base': 17800,
 'sky_texture_base': 10065,
 'current_planet_size_factor': 1,
 'current_planet_texture_source': 'near_textures'}

LAYOUTS = {'x86_64': {'sky_gate': ['__text',
                         0,
                         94,
                         '498b3c24e87eb90d0085c04989df75374183bf1401000003752d488d1dccdc2500488b3bbe8b4500004c89f231c9e8122a1200488b3b498d973c020000be54270000e923030000488d058fdc2500488b38e8c9f10d003c010f8557010000'],
            'sky_plain': ['__text',
                          437,
                          106,
                          '4c89fb4c8d3d2edb25004d8b2f4c8d2514db2500498b3c24e89bf00d004889c7e897d60b0005884500000fb7f04c89ef4c89f231c9e8562812004d8b3f498b3c24e872f00d004889c7e86ed60b00488d933c0200004989dc05512700000fb7f04c89ff31c9e856221200'],
            'sky_special': ['__text',
                            913951,
                            78,
                            '554889e553504889fb488bb3b8000000488bbb18020000e848b4ffff88c130c084c97522488bbb28020000e8a2e4fdff89c130c083f91b750d81bb780200009e0000000f9cc04883c4085b5dc390'],
            'planet_scale': ['__text',
                             884606,
                             74,
                             '498b3c24be204e0000e8193d04004189c7488d05475d1800488b384181c7204e0000e8e239000083fb0b0f9f8508feffff4189dc85c07512f3410f2ac7f30f590522b30a00f3440f2cf8'],
            'constant_1832e5': ['__const', 1585893, 4, '0000003f'],
            'planet_current': ['__text',
                               882686,
                               64,
                               '498b3fe88141000085c0754383bdf8fdffff03753a488b8528feffff8b8d20feffff894878488b4018488b50084c01e2498b7d00be3b27000031c9e837ac0400'],
            'planet_near': ['__text',
                            882765,
                            61,
                            '488b8508feffff488b40084a8b7c60f8498b5d00e8d5260000488b8d18feffff488b09488b51084c01e24863c0488d0d946d0b000fb734814889dfebad'],
            'constant_18e615': ['__const', 1631765, 8, '3a2700003b270000']},
 'armv7': {'sky_gate': ['__text',
                        0,
                        78,
                        '3068cdf85481ccf00dfcc0b9dbf8c000032814d1d0464ff0ff35d8f8000044f28b5155950023159c2246d9f1bdfdd8f800000bf5cc72559542f2547150e130684ff0ff345594d0f027fb012819d1'],
           'sky_plain': ['__text',
                         130,
                         76,
                         '3068d046d8f800505594d0f020fb5594aef04bf9559444f288510844159a002381b22846d9f17ffd3068d8f800505594d0f00dfb5594aef038f942f2517108440bf5cc72559481b228467be0'],
           'sky_special': ['__text',
                           853656,
                           56,
                           '90b5044601af616fd4f88801faf702ff00281cbf002090bdd4f89001ddf7d6fd014600201b2918bf90bdd4f8d4119e29b8bf012090bd00bf'],
           'planet_scale': ['__text',
                            824158,
                            70,
                            '44f6206103601098006867950df1c7f914994ff400420c2c09686795b8bf00220f9244f6206200eb020a084603f04bfa48b94aec30abfbff200640ff9a0dbbff200710ee10aa'],
           'planet_half': ['__text', 823828, 4, '86ef10af'],
           'planet_current': ['__text',
                              823196,
                              56,
                              'd8f80000cdf89ca103f03efc002804bf11980328bed1179c0023ddf85880c4f850806069416815984a1942f23b710068cdf89ca110f1defb'],
           'planet_near': ['__text',
                           823088,
                           60,
                           'd8461599d8f80400d1f800b050f82600cdf89ca101f046ff179c002361694a684cf68c61c0f21901cdf89ca179442a4431f820105846c34610f112fc']}}

# Independently verified alternate Mac compiler layout.
MAC_ALTERNATE = {'sky_gate': ['__text',
              0,
              94,
              '498b3c24e8f6bb0d0085c04989df75374183bf1401000003752d488d1da4842500488b3bbe8b4500004c89f231c9e8ea211200488b3b498d973c020000be54270000e923030000488d0567842500488b38e841f40d003c010f8557010000'],
 'sky_plain': ['__text',
               437,
               106,
               '4c89fb4c8d3d068325004d8b2f4c8d25ec822500498b3c24e813f30d004889c7e80fd90b0005884500000fb7f04c89ef4c89f231c9e82e2012004d8b3f498b3c24e8eaf20d004889c7e8e6d80b00488d933c0200004989dc05512700000fb7f04c89ff31c9e83e1a1200'],
 'sky_special': ['__text',
                 914583,
                 78,
                 '554889e553504889fb488bb3b8000000488bbb18020000e848b4ffff88c130c084c97522488bbb28020000e8a2e4fdff89c130c083f91b750d81bb780200009e0000000f9cc04883c4085b5dc390'],
 'planet_scale': ['__text',
                  885238,
                  74,
                  '498b3c24be204e0000e8793804004189c7488d05a7021800488b384181c7204e0000e8e239000083fb0b0f9f8508feffff4189dc85c07512f3410f2ac7f30f5905f24e0a00f3440f2cf8'],
 'constant_1832e5': ['__const', 1560877, 4, '0000003f'],
 'planet_current': ['__text',
                    883318,
                    64,
                    '498b3fe88141000085c0754383bdf8fdffff03753a488b8528feffff8b8d20feffff894878488b4018488b50084c01e2498b7d00be3b27000031c9e8a7a10400'],
 'planet_near': ['__text',
                 883397,
                 61,
                 '488b8508feffff488b40084a8b7c60f8498b5d00e8d5260000488b8d18feffff488b09488b51084c01e24863c0488d0dd4090b000fb734814889dfebad'],
 'constant_18e615': ['__const', 1606861, 8, '3a2700003b270000']}
