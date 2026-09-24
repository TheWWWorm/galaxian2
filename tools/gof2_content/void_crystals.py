"""Guarded Mac declarations for the ordinary Void crystal mission.

This reader emits stable content and provenance, never original executable bytes.
Portal entry, scenery placement, mining, actor control, and story transactions
remain the responsibility of their existing native owners.
"""

import copy

from .post_probe_visits import VALUES as POST_PROBE_APP, MAC_VALUES as POST_PROBE_OLD
from .station_exterior import hashed_variants


def extract_void_crystals(mach, arrival, visits, population, resources):
    """Read cursor 33 only when its own and shared declarations agree."""
    variant, proof = hashed_variants(mach, arrival, [LAYOUTS, MAC_ALTERNATE])
    if not proof:
        return {}, {}
    expected_visits = (POST_PROBE_APP, POST_PROBE_OLD)[variant]
    if visits != expected_visits or not _shared_field(population, resources):
        return {}, {}
    return copy.deepcopy((VALUES, MAC_VALUES)[variant]), proof


def _shared_field(population, resources):
    """The common scenery readers own these values and their source proof."""
    try:
        return (population["count_base"] == 80
                and population["count_bound"] == 80
                and isinstance(population["provenance"], dict)
                and len(population["provenance"]) == 6
                and resources["ore_item_ids"] == list(range(154, 164))
                and resources["fallback_item_id"] == 164
                and resources["location_weight"] == 100
                and resources["model_ids"] == [16900, 16921, 16904, 18836]
                and resources["override_cursor"] == 90
                and isinstance(resources["provenance"], dict)
                and len(resources["provenance"]) == 12)
    except (KeyError, TypeError):
        return False


VALUES = {
    "scope": "void_crystal_mission33",
    "mission33": {
        "campaign_cursor": 33, "kind": 8, "station_id": 10, "system_id": 6,
        "story": True, "reward": 0, "bonus": 0,
        "required_item_id": 164, "required_quantity": 50,
        "briefing_events": [],
        "result_events": [
            {"speaker_id": speaker, "text_id": 1971 + index,
             "voice_event_id": 355 + index}
            for index, speaker in enumerate((20, 0, 0, 6, 0, 6, 0, 6, 0))
        ],
        "completion": {
            "result_mode": 1, "requires_landed_target": True,
            "cargo_predicate": "at_least", "completed_on_result_open": True,
            "intermediate_next_keeps_cursor": 33,
            "final_next_requires_all_modal_acknowledgements": True,
            "final_next_advances_to_cursor": 34,
            "stays_landed_station_id": 10,
        },
    },
    "field": {
        "applies_when": "selected_equals_retained_void",
        "station_seed": -1, "count_base": 80, "count_bound": 80,
        "center": [-30000, 0, 30000],
        "ore_item_id": 164, "model_id": 16921,
    },
    "void_population": {
        "applies_when": "selected_equals_retained_void_before_ordinary_traffic",
        "rank_source": "career_rank", "rank_scale": 0.5,
        "rank_offset": -1.0, "initial_count": 2,
        "first_draw_bound": 2,
        "second_draw_only_if_base_plus_first_at_least": 2.0,
        "second_draw_bound": 2,
        "count_if_second_drawn": "truncate_base_plus_second",
        "actor_kind": 9, "actor_subtype": 0, "hull_id": 8,
        "position_bounds": [120000, 80000, 120000],
        "position_offsets": [-60000, -40000, -60000],
        "shared_activation_setter_argument": 1,
        "authored_cast": [], "authored_radio_events": [],
    },
    "final_next": {
        "debit_item_id": 164, "debit_quantity": 50,
        "preserves_surplus_cargo": True, "reward_credits": 0,
        "blueprint": {
            "only_if_existing_item_entry": True, "item_id": 85,
            "sets_available": True, "recipe_item_id": 164,
            "recipe_precredit_quantity": 50,
            "adds_material_value_to_blueprint_entry": True,
            "grants_player_cargo": False, "installs_drive": False,
        },
    },
    "next_mission": {
        "campaign_cursor": 34, "kind": 11,
        "station_id": 30, "system_id": 2,
        "story": True, "reward": 0, "bonus": 0,
    },
}

MAC_VALUES = copy.deepcopy(VALUES)
for _event in MAC_VALUES["mission33"]["result_events"]:
    _event["text_id"] -= 14

