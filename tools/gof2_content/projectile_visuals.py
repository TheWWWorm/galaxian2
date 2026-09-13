"""Fresh ordinary projectile draw declarations, independently recognized per edition."""
import copy
from .ship_models import section_bytes

VALUES = {'item_ids':[2,19], 'model_ids':[6756,6795], 'kinds':[0,1],
          'camera_facing_kind':1, 'shrink_below_ms':1000, 'shrink_divisor':1000.0,
          'hidden_position_x':50000.0, 'reduced_billboard_scale':0.6000000238418579,
          'animation_speed':1.0, 'animation_loop':True, 'animation_shared_per_weapon':True,
          'render_type':2}


def extract_projectile_visuals(mach,staging,actors,opening):
    arch=mach.architecture
    if arch not in LAYOUTS:return {}
    try:
        if not staging['player_flight'] or actors['npc_initialization']['primary_weapon']['item_id']!=19:return {}
        if opening['ship_id']!=10:return {}
        origin=staging['provenance']['initial']['offset']
        at=mach.text['address']+origin-mach.slice_offset-mach.text['offset']
        proof={}
        for key,(delta,size,raw) in LAYOUTS[arch].items():
            section=b'__const' if (key in ['model_2','model_19'] or arch=='x86_64' and key.endswith('_constant')) else b'__text'
            found=section_bytes(mach,at+delta,size,section)
            if found is None or found[0]!=bytes.fromhex(raw):return {}
            proof[key]={'offset':found[1],'bytes':size}
        result=copy.deepcopy(VALUES);result['provenance']=proof
        return result
    except (KeyError,TypeError,IndexError,ValueError,OverflowError):return {}


