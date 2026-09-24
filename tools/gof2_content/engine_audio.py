"""Read ordinary player engine selection and source control declarations.

Runtime owners and spatial rendering are separate capabilities. No original
instructions, executable pointers or executable bytes enter the binding pack.
"""
import copy
import math
import struct
from .ship_models import section_bytes
from .declaration_layouts import recognize

VALUES = {'selection_input': 'handling_before_equipment',
          'event_ids': [42, 43, 44, 45],
          'ship_overrides': [[42, 1104], [43, 1106], [40, 1107]],
          'steering_parameter': 0, 'horizontal_parameter': 1,
          'steering_rule': 'max_absolute_source_commands',
          'horizontal_input': 'source_yaw_command',
          'horizontal_offset': 0.5,
          'update_order': 'before_manual_motion'}


def extract_engine_audio(mach, vehicle, rotation):
    arch = mach.architecture
    if arch not in LAYOUTS:
        return {}
    try:
        origin = vehicle['provenance']['handling_setup']['offset']
        address = mach.text['address'] + origin - mach.slice_offset - mach.text['offset']
        layouts = [LAYOUTS[arch]] + ([MAC_ALTERNATE] if arch == 'x86_64' else [])
        proof = recognize(mach, origin, layouts)
        if not proof:
            return {}
        if (proof['handling_setup'] != vehicle['provenance']['handling_setup'] or
                proof['rotation_anchor'] != rotation['provenance'][0]):
            return {}
        values = {}
        for key, (delta, section) in DATA[arch].items():
            if arch == 'x86_64':
                # Both complete Mac contexts place RIP operands at the same offsets.
                # Import the value selected by its consumer in this source.
                owner, displacement, end = MAC_DATA_REFERENCES[key]
                start = proof[owner]['offset']
                relative = struct.unpack_from('<i', mach.data, start-mach.slice_offset+displacement)[0]
                delta = start+end+relative-origin
            found = section_bytes(mach, address+delta, 4, section.encode())
            if found is None:
                return {}
            value = struct.unpack('<f', found[0])[0]
            if not math.isfinite(value) or not 0 < value < 100:
                return {}
            values[key] = value
            proof[key] = {'offset': found[1], 'bytes': 4}
        thresholds = [values[k] for k in ['threshold_low', 'threshold_middle', 'threshold_high']]
        if not thresholds[0] < thresholds[1] < thresholds[2]:
            return {}
        # ARM encodes 0.5 in its verified vmov instruction.
        if values.get('horizontal_offset', 0.5) != 0.5:
            return {}
        result = copy.deepcopy(VALUES)
        result.update(thresholds=thresholds, horizontal_scale=values['horizontal_scale'], provenance=proof)
        return result
    except (KeyError, IndexError, TypeError, ValueError, OverflowError, struct.error):
        return {}


# Reviewed compiler signatures are filled from the private source investigation.
LAYOUTS = {'x86_64': {'handling_setup': [0, 13, 'e8b9b40200f30f1183a4010000'],
            'selection': [13,
                          229,
                          '498b3ee8e7ab04004889c7e831b4020083f82a7511c7433850040000be50040000e9b0000000488d0536cf1c00488b38e8baab04004889c7e804b4020083f82b7511c7433852040000be52040000e983000000488d0509cf1c00488b38e88dab04004889c7e8d7b3020083f828750ec7433853040000be53040000eb59f30f1083a40100000f2e0593cd0f00720ec743382d000000be2d000000eb3a0f2e0580cd0f00720ec743382c000000be2c000000eb230f2e05f5b80f00720ec743382b000000be2b000000eb0cc743382a000000be2a000000488d05bece1c00488b38e88246f4ff'],
            'ship_getter': [177230, 8, '554889e58b075dc3'],
            'equipment_after_selection': [242,
                                          79,
                                          '4c8d2d77ce1c00498b7d00e8faaa04004889c7e8f6b402000f57c0f30f2ac0f30f1183f0020000f30f5e058b540f00f30f108ba4010000f30f59c1f30f58c1f30f590513550f00f30f1183a4010000'],
            'control_owner': [12602, 25, '4189f64989fc488d0551a41c004c8b38498b3c24e847b2ffff'],
            'controls': [12627,
                         175,
                         'f3410f1084240c0300000f57db0f2ec30f28d0770bf30f1015c89d0f000f57d0f3410f108c24040300000f2ecb0f28d9770bf30f101dab9d0f000f57d90f2ed376110f57c90f2ec1771b0f5705949d0f00eb120f57c00f2ec877070f570d839d0f000f28c14c89ff4889c631d2e8c94eedff488d05cca31c00488b18498b3c24e8c2b1fffff3410f10842404030000f30f590572f70e00f30f580586f30e004889df4889c6ba01000000e88c4eedff'],
            'rotation_anchor': [12859, 24, 'f30f10151d9c0f00f30f101d356a0f00f30f100d016a0f00'],
            'instance_getter': [-7270, 12, '554889e5488b87000100005d'],
            'parameter_wrapper': [-1212274,
                                  72,
                                  '554889e54883ec10f30f1145f44883bfd847000000742b4885f67426488d45f84889f789d64889c2e8518e210089c6e826eaffff488b7df8f30f1045f4e8188e21004883c4105dc3']},
 'armv7': {'handling_setup': [0, 8, '25f041f9c5f85001'],
           'selection': [8,
                         170,
                         'daf80000089447f0d0fd089425f00ff92a2802d14ff48a6138e0daf80000089447f0c3fd089425f002f92b2802d140f252412be0daf800004ff0ff34089447f0b4fd089425f0f3f8282802d140f253411ce095ed540a9fed6f2ab4eec20af1ee10fa10da9fed6d2ab4eec20af1ee10fa0bda9fed6a2ab4eec20af1ee10fab4bf2a212b2102e02d2100e02c21e96142f21c50c0f222004ff0ff367844d0f80080d8f80000089653f700fb'],
           'ship_getter': [152118, 4, '00687047'],
           'equipment_after_selection': [178,
                                         56,
                                         'daf80000089647f07bfd089625f04cf940ec300bbbff2006c3ef142f80ee0a1a85ed940a95ed540a40ff110d40ef200d00ffb20d85ed540a'],
           'control_owner': [10616, 24, '04464ff63e40c0f2210088467844066820683568fbf7e1ff'],
           'controls': [10640,
                        148,
                        '94ed9b1a0146b5eec01af1ee10fa21ef1121d8bfb9ff812794ed990ab5eec00af1ee10fa20ef1031d8bfb9ff8037b4eec32af1ee10fa09ddb5eec01af1ee10fad4bfb9ff810721ef110106e0b5eec00af1ee10fad8bfb9ff800710ee103a284600224ff0000b8bf694fe20683568fbf7a8ff9fedc70ac6ef100f94ed991a01462846012241ff102d02efa00d10ee103a8bf67ffe'],
           'rotation_anchor': [10920,
                               90,
                               '9fed9f0a94ed9d1a94ed9e2a4ff64e3041ff104dc0f2210042ff102d9fed990a784444ff900d006842ff902d9fed960a48ff300d48ff322d00ff901d02ff900d11ee102a10ee103a90ed000a28a88ded000a20ef100161f168f8'],
           'instance_getter': [-5806, 6, 'd0f8f0007047'],
           'parameter_wrapper': [-1513694,
                                 66,
                                 '80b56f462ded028b81b042f2f43950f80900002818bf00290fd043ec183b6b46084611461a4692f2fdfc0146fff728fa18ee101a009894f2b7fb01b0bdec028b80bd']}}
