"""Bounded radio name and fixed portrait declarations; emits data only."""
import struct
from .opening_loadout import template
from .ship_models import section_bytes

MAC_SPEAKERS = """
e8
{call_1:4}
4189c64181fe
{number_b:4}
7c6b498b7d204885ff7405e8
{call_1b:4}
bf14000000e8
{call_25:4}
49894520418d86
{number_30:4}
448975a84c63f031db4c8d3d
{ref_40:4}
498b07488b00488b40084a8b3cf0e8
{call_53:4}
8b0498498b4d2089049948ffc383fb0575db498b452031dbc645af01448b75a8e9be0000004183fe
{number_7f:1}
7f064183fe
{number_85:1}
7557bb020000004183fe41741631db4183fe40740e4183fe
{number_9e:1}
0f94c00fb6c08d5c0001498b7d204885ff7405e8
{call_b3:4}
49c7452000000000488d05
{ref_c2:4}
488b38be0100000089dae8
{call_d1:4}
49894520c645af01eb5b498b7d204885ff7405e8
{call_e9:4}
bf14000000e8
{call_f3:4}
498945204963ce488d15
{ref_101:4}
488b0cca31d28b3491893490498b452048ffc283fa0575ee
"""

MAC_NAMES = """
e8
{call_1:4}
4189c54c8d35
{ref_b:4}
498b3ebe2fffffffe8
{call_18:4}
488b53104d8b26418b442404418b4c24080faf028b53508955b4418b9424d802000039c20f47c28b53488955b0448b7b4c4181fd
{number_50:4}
448d74010a7c4f418d85
{number_5e:4}
4863c0488d0d
{ref_68:4}
488b09488b09488b4908488b34c14c8d6dc84c89efe8
{call_82:4}
4c892c244c89e7be070000004489fa8b4db4448b45b04589f1e8
{call_a0:4}
488d7dc8eb49488d05
{ref_ad:4}
488b38418db5
{number_b7:4}
e8
{call_bc:4}
4c8d6db84c89ef4889c631d2e8
{call_cd:4}
4c892c244c89e7be070000004489fa8b4db4448b45b04589f1e8
{call_eb:4}
488d7db8e8
{call_f4:4}
"""

ARM_SPEAKERS = """
{call_0:4}
0646
{value_6:4}
864231dbdaf81000002818bf
{call_16:4}
4ff0ff381420cdf86080
{call_24:4}
caf81000
{value_2c:4}
a6eb000b0c96
{value_36:4}
0026
{value_3c:4}
7844056828680068406850f82b00cdf86080
{call_52:4}
daf8101050f8260041f826000136052eedd100200b9001200a9059e0
{number_72:1}
2e2ddc
{number_76:1}
2e2bd0daf81000002818bf
{call_82:4}
{value_86:4}
4ff0ff31
{value_8e:4}
1891784450f826501420
{call_9c:4}
01460020caf8101055f8202041f8202001300528f8d1
"""

ARM_NAMES = """
{call_0:4}
0446
{value_6:4}
{value_a:4}
6ff0d0017844056807952868cdf840a0
{call_1e:4}
b068b16b0991f16bd6f834b008962e680068d6e901230a91d6f8d8125043814288bf0846184400f10a08
{value_4c:4}
844231db
{value_54:4}
{value_58:4}
{value_5c:4}
{value_60:4}
7844006800680068406800eb84000dac41582046cdf840a0
{call_7c:4}
01201090099a30460a9b0721cdf800b0cdf804800294
{call_96:4}
4ff0ff3010900da82fe0bb684ff0ff301090304621464246
{call_b2:4}
a1e0
{value_b8:4}
{value_bc:4}
{value_c0:4}
784400680068cdf840a0
{call_ce:4}
0bac01460022cdf840a02046
{call_de:4}
03201090099a30460a9b0721cdf800b0cdf804800294
{call_f8:4}
4ff0ff3010900ba8
{call_104:4}
"""

def data_region(mach, address, size):
    for section in mach.sections:
        if section['name'] in [b'__data', b'__const'] and section['address'] <= address and address + size <= section['address'] + section['length']:
            offset = section['offset'] + address - section['address']
            return mach.data[offset:offset + size], offset + mach.slice_offset
    return None