LAYOUTS = {'x86_64': {'player_model_table': [-57355, 28, '488b45d04863c0488d0d5c1117008b04818945b085c00f8885010000'],
            'player_wrapper': [-56975, 27, '4c89ef4489fe4c89f28b4db041b8e80300004c8b4dc8e80b410600'],
            'npc_model': [-65918, 31, '41c78424a0000000010000004c89e7be13000000e89e43fcff41bf8b1a0000'],
            'npc_wrapper': [-63455, 29, '4889df31f64c89e24489f941b8112700004c8b7d984d89f9e8595a0600'],
            'wrapper_load': [353223, 26, '418b742420488d0514fb1d00488b38410fb7d731c9e83e7c0a00'],
            'orientation_kind': [353299, 31, '418b8ea000000083f908770cb001ba0a0100000fa3ca720230c04188442468'],
            'reduced_scale': [353330,
                              61,
                              '488d05d2011e00f600017431418b86a000000083f808772cb90a0100000fa3c1732241c74424589a99193f41c744245c9a99193f41c74424609a99193f'],
            'model_tick': [354101,
                           55,
                           '418b7620488d05a7f71d00488b38e897860a004963f54889b590feffff4889c731d2e8e307090045896e50498b7e104489eee85bfbf5ff'],
            'live_position': [356328,
                              44,
                              '488b48184863fa4c8d2c7ff3420f1004a90f2e05bb48100075060f8bc307000089b550fbffff899554fbffff'],
            'velocity': [356424,
                         78,
                         '498b4710488b78304c01f7e867e40800f30f118dd0fefffff30f1185c8feffff660f70c001f30f1185ccfeffff488b9d58fbffff4889df488db5c8feffffe874d9080041f64768010f849d010000'],
            'camera_basis': [356564,
                             269,
                             '488d050cee1d00488b184889dfe8e9820a004889df89c6e80f7f0a00488d5d984889df4889c6e850950b004889dfe828a30b00f30f118db0fefffff30f1185a8feffff660f70c001f30f1185acfeffff488dbdb8feffff488db5a8feffffe8c8d80800498b4710f30f1045984c8bad60fbfffff3410f114500f30f1045a8f3410f1187a0000000f30f1045b8f3410f1187b0000000f30f10459c8b8d54fbfffff3410f118794000000f30f1045acf3410f1187a4000000f30f1045bcf3410f1187b4000000f30f1085b8fefffff30f100dc6e310000f57c1f3410f118798000000f30f1085bcfeffff0f57c1f3410f1187a8000000f30f1085c0feffff0f57c1f3410f1187b8000000488b5078'],
            'last_second': [356833,
                            44,
                            '8b0c8a81f9e70300007f26f30f2ad1f30f5e151f731000488dbd68feffff4c89ee0f28c20f28cae8e2b30b00'],
            'new_shot_scale': [356882,
                               33,
                               'f68091000000010f8454040000488dbd28feffff4c89eef30f1015c6421000ebcf'],
            'world_up': [357482,
                         266,
                         'c785e8fcffff00000000c785ecfcffff0000803fc785f0fcffff000000004c89e7488db5e8fcffffe868d508004c89e74c89f6e86ddf0800f30f118de0fcfffff30f1185d8fcffff660f70c001f30f1185dcfcffff488b9d40fbffff4889df488db5d8fcffffe82ad508004889dfe8e2df0800f30f118dd0fcfffff30f1185c8fcffff660f70c001f30f1185ccfcffff4889df488db5c8fcffffe8f6d408004c89f74889dee8fbde0800f30f118dc0fcfffff30f1185b8fcffff660f70c001f30f1185bcfcffff4c89e7488db5b8fcffffe8bfd408004c89e7e877df0800f30f118db0fcfffff30f1185a8fcffff660f70c001f30f1185acfcffff4c89e7488db5a8fcffffe88bd40800'],
            'flight_basis': [357748,
                             193,
                             '8b8554fbfffff30f10034c8bad60fbfffff3410f114500f3410f108788000000f3410f1187a0000000f3410f10878c000000f3410f1187b0000000f3410f100424f3410f118794000000f3410f10477cf3410f1187a4000000f3410f108780000000f3410f1187b4000000f3410f1006f3410f118798000000f3410f104770f3410f1187a8000000f3410f104774f3410f1187b8000000498b4f10488b51788b04823de70300007f18f30f2ad0f30f5e15ee6e1000488dbd68fcffffe9cafbffff'],
            'scale_preset': [358010,
                             45,
                             '488d058aef1d00f600017421f3410f105760f3410f104758f3410f104f5c488dbde8fbffff4c89eee848af0b00'],
            'draw': [358293, 36, '418b7720488d1d47e71d00488b3b4c89eae8446e0a00418b7720488b3b31d2e856260a00'],
            'loop_setup': [1040855,
                           60,
                           'be0200000048ba0000000000000000488b45e04805b00100008b4df44889c78975bc89ce488955b0e89fbf0500488b388b75bc488b55b0e84c8bfeff'],
            'loop_update': [946100,
                            187,
                            '488b8830010000483b88280100000f8ea7000000488b8548ffffff817878020000000f8577000000488b8548ffffff4881b828010000000000000f851a000000488b8548ffffff488b882001000048898830010000e940000000488b8548ffffff488b8030010000488b8d48ffffff488b9120010000488bb12801000048899540ffffff489948f7fe488b8540ffffff4801c248899130010000e91c000000488b8548ffffffc6800d01000000488b882801000048898830010000'],
            'animation_defaults': [942446,
                                   39,
                                   '48c7803001000000000000c6800d0100000148c7801801000000000000c780100100000000803f'],
            'model_2': [1454439, 4, '641a0000'],
            'model_19': [1454507, 4, '8b1a0000'],
            'shrink_constant': [1434903, 4, '00007a44'],
            'hidden_constant': [1423547, 4, '00504347'],
            'unit_constant': [1422583, 4, '0000803f']},
 'armv7': {'player_model_table': [-59732, 18, '4af21471c0f2240117907944179851f82530'],
           'player_wrapper': [-58502, 22, '28914ff47a720f990092224601910e99109b67f011fc'],
           'npc_model': [-66740, 22, '269801222699ca651321cdf8c0b0c8f7e4fc41f68b2a'],
           'npc_wrapper': [-65584, 22, '2898309142f211712a468de802010021534669f0e6f9'],
           'wrapper_load': [364900, 24, '02980222039b836201690098006808929ab200235bf143ff'],
           'orientation_kind': [364942,
                                42,
                                '0198c06d40f00201032901d1012103e00021082808bf012147f28252c0f22202029b7a44126883f84c10'],
           'reduced_scale': [364984,
                             44,
                             '117899b118281edc0a2811dc082800f276800121814011f4857f70d0029a49f69a11c3f61971d16311645164'],
           'model_tick': [365996,
                          38,
                          '29697844d0f80080d8f800005cf111f8e61721463246002350f19bfd6c632146a86860f768fb'],
           'draw_constants': [367774, 10, '9fedacaa79449fedacca'],
           'live_position': [367876, 22, 'c168d046314491ed000ab4eeca0af1ee10fa00f08080'],
           'velocity': [367922, 30, 'dbf80800189680698119cdae30464ff187f8284631464ef1c3fd9bf84c00'],
           'camera_basis': [367978,
                            134,
                            '17985546066830465bf1c8fe01463046aa465bf121fdfdad0146284667f17cf8c7ae2946304667f147fdcaa831464ef19bfddbf80800fd99cbf87410ddf80414cbf88410ddf81414cbf89410fe99cbf87810ddf80814cbf88810ddf81814cbf898109dedca0ab9ff80078bed1f0a9dedcb0ab9ff80078bed230a9dedcc0ab9ff80078bed270a'],
           'last_second': [368112,
                           42,
                           'c16b51f8241020ef1001b1f57a7f80f2868041ec301bb8a8bbff200680ee0c0a10ee102a8ded000a0ee1'],
           'new_shot_scale': [368398,
                              34,
                              '90f84d00002800f094804ff07e5051460090a9a84ff07e524ff07e5368f1e4fb87e0'],
           'world_up': [368478,
                        102,
                        '00204ff07e517090719170a9729030464ef1b0fc0df5da7a31462a4650464ef123ffb0460d9e514630464ef1a3fc6aad314628464ef15eff304629464ef19afc67ad1599324628464ef10eff404629464ef190fc64ad414628464ef14bff404629464ef187fc'],
           'flight_basis': [368580,
                            124,
                            'dbf86800cbf87400dbf86c00cbf88400dbf87000cbf89400dbf85c00cbf87800dbf86000cbf88800dbf86400cbf89800dbf85000cbf87c00dbf85400cbf88c00dbf85800cbf89c00dbf80800c16b51f82410b1f57a7fbff654ae41ec301b55a8bbff2006ddf840a080ee0c0a8ded000a10ee102a5146134668f15bfb'],
           'scale_preset': [368704, 32, '1498159d007858b1dbe90f2337a89bed110a51468ded000a20ef100168f14bfb'],
           'draw': [368918, 34, '179e5246dbf8101030685bf17ff9dbf810100022306858f1d5fadbf80800139a189e'],
           'loop_setup': [1790306, 18, '0221c0f200010022c0f200020068f4f78bff'],
           'loop_update': [1745310,
                           184,
                           'd2f80431d2f808914ff0000c4945e646d8bf4ff0010e984298bf4ff0010c494508bfe646bef1000f46d1ffe70e98816d022934d10e98d0f80411d0f80821114300290ad1ffe70e98d0f8fc10d0f80021c0f81021c0f80c1120e00e98d0f80c010e99d1f810110e9ad2f8fc30d2f80091d2f80421ddf838c0dcf808e10d937346cdf830904bf09ae90d9a80180c9a41eb02010e9ac2f80c01c2f810110be000200e9981f8ed00d1f80401d1f80821c1f81021c1f80c01ffe7'],
           'animation_defaults': [1743666, 18, 'c1f8f420012081f8ed004ff07e50c1f8f000'],
           'model_2': [2342358, 4, '641a0000'],
           'model_19': [2342426, 4, '8b1a0000'],
           'shrink_constant': [368470, 4, '00007a44'],
           'hidden_constant': [368466, 4, '00504347']}}