DATA = {'x86_64': {'threshold_high': [1035820, '__const'],
            'threshold_middle': [1035824, '__const'],
            'threshold_low': [1030588, '__const'],
            'horizontal_scale': [993628, '__const'],
            'horizontal_offset': [992632, '__const']},
 'armv7': {'threshold_high': [542, '__text'],
           'threshold_middle': [546, '__text'],
           'threshold_low': [550, '__text'],
           'horizontal_scale': [11554, '__text']}}


# Complete alternate Mac compiler layout, linked to handling and rotation owners.
MAC_ALTERNATE = {'handling_setup': [0, 13, 'e811b50200f30f1183a4010000'],
 'selection': [13,
               229,
               '498b3ee847ac04004889c7e889b4020083f82a7511c7433850040000be50040000e9b0000000488d05f6741c00488b38e81aac04004889c7e85cb4020083f82b7511c7433852040000be52040000e983000000488d05c9741c00488b38e8edab04004889c7e82fb4020083f828750ec7433853040000be53040000eb59f30f1083a40100000f2e05136a0f00720ec743382d000000be2d000000eb3a0f2e05006a0f00720ec743382c000000be2c000000eb230f2e0575550f00720ec743382b000000be2b000000eb0cc743382a000000be2a000000488d057e741c00488b38e8ae40f4ff'],
 'ship_getter': [177318, 8, '554889e58b075dc3'],
 'equipment_after_selection': [242,
                               79,
                               '4c8d2d37741c00498b7d00e85aab04004889c7e84eb502000f57c0f30f2ac0f30f1183f0020000f30f5e05cbf00e00f30f108ba4010000f30f59c1f30f58c1f30f590553f10e00f30f1183a4010000'],
 'control_owner': [12602, 25, '4189f64989fc488d05214a1c004c8b38498b3c24e847b2ffff'],
 'controls': [12627,
              175,
              'f3410f1084240c0300000f57db0f2ec30f28d0770bf30f1015483a0f000f57d0f3410f108c24040300000f2ecb0f28d9770bf30f101d2b3a0f000f57d90f2ed376110f57c90f2ec1771b0f5705143a0f00eb120f57c00f2ec877070f570d033a0f000f28c14c89ff4889c631d2e8b135edff488d059c491c00488b18498b3c24e8c2b1fffff3410f10842404030000f30f5905a2930e00f30f5805b68f0e004889df4889c6ba01000000e87435edff'],
 'rotation_anchor': [12859, 24, 'f30f10159d380f00f30f101db5060f00f30f100d81060f00'],
 'instance_getter': [-7270, 12, '554889e5488b87000100005d'],
 'parameter_wrapper': [-1218698,
                       72,
                       '554889e54883ec10f30f1145f44883bfd847000000742b4885f67426488d45f84889f789d64889c2e89d43210089c6e826eaffff488b7df8f30f1045f4e8644321004883c4105dc3']}
MAC_DATA_REFERENCES = {'threshold_high': ['selection', 136, 140],
 'threshold_middle': ['selection', 159, 163],
 'threshold_low': ['selection', 182, 186],
 'horizontal_scale': ['controls', 147, 151],
 'horizontal_offset': ['controls', 155, 159]}