def extract_speaker_bindings(mach):
    import capstone
    mac = mach.architecture == 'x86_64'
    if not mac and mach.architecture != 'armv7': return {}
    decoder = capstone.Cs(capstone.CS_ARCH_X86 if mac else capstone.CS_ARCH_ARM,
                          capstone.CS_MODE_64 if mac else capstone.CS_MODE_THUMB)
    decoder.detail = True
    section = mach.text
    code = mach.data[section['offset']:section['offset'] + section['length']]
    def unique(spec):
        matches = [m for m in template(spec).finditer(code) if mac or m.start() % 2 == 0]
        if len(matches) != 1: raise ValueError('Missing or ambiguous radio speaker declaration')
        return matches[0]
    def address(match, key): return section['address'] + match.start(key)
    def relative(match, key): return address(match,key) + 4 + struct.unpack('<i',match[key])[0]
    def number(match, key): return int.from_bytes(match[key], 'little', signed=True)
    def instruction(match, key, mnemonic, registers):
        ins = list(decoder.disasm(match[key], address(match,key)))
        if len(ins) != 1 or ins[0].mnemonic != mnemonic or len(ins[0].operands) != len(registers)+1 or ins[0].operands[-1].type != 2:
            raise ValueError('Unsupported radio declaration scalar')
        if [ins[0].reg_name(o.reg) for o in ins[0].operands[:-1]] != registers:
            raise ValueError('Radio declaration register mismatch')
        return ins[0].operands[-1].imm
    def call(match, key, mnemonic='bl'):
        return relative(match,key) if mac else instruction(match,key,mnemonic,[])
    def arm_ref(match, low, high, pc, register='r0'):
        lo = instruction(match,low,'movw',[register]); hi = instruction(match,high,'movt',[register])
        return section['address']+match.start()+pc+lo+(hi<<16)
    try:
        speakers = unique(MAC_SPEAKERS if mac else ARM_SPEAKERS)
        names = unique(MAC_NAMES if mac else ARM_NAMES)
        if not mac:
            for block in [speakers, names]:
                for key in block.groupdict():
                    if key.startswith('call_'):
                        call(block, key, 'blx' if block is speakers and key in ['call_16','call_24','call_82','call_9c'] else 'bl')
        getter = call(speakers,'call_1' if mac else 'call_0')
        if getter != call(names,'call_1' if mac else 'call_0'): raise ValueError('Different speaker accessors')
        getter_bytes = bytes.fromhex('554889e58b47145dc3' if mac else 'c0687047')
        found = section_bytes(mach,getter,len(getter_bytes),b'__text')
        if found is None or found[0] != getter_bytes: raise ValueError('Unknown radio speaker field')
        if mac:
            threshold = number(speakers,'number_b')
            if number(speakers,'number_30') != -threshold or number(names,'number_50') != threshold or number(names,'number_5e') != -threshold:
                raise ValueError('Conflicting authored-agent name boundary')
            count = number(speakers,'number_7f')+1
            excluded = number(speakers,'number_85')
            if number(speakers,'number_9e') != excluded: raise ValueError('Conflicting procedural speaker')
            if len({call(speakers,k) for k in ['call_1b','call_b3','call_e9']}) != 1 or call(speakers,'call_25') != call(speakers,'call_f3'):
                raise ValueError('Inconsistent portrait lifetime declarations')
            if call(names,'call_a0') != call(names,'call_eb'): raise ValueError('Different name presentation destinations')
            if relative(speakers,'ref_40') != relative(names,'ref_68'): raise ValueError('Different authored-agent catalogues')
            first_name = number(names,'number_b7')
            table = relative(speakers,'ref_101')
        else:
            threshold = instruction(speakers,'value_6','movw',['r0'])
            if instruction(speakers,'value_2c','movw',['r0']) != threshold or instruction(names,'value_4c','movw',['r0']) != threshold:
                raise ValueError('Conflicting authored-agent name boundary')
            agent_displacement = instruction(names,'value_58','movw',['r1']) + (instruction(names,'value_60','movt',['r1'])<<16)
            if agent_displacement != ((-threshold*4)&0xffffffff): raise ValueError('Unknown authored-agent name indexing')
            count = number(speakers,'number_72')+1
            excluded = number(speakers,'number_76')
            if call(speakers,'call_16','blx') != call(speakers,'call_82','blx') or call(speakers,'call_24','blx') != call(speakers,'call_9c','blx'):
                raise ValueError('Inconsistent portrait lifetime declarations')
            if call(names,'call_96') != call(names,'call_f8'): raise ValueError('Different name presentation destinations')
            if arm_ref(speakers,'value_36','value_3c',0x44) != arm_ref(names,'value_54','value_5c',0x68):
                raise ValueError('Different authored-agent catalogues')
            first_name = instruction(names,'value_bc','addw',['r1','r4'])
            table = arm_ref(speakers,'value_86','value_8e',0x98)
            # Check every captured instruction, including pointers whose concrete
            # global address is irrelevant to the emitted constant declarations.
            arm_ref(names,'value_6','value_a',0x16)
            arm_ref(names,'value_b8','value_c0',0xc8)
        if not 1 <= count <= 128 or not 0 <= excluded < count or not count < threshold <= 65535 or not 0 <= first_name <= 65535-count:
            raise ValueError('Unsupported speaker declaration bounds')
        width = 8 if mac else 4
        source = data_region(mach,table,count*width)
        if source is None or table%width: raise ValueError('Portrait pointer table is unavailable')
        rows = []
        for index,pointer in enumerate(struct.unpack('<'+str(count)+('Q' if mac else 'I'),source[0])):
            if pointer % 4: raise ValueError('Unaligned portrait definition')
            row = {'speaker_id':index}
            if index == excluded:
                row['status'] = 'procedural'
            else:
                entry = data_region(mach,pointer,20)
                if entry is None:
                    row['status'] = 'unavailable'
                else:
                    values = list(struct.unpack('<5i',entry[0]))
                    if not 0 <= values[0] <= 255 or any(not -1 <= value <= 255 for value in values[1:]):
                        raise ValueError('Invalid fixed portrait definition')
                    row.update(status='fixed',family=values[0],parts=values[1:],source_offset=entry[1],source_bytes=20)
            rows.append(row)
        return {'first_name_id':first_name,'agent_speaker_start':threshold,'fixed_speaker_count':count,
                'procedural_speaker':excluded,'portraits':rows,
                'provenance':{
                    'speaker_selection':{'offset':mach.slice_offset+section['offset']+speakers.start(),'bytes':len(speakers[0])},
                    'name_selection':{'offset':mach.slice_offset+section['offset']+names.start(),'bytes':len(names[0])},
                    'speaker_getter':{'offset':found[1],'bytes':len(found[0])},
                    'portrait_table':{'offset':source[1],'bytes':len(source[0])}}}
    except (ValueError,IndexError,KeyError,struct.error):
        return {}
