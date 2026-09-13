"""Recognize ordinary projected-forward aim declarations without executing code."""
import copy
from .ship_models import section_bytes

VALUES = {'mode': 'projected_forward', 'distance': 22000.0, 'new_weight': 0.20000000298023224, 'previous_weight': 0.800000011920929, 'initial_aim': [0, 0, 0], 'initial_contact': False, 'initial_contact_ms': 0, 'contact_limit_ms': 201, 'reticle_phase': 4, 'image_ids': [1216, 1230], 'texture_id': 10062, 'image_regions': [115, 129], 'motion_before_aim': True, 'aim_before_camera': True, 'draw_before_contact_expiry': True}

def extract_player_aim(mach, staging, projection):
    arch=mach.architecture
    if arch not in LAYOUTS:return {}
    try:
        if not staging['player_flight'] or not staging['player_motion'] or not staging['projectile_impacts'] or not projection:return {}
        origin=staging['provenance']['initial']['offset']
        at=mach.text['address']+origin-mach.slice_offset-mach.text['offset']
        proof={}
        for key,(delta,size,raw) in LAYOUTS[arch].items():
            found=section_bytes(mach,at+delta,size,b'__const' if key.endswith('_constant') else b'__text')
            if found is None or found[0]!=bytes.fromhex(raw):return {}
            proof[key]={'offset':found[1],'bytes':size}
        result=copy.deepcopy(VALUES);result['provenance']=proof
        return result
    except (KeyError,TypeError,IndexError,ValueError,OverflowError):return {}

