"""Optional Mac ordinary weapon model mappings for the training encounter."""
import copy
import hashlib
from .station_exterior import declaration_bytes


def extract_combat_training_visuals(mach, arrival, weapons, staging):
    if mach.architecture != 'x86_64':
        return {}
    try:
        if weapons.get('scope') != 'combat_training_ordinary_weapons':
            return {}
        if not staging['projectile_visuals'] or not staging['projectile_impacts']:
            return {}
        origin = arrival['provenance']['actor']
        if origin['bytes'] != 315:
            return {}
        anchor = mach.text['address'] + origin['offset'] - mach.slice_offset - mach.text['offset']
        proof = {}
        for key, (delta, size, section, digest) in LAYOUTS.items():
            found = declaration_bytes(mach, anchor + delta, size, section.encode())
            if found is None or hashlib.sha256(found[0]).hexdigest() != digest:
                return {}
            proof[key] = {'offset': found[1], 'bytes': size}
        result = copy.deepcopy(VALUES)
        result['provenance'] = proof
        return result
    except (KeyError, TypeError, ValueError, IndexError, OverflowError):
        return {}


VALUES = {'scope': 'combat_training_ordinary_visuals',
 'campaign_cursor': 7,
 'weapons': [{'owner': 'player',
              'actor_ids': [],
              'item_id': 0,
              'kind': 0,
              'capacity': 20,
              'projectile_model_id': 6754,
              'projectile_resource': 'resources/data/assets/main/3d/meshes/fx/projectile_000_anim_add.aem',
              'impact_model_id': 14600,
              'impact_resource': 'resources/data/assets/main/3d/meshes/fx/impact_000_lookat_anim_add.aem'},
             {'owner': 'player',
              'actor_ids': [],
              'item_id': 22,
              'kind': 2,
              'capacity': 25,
              'projectile_model_id': 6798,
              'projectile_resource': 'resources/data/assets/main/3d/meshes/fx/projectile_022_anim_add.aem',
              'impact_model_id': 14606,
              'impact_resource': 'resources/data/assets/main/3d/meshes/fx/impact_006_lookat_anim_add.aem'},
             {'owner': 'npc',
              'actor_ids': [0, 1, 2],
              'item_id': 19,
              'kind': 1,
              'capacity': 4,
              'projectile_model_id': 6795,
              'projectile_resource': 'resources/data/assets/main/3d/meshes/fx/projectile_019_anim_add.aem',
              'impact_model_id': 14605,
              'impact_resource': 'resources/data/assets/main/3d/meshes/fx/impact_005_lookat_anim_add.aem'},
             {'owner': 'npc',
              'actor_ids': [3],
              'item_id': 25,
              'kind': 0,
              'capacity': 4,
              'projectile_model_id': 6802,
              'projectile_resource': 'resources/data/assets/main/3d/meshes/fx/projectile_026_anim_add.aem',
              'impact_model_id': 14606,
              'impact_resource': 'resources/data/assets/main/3d/meshes/fx/impact_006_lookat_anim_add.aem'}],
 'player_effect_setup_before_field_seed': True,
 'player_impact_assignments': 1,
 'impact_random_flip_used': False}

LAYOUTS = {'wrapper_default': [475185,
                     6,
                     '__text',
                     'f14ae3be6b76e78dd58bc5fa7949d2e1b7bc01db4e86f1d085cb21464a2e0270'],
 'captured_up_draw': [479454,
                      55,
                      '__text',
                      '133471d491c02b536b4bfc5795c3e4f93144d323ac7da78f8d750cfd9bcbeca7'],
 'captured_up_launch': [-186411,
                        59,
                        '__text',
                        '07c737c5bb22c816baabe42ff63b156d8c52706fc79e3f0b8c205cecb7c86168'],
 'matrix_up': [1241222,
               15,
               '__text',
               'b786e38224ecb3139b2bf7e734bd7d0048ca7a64bd68e95f64e3ccc055bafb9d'],
 'player_flag': [-187812,
                 14,
                 '__text',
                 '84a110a2d5d1a9f1e1342afe8dd9c22d4961fd8e1b386c8a096d305d27472d47'],
 'impact_0': [1572842,
              4,
              '__const',
              '2f71717123e07e2e209cc0dc807e9d1e48dd2e9d0cddb9e5238afa837b209770'],
 'impact_19': [1572918,
               4,
               '__const',
               'ba68c0bc07a4ca462026f5108537fb3a023f3095f79c0d4c205fde3e86089e80'],
 'impact_22': [1572930,
               4,
               '__const',
               'b18cc146d20e56ff0808059bc8ddf272dc008ee143402c5d32424175d3b54720'],
 'impact_25': [1572942,
               4,
               '__const',
               'b18cc146d20e56ff0808059bc8ddf272dc008ee143402c5d32424175d3b54720'],
 'projectile_0': [1576458,
                  4,
                  '__const',
                  '36984f0f9871e85edea08d3492809d05459229f43a3e948d05df70451e7ad6b3'],
 'projectile_22': [1576546,
                   4,
                   '__const',
                   'e7a31085b22247cc08bcdbd23fb51854506464a75e14e65185a301f27b7e704b']}
