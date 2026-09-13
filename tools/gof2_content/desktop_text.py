"""Read the Mac's finite desktop text substitutions without running original code."""
import copy
from .ship_models import section_bytes

def extract_desktop_text(mach, arrival):
    if mach.architecture!='x86_64':return {}
    try:
        origin=arrival['provenance']['actor']
        if origin['bytes']!=315:return {}
        anchor=mach.text['address']+origin['offset']-mach.slice_offset-mach.text['offset']
        proof={}
        for key,(delta,size,pattern) in LAYOUTS.items():
            found=section_bytes(mach,anchor+delta,size,b'__text')
            if found is None or found[0]!=bytes.fromhex(pattern):return {}
            proof[key]={'offset':found[1],'bytes':size}
        result=copy.deepcopy(VALUES);result['provenance']=proof
        return result
    except (KeyError,TypeError,ValueError,IndexError,OverflowError):return {}

VALUES = {'scope': 'mac_desktop_text',
 'pairs': [[16, 17],
           [188, 189],
           [573, 574],
           [579, 580],
           [582, 583],
           [615, 616],
           [618, 619],
           [624, 625],
           [627, 628],
           [631, 632],
           [1658, 1659],
           [1696, 1697],
           [1703, 1704],
           [1708, 1709],
           [1728, 1729],
           [1853, 1854],
           [592, 593],
           [595, 596],
           [598, 599]],
 'lookup': 'first_match_once'}

LAYOUTS = {'declaration': [-228336,
                 316,
                 'bf98000000e80cfe1a004889c3c70310000000c7430411000000c74308bc000000c7430cbd000000c743103d020000c743143e020000c7431843020000c7431c44020000c7432046020000c7432447020000c7432867020000c7432c68020000c743306a020000c743346b020000c7433870020000c7433c71020000c7434073020000c7434474020000c7434877020000c7434c78020000c743507a060000c743547b060000c74358a0060000c7435ca1060000c74360a7060000c74364a8060000c74368ac060000c7436cad060000c74370c0060000c74374c1060000c743783d070000c7437c3e070000c7838000000050020000c7838400000051020000c7838800000053020000c7838c00000054020000c7839000000056020000c7839400000057020000488b3d5bb628004889deba26000000e8de911400'],
 'setter': [1120042,
            153,
            '554889e54883ec3048897df8488975f08955ec488b75f8817dec00000000488975e00f84350000008b45ec83e001b9020000003d01000000894ddc0f8513000000488d3dacc70a00b000e871520500e93f000000488b7de0e821640600c745e8000000008b45e83b45ec0f83230000008b45e8488b4df08b3c81488b75e0e8436706008b45e805010000008945e8e9d1ffffff4883c4305dc3'],
 'lookup': [1120202,
            253,
            '554889e54883ec2048897df08975ec488b7df0c745e80000000048897de08b45e8488b4de03b010f83440000008b75e8488b7de0e8816906008b303b75ec0f851d0000008b45e80501000000488b7de089c6e8636906008b308975ece9100000008b45e805020000008945e8e9adffffff8b45ec488b4de03b41300f8d52000000817dec000000000f8c45000000488b45e048817818000000000f8433000000486345ec488b4de0488b511848813cc2000000000f8419000000486345ec488b4de0488b5118488b04c2488945f8e920000000488d3db0c60a008b75ecb000e83c510500488b7de04881c72000000048897df8488b45f84883c4205dc3']}
