"""Bounded Mac declarations for buying an offered ship in an ordinary Hangar.

This reader recognizes both supported Mac code layouts as complete units. It
returns transaction parameters and source-relative extents, never executable
bytes or an executable representation of the source handler.
"""

import copy

from .ordinary_shopping import VALUES as SHOPPING_VALUES
from .station_exterior import hashed_variants


VALUES = {
    'scope': 'ordinary_hangar_offered_ship_purchase',
    'quotes': {
        'offer': 'retained_offer_instance',
        'current': 'retained_current_ship_instance',
        'preflight': 'offer_lte_wallet_plus_current',
        'shortfall': 'offer_minus_wallet_minus_current',
        'sell_credit_percent': 100,
        'sell_wallet_delta': 'current_minus_offer',
        'keep_wallet_delta': 'negative_offer',
        'keep_requires_full_offer_affordability': True,
    },
    'entry': {
        'clone_without_override_preserves_instance_quote': True,
        'fresh_career_current_ship_id': 10,
        'fresh_career_quote_base': 'catalogue_ship_price',
        'fresh_career_quote_divisor': 1.25,
        'fresh_career_quote_arithmetic': 'float32_division_then_truncate_i32',
        'hangar_current_quote_refresh': 'on_hangar_model_rebuild',
        'hangar_refresh_requires_current_station': True,
        'hangar_refresh_requires_positive_existing_quote': True,
        'hangar_refresh_quote_base': 'catalogue_ship_price',
        'hangar_refresh_pricing_owner': 'ordinary_base_station_stock.ships',
        'fresh_catalogue_generated_offer_tags': [],
    },
    'text_ids': {
        'buy_prompt': 293,
        'sell_or_keep_prompt': 316,
        'sell_label': 319,
        'keep_label': 320,
        'insufficient_credits': 192,
        'insufficient_credits_legacy_upsell': 123,
        'passengers': 325,
        'restricted_sale': 314,
        'same_ship': 318,
        'duplicate_parked_old_type': 317,
    },
    'choices': {'sell_result': 0, 'keep_result': 1, 'dismissal_changes_state': False},
    'guards': {
        'passenger_count_must_be_zero': True,
        'restricted_sale_career_state': 77,
        'restricted_sale_current_ship_id': 37,
        'offered_ship_id_must_differ': True,
        'keep_requires_no_parked_old_ship_type': True,
        'cargo_capacity_rejection_during_exchange': False,
    },
    'transfer': {
        'owned_cargo_source': 'committed_hangar_rows',
        'new_ship_source': 'catalogue_prototype_for_offer_id',
        'new_ship_affiliation_source': 'offered_instance',
        'new_ship_quote': 'locally_recalculated_after_offer_affiliation',
        'debit_quote_source': 'retained_offered_instance',
        'cargo_instances_keep_quantity_price_and_protection': True,
        'installed_instances_cloned': True,
        'installed_instances_keep_quantity': True,
        'installed_slot_order': 'old_ship_order',
        'installed_fit': 'first_compatible_free_slot',
        'failed_installed_fit': 'same_instance_to_new_cargo',
        'purchased_ship_tags_source': 'offered_instance',
        'former_ship_tags_source': 'old_current_instance',
        'old_live_pools_copied': False,
    },
    'stock': {
        'sell': 'replace_purchased_offer_at_same_index_with_stripped_old_ship',
        'keep': 'remove_purchased_offer_and_park_stripped_old_ship',
        'former_ship_affiliation_source': 'old_current_instance',
        'sell_replacement_quote': 'locally_recalculated',
    },
    'commit': {
        'current_ship_replaced_once': True,
        'ship_derived_stats_recomputed': True,
        'hangar_rows_rebuilt': True,
    },
}

# Each layout is one complete source proof, relative to the established rescue
# actor anchor. The final five spans bind the already-owned ordinary departure,
# next-flight cache and ship-tag rules without exporting those rules here.
LAYOUTS = {
    'purchase_preflight': [-134575, 838, '__text', '9f9a6897d5917d0596a5d20f0b7171e96e4cc1c987edd7fa5e877ebe48f7994c'],
    'choice_and_transfer': [-144254, 989, '__text', '3e4031461eea569727eb1710fd00db8f92a185b41c55cc96c71691f960e0e8df'],
    'ship_exchange': [-143205, 1796, '__text', '88d32265e75b68539f08c94dff9d9b1250e796d1c23cd4143f7e9482607e4dcd'],
    'current_ship_setter': [872734, 73, '__text', 'fdf90060c1029918d3b01d00b740a9969d4d27bec2d1c0345971a02d06d541b3'],
    'current_ship_getter': [858758, 13, '__text', 'a85a422bc4ba2fd3ca47339b1cbca25d19fff857c40efca32eaf13471817cb8c'],
    'ordinary_departure_reset': [432297, 126, '__text', '22e22d431eb8490d3fb080a6ff593846fe5a8be334465ac95478827768b22415'],
    'fresh_player_restore': [334997, 128, '__text', '5cf21a54777df3cc4c2e38a712b64f42e5efbabf3d45bc28b9b60c5c2fb356db'],
    'new_ship_cache_refresh': [335134, 126, '__text', '44c87b5e774ae49241049d363a8dc172de92073e8f3682012570e7b29dd4cf7b'],
    'hull_upgrade_tags': [730112, 59, '__text', '85474c16572f13826cd893ed9a0d965aef9342c75521889a2119aa9f53ed3278'],
    'ships_bin_catalogue': [-677542, 430, '__text', '4069285f74981e4be4fba150bf168feae6454cdd1b004a3795b5df91701a9821'],
    'ship_constructor_entry': [727934, 10, '__text', 'aafd66af2c321a1032ffdbaea51ef446e7df7cd4b20fe53e4fdf6af362acadb2'],
    'ship_instance_constructor': [727944, 260, '__text', 'd1cc700828a22fff6613c920e0e21f7490bbded75b8a1e98299ebdf18f90905e'],
    'ship_instance_clone': [733492, 182, '__text', '6f87fcd3198ac249f1350b5e9d5a674312951aaac80467bcb301321cf0e81f9c'],
    'ship_clone_price_guard': [733464, 28, '__text', '687e37637f00e9bb61a7e3f4fb15f9c1283c66456e14083aa7b7c956b116d4a2'],
    'new_career_quote': [733674, 48, '__text', '64270e12465b5f7f6f4c856c58210829921881b6aea3911606236d4d74d163a0'],
    'new_career_current_ship': [883792, 51, '__text', 'c137488159c31cd8e180bdafd2ff9857ffbcff9826e3ca228ae164c976af656b'],
    'ordinary_ship_factory': [-242998, 3820, '__text', '5a33c53e1044f880aab805a1693eeb5146bba3ab62008568f5d47501edbe8ec0'],
    'current_quote_reprice': [733722, 206, '__text', 'c9f5d5d5b0d9d6676259ee5bf78a52f3765bc2cc60687d945a2992c5311e7a92'],
    'hangar_quote_refresh': [-173140, 4582, '__text', '7957b6e6f04f7c9507b5446187971a5c3dfb1bf3391ce83e092435fcb2ef97b6'],
    'hangar_owner_create': [440227, 46, '__text', '063e3593b8c7a5a620d1037603adcf4a4a565d2430c5f0361c8cf3a69f2d7f08'],
}

