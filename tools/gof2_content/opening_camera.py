"""Recover opening camera declarations; executable bytes are never emitted.

Only the recognized opening cuts, fixed-eye pan and follow-mode handoff qualify.
Ship motion, audio and mission effects stay outside this camera-only scope.
"""
import math
import struct
from .opening_loadout import template
from .opening_staging import MAC_INITIAL, ARM_INITIAL, MAC_FORMATION, ARM_FORMATION
from .ship_models import section_bytes

MAC_ATTACH = """
554889e541574156534883ec284889f34989fe4889dfe8
{call_16:4}
4885c074
{jump_1e:1}
4d8b7e184889dfe8
{call_27:4}
488b70104c89ffe8
{call_33:4}
488d75d8498b7e18c745d800000000c745dc00001644c745e0008022c4e8
{call_55:4}
488d75c8498b7e18c745c800000000c745cc00001644c745d00040a7c4e8
{call_77:4}
4883c4285b415e415f5dc3
"""

MAC_CUT = """
83f9020f8f
{jump_3:4}
48899db0d0ffff488d05
{ref_10:4}
488b38f30f1005
{ref_1a:4}
e8
{call_22:4}
f30f5805
{ref_27:4}
f30f1185a0d0ffff31db498b442408488b04d8488b7810660fefc0f30f108da0d0ffff660fefd2e8
{call_56:4}
48ffc383fb0375
{jump_61:1}
418b452883f80175
{jump_6a:1}
488b9db0d0ffff488b4308488b7830e8
{call_7b:4}
3c0175
{jump_82:1}
41c7452802000000498b7d18498b442408488b00488b7010e8
{call_9c:4}
f30f100d
{ref_a1:4}
f30f1015
{ref_a9:4}
498b7d18660f6fc2e8
{call_b9:4}
48899db0d0ffff418b452883f8020f85
{jump_cc:4}
488d05
{ref_d2:4}
488b38be8e000000e8
{call_e1:4}
84c075
{jump_e8:1}
488d1d
{ref_ea:4}
488b3b8b37e8
{call_f6:4}
488b3bbe8e00000031d231c9660fefc0e8
{call_10b:4}
"""

MAC_PAN2 = """
498b7d180f57d2f3410f2ad6f30f1005
{ref_c:4}
f30f59c2f30f5915
{ref_18:4}
660fefc9e8
{call_24:4}
488b85b0d0ffff488b4008488b7838e8
{call_38:4}
3c010f85
{jump_3f:4}
41c745280300000031db498b442408488b3cd8be01000000e8
{call_5d:4}
498b442408488b04d8488b7810be01000000e8
{call_74:4}
498b442408488b3cd8488b07ff5018488d430183f803498b4c2408488b0cd9c7817801000050c30000498b4c2408488b0cd9488b4908c64160014889c375
{jump_b6:1}
e9
{jump_b8:4}
"""

MAC_PAN3 = """
83f9040f84
{jump_3:4}
83f9030f85
{jump_c:4}
498b7d18f3410f2ad6f30f1005
{ref_1b:4}
f30f59c2f30f5915
{ref_27:4}
660fefc9e8
{call_33:4}
488b430848899db0d0ffff488b7840e8
{call_47:4}
3c010f85
{jump_4e:4}
49c785a00000000000000041c74528040000004c89ff31f6e8
{call_6c:4}
498b07c6406200498b8510010000c6809000000001498b7d20e8
{call_8a:4}
4889c7be01000000e8
{call_97:4}
41c6451100498b7d1831f6e8
{call_a7:4}
498b7710498b7d18e8
{call_b4:4}
41c645120141c6452c00e9
{jump_c3:4}
"""