# Image-relative reviewed source windows, encoded relative to the established
# actor anchor; SHA-256 digests guard both editions without matching whole files.
LAYOUTS = {'world_scenery_gate': [-42445,
                        49,
                        '__text',
                        'cb415347c316ac0eef289a3b17912a236bec7e0b64828c73d978279c84cf7a2e'],
 'world_actor_selection': [-42348,
                           319,
                           '__text',
                           '7b0a1870332e738ca68c73fe1181d40c4b093e68bf85eff86553924daf5cde02'],
 'field_count': [-35126, 92, '__text', 'f5b6356bb22bb88689ed185e40cea148c475e555c7d1ec502c84ac78836ba8f5'],
 'field_center': [-34983, 54, '__text', '722f2e887dac95936b559fe59b1b8283aabbe31c3aebb2c5dbe4bdf638a12b5f'],
 'field_ore_direct': [-34208,
                      35,
                      '__text',
                      'b67bfa9839cceda0ffc5a792a5e5e66779cd5ff64ebe3e1d5a51b0b911a1614d'],
 'field_model_choice': [-34173,
                        52,
                        '__text',
                        '47d3d7d995bfdee1ac978d7ee00e0815dbc4e4a97718c4b68e9eca4948c082b8'],
 'ore_match_weights': [-664016,
                       191,
                       '__text',
                       '8c01b009dee85ef5a24b4c667210d145f7bd5345ca81a339836853604345c6c8'],
 'ore_fallback_weight': [-663597,
                         28,
                         '__text',
                         '790e0ac18b910bd4d2246277c25d05a9cbc47eebd6461156b3e3a3d940150263'],
 'location_match': [858690, 25, '__text', '45aa26dc13ff389c5311ab6b36975be7240af18589dd560d77761b19b858cfa7'],
 'void_actor_selected': [-31836,
                         27,
                         '__text',
                         '62bc4c951fd1c8c56cae4b29e0bdee802e345a4d5d0952c65b78a0c7d191d49b'],
 'void_actor_route': [-31777,
                      23,
                      '__text',
                      '2509eabe33243fc7a53ce63acbfe90e1193f03da2b5e6e3020d57a98da83b18b'],
 'void_actor_count': [-31754,
                      136,
                      '__text',
                      '4e6d2017f2891a3722cdf8e449b89641fa6c8008a0b078e48be4ac59a5bcac64'],
 'void_actor_array': [-31618,
                      82,
                      '__text',
                      '0de69f05aa42fbc76aa75dedb1197e64fda52b215e9e198d891568d8e51cbb99'],
 'void_actor_spawn': [-31526,
                      224,
                      '__text',
                      '3e534baaffdbd35ecce515b2c99f7b14b80c6d35834afa9efaa67d42ff2606c7'],
 'rank_getter': [876982, 12, '__text', '1847659543b75281d1875a91cb669f7023d2e352208c89e5c69e2cc33a63d323'],
 'hull_choice': [-221734, 184, '__text', '45f4e61b4f44050685556643d95bc93a485b21c4db3e84c8049fd805bc7ba010'],
 'actor_flags': [536160, 28, '__text', 'b6bfcb7e235910cff0dd3613bb0d4daaad101ddbdbf2166b2708e8a5426891bb'],
 'count_constant': [1519570,
                    4,
                    '__const',
                    'd99e58435243d9fef9c88273b8d553b4fba4d0baf8009d29eae74fa99e0d9f57'],
 'base_constant': [1531978, 4, '__const', 'c68830a25204a09f8e77aada6bc5807f607cccaaa0ebb2a7122d317584478a8b'],
 'threshold_constant': [1532082,
                        4,
                        '__const',
                        'd88c86f15bbea365d658ad95a81d45367c465f7af6f7264fb077f01747ddc77d'],
 'kind8_dispatch': [875556, 16, '__text', 'bf7299d92433e846d5676f066b5d1367845265e554d5d71e04680888a490f180'],
 'kind8_table': [876026, 28, '__text', '31ab387819ef21a1c4f6d5d9d40db04349e10d8c458002aba082a7be6f46a127'],
 'kind8_branch': [874683, 123, '__text', '68636a486d163da345369843f69f8880e24bd6b68efe5184bf5891fcaaf6287c'],
 'kind8_cargo_predicate': [875440,
                           87,
                           '__text',
                           'e60d80b1f36556ba17719e0aa73bf789a11a443cc04c2dedc10c70dad237a6c7'],
 'cargo_at_least': [-84162, 50, '__text', '09f5edce7250238cb3d7138d1d9fa230c0afba2f823110c59c99e76edd84e3bf'],
 'station_result_predicate': [446607,
                              55,
                              '__text',
                              '0ceeff2b4667cc1147128e6a87db5d2df70fc0151590d335ff3ec5e28226f7e3'],
 'final_kind8_branch': [428689,
                        121,
                        '__text',
                        '9adb74140d0bca96daf49c6005505abfd618e58e1ee4d9b3a5e185cc38004f52'],
 'factory34_table_entry': [872170,
                           4,
                           '__text',
                           '9b13c8b397d030bdeb785419b26feef6e56fba906e436ac9ea284ef67900e54e'],
 'factory34': [863119, 164, '__text', '380d5b53cf676776cea77adaeedeeaefb98a267ce0d466b7598c878e81c03bb5'],
 'cargo_remove': [731326, 161, '__text', '5578e3c8460b438a90710cde56ffde0973cd840081489914df467100c17bc456'],
 'blueprint_id': [-719938, 9, '__text', '1ca715237b0d171af58ca1f1f0e87a7b5936db4872c6d54305dd3a3ea77728a4'],
 'blueprint_unlock': [-719450,
                      10,
                      '__text',
                      'd2751a26470d3e880b00ec4102f136c7d5bfa7c0fd5a28dfb9f252eea86837a2'],
 'blueprint_material': [-720430,
                        185,
                        '__text',
                        '82a47c27e07f10272f76e6ec3708c202159a4e0c30960ee31743c7cc027b3fec'],
 'result33_count': [1530374,
                    4,
                    '__const',
                    '7d8e29fa389a36cca29bc0f07a7892dddd6f9070b9e33d12dce8ce3569f81810'],
 'result33_pairs': [1523018,
                    72,
                    '__const',
                    'd62b8bf9b8c3b1de72eaac8778fe2c754c2d3bd058fb4075da338dd13ac50712'],
 'result33_voices': [1536754,
                     72,
                     '__const',
                     '28c8627fdee74686b506929f8a2c187e32d4972aa7275d83a0b2ad5ff744c7c0']}