MAC_ALTERNATE = {
    'purchase_preflight': [-134197, 838, '__text', 'd0308a3da382173134d5372e05b5113799b08bcfb9958c84e52c1ccebf8cac1f'],
    'choice_and_transfer': [-143770, 989, '__text', '6e4f0ab654be29b49631016063392723f0395be15856f52728effd19a73d39a2'],
    'ship_exchange': [-142721, 1796, '__text', '8fd75c616d0bdb097fb8d0f634d40be0aeafc3e22a799c340dcab5c123bbccb7'],
    'current_ship_setter': [872102, 73, '__text', '1680b7721cff32840efc63cd8b7bf369e0772c0f444946abf03dde614181da25'],
    'current_ship_getter': [858126, 13, '__text', 'a85a422bc4ba2fd3ca47339b1cbca25d19fff857c40efca32eaf13471817cb8c'],
    'ordinary_departure_reset': [431869, 126, '__text', 'faf79612974e31946653c4d52efa1d5977ea201dc5e3e86d8a07d688248fa066'],
    'fresh_player_restore': [335297, 128, '__text', '486f54b55a45f112a593ff7349457877b4600ad7acfe18ceb238229314e14af9'],
    'new_ship_cache_refresh': [335434, 126, '__text', '6e71bdf4b553dc44cb35de2e059cd34219e8bd8df5744ae0af126d37dcf4dc12'],
    'hull_upgrade_tags': [729488, 59, '__text', '85474c16572f13826cd893ed9a0d965aef9342c75521889a2119aa9f53ed3278'],
    'ships_bin_catalogue': [-671654, 430, '__text', '284e42bf66fa6c8bdbe92ed282ecf4643f760565c65c1fd8f2725da3518ac054'],
    'ship_constructor_entry': [727310, 10, '__text', 'aafd66af2c321a1032ffdbaea51ef446e7df7cd4b20fe53e4fdf6af362acadb2'],
    'ship_instance_constructor': [727320, 260, '__text', 'ea425c01273b6c49e1ccfaab3a56f7cc18fa901758790c41b5fa92872d552f2f'],
    'ship_instance_clone': [732860, 182, '__text', '1c626e1cd4cff98bb52e3ce9119c95ecc0ae6532c0e7b01377097d0f17b4ab9f'],
    'ship_clone_price_guard': [732832, 28, '__text', '687e37637f00e9bb61a7e3f4fb15f9c1283c66456e14083aa7b7c956b116d4a2'],
    'new_career_quote': [733042, 48, '__text', 'd5f92155b800fb58fdc7000f625840519ab550a8ec044aa57c3ad1828c7c542f'],
    'new_career_current_ship': [883160, 51, '__text', 'fdf3e8e40239adb22dfeb3a6335113346f2809740a6a63fa5b14ee79f05a64a1'],
    'ordinary_ship_factory': [-241510, 3352, '__text', 'cc6b1f75ddb0663cea1a8b9ce04b0ad5277441a068706a5f0ee5f8034998c479'],
    'current_quote_reprice': [733090, 206, '__text', 'b95d0557902622b28717f9209dc144775b5a8ef2a3f11360d19814ec90a318e5'],
    'hangar_quote_refresh': [-172648, 4582, '__text', 'f3016951cc9ce84e555405db13f23e1db908166a93a796012b84d54f11180001'],
    'hangar_owner_create': [439715, 46, '__text', '83fefbe2fa23e2a23d4c01c8207675637f0d05d340caa912cf3254ff445c22a4'],
}


def extract_ship_purchase(mach, arrival, ordinary_shopping):
    """Return declarations with provenance only for one fully proved Mac layout.

    The caller supplies the already imported ordinary-shopping declaration and
    rescue actor anchor; this does not add a binding or enable a purchase path.
    """
    if ordinary_shopping != SHOPPING_VALUES:
        return {}
    _, proof = hashed_variants(mach, arrival, [LAYOUTS, MAC_ALTERNATE])
    if not proof:
        return {}
    result = copy.deepcopy(VALUES)
    result['provenance'] = proof
    return result