MAC_DEFAULTS = """
554889e54157415641554154534881ecd80000004989d44889fb0f1345b8f30f114dc08b45c08945d0488b45b8488945c80f135598f30f115da0488d7b34488d4dc88b45a08945b0488b4598488945a8c7435800000000c7435c00000000c7436000000000c743480000000048c743400000000048c743380000000048c743300000000048c743280000000048c743200000000048c743180000000048c7431000000000c783bc0000000000803f48c783c80000000000000048c783c000000000000000c783d00000000000803f48c783dc0000000000000048c783d400000000000000c783e40000000000803fc783e800000000000000c783ec0000000000803fc783f00000000000803fc783f40000000000803fc783fc00000000000000c7830001000000000000c7830401000000000000c783440100000000803f48c783500100000000000048c7834801000000000000c783580100000000803f48c783640100000000000048c7835c01000000000000c7836c0100000000803fc7837001000000000000c783740100000000803fc783780100000000803fc7837c0100000000803f89334c8963084889ce4989cee8
{call_1b2:4}
488d7b40488d75a8e8
{call_1bf:4}
4c8d6b10488d7588c7458800000000c7458c00000000c74590000000004c89efe8
{call_1e4:4}
4c8d7b1c488db578ffffffc78578ffffff00000000c7857cffffff00000000c74580000000004c89ffe8
{call_212:4}
4c89e7e8
{call_21a:4}
4c8da538ffffff488b4820488b5028488b70308b783889bd70ffffff4889b568ffffff48899560ffffff48898d58ffffff488b481848898d50ffffff488b481048898d48ffffff488b08488b400848898540ffffff48898d38ffffff4c89e74c89f6e8
{call_281:4}
488db528fffffff30f118d30fffffff30f118528ffffff660f70c001f30f11852cffffff4c89ffe8
{call_2ad:4}
4c89e74c8d75a84c89f6e8
{call_2bc:4}
488db518fffffff30f118d20fffffff30f118518ffffff660f70c001f30f11851cffffff4c89efe8
{call_2e8:4}
488d7b28488db508ffffffc78508ffffff00000000c7850cffffff0000803fc78510ffffff00000000e8
{call_316:4}
c6434c00c6434f00c6434d00c7435000000000c6434e01c6435400c683f800000000c6830801000000c6831401000001c7831801000000000000c7831c010000050000004c89f7e8
{call_362:4}
660f6fc8488d7368488d5370488d4b784989d84983e8804c8d8b88000000f30f1005
{ref_385:4}
f30f118bb8000000c783300100000ad7a33bc78334010000a69bc43bc7833801000000000000c7833c0100000000c842c6834001000000e8
{call_3c4:4}
f30f108334010000488db390000000488d9398000000488d8ba00000004c8d83a80000004c8d8bb0000000e8
{call_3f4:4}
4881c4d80000005b415c415d415e415f5dc3
"""

MAC_INCREMENT = """
554889e5f30f105f10f30f58d8f30f115f10f30f105f14f30f58d9f30f115f14f30f105f18f30f58daf30f115f18f30f58471cf30f11471cf30f584f20f30f114f20f30f585724f30f115724bee80300005de9
{jump_52:4}
90
"""

ARM_ATTACH = """
f0b503af86b00d4604462846
{call_c:4}
{jump_10:2}
28462669
{call_16:4}
81683046
{call_1e:4}
0026
{word_24:4}
00252069
{word_2c:4}
{word_30:4}
03950496059103a9
{call_3c:4}
{word_40:4}
2069
{word_46:4}
8de8600002916946
{call_52:4}
06b0f0bd
"""

ARM_CUT = """
ddf874800229
{jump_6:4}
1b94
{word_c:4}
2095
{word_12:4}
{word_16:4}
0df5005b78444ff0ff38
{word_24:4}
00680068cbf82484
{call_30:4}
c6ff100f1f9d40ec320b002602efa00d10ee104a68680df5005b00212246002350f826008068cbf82484
{call_5e:4}
0136032e
{jump_66:2}
daf818000128
{jump_6e:2}
1b980df500564ff0ff3440688069c6f82444
{call_82:4}
0128
{jump_88:2}
0220caf8180068680df500550168daf810008968c5f82444
{call_a2:4}
{word_a6:4}
daf8100000220df50055
{word_b4:4}
{word_b8:4}
0b46c5f82444
{call_c2:4}
daf81800cdf884a00228
{jump_d0:4}
{word_d4:4}
0df50056
{word_dc:4}
4ff0ff3478448e2105682868c6f82444
{call_f0:4}
{jump_f4:2}
28680df500560168c6f82444
{call_102:4}
28680df5005500210022c5f82444002300918e21
{call_11a:4}
"""

