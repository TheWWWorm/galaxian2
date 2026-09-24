"""Static Mac declarations for physical player/scenery contacts.

The two recognized compiler layouts are read as bounded data. This reader does
not execute the source binary or emit any of its instructions into a pack.
"""

import copy

from .declaration_layouts import recognize
from .station_exterior import declaration_bytes


VALUES = {
    'scope': 'physical_scenery_contacts',
    'player_stage': 'after_motion_before_aim_recharge',
    'collision_gate': 'player_permission_and_active_statistics',
    'station_slot': 0,
    'station_contact': 'strict_authored_point_volume',
    'station_projection_passes': 2,
    'station_damage': 0,
    'asteroid_contact': 'strict_point_inside_intact_body_axis_box',
    'asteroid_damage': 9999,
    'player_damage': 20,
    'asteroid_impact': 'body_center_minus_player_center_normalized',
    'selected_mining_target_excluded': True,
    'mining_finish': 'inactive_negative_hull_without_combat_destruction',
    'opening_collision_initial_enabled': False,
    'opening_collision_enabled_phase': 4,
    'opening_collision_escape_phase': 5,
    'opening_collision_earned_escape_enabled': False,
    'opening_collision_sample': 'incoming_player_phase_before_controller',
}

# Layouts are relative to the already verified arrival actor. SHA-256 protects
# each complete route, including response geometry and the mining sentinel.
# The order is App Store Mac, then the older Mac source.
LAYOUTS = (
    {
        'player_sample': (571779, 52, '__text', 'sha256:e43364b1b218711b28814b560af59a8b342c147e960c3cf5628f6e15fdd1df13'),
        'player_motion': (576697, 142, '__text', 'sha256:31c1173b85f29179770f519832110c42703c75837aea26cb4faf40464ed2ccfd'),
        'collision_gate': (576839, 90, '__text', 'sha256:293bec3c26245ba45cb0f1f83c7007e8c0742edca43f97cd636ea4f9e039bf07'),
        'world_contact': (585516, 1666, '__text', 'sha256:6291961459685f1c54e878ed459442c56c2bb4e1e557f57861f3cffc0d7df75b'),
        'asteroid_active': (547365, 22, '__text', 'sha256:68f1f2cde96fa48a3e3e78f682a34986b35d17fd70e21eb0c9b0065a23137d1b'),
        'asteroid_normal': (550106, 158, '__text', 'sha256:9a2741c5a98ab7f493032d0db64741988815125b3c76c6b4bd055ad0a59a4661'),
        'asteroid_collider': (550264, 202, '__text', 'sha256:323b3f0aa70674d1cf6623bb81f2e31a5b5d787444fbce3174d66004f31eafe0'),
        'asteroid_vtable': (2376994, 72, '__const', 'sha256:4786838275210ca1cf9d9b6c1dad20b9e2907203b651b1c732377ad1eaeaf185'),
        'station_query': (650374, 232, '__text', 'sha256:fb5c26f9ca56ebe49f7b5725afc701ab8c33622a7a223bd23430c72546bb1b25'),
        'station_projection': (-713946, 190, '__text', 'sha256:f87b4e38414c5d4bce79fc21926ba8dbe8e8dfa53de88199f4849d111f1e9e59'),
        'station_response_vtable': (2378722, 24, '__const', 'sha256:140b9de14b108a9ded457c2e5eaa488e2065394f820a145a81f78c4307b33f20'),
        'box_projection': (-715776, 498, '__text', 'sha256:65462a43ad8150a0d241548447f875b21c9217184361f5a6d57a792bc0bfa323'),
        'sphere_projection': (-714814, 236, '__text', 'sha256:1e8711e9b6dfb1ad2d877e82172217b15753231f85996a22b5de806142679681'),
        'mining_finish': (602607, 61, '__text', 'sha256:22664bc5ac3d8d0148c7fcf21212078b47585079d01244ac1ab924b5a0643a4c'),
        'permission_setter': (560162, 14, '__text', 'sha256:72c854ab442e1d26da6d19e240e26911b289aa942d1d28ebd5fa79efb1dc85e2'),
        'opening_constructor_off': (122009, 18, '__text', 'sha256:6d9d874bc7a4286be626c884c4c1462d6ad8cbeb5ce523c992b52887deee397a'),
        'opening_release_on': (139783, 128, '__text', 'sha256:34d4f4a5ab2018215ae4197c1a9d7279c05103c687f3af5aa3c099075cf3ece7'),
        'opening_escape_off': (150612, 306, '__text', 'sha256:29aa6d80b917e302bbe916b75e96f74fd96996807e1949422eb6fcb8aa716861'),
        'opening_escape_guard': (150932, 250, '__text', 'sha256:1073984dc13794f28a8a9fd65528f7dfa5952f7dca68bfa745995b3ee55bc040'),
    },
    {
        'player_sample': (571243, 52, '__text', 'sha256:d30c0e56ca68e9763192db1db9d03c20a6790c33159343c950886b930376d91c'),
        'player_motion': (576161, 142, '__text', 'sha256:494a9a3967940c307708445641b658c3089efe1e856b3f1cf78668042ab58a57'),
        'collision_gate': (576303, 90, '__text', 'sha256:737ab42ce6d4158870418b9c89b9467b87af3b5a315c182fc242354623cc5469'),
        'world_contact': (584980, 1664, '__text', 'sha256:dba54a15b0187d1df48d2606405ccdb99b49380e238efca044a092c593bd024a'),
        'asteroid_active': (546829, 22, '__text', 'sha256:68f1f2cde96fa48a3e3e78f682a34986b35d17fd70e21eb0c9b0065a23137d1b'),
        'asteroid_normal': (549570, 158, '__text', 'sha256:5ff6dbf2a5bca2966f365ec228b780a40df56df2ed6552f0015b92ef8f31ab40'),
        'asteroid_collider': (549728, 202, '__text', 'sha256:c2e45edc38e4b96153881f0a328c82f0cef4f8bdadc10f13fdf754b75ed2afcd'),
        'asteroid_vtable': (2399562, 72, '__const', 'sha256:98ceb7da740629ba09baae43eac283fe612cc0fe8adcf5e2b9809611e1e383ee'),
        'station_query': (649826, 232, '__text', 'sha256:fb5c26f9ca56ebe49f7b5725afc701ab8c33622a7a223bd23430c72546bb1b25'),
        'station_projection': (-708050, 190, '__text', 'sha256:27c3fcc081133c72c85fcf7aa95d63f90eafaff322fd9553f1bb3c70c30df61b'),
        'station_response_vtable': (2401290, 24, '__const', 'sha256:cfd1fbfaedf52ae26138ab528022d02fd1a05d8e689829ccd2b7d962d975d363'),
        'box_projection': (-709880, 498, '__text', 'sha256:bdd49c9c468882734200b5c30f1c2ffe93f4a175356a1a85a79a7b0b490da03d'),
        'sphere_projection': (-708918, 236, '__text', 'sha256:146dc1e4b292e53be36ef132aafa7000fde518513f2dce1f9ff7930c706ca23d'),
        'mining_finish': (602059, 61, '__text', 'sha256:3f907355c0f646f4e39c4783753a35f84b0e4c34322999f7b5116f72a856c5c4'),
        'permission_setter': (559626, 14, '__text', 'sha256:72c854ab442e1d26da6d19e240e26911b289aa942d1d28ebd5fa79efb1dc85e2'),
        'opening_constructor_off': (122009, 18, '__text', 'sha256:bd8a2d1f69a8e7d58e1053130e20ceedf2f32704acd8a2fda7f4eb9a6a46982b'),
        'opening_release_on': (139783, 128, '__text', 'sha256:1c29ed2df466f05d3f090107ef2c00c54dc5815cd479848506eaa7972c01ce1b'),
        'opening_escape_off': (150612, 306, '__text', 'sha256:81bf5e61d073d8d88f9bbd3589bd0807ae686e10b2d094dbb030a6aef5149d64'),
        'opening_escape_guard': (150932, 250, '__text', 'sha256:1d44cf7c84cc588cb30af3fa872ac75866c64a8bf47b93774ae2a86cd6804a24'),
    },
)


