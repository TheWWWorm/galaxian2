"""Guarded Mac constants for the landed Néhma visit at campaign cursor 34.

The generic kind-11 station, acknowledgement, population and reward owners
remain separate. This reader emits content identities, never executable bytes.
"""

import copy

from .station_exterior import hashed_variants
from .void_crystals import VALUES as VOID_APP, MAC_VALUES as VOID_OLD


def extract_nehma_visit(mach, arrival, crystals):
    """Read cursor 34 only after its edition-local cursor 33 declaration."""
    variant, proof = hashed_variants(mach, arrival, [LAYOUTS, MAC_ALTERNATE])
    if not proof or crystals != (VOID_APP, VOID_OLD)[variant]:
        return {}, {}
    return copy.deepcopy((VALUES, MAC_VALUES)[variant]), proof


_VOICE_ORDER = (364, 365, 371, 372, 373, 374, 375, 376, 377, 378,
                366, 367, 368, 369, 370)

VALUES = {
    "scope": "nehma_station_visit34",
    "mission34": {
        "campaign_cursor": 34, "kind": 11, "station_id": 30, "system_id": 2,
        "story": True, "reward": 0, "bonus": 0,
        "briefing_events": [],
        "result_events": [
            {"speaker_id": 1 if index % 2 == 0 else 0,
             "text_id": 1980 + index, "voice_event_id": voice}
            for index, voice in enumerate(_VOICE_ORDER)
        ],
        "completion": {
            "result_mode": 1, "requires_landed_target": True,
            "completed_on_result_open": True,
            "intermediate_next_keeps_cursor": 34,
            "final_next_requires_all_modal_acknowledgements": True,
            "final_next_advances_to_cursor": 35,
            "reward_credits": 0, "stays_landed_station_id": 30,
            "cargo_or_equipment_change": False,
            "extra_blueprint_change": False,
            "extra_system_access_granted": False,
        },
    },
    "world": {
        "authored_cast": [], "authored_radio_events": [],
        "selected_kind11_actor_count": 0,
    },
    "next_mission": {
        "campaign_cursor": 35, "kind": 11,
        "station_id": 29, "system_id": 5,
        "story": True, "reward": 0, "bonus": 0,
        "briefing_events": [],
    },
}

MAC_VALUES = copy.deepcopy(VALUES)
for _event in MAC_VALUES["mission34"]["result_events"]:
    _event["text_id"] -= 14

# Relative to the established actor source anchor. Each digest guards the
# reviewed bounded window in its own Mac edition.
LAYOUTS = {
    "factory35_entry": [872174, 4, "__text", "2c97f581be48a0b4bf28ac2b314ce3170f35c893b06d7911ea84d9a5017418ce"],
    "factory35": [863293, 38, "__text", "2af677dd31b4533b66e7f6c93ac75d7e63b69c038c88b6288337271c0e0f1b26"],
    "brief34_35_counts": [1529722, 8, "__const", "af5570f5a1810b7af78caf4bc70a660f0df51e42baf91d4de5b2328de0e83dfc"],
    "result34_count": [1530378, 4, "__const", "4f5e1d312b4d1bb8ccaf069c18cddeca414ae78160fb3c793ffc730eef4e4f17"],
    "result34_pairs": [1523090, 120, "__const", "0013e514119eca7658f6e0e131f3259d5fbcfdb0ed9a75352c23a71958b50426"],
    "result34_voices": [1536826, 120, "__const", "d089a2004dfb9ca752a8e0bdabdded7bec41262fc9ac91afaa8eb642d87ae2d9"],
    "radio34_entry": [104622, 4, "__text", "252213ec6e7c761917a66a526c67bfe75b5eedfbc077d8a3368ae7908990604a"],
}

MAC_ALTERNATE = {
    "factory35_entry": [871542, 4, "__text", "2c97f581be48a0b4bf28ac2b314ce3170f35c893b06d7911ea84d9a5017418ce"],
    "factory35": [862661, 38, "__text", "1a677c78c4a67e30b6b519be76290db9dda8c19d0bea4e36076a74735b58366c"],
    "brief34_35_counts": [1554738, 8, "__const", "af5570f5a1810b7af78caf4bc70a660f0df51e42baf91d4de5b2328de0e83dfc"],
    "result34_count": [1555394, 4, "__const", "4f5e1d312b4d1bb8ccaf069c18cddeca414ae78160fb3c793ffc730eef4e4f17"],
    "result34_pairs": [1548106, 120, "__const", "6c3888a20b9815a66384c0171036f864298841981b720ff510ba53a23c866efe"],
    "result34_voices": [1561762, 120, "__const", "be7f687b6369d16fbe6861cf31e190dc59aa0311344dbdf2aa0b4482bb05313e"],
    "radio34_entry": [104622, 4, "__text", "252213ec6e7c761917a66a526c67bfe75b5eedfbc077d8a3368ae7908990604a"],
}