ARM_PAN2 = """
1e980df50055
{literal_6:4}
0022
{literal_c:4}
40ec300b2198fbff20060069c5f8244400ff900d00ff911d10ee101a11ee103a
{call_30:4}
1b980df500554068c069c5f82444
{call_42:4}
0128
{jump_48:4}
2199032000244ff0ff354ff00108
{word_5a:4}
88611f98406850f824000df5005b0121cbf82454
{call_72:4}
1f980df5005b01210646706850f824008068cbf82454
{call_8c:4}
70680df5005b50f824000168c968cbf824548847706850f824100134032cc1f824a1496881f85c80
{jump_b8:2}
{jump_ba:4}
"""

ARM_ROUTE3 = """
20950429
{jump_4:4}
"""

ARM_PAN3 = """
0329
{jump_2:4}
1e980df50056
{literal_c:4}
4ff0ff35
{literal_14:4}
002240ec300bdaf81000fbff2006cdf884a0c6f824544ff0000a00ff900d00ff911d10ee101a11ee103a
{call_42:4}
60681b940df50054006ac4f82454
{call_54:4}
0128
{jump_5a:4}
219e0df5005b04200021c6f88ca0c6f890a0b061cbf824541d9c2046
{call_7a:4}
20684ff001080df5005b80f85ea0d6f8d00080f848807069cbf82454
{call_9a:4}
0df5005b0121cbf82454
{call_a8:4}
86f80da00df5005b30690021cbf82454
{call_bc:4}
a1680df500543069c4f82454
{call_cc:4}
86f80e8086f81ca0
{jump_d8:4}
"""

ARM_DEFAULTS = """
f0b503af2de9000d2ded028ba8b00446c0ef500080ef1080b86825939346269004f134003e694ff00008fd684ff07e5ad7f81490ba692296cdf88c902795249284ed148bc4f8588040f98f0a04f1280040f98f0a04f1180040f98f0a04f1080040f98f0a0546039004f1b400c4f8b0a040f98f0a04f1c800c4f8c4a040f98f0a04f59e70c4f8d8a0c4f8dc80c4f8e0a0c4f8e4a0c4f8e8a0c4f8f080c4f8f480c4f8f880c4f838a140f98f0a04f5a870c4f84ca140f98f0a04f12c00c4f860a1c4f86481c4f868a1c4f86ca1c4f870a184e8020825a9
{call_d6:4}
04f1380022a9
{call_e0:4}
1fa928468ded1f8bcdf88480
{call_f0:4}
04f114061ca98ded1c8b3046cdf87880
{call_104:4}
5846
{call_10a:4}
00f12c010dad61f98f0a05f12c010df1280b25aa41f98f0a00f1200161f98f0a05f1200141f98f0a00f1100161f98f0a05f1100141f98f0a294660f98f0a584645f98f0a
{call_152:4}
30465946
{call_15a:4}
07ae294622ad30462a46
{call_168:4}
03983146
{call_170:4}
04f1200004a9cdf81080cdf814a0cdf81880
{call_186:4}
012084f8448084f847804ff0050984f84580c4f8488084f8460084f84c8084f8ec8084f8fc8084f808012846c4e94389
{call_1ba:4}
{word_1be:4}
0022c4f8ac00
{word_1c8:4}
{word_1cc:4}
{word_1d0:4}
{word_1d4:4}
c4f82411c4f8280104f16c03c4f82c8104f17c00c4f8302104f1740284f83481009304f16403019204f15c020290
{call_206:4}
d4f8281104f1940304f19c020093019204f1a40004f1840204f18c030290
{call_228:4}
204628b0bdec028bbde8000df0bd
"""

ARM_INCREMENT = """
43ec113b42ec122b41ec101b00f10801f0ee420a61f98f0af0ee401a40efc00d41f98f0a4ff47a7190ed063a03ef022d80ed062a90ed072a02ef010d80ed070a20ef1001
{jump_44:4}
"""