def extract_physical_scenery_contacts(mach, arrival, scenery_resources, station_exterior, opening_staging):
    """Return a new optional capability only when one whole Mac layout matches."""
    if mach.architecture != 'x86_64' or not scenery_resources or station_exterior.get('scope') != 'first_mining_station_exterior':
        return {}
    try:
        origin = arrival['provenance']['actor']
        if origin['bytes'] != 315:
            return {}
        initial = opening_staging['provenance']['initial']
        motion = opening_staging['player_motion']
        escape = opening_staging['escape']
        if (initial['bytes'] != 366 or motion['motion_before_controller'] is not True
                or motion['release_phase'] != VALUES['opening_collision_enabled_phase']
                or motion['release_after_event_finished'] != 8
                or escape['entry_phase'] != motion['release_phase']
                or escape['first_phase'] != VALUES['opening_collision_escape_phase']
                or escape['entry_after_event_finished'] != 10):
            return {}
        links = {
            'opening_constructor_off': initial['offset'] - 18,
            'opening_release_on': motion['provenance']['release']['offset'],
            'opening_escape_off': escape['provenance']['entry']['offset'],
        }
        layouts = [{key: (row[2], row[0], row[1], row[3])
                    for key, row in variant.items()} for variant in LAYOUTS]
        proof = recognize(mach, origin['offset'], layouts, links=links, reader=declaration_bytes)
        if not proof:
            return {}
        result = copy.deepcopy(VALUES)
        result['provenance'] = proof
        return result
    except (KeyError, TypeError, ValueError, IndexError, OverflowError):
        return {}
