"""Optional Mac game-over atlas and display declarations, read only at import."""
import copy
from .declaration_layouts import recognize
from .station_exterior import declaration_bytes

def extract_game_over_presentation(mach,arrival,death):
    if mach.architecture!='x86_64':return {}
    try:
        if death['scope']!='mac_starter_player_destruction' or death['game_over_image_id']!=1313 or death['continue_text_id']!=188:return {}
        origin=arrival['provenance']['actor']
        if origin['bytes']!=315:return {}
        layouts=[{k:[v[2],v[0],v[1],v[3]] for k,v in rows.items()} for rows in [LAYOUTS,MAC_ALTERNATE]]
        proof=recognize(mach,origin['offset'],layouts,reader=declaration_bytes)
        if not proof:return {}
        values=VALUES
        result=copy.deepcopy(values);result['provenance']=proof
        return result
    except (KeyError,TypeError,ValueError,IndexError,OverflowError):return {}

VALUES = {'scope': 'mac_starter_game_over_presentation',
 'image_id': 1313,
 'texture_id': 10062,
 'region': 211,
 'resource': 'resources/data/textures/gof2_interface.aei',
 'continue_text_id': 188,
 'blink_radians_per_millisecond': 0.003000000026077032,
 'prompt_gap': 10,
 'center_image': True,
 'center_prompt': True,
 'prompt_rgb': [255, 255, 255],
 'prompt_after_full_fade': True,
 'blink_uses_absolute_milliseconds': True}

LAYOUTS = {'image_alias': [-524764,
                 64,
                 '__text',
                 'bf18000000e8fe831f004889c3bf04000000e8f1831f0066c7004e2766c74002d30066c7032105c7430403000000c74308ffffffff4889431048899d40d6ffff'],
 'alias_collection': [-388935,
                      32,
                      '__text',
                      '488db5f0b2ffff4d8967104c897db0498b4640488b38ba99090000e8a1351700'],
 'alias_collection_helper': [1132154,
                             64,
                             '__text',
                             '554889e54883ec2048897df8488975f08955ec488b75f8488b7df08b55ec4881c668010000488975e089d6488b55e0e8ae3506004883c4205dc3660f1f440000'],
 'failure_display': [390050,
                     435,
                     '__text',
                     'sha256:89182536edb047b0d25f86933ebc1736af0bffa0361e8c7d23d5fc705d1fae55'],
 'image_positioning': [1140682,
                       1120,
                       '__text',
                       'sha256:0f0b1ef38f9ac188e368e5a7ab686e47e1060ded0b46205b410f5be4aada1771'],
 'image_height': [1140586,
                  96,
                  '__text',
                  '554889e54883ec2048897df08975ec488b7df08b75ec3bb79801000048897de00f820c000000c745fc00000000e91f000000488b45e04805980100008b75ec4889c7e825160600488b000fb770168975fc8b45fc4883c4205dc3660f1f440000'],
 'sine_wrapper': [1248314,
                  48,
                  '__text',
                  '554889e54883ec10f30f1145fcf30f5a45fce8f5760400f20f5ac04883c4105dc36666666666662e0f1f840000000000'],
 'blink_constant': [1584146, 4, '__const', 'a69b443b'],
 'alpha_constant': [1573874, 4, '__const', '00007f43']}

# Complete independently verified alternate Mac layout.
MAC_ALTERNATE = {'image_alias': [-527198,
                 64,
                 '__text',
                 'bf18000000e8cc2b1f004889c3bf04000000e8bf2b1f0066c7004e2766c74002d30066c7032105c7430403000000c74308ffffffff4889431048899d18d6ffff'],
 'alias_collection': [-390823, 32, '__text', '488db500b2ffff4d8967104c897db8498b4640488b38bab8090000e8d9391700'],
 'alias_collection_helper': [1131346,
                             64,
                             '__text',
                             '554889e54883ec2048897df8488975f08955ec488b75f8488b7df08b55ec4881c668010000488975e089d6488b55e0e822d705004883c4205dc3660f1f440000'],
 'failure_display': [390566, 435, '__text', 'sha256:03031925d9149fe368e8f07a93185bb0cbb01c4af24962a2458dc474ad7382a7'],
 'image_positioning': [1139394,
                       1040,
                       '__text',
                       'sha256:2aa4561a7de1b1e774c1ffea65082c48bf7bdf011adadb9949cec67088a2442e'],
 'image_height': [1139298,
                  96,
                  '__text',
                  '554889e54883ec2048897df08975ec488b7df08b75ec3bb79801000048897de00f820c000000c745fc00000000e91f000000488b45e04805980100008b75ec4889c7e879b90500488b000fb770168975fc8b45fc4883c4205dc3660f1f440000'],
 'sine_wrapper': [1241138,
                  48,
                  '__text',
                  '554889e54883ec10f30f1145fcf30f5a45fce849310400f20f5ac04883c4105dc36666666666662e0f1f840000000000'],
 'blink_constant': [1559210, 4, '__const', 'a69b443b'],
 'alpha_constant': [1548938, 4, '__const', '00007f43']}