MAC_ALTERNATE = {'world_scenery_gate': [-42445,
                        49,
                        '__text',
                        'cb415347c316ac0eef289a3b17912a236bec7e0b64828c73d978279c84cf7a2e'],
 'world_actor_selection': [-42348,
                           319,
                           '__text',
                           'da28037bcd1a57ae9a8ab4f7111c0dd688e3366ea572f3afcb1a21e56f9ab79b'],
 'field_count': [-35126, 92, '__text', 'a5932f9824cf10faa47fb5aa1d4eec2cb9ec3b3d8ad21742175fd216b86542b7'],
 'field_center': [-34983, 54, '__text', '8b287fb1ad4e441d12aa1fe41669561d409f8e0ae0313c9c0cd1e267ebe39400'],
 'field_ore_direct': [-34208,
                      35,
                      '__text',
                      'b67bfa9839cceda0ffc5a792a5e5e66779cd5ff64ebe3e1d5a51b0b911a1614d'],
 'field_model_choice': [-34173,
                        52,
                        '__text',
                        '5076fd3abdee2c66b82336c9628faae5d17c832cf645e05e5757d147f793718f'],
 'ore_match_weights': [-658128,
                       191,
                       '__text',
                       '4c6c5eed6fd5ba1a733364cd32021fec86091b8fb8dd3808619984f5f90581d7'],
 'ore_fallback_weight': [-657709,
                         28,
                         '__text',
                         '790e0ac18b910bd4d2246277c25d05a9cbc47eebd6461156b3e3a3d940150263'],
 'location_match': [858058, 25, '__text', '45aa26dc13ff389c5311ab6b36975be7240af18589dd560d77761b19b858cfa7'],
 'void_actor_selected': [-31836,
                         27,
                         '__text',
                         'af9b7d03e534706b4bba6c2b688d7ad5fcc155e40569c85b8fe72beb363eab57'],
 'void_actor_route': [-31777,
                      23,
                      '__text',
                      '20440238be1fe5d1b6aa4fc1c6ed55b95666786ef1b1704328bc9b826cc3dcf4'],
 'void_actor_count': [-31754,
                      136,
                      '__text',
                      '552ced0e8288e5b1becf4e202a9525c4cad0e82eef57a0ae3da0732f0e4786f4'],
 'void_actor_array': [-31618,
                      82,
                      '__text',
                      'c091dc90bfa97b0568b0ccb678ff9ea28bf6a94eaa269d1bf46fd43a410d18e9'],
 'void_actor_spawn': [-31526,
                      224,
                      '__text',
                      'd8b517681cfd0c9d41de32fff0f174af6ab145989ec687407208b003c3f4a43c'],
 'rank_getter': [876350, 12, '__text', '1847659543b75281d1875a91cb669f7023d2e352208c89e5c69e2cc33a63d323'],
 'hull_choice': [-220778, 184, '__text', '9a7527f297a7b707ed7fc90203c414af5fc983370c17c0dcf55308f81c59990c'],
 'actor_flags': [535624, 28, '__text', 'b6bfcb7e235910cff0dd3613bb0d4daaad101ddbdbf2166b2708e8a5426891bb'],
 'count_constant': [1544586,
                    4,
                    '__const',
                    'd99e58435243d9fef9c88273b8d553b4fba4d0baf8009d29eae74fa99e0d9f57'],
 'base_constant': [1556978, 4, '__const', 'c68830a25204a09f8e77aada6bc5807f607cccaaa0ebb2a7122d317584478a8b'],
 'threshold_constant': [1557082,
                        4,
                        '__const',
                        'd88c86f15bbea365d658ad95a81d45367c465f7af6f7264fb077f01747ddc77d'],
 'kind8_dispatch': [874924, 16, '__text', 'bf7299d92433e846d5676f066b5d1367845265e554d5d71e04680888a490f180'],
 'kind8_table': [875394, 28, '__text', '31ab387819ef21a1c4f6d5d9d40db04349e10d8c458002aba082a7be6f46a127'],
 'kind8_branch': [874051, 123, '__text', 'c7e5fb8ded2c1dd478805119a3ef5669ccdc916d96a8ea1eba462ca172e575de'],
 'kind8_cargo_predicate': [874808,
                           87,
                           '__text',
                           'd7d66292022032525574e50c57cbc8f2e1ff55bbbc3207b8780fbd05282ffaab'],
 'cargo_at_least': [-84162, 50, '__text', '09f5edce7250238cb3d7138d1d9fa230c0afba2f823110c59c99e76edd84e3bf'],
 'station_result_predicate': [446081,
                              55,
                              '__text',
                              'c57a9aaf17fd5ac06f9a41b7c920fcbb253a9ceb834af1105e1ba9a7562765d4'],
 'final_kind8_branch': [428261,
                        121,
                        '__text',
                        '3be11dcd75f9bb2eb806be2dd0191d867171bf222fef91715546a71c0728c96f'],
 'factory34_table_entry': [871538,
                           4,
                           '__text',
                           '9b13c8b397d030bdeb785419b26feef6e56fba906e436ac9ea284ef67900e54e'],
 'factory34': [862487, 164, '__text', '14a284ca80c44233925d4655388e1d3aef8c2878941ef22f78cf87a7be3898aa'],
 'cargo_remove': [730694, 161, '__text', '348f1ecacf19b4775a08e917a0acb1fab3d648e337089d71a46c3c83fe9671c1'],
 'blueprint_id': [-714042, 9, '__text', '1ca715237b0d171af58ca1f1f0e87a7b5936db4872c6d54305dd3a3ea77728a4'],
 'blueprint_unlock': [-713554,
                      10,
                      '__text',
                      'd2751a26470d3e880b00ec4102f136c7d5bfa7c0fd5a28dfb9f252eea86837a2'],
 'blueprint_material': [-714534,
                        185,
                        '__text',
                        '88dd3405e8c8cb657a005055e7a5cfbd11dccd84993d521a7ac06f95304b7097'],
 'result33_count': [1555390,
                    4,
                    '__const',
                    '7d8e29fa389a36cca29bc0f07a7892dddd6f9070b9e33d12dce8ce3569f81810'],
 'result33_pairs': [1548034,
                    72,
                    '__const',
                    '93ae22772df71b76f1d7b27e68a2bf3f0da367f7072a44afda7486a556c137c4'],
 'result33_voices': [1561690,
                     72,
                     '__const',
                     'f0aa76cec524b557605b11e58067b59e84233b584c7e4427a5454e399df7bb1d']}
