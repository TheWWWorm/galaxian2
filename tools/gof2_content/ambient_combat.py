"""Original early Mido normal-hit and freighter collision declarations.

These declarations do not unlock a mission or supply destruction behavior.
"""
import copy
from .station_exterior import hashed_declarations
from .ambient_population import VALUES as POPULATION_VALUES

def extract_ambient_combat(mach,arrival,population):
    if not isinstance(population,dict) or any(population.get(key)!=value for key,value in POPULATION_VALUES.items()):return {}
    proof=hashed_declarations(mach,arrival,LAYOUTS)
    if not proof:return {}
    result=copy.deepcopy(VALUES);result['provenance']=proof
    return result

VALUES = {'scope': 'early_mido_ambient_combat',
 'campaign_cursor': 11,
 'station_id': 79,
 'system_id': 15,
 'actor_kind': 3,
 'supported_ranks': [0, 1, 2],
 'initial_actor_mode': 0,
 'initial_active': True,
 'freighter': {'subtype': 1,
               'hull_catalogue_id': 15,
               'hull_multiplier': 5,
               'point_geometry': True,
               'boxes': [{'offset': [0, -199, 4708], 'half_extents': [490, 765, 620]},
                         {'offset': [0, -14, -98], 'half_extents': [2250, 702.5, 4430]}]}}

LAYOUTS = {'factory': [77944,
             3478,
             '__text',
             '9b9cfd3e564cc131a926a3f0704be2479fa2ee4dcf4c291e129e904aeb57b6cb'],
 'base_actor': [-81548,
                948,
                '__text',
                'f12861749d41ef2ca9eac32cd4814ba5a3e3e9b12d3d34206d636457a5c0835e'],
 'statistics': [534164,
                980,
                '__text',
                'e235632f01e8c249256c9ec437003dd47e24d213c1f137d04836fab3437d958b'],
 'freighter_constructor': [631244,
                           1108,
                           '__text',
                           '39596638f6c7393a8e4af981e4162d2f1ffeb8e3f51bf20045112a50014d0da6'],
 'normal_hit': [538936,
                1846,
                '__text',
                'bf43e8c8d5ea3461a0c97d0794cf51c69df8f95220efcaf59786d0042e357778'],
 'point_wrapper': [-76580,
                   26,
                   '__text',
                   '9bead5a886f6540a33e6b291db2ce8b8ce31f47b43028700a06efa9ae6676fb0'],
 'freighter_point': [638832,
                     218,
                     '__text',
                     'f3939053e839e83f54fc8886f028bf8daef9d07c152b299addb966381e760e57'],
 'box_constructor': [-710254,
                     138,
                     '__text',
                     '26f9914c4ae9807b7ead0893f11d3b516edb4916968681a9c74a4ad086080962'],
 'box_point': [-710024,
               122,
               '__text',
               'ed39d6edebadeaa30e762599d6c92439c73a5786159abc733801b6cf712a8f76'],
 'freighter_position': [633042,
                        280,
                        '__text',
                        '241b12d3d590c5c8684aecacf28bc717857e2a440cb61c439f7b0a06fda7f26f'],
 'projectile_point_selection': [-181241,
                                192,
                                '__text',
                                '514132460b0c5a267454acc7f8ba7a5242bf8617196ff1a7f14e2f59718c489e'],
 'freighter_hostility': [634203,
                         154,
                         '__text',
                         'eedbaf93e238e789270652b36e3295696d78817ee0177c3e75cc144136cf0575'],
 'box_values': [1575362,
                32,
                '__const',
                'abbc25d14673f54cff918e1102c121ccada75722b5dce4ec0e6e32502637896c'],
 'half_extent_scale': [1544586,
                       4,
                       '__const',
                       'd99e58435243d9fef9c88273b8d553b4fba4d0baf8009d29eae74fa99e0d9f57']}