ARM_FIELDS = {'ARM_ATTACH': {'call_c': {'kind': 'bl'}, 'jump_10': {'kind': 'cbz', 'register': 'r0'}, 'call_16': {'kind': 'bl'}, 'call_1e': {'kind': 'bl'}, 'word_24': {'kind': 'movw', 'register': 'r1'}, 'word_2c': {'kind': 'movt', 'register': 'r6'}, 'word_30': {'kind': 'movt', 'register': 'r1'}, 'call_3c': {'kind': 'bl'}, 'word_40': {'kind': 'movw', 'register': 'r1'}, 'word_46': {'kind': 'movt', 'register': 'r1'}, 'call_52': {'kind': 'bl'}}, 'ARM_CUT': {'jump_6': {'kind': 'bgt.w'}, 'word_c': {'kind': 'movw', 'register': 'r1'}, 'word_12': {'kind': 'movw', 'register': 'r0'}, 'word_16': {'kind': 'movt', 'register': 'r0'}, 'word_24': {'kind': 'movt', 'register': 'r1'}, 'call_30': {'kind': 'bl'}, 'call_5e': {'kind': 'bl'}, 'jump_66': {'kind': 'bne'}, 'jump_6e': {'kind': 'bne'}, 'call_82': {'kind': 'bl'}, 'jump_88': {'kind': 'bne'}, 'call_a2': {'kind': 'bl'}, 'word_a6': {'kind': 'movw', 'register': 'r1'}, 'word_b4': {'kind': 'movt', 'register': 'r1'}, 'word_b8': {'kind': 'movt', 'register': 'r2'}, 'call_c2': {'kind': 'bl'}, 'jump_d0': {'kind': 'bne.w'}, 'word_d4': {'kind': 'movw', 'register': 'r0'}, 'word_dc': {'kind': 'movt', 'register': 'r0'}, 'call_f0': {'kind': 'bl'}, 'jump_f4': {'kind': 'cbnz', 'register': 'r0'}, 'call_102': {'kind': 'bl'}, 'call_11a': {'kind': 'bl'}}, 'ARM_PAN2': {'literal_6': {'kind': 'vldr', 'register': 's0'}, 'literal_c': {'kind': 'vldr', 'register': 's2'}, 'call_30': {'kind': 'bl'}, 'call_42': {'kind': 'bl'}, 'jump_48': {'kind': 'bne.w'}, 'word_5a': {'kind': 'movw', 'register': 'sl'}, 'call_72': {'kind': 'bl'}, 'call_8c': {'kind': 'bl'}, 'jump_b8': {'kind': 'bne'}, 'jump_ba': {'kind': 'b.w'}}, 'ARM_ROUTE3': {'jump_4': {'kind': 'bne.w'}}, 'ARM_PAN3': {'jump_2': {'kind': 'bne.w'}, 'literal_c': {'kind': 'vldr', 'register': 's0'}, 'literal_14': {'kind': 'vldr', 'register': 's2'}, 'call_42': {'kind': 'bl'}, 'call_54': {'kind': 'bl'}, 'jump_5a': {'kind': 'bne.w'}, 'call_7a': {'kind': 'bl'}, 'call_9a': {'kind': 'bl'}, 'call_a8': {'kind': 'bl'}, 'call_bc': {'kind': 'bl'}, 'call_cc': {'kind': 'bl'}, 'jump_d8': {'kind': 'b.w'}}, 'ARM_DEFAULTS': {'call_d6': {'kind': 'bl'}, 'call_e0': {'kind': 'bl'}, 'call_f0': {'kind': 'bl'}, 'call_104': {'kind': 'bl'}, 'call_10a': {'kind': 'bl'}, 'call_152': {'kind': 'bl'}, 'call_15a': {'kind': 'bl'}, 'call_168': {'kind': 'bl'}, 'call_170': {'kind': 'bl'}, 'call_186': {'kind': 'bl'}, 'call_1ba': {'kind': 'bl'}, 'word_1be': {'kind': 'movw', 'register': 'r1'}, 'word_1c8': {'kind': 'movw', 'register': 'r0'}, 'word_1cc': {'kind': 'movt', 'register': 'r1'}, 'word_1d0': {'kind': 'movt', 'register': 'r0'}, 'word_1d4': {'kind': 'movt', 'register': 'r2'}, 'call_206': {'kind': 'bl'}, 'call_228': {'kind': 'bl'}}, 'ARM_INCREMENT': {'jump_44': {'kind': 'b.w'}}}