LAYOUTS = {'x86_64': {'initial_aim': [428166, 22, '48c783d80000000000000048c783d000000000000000'],
            'initial_timer': [428859, 10, 'c783e802000000000000'],
            'initial_world_contact': [-168052, 4, 'c6434000'],
            'body_vectors': [460729,
                             96,
                             '498b3e4883c708e8ca0c0a00f30f118d20fdfffff30f118518fdffff660f70c001f30f11851cfdffff498b3e4883c708e8410c0a00f30f118d10fdfffff30f118508fdffff660f70c001f30f11850cfdffff41f68618020000010f849a000000'],
            'projected_mode': [460979,
                               263,
                               '488d051d581c008338007420807d1800751a41f686a8010000018b45200f84e400000083f8010f84e4000000488dbd08fdffffe8d44b0700f30f118d20fcfffff30f118518fcffff660f70c001f30f11851cfcfffff30f1005ef540f00488dbd18fcffffe8e3450700488dbd18fdffff488db528fcfffff30f118d30fcfffff30f118528fcffff660f70c001f30f11852cfcffffe8a3430700488db538fcffff488d15b59c1c00488d0586551c00f30f118d40fcfffff30f118538fcffff660f70c001f30f11853cfcffff488b38e899f10800660fefc0f30f100d859c1c000f2ec80f861d0300008b05769c1c00898510fcffff488b05619c1c0048898508fcffffe990030000'],
            'smoothing': [462008,
                          165,
                          '488d3d50991c00f30f1005fcab0e00e8c3410700f30f118d00fcfffff30f1185f8fbffff660f70c001f30f1185fcfbffff498dbed0000000f30f100557ad0e00e892410700488dbdf8fbffff488db5e8fbfffff30f118df0fbfffff30f1185e8fbffff660f70c001f30f1185ecfbffffe8c23f0700f30f118d10fcfffff30f118508fcffff660f70c001f30f11850cfcffff488d3dbe981c00488db508fcffffe8a23c0700'],
            'retain_aim': [462265, 19, '498dbed0000000488d3548981c00e8333c0700'],
            'image_loads': [430949,
                            57,
                            '488d93d80200004c8d3d74cb1c004885c00f958342040000498b3fbec0040000e8f5160900488d93dc020000498b3fbece040000e8e1160900'],
            'idle_alias': [-650759,
                           64,
                           'bf18000000e87e931f004889c3bf04000000e871931f0066c7004e2766c74002730066c703c004c7430403000000c74308ffffffff4889431048899d50d4ffff'],
            'contact_alias': [-650439,
                              64,
                              'bf18000000e83e921f004889c3bf04000000e831921f0066c7004e2766c74002810066c703ce04c7430403000000c74308ffffffff4889431048899d78d4ffff'],
            'player_contact_enable': [-57001, 13, '4c89f7be01000000e83f24fcff'],
            'contact_setter': [-309853, 14, '554889e54088b7480100005dc390'],
            'npc_contact': [-304564, 24, '41c64424580141f68748010000017408498b4770c6404001'],
            'draw_gate': [481324,
                          203,
                          '4883bb00020000000f856e020000488bbb780200004885ff7413f6831802000001750ae8738b0600e94f020000488bbb700200004885ff740ae8cbd9fcffe939020000f68388020000010f85ff010000488b3be8a3fefeff85c00f8eef010000f64340010f85e50100004180f6014584f60f85d8010000f68348020000010f85cb010000f68382020000010f85be010000f68381020000010f85b1010000f683f203000001740df68318020000010f849b0100008a8318020000f683a8010000017408a8010f8484010000'],
            'draw_feedback': [481770,
                              143,
                              '488d05f6041c00488b38488b4318f6404001744a8bb3dc020000f30f2c0d074c1c00f30f2c15fb4b1c0041b81100000041b944000000e8fa3008008b83e80200000383840100008983e80200003dc90000007c62488b4318c6404000eb588bb3d8020000f30f2c0dbd4b1c00f30f2c15b14b1c0041b81100000041b944000000e8b0300800c783e802000000000000'],
            'player_before_world': [244328, 40, 'e804200300498b7d60e875ef020088c349637548498bbd90000000410fb6556b83e201e89933fcff'],
            'controller_later': [255610, 5, 'e8965afcff'],
            'distance_constant': [1465855, 4, '00e0ab46'],
            'new_weight_constant': [1423555, 4, 'cdcc4c3e'],
            'previous_weight_constant': [1423951, 4, 'cdcc4c3f']},
 'armv7': {'initial_aim': [384182,
                           100,
                           '80ef5080044604f144004ff07e532364002200f98f8a04f158000125636500f98f8a04f19400a366e26623676367a367c4f84421c4f84821c4f84c21c4f86021c4f86421c4f86821c4f8c421c4f8c821c4f8cc21c4f82022c4f82422c4f8282200f98f8a'],
           'initial_timer': [384570, 4, 'c4f84822'],
           'initial_world_contact': [-163182,
                                     238,
                                     'c0ef500000f5ea7300224ff07e59c0f8b420c7ef502fc0f8b820c0f8bc20c0f8c820c0f8cc20c0f8d020c0f88c21c0f89021c0f89421c0f8d09143f98f0a00f5f473c0f8e49143f98f0a00f50473c0f8f891c0f8fc21c0f80092c0f80492c0f80892c0f80c9243f98f0a00f50973c0f8209243f98f0a00f50f73c0f83492c0f8382243f98f2a00f5137343f98f0a00f51873c0f85c9243f98f0a00f11c03c0f87092c0f87422c0f87892c0f87c92c0f88092c0f8c0104ff0ff310161c16081604160c0f8c420c0f8b020c0f84821c0f84421c0f84021c0f85021c0f8542180f8582143f98f0a00f19003c0f82d20'],
           'body_vectors': [409376, 34, 'dbf80000ec95011d54a85df192fcdbf80000ec95011d51a85df173fc9bf89c0158b3'],
           'projected_mode': [409498,
                              54,
                              'd8f8001000207a6900294ff0000108bf0121114340f0bd809bf854110029b96908bf01200a46012a18bf0021084318bf032a00f0ae80'],
           'projection_smoothing': [409900,
                                    204,
                                    '30ac51a9da464ff0ff3b2046cdf8b0b344f189fe33ad4ef20001c4f2ab6122462846cdf8b0b344f154fd36ae54a92a46cdf8b0b3304644f1aafc07983146006846f2e244c0f22404cdf8b0b37c44224651f113fe94ed020ab5eec00af1ee10fa06ddd4ed000ba0682f90cded2d0b21e046f2b0412aacc0f224014cf6cd427944c3f64c622046cdf8b0b344f1f8fc27ad4cf6cd420af19401c3f64c722846cdf8b0b344f1ecfc2da821462a46cdf8b0b344f16dfc46f26c404ff0ff31c0f22400ec9178442da944f16efb5646'],
           'retain_aim': [410516, 34, '46f2b021c0f224014ff0ff34002818bf012086f87403794406f19400ec9444f18efa'],
           'image_loads': [386034, 40, '05f50e72d1f800804ff49861d8f80000089454f10bfdd8f8000005f50f7240f2ce41089454f102fd'],
           'idle_alias': [-945118,
                          98,
                          '1020c4f87035dbf290efc5f8080940f64100c4f870050420dbf286ef03ae42f24e7206f58151c0f273024ff4986313ae0d46d5f808190260d5f8082913800323d5f8082953604ff0ff33d5f808299360d5f80829d06006f58b4241f214100bae1150'],
           'contact_alias': [-944598,
                             98,
                             '1020c4f87035dbf28ceec5f81c0940f64600c4f870050420dbf282ee03ae42f24e7206f58151c0f2810240f2ce4313ae0d46d5f81c190260d5f81c2913800323d5f81c2953604ff0ff33d5f81c299360d5f81c29d06006f58b4241f228100bae1150'],
           'player_contact_enable': [-58526, 10, '204601212895c6f779fe'],
           'contact_setter': [-292770, 6, '80f8f0107047'],
           'npc_contact': [-288898,
                           350,
                           '0125012851d11ae20e98012501284cd19ded490a9ded431adaf8000061ef000d9ded460a40ec320b00ef802dbbff2206b4eec02af1ee10fa40f1ad81404240ec300bbbff2016b4eec12af1ee10fa40f3a2819ded4a2a9ded443a9ded474a63ef020d00ef842db4eec02af1ee10fa40f19281b4eec12af1ee10fa40f38c819ded4b2a9ded453a9ded484a63ef020d00ef842db4eec02af1ee10fa40f17c81b4eec12af1ee10fa40f376810898012800f0a081dbf8641047f625000c94ccf29950814204d09bf8f9203046a1f025ffdbf804000f9c18b190f85c00002818d096f8690038b3dbf8380043f09afb10b3dbf8380043f095fba5f0edfb01281ad19bed180afbff000640ff980d40ff9a0d08e096f8690070b19bed180afbff000640ff9c0dbbff2007dbf8583010ee101a05e0cdcc4c3edbf85830dbf860109bf8f9203046a2f00bf886f8545046ab9bf8f000a84600281cbfdbf8380080f83050'],
           'draw_gate': [424998,
                         164,
                         'b0b502af4df8048d91b004460d46d4f89001002840f00581d4f8e40118b194f89c1100293bd0d4f8e00110b1def704faf7e094f8f00108bb2068f3f7bdfc01281cdb94f82400c8b995f0010004bf94f8bc01002812d194f8ea0178b994f8e90160b994f8520310b194f89c0130b194f89c0194f85411a9b1002813d194f85401002840f0cb8094f85203002800f0c980d4f8c00101380328c0f0c380bee05ef0c5f8bee0'],
           'draw_feedback': [425328,
                             210,
                             'e06890f830102868002944d042f6ce014ff04409c0f224014ff01108794491ed000a91ed011abbff0007d4f83c12bbff0117cde9008910ee102a11ee103a49f1c6fdd4f83001d4f848120844c4f84802c928a2bfe068002180f8301039e042f68401c0f22401794491ed000a91ed011abbff0007d4f84012bbff011710ee102a11ee103a4ff044094ff01108cde9008949f19dfd1de042f644014ff04409c0f224014ff01108794491ed000a91ed011abbff0007d4f83812bbff0117cde9008910ee102a11ee103a49f181fd0020c4f84802'],
           'player_before_world': [253418, 40, '23f096fedbf854004ff0ff36b49621f095fcdbf83c1005469bf85b30dbf87000ca17b496c1f7e0f9'],
           'controller_later': [264340, 4, 'c2f7cdfd']}}
