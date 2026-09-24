"""Recover the bounded ordinary flight music selector from Mac source.

This optional declaration is tied to the already verified radar HUD phase. The
matched executable bytes are discarded; only constant choices and proof extents
enter a future binding pack. Unsupported location music remains guarded.
"""
import copy

from .declaration_layouts import recognize
from .station_exterior import declaration_bytes


VALUES = {
    'scope': 'ordinary_flight_music',
    'sample_phase': 'radar_hud_after_world',
    'requires_visible_radar': True,
    'intro_hold_id': 143,
    'battle_maximums': [2, 4],
    'battle_event_ids': [140, 141, 142],
    'faction_event_ids': [134, 139, 138, 137],
    'portal_battle_id': 136,
    'portal_peace_id': 145,
    'deep_science_peace_id': 152,
    'kind10_battle_id': 151,
    'marked_battle_event_ids': [149, 150],
    'marked_battle_maximum': 4,
    'marked_actor_base_flag': False,
    'marked_root_bit_initial': False,
    'marked_actor_effective': 'actor_flag_and_root_bit',
    'marked_world_roll': {'faction': 0, 'group_count_positive': True,
                          'bound': 100, 'below': 30, 'extra_group_sizes': [7, 8]},
    'battle_retained_ids': [136, 140, 141, 142, 149, 150, 151],
    'peace_retained_ids': [127, 128, 129, 130, 134, 137, 138, 139, 145, 146, 147, 148, 152],
    'switch_action': 'stop_then_start',
    'stop_fade_ms': 800,
    'normal_world_context_only': True,
}


def selected_event_ids():
    """Music loops this bounded selector can newly start."""
    return sorted(set(VALUES['battle_event_ids'] + VALUES['faction_event_ids'] +
                      VALUES['marked_battle_event_ids'] +
                      [VALUES['intro_hold_id'], VALUES['portal_battle_id'],
                       VALUES['portal_peace_id'], VALUES['deep_science_peace_id'],
                       VALUES['kind10_battle_id']]))