def extract_opening_camera(mach, staging):
    import capstone
    mac = mach.architecture == 'x86_64'
    if not staging or (not mac and mach.architecture != 'armv7'): return {}
    text = mach.text
    code = mach.data[text['offset']:text['offset'] + text['length']]
    base = text['address']
    decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
    decoder.detail = True
    provenance = {}
    matches = {}
    def unique(key, spec, source_name=None):
        found = [m for m in template(spec).finditer(code) if mac or m.start() % 2 == 0]
        if len(found) != 1: raise ValueError('Missing or ambiguous camera declaration')
        m = found[0]
        if not mac and source_name:
            for name, expected in ARM_FIELDS[source_name].items():
                ins = instruction(m, name)
                if ins.mnemonic != expected['kind']: raise ValueError('Changed camera operand kind')
                if 'register' in expected and ins.reg_name(ins.operands[0].reg) != expected['register']:
                    raise ValueError('Changed camera operand register')
                if name.startswith('literal_') and (ins.operands[1].type != 3 or ins.reg_name(ins.operands[1].mem.base) != 'pc'):
                    raise ValueError('Invalid camera scalar load')
                if name.startswith('word_') and ins.operands[1].type != 2: raise ValueError('Invalid camera immediate')
        provenance[key] = {'offset': mach.slice_offset + text['offset'] + m.start(), 'bytes': len(m[0])}
        matches[key] = m
        return m
    def instruction(m, name):
        result = list(decoder.disasm(m[name], base + m.start(name)))
        if len(result) != 1 or result[0].size != len(m[name]): raise ValueError('Invalid camera instruction')
        return result[0]
    def destination(m, name):
        if mac: return base + m.end(name) + int.from_bytes(m[name], 'little', signed=True)
        ins = instruction(m, name)
        if ins.operands[-1].type != 2: raise ValueError('Invalid camera branch')
        return ins.operands[-1].imm
    def require(ok):
        if not ok: raise ValueError('Inconsistent opening camera context')
    def same_call(rows):
        targets = [destination(matches[key], field) for key, field in rows]
        require(len(set(targets)) == 1)
        return targets[0]
    def helper(name, address, raw):
        raw = bytes.fromhex(raw)
        found = section_bytes(mach, address, len(raw), b'__text')
        require(found is not None and found[0] == raw)
        provenance[name] = {'offset': found[1], 'bytes': len(raw)}
    def scalar(key, field):
        m = matches[key]
        if mac: address = destination(m, field); section = b'__const'
        else:
            ins = instruction(m, field)
            address = ((ins.address + 4) & ~3) + ins.operands[1].mem.disp
            section = b'__text'
        found = section_bytes(mach, address, 4, section)
        require(found is not None)
        provenance[key + '_' + field] = {'offset': found[1], 'bytes': 4}
        return struct.unpack('<f', found[0])[0]
    def immediate_float(m, low, high):
        lo = instruction(m, low).operands[1].imm if low else 0
        hi = instruction(m, high).operands[1].imm
        return struct.unpack('<f', struct.pack('<I', lo | (hi << 16)))[0]
    try:
        prefix = 'MAC_' if mac else 'ARM_'
        for key in ['attach', 'cut', 'pan2', 'pan3', 'defaults', 'increment'] + ([] if mac else ['route3']):
            name = prefix + key.upper()
            unique(key, globals()[name], name)
        initial = unique('initial_context', MAC_INITIAL if mac else ARM_INITIAL)
        formation = unique('formation_context', MAC_FORMATION if mac else ARM_FORMATION)
        for key in ['initial', 'formation']:
            require(provenance.pop(key + '_context') == staging['provenance'][key])
        cut, pan2, pan3, attach = [matches[k] for k in ['cut', 'pan2', 'pan3', 'attach']]
        start = lambda m: base + m.start()
        end = lambda m: base + m.end()
        require(end(cut) == start(pan2))
        require(destination(formation, 'jump_4e' if mac else 'jump_28') == start(cut))
        require(destination(attach, 'jump_1e' if mac else 'jump_10') == start(attach) + (0x7c if mac else 0x56))
        if mac:
            local = [('cut','jump_61',0x39),('cut','jump_6a',0xc9),('cut','jump_82',0xbe),('pan2','jump_b6',0x4f),('pan3','jump_3',0xc8)]
            exits = [('cut','jump_cc'),('pan2','jump_3f'),('pan2','jump_b8'),('pan3','jump_4e'),('pan3','jump_c3')]
            require(destination(cut,'jump_3') == start(pan3) and end(pan2) == start(pan3))
            require(destination(cut,'jump_e8') == start(pan2))
            mode = destination(initial,'call_75')
            require(mode == destination(pan3,'call_a7'))
            helper('mode_setter',mode,'554889e54088774d5dc3')
            target = same_call([('attach','call_33'),('cut','call_9c'),('pan3','call_b4')])
            helper('target_setter',target,'554889e5488977085dc3')
            getter = same_call([('attach','call_16'),('attach','call_27'),('pan3','call_8a')])
            require(getter == destination(initial,'call_41'))
            require(same_call([('cut','call_7b'),('pan2','call_38'),('pan3','call_47')]) == destination(formation,'call_43'))
            require(destination(cut,'call_b9') == destination(formation,'call_b5'))
            require(same_call([('pan2','call_24'),('pan3','call_33')]) == start(matches['increment']))
            eye = [scalar('cut','ref_a9'), scalar('cut','ref_a1'), scalar('cut','ref_a9')]
            velocity = [scalar('pan2','ref_c'),0.0,scalar('pan2','ref_18')]
            require(velocity == [scalar('pan3','ref_1b'),0.0,scalar('pan3','ref_27')])
        else:
            local = [('cut','jump_66',0x48),('cut','jump_6e',0xca),('cut','jump_88',0xc6),('pan2','jump_b8',0x64)]
            exits = [('cut','jump_d0'),('pan2','jump_48'),('pan2','jump_ba'),('pan3','jump_5a'),('pan3','jump_d8')]
            require(destination(cut,'jump_6') == start(matches['route3']))
            require(destination(matches['route3'],'jump_4') == start(pan3))
            require(destination(cut,'jump_f4') == start(pan2))
            mode = destination(initial,'call_52')
            require(mode == destination(pan3,'call_bc'))
            helper('mode_setter',mode,'80f845107047')
            target = same_call([('attach','call_1e'),('cut','call_a2'),('pan3','call_cc')])
            helper('target_setter',target,'41607047')
            getter = same_call([('attach','call_c'),('attach','call_16'),('pan3','call_9a')])
            require(getter == destination(initial,'call_1a'))
            require(same_call([('cut','call_82'),('pan2','call_42'),('pan3','call_54')]) == destination(formation,'call_18'))
            require(destination(cut,'call_c2') == destination(formation,'call_82'))
            require(same_call([('pan2','call_30'),('pan3','call_42')]) == start(matches['increment']))
            x = immediate_float(cut,'word_a6','word_b4')
            eye = [x,immediate_float(cut,None,'word_b8'),x]
            velocity = [scalar('pan2','literal_6'),0.0,scalar('pan2','literal_c')]
            require(velocity == [scalar('pan3','literal_c'),0.0,scalar('pan3','literal_14')])
        for key,field,offset in local: require(destination(matches[key],field) == start(matches[key])+offset)
        require(len({destination(matches[k],f) for k,f in exits}) == 1)
        for key,m in matches.items():
            if key.endswith('_context'): continue
            for field in m.groupdict():
                if field.startswith(('call_','jump_')):
                    # Calls/branches retain backed targets, including the shared
                    # post-opening update; no target bytes are emitted.
                    require(section_bytes(mach,destination(m,field),2,b'__text') is not None)
        for vector in [eye,velocity]:
            require(all(math.isfinite(v) and abs(v)<=10000000 for v in vector))
        # Indices, flags and source phases are literal operands in the matched
        # declarations. This data does not grant gameplay progress or rewards.
        return {'initial_target':'player','initial_fixed_eye':True,'inherit_target_up':True,
                'actor_cut':{'after_event_finished':6,'actor_id':0,'eye':eye},
                'pan':{'velocity_per_ms':velocity,'engagement_after_event_finished':7,
                       'follow_player_after_event_finished':8},'provenance':provenance}
    except (ValueError,KeyError,IndexError,TypeError,struct.error,OverflowError):
        return {}
