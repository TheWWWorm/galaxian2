"""Optional Deep Science stock declarations; no achievement state is invented.

The caller supplies the retained all-base-gold result. The medal prerequisite
also proves why a fresh native profile within the supported early campaign has
not earned that result; it is not a migration rule for original profiles.
"""
import copy

from .base_station_stock import VALUES as BASE_VALUES, MAC_VALUES as MAC_BASE_VALUES
from .station_exterior import hashed_variants

VALUES = {'scope': 'deep_science_base_station_stock',
 'station_id': 10,
 'first_cursor': 15,
 'last_cursor': 83,
 'all_base_gold_count': 1,
 'all_base_gold_ship_id': 8,
 'base_medal_count': 36,
 'gold_level': 1,
 'required_medal_id': 30,
 'required_campaign_cursor': 45}

LAYOUTS = {'station10_count': [-240253,
                     114,
                     '__text',
                     '42b4e84a67fac1eeefdf4a093eb34da97af1e716966fba3c771aa7f244d72dfe'],
 'station10_fixed_ship': [-240063,
                          216,
                          '__text',
                          'f2bc8a85cdbc9375b412c452b9fa9a9868b0eaf85750c45c0c1d1229b6f5915e'],
 'all_base_gold': [-726102,
                   106,
                   '__text',
                   '85ee27442b883407ad6ba7f01f77e0ee18ba0bfe1fb1c727c22f35ece0da8ad6'],
 'all_base_gold_getter': [-725984,
                          12,
                          '__text',
                          '5f68ffd5c8955b9ca27b41638b05fd417d875e5564c4464f76fbb501f99d3762'],
 'retained_medals': [-725630,
                     110,
                     '__text',
                     '89332ed1f86be9858c5dbfb03cc0ce0709c6c23f9ae3cefc00b49e9e2f78d150'],
 'medal_dispatch': [-727879,
                    128,
                    '__text',
                    'e65c41506056226d3c78e7a9987615c6d06a1a80424293340a52c4235444062f'],
 'required_medal_dispatch': [-726378,
                             4,
                             '__text',
                             'b0a5a58bf91df6878e7d1ce4b0b0a0b6f78f2b47802eae9c71ff73e9f3902fc6'],
 'required_medal_predicate': [-726907,
                              20,
                              '__text',
                              'f037a2cd6fda3fa9841267482f14ca1e645e94ebaf5d2c61a4d755e115018cf4'],
 'required_medal_levels': [1544402,
                           12,
                           '__const',
                           'a726945aefa97eb220a4cb0ea8dcf9d5bbe181b5414f90ae37dc20fa50af7aa1'],
 'required_campaign_progress': [858140,
                                28,
                                '__text',
                                'a20af8706e81d893632a210abaacb20912dc5863ca5c295fed5da00b9844e607']}

MAC_ALTERNATE = {'station10_count': [-241720,
                     110,
                     '__text',
                     'c2229e8f0b3c8819d9492f28b4ffdcdaa5c3b0dda9563cf98fffb8aac0f4dcf2'],
 'station10_fixed_ship': [-241531,
                          213,
                          '__text',
                          'dc501f65bf9b328a430f77013fae3c49d489de254f1116d1456c618ed34f4738'],
 'all_base_gold': [-731998,
                   106,
                   '__text',
                   '85ee27442b883407ad6ba7f01f77e0ee18ba0bfe1fb1c727c22f35ece0da8ad6'],
 'all_base_gold_getter': [-731880,
                          12,
                          '__text',
                          '5f68ffd5c8955b9ca27b41638b05fd417d875e5564c4464f76fbb501f99d3762'],
 'retained_medals': [-731526,
                     110,
                     '__text',
                     '89332ed1f86be9858c5dbfb03cc0ce0709c6c23f9ae3cefc00b49e9e2f78d150'],
 'medal_dispatch': [-733775,
                    128,
                    '__text',
                    'b5941d4d31ff1c09a1328f21cb615952438c193796c530f99e31eefc74f37228'],
 'required_medal_dispatch': [-732274,
                             4,
                             '__text',
                             'b0a5a58bf91df6878e7d1ce4b0b0a0b6f78f2b47802eae9c71ff73e9f3902fc6'],
 'required_medal_predicate': [-732803,
                              20,
                              '__text',
                              '2e479501ba559d21b938a05f5ada905c06ac32bb87c9ef98fd8603a049fe463c'],
 'required_medal_levels': [1519386,
                           12,
                           '__const',
                           'a726945aefa97eb220a4cb0ea8dcf9d5bbe181b5414f90ae37dc20fa50af7aa1'],
 'required_campaign_progress': [858772,
                                28,
                                '__text',
                                'a20af8706e81d893632a210abaacb20912dc5863ca5c295fed5da00b9844e607']}

def extract_deep_science_stock(mach, arrival, base_stock):
    variant, proof = hashed_variants(mach, arrival, [LAYOUTS, MAC_ALTERNATE])
    if not proof or base_stock != (BASE_VALUES, MAC_BASE_VALUES)[variant]:
        return {}
    result = copy.deepcopy(VALUES)
    result['provenance'] = proof
    return result
