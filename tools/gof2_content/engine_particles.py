"""Optional Mac Betty exhaust declarations, recovered at import only.

These bounded source spans establish constant content. Executable bytes are
never retained, and particle behavior is implemented independently in Godot.
"""
import copy
from .station_exterior import hashed_declarations

def extract_engine_particles(mach,arrival,damage):
    if mach.architecture!='x86_64':return {}
    try:
        if damage['scope']!='damage_particle_sprite_presets' or 'emitter_defaults' not in damage:return {}
        proof=hashed_declarations(mach,arrival,{key:[delta,size,section,digest[7:]]
            for key,(delta,size,section,digest) in LAYOUTS.items()})
        if not proof:return {}
        result=copy.deepcopy(VALUES);result['provenance']=proof
        return result
    except (KeyError,TypeError,ValueError,IndexError,OverflowError):return {}

VALUES = {'scope': 'mac_betty_nozzle_particles',
 'ship_id': 0,
 'attachment_category': 3,
 'nozzle_count': 4,
 'first_preset': 29,
 'scale_multiplier': 1.5,
 'scale_limit': 1.0,
 'initial_emitting': True,
 'material_type': 3,
 'texture_id': 24202,
 'preset': {'preset_id': 29,
            'material_id': 20090,
            'flags': 17,
            'capacity': 20,
            'size_jitter': 0,
            'lifetime_ms': 80,
            'even_spacing': 1,
            'fade_in_ms': 0,
            'size_growth_per_second': -1000,
            'scatter_xz': 0,
            'scatter_y': 0,
            'velocity_scatter': 100,
            'animation_frames': 0,
            'size': 250.0,
            'distance_spacing': 8.0,
            'relative_velocity_factor': 0.800000011920929,
            'local_velocity_z': -4000.0,
            'local_offset_x': 0.0,
            'local_offset_y': 0.0,
            'local_offset_z': 0.0,
            'local_offset_z_jitter': 0.0,
            'minimum_squared_speed': 1,
            'start_rgba': [221, 221, 221, 255],
            'end_rgba': [0, 0, 0, 0],
            'uv_rect': [0.005859375, 0.005859375, 0.119140625, 0.119140625]}}

LAYOUTS = {'defaults': [483042,
              211,
              '__text',
              'sha256:a45d4e3d94355bfb5e51a7428f530d9c92088984bdfa01d4d591f7824e1409fd'],
 'basic_and_four_copies': [483319,
                           2344,
                           '__text',
                           'sha256:4f724e4fd68ede043f7ac5f905693eff9362905107b0d26e03f94a645c9630b8'],
 'nozzle_setup': [61403,
                  694,
                  '__text',
                  'sha256:73a3a672452aece3899787c80fe596a6f09d29f2f8ac334631b3ea50926b654b'],
 'nozzle_constants': [1582362,
                      32,
                      '__const',
                      'sha256:6910dcd8fe2e9423be9b60b97a8de56c1681144145aa2f40455f36400efde5f2'],
 'size_constant': [1575358,
                   4,
                   '__const',
                   'sha256:790ae12c34496bfe41c52a4786035ab076ce6771b936c6adf4608fd641420958'],
 'speed_constant': [1575098,
                    4,
                    '__const',
                    'sha256:d4d7872536d6219129a11acebac252c04c1129ef770c2ecc9ebdf1ac7d5abc93'],
 'hull_color': [1576010,
                4,
                '__const',
                'sha256:9d9f290527a6be626a8f5985b26e19b237b44872b03631811df4416fc1713178'],
 'color_cases': [64294,
                 36,
                 '__text',
                 'sha256:67ce6de3545b8bb2fa539afcd8f67777e2c44526df277265e724879d852b2845'],
 'manager': [-43546,
             44,
             '__text',
             'sha256:43ea15109f982ad5e4eee9df6f07298a086a138b672d26282428af7e3b8547a8'],
 'attachment_positions': [-36633,
                          278,
                          '__text',
                          'sha256:52e99e9f75d8e10acc771cefef3f8dedfa6e9be670f130a1a57a29b57e95ae19']}