# Relative to fast_forward.radar.provenance.radar_music_publication_gate.
# Whole selector hashes preserve the branch and caller relationships. The
# bounded helper extents also guard the station, retained-Void, source-station,
# system and cursor predicates used by the native ordinary-context classifier.
LEGACY = {
    'selector': ['__text', 10, 1001, 'sha256:c7d8ac206dcd08953d58cbb276119fb59919540de5df4772b61325a21487085d'],
    'faction_getter': ['__text', 57760, 10, 'sha256:89fcfb1a4e11c14ec174b815f4ca804bac72b0fb13c54f03598369d97cbb108e'],
    'faction_table': ['__const', 912162, 16, 'sha256:afcc9b44380fab02f88868bcb5e776ea8436d061fb8cfc2a54bc9b32f6495cd0'],
    'selected_retained': ['__text', 181154, 27, 'sha256:eb62362e8e3f8ab8631e2e1595c2ff765856adb248f75b2adac62ada9bf427e6'],
    'station_source': ['__text', 174480, 29, 'sha256:21a6eba1ec6be012caa4aae9829d34b67179740d8dffa8e4c4bf7e2e6fe82c82'],
    'system_special': ['__text', 195740, 79, 'sha256:fd9af73c29a3a1ec1559bd5799fefc49539ba0122be036cbec716fc549e6b430'],
    'station_special': ['__text', 195976, 83, 'sha256:04815ae4264c4eb89a27a10bc65b243e6b834072838dc3f0c6e6c42a2f57ca32'],
    'location_equal': ['__text', 176384, 23, 'sha256:8a2df1abacc57723b0f2e94d5540132e93acd470475053bb5f316cee6d4c280d'],
    'station_getter': ['__text', 174448, 11, 'sha256:d99bbc4ffe82d25777d4b9575dd91aa5a9f74211671f62f732b7a642c66250b4'],
    'system_getter': ['__text', 57710, 11, 'sha256:e362e47ab3d07d5ac9dd470924877a46b887bf4a660c9f38afe34f0c60a34bf3'],
    'cursor_getter': ['__text', 181252, 13, 'sha256:1d87a335bcc634afa77a6b7f86c755e5352d4023f36d2a60a634eea31f1b1e61'],
    'actor_marker_clear': ['__text', -758044, 4, 'sha256:585f275aa1062b30c602e7439f49ad95906bf77ff551e87f7ad685c418bd1a32'],
    'marked_faction_origin': ['__text', -707598, 97, 'sha256:c3f8bd622597fdb9812c9ad441c3e34227804513c56ede81daa74934193abcb8'],
    'marked_roll_gate': ['__text', -702453, 71, 'sha256:2722d0441949b84fc98ad445217442f50c3685199a5aa1698f9f9170feddff68'],
    'marked_group_size': ['__text', -702103, 31, 'sha256:d3bc96faa86206d5fe3de1748bb482ffafde4e34af094ce0dbe7add134cc89a8'],
    'marked_actor_branch': ['__text', -701268, 940, 'sha256:1427108d4f0d4ff6df99d9cf4c284d1140d0f7f5786abc3d45e2cfc00f89f877'],
    'stats_marker_zero': ['__text', -141911, 7, 'sha256:0cfdc0ec16ab0260998560175e8b17450d9e84dfcbd19c405fb37a4b089ece89'],
    'stats_marker_setter': ['__text', -141280, 28, 'sha256:b6bfcb7e235910cff0dd3613bb0d4daaad101ddbdbf2166b2708e8a5426891bb'],
    'stats_marker_getter': ['__text', -141210, 14, 'sha256:bca26001ae5a54fb2facaffe335c308dbd1058c197cee2aa15409db14928d005'],
}
APPSTORE = {
    'selector': ['__text', 10, 1001, 'sha256:2ba07009b190faecf6434e3f3cc09746662d51fd1d432ac34560f4175c075bc8'],
    'faction_getter': ['__text', 57844, 10, 'sha256:89fcfb1a4e11c14ec174b815f4ca804bac72b0fb13c54f03598369d97cbb108e'],
    'faction_table': ['__const', 886710, 16, 'sha256:afcc9b44380fab02f88868bcb5e776ea8436d061fb8cfc2a54bc9b32f6495cd0'],
    'selected_retained': ['__text', 181238, 27, 'sha256:eb62362e8e3f8ab8631e2e1595c2ff765856adb248f75b2adac62ada9bf427e6'],
    'station_source': ['__text', 174564, 29, 'sha256:fbb3e743b5e712cb82fb7e320f8f3119689c7aec933ae2b2d9b395f5ddc62795'],
    'system_special': ['__text', 195824, 79, 'sha256:fd9af73c29a3a1ec1559bd5799fefc49539ba0122be036cbec716fc549e6b430'],
    'station_special': ['__text', 196060, 83, 'sha256:04815ae4264c4eb89a27a10bc65b243e6b834072838dc3f0c6e6c42a2f57ca32'],
    'location_equal': ['__text', 176468, 23, 'sha256:8a2df1abacc57723b0f2e94d5540132e93acd470475053bb5f316cee6d4c280d'],
    'station_getter': ['__text', 174532, 11, 'sha256:d99bbc4ffe82d25777d4b9575dd91aa5a9f74211671f62f732b7a642c66250b4'],
    'system_getter': ['__text', 57794, 11, 'sha256:e362e47ab3d07d5ac9dd470924877a46b887bf4a660c9f38afe34f0c60a34bf3'],
    'cursor_getter': ['__text', 181336, 13, 'sha256:1d87a335bcc634afa77a6b7f86c755e5352d4023f36d2a60a634eea31f1b1e61'],
    'actor_marker_clear': ['__text', -758592, 4, 'sha256:585f275aa1062b30c602e7439f49ad95906bf77ff551e87f7ad685c418bd1a32'],
    'marked_faction_origin': ['__text', -708146, 97, 'sha256:86a390687611942faab965fc9e736a601f7afffd07bc2bc8800adfa15e667c40'],
    'marked_roll_gate': ['__text', -703001, 71, 'sha256:18462870144fc60f9760fcb28f4974cbc22153058c9d4126a04518c563c19ceb'],
    'marked_group_size': ['__text', -702651, 31, 'sha256:d3bc96faa86206d5fe3de1748bb482ffafde4e34af094ce0dbe7add134cc89a8'],
    'marked_actor_branch': ['__text', -701816, 940, 'sha256:8c29d8aeeadd05d2eb25945ffeb843a7899afa081eaa71c3def49278b63f0665'],
    'stats_marker_zero': ['__text', -141923, 7, 'sha256:0cfdc0ec16ab0260998560175e8b17450d9e84dfcbd19c405fb37a4b089ece89'],
    'stats_marker_setter': ['__text', -141292, 28, 'sha256:b6bfcb7e235910cff0dd3613bb0d4daaad101ddbdbf2166b2708e8a5426891bb'],
    'stats_marker_getter': ['__text', -141222, 14, 'sha256:bca26001ae5a54fb2facaffe335c308dbd1058c197cee2aa15409db14928d005'],
}


def extract_ordinary_music(mach, fast_forward, audio=None):
    """Return a verified optional declaration, or empty for unsupported layouts.

    The importer extracts FEV audio after executable registrations. When audio
    is supplied by a source check, also verify the selected event metadata.
    Native binding validation always checks that metadata after FEV parsing.
    """
    if getattr(mach, 'architecture', None) != 'x86_64':
        return {}
    try:
        radar = fast_forward['radar']['provenance']['radar_music_publication_gate']
        origin = radar['offset']
        if type(origin) is not int or radar['bytes'] != 22:
            return {}
        if audio is not None:
            if not isinstance(audio, dict):
                return {}
            events = audio['events']
            if len(events) != 2293:
                return {}
            for event_id in selected_event_ids():
                event = events[event_id]
                if (event['id'] != event_id or event['categories'] != ['music'] or
                        event['properties']['fade_out_ms'] != VALUES['stop_fade_ms'] or
                        event['properties']['max_playbacks'] != 1 or
                        event['sound']['flags'] != 0 or event['simple_flags'] != 1):
                    return {}
        proof = recognize(mach, origin, [LEGACY, APPSTORE], reader=declaration_bytes)
        if not proof:
            return {}
        result = copy.deepcopy(VALUES)
        result['provenance'] = proof
        return result
    except (KeyError, IndexError, TypeError, ValueError, OverflowError):
        return {}
