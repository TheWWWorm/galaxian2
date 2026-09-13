"""Static declarations for the fresh opening's generated coordinate patrol routes."""
import copy
import struct
from .opening_loadout import template
from .opening_npc_guidance import LAYOUTS as GUIDANCE_LAYOUTS

VALUES = {'candidate_origins':[[-30000,-10000,20000],[5000,-10000,20000],
                                [5000,-10000,55000],[-30000,-10000,55000]],
          'coordinate_bounds':[25000,10000,25000], 'count_minimum':2,'count_bound':3,
          'candidate_bound':4,'initial_index':0,'loop':True,'arrival_half_extent':2000}


def extract_npc_routes(mach, actors):
    import capstone
    if mach.architecture not in LAYOUTS:return {}
    mac=mach.architecture=='x86_64';arch=mach.architecture
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    proof={};matched={};bases={}
    def require(value):
        if not value:raise ValueError('Unsupported generated NPC route declaration')
    def address(span):
        offset=span['offset']-mach.slice_offset
        rows=[s for s in mach.sections if s['offset']<=offset and offset+span['bytes']<=s['offset']+s['length']]
        require(len(rows)==1)
        return rows[0]['address']+offset-rows[0]['offset']
    def read(key,at,size,segment=b'__TEXT',section=b'__text'):
        rows=[s for s in mach.sections if s['segment']==segment and s['name']==section and s['address']<=at and at+size<=s['address']+s['length']]
        require(len(rows)==1);offset=rows[0]['offset']+at-rows[0]['address']
        raw=mach.data[offset:offset+size];require(len(raw)==size)
        span={'offset':offset+mach.slice_offset,'bytes':size}
        require(key not in proof or proof[key]==span)
        proof[key]=span
        return raw
    def target(key,field):
        row,at=matched[key]
        if mac:return at+row.end(field)+int.from_bytes(row[field],'little',signed=True)
        instructions=list(decoder.disasm(row[field],at+row.start(field)))
        require(len(instructions)==1)
        i=instructions[0];require(i.mnemonic in ['bl','b.w'] and i.operands[-1].type==capstone.arm.ARM_OP_IMM)
        return i.operands[-1].imm
    try:
        initial=actors['npc_initialization'];flight=initial['flight'];guidance=initial['guidance']
        require(initial['holding'] and [r['actor_kind'] for r in actors['actors']]==[8,8,8])
        require([r['hull_catalogue_id'] for r in actors['actors']]==[2,23,2])
        pointer=int.from_bytes(read('virtual_update',address(flight['provenance']['virtual_update']),8 if mac else 4,b'__DATA',b'__const'),'little')
        if not mac:require(pointer&1)
        bases={'constructor':address(flight['provenance']['bank'])-(2272 if mac else 1794),'update':pointer if mac else pointer&~1}
        selection=guidance['provenance']['selection'];at=address(selection)
        row=template(GUIDANCE_LAYOUTS[arch]['selection'][3]).fullmatch(read('selection',at,selection['bytes']));require(row is not None)
        matched['selection']=(row,at);rng=target('selection','call_33' if mac else 'call_3c')
        for key in ['generation','policy','wrapper','route','loop','copy_points','copy_plain','dispatch','waypoint','waypoint_tail','near_gate','fire_gate','advance_wrapper','advance']:
            if key not in LAYOUTS[arch]:continue
            base,delta,size,pattern=LAYOUTS[arch][key]
            if base not in bases:
                source,field=LINKS[arch][base];bases[base]=target(source,field)
            at=bases[base]+delta;row=template(pattern).fullmatch(read(key,at,size));require(row is not None)
            matched[key]=(row,at)
        for key,fields in SAME_TARGETS[arch].items():
            values=[target(*field.split('.')) for field in fields]
            require(len(set(values))==1)
            if key=='random':require(values[0]==rng)
        for field,value in LITERALS[arch].items():
            key,name=field.split('.');row,at=matched[key]
            if mac:at=target(key,name)
            else:
                i=list(decoder.disasm(row[name],at+row.start(name)))
                require(len(i)==1 and i[0].mnemonic=='vldr' and i[0].reg_name(i[0].operands[-1].mem.base)=='pc')
                at=((i[0].address+4)&~3)+i[0].operands[-1].mem.disp
            literal_key='positive_extent' if value>0 else 'negative_extent'
            raw=read(literal_key,at,4,b'__TEXT',b'__const' if mac else b'__text')
            require(struct.unpack('<f',raw)[0]==value)
        spans=sorted((s['offset'],s['offset']+s['bytes']) for s in proof.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        result=copy.deepcopy(VALUES);result['provenance']=proof;return result
    except (ValueError,KeyError,TypeError,IndexError,OverflowError):return {}

LAYOUTS = {'armv7': {'advance': ['advance',
                       0,
                       246,
                       'f0b5064603aff56830682c68a04271da3469646854f82040002c6bd141ec301b696851f8200090ed480afbff0026 '
                       '{ref_46:4} 20efa21db4eec01af1ee10fa59d5 {ref_64:4} '
                       'b4eec21af1ee10fa52dd90ed491a42ec302bfbff012620efa21db4eec01af1ee10fa45d5b4eec21af1ee10fa40dd90ed4a1a43ec303bfbff012620efa21db4eec01af1ee10fa33d5b4eec21af1ee10fad8bff0bd0021 '
                       '{call_154:4} f1683068496851f82000 {call_168:4} '
                       '31684d1c3560f068327992b10268531e99420edb0025002a35600ad0406850f82500 {call_206:4} '
                       'f068013501688d42f5d3356801688d4207da4068012150f82500bde8f040 {call_240:4} f0bd'],
           'advance_wrapper': ['advance_wrapper', 0, 14, 'd1f800904a688b684946 {call_10:4} '],
           'copy_plain': ['copy',
                          408,
                          46,
                          '4ff0ff3007960c901820 {call_10:4} 03220a900a98d8f800100c9201eb41025146 {call_32:4} '
                          '0a9c079800790a990871'],
           'copy_points': ['copy',
                           110,
                           88,
                           'adb1d8f804100af10400002251f822300132aa42d3f8204140f8044cd3f824410460d3f82831436000f10c00eed33469002c1cbf2068002800f0778062680021002352f823500133002d18bf01218342f7d311f0010f68d0'],
           'dispatch': ['update',
                        3430,
                        158,
                        '00208af82801daf83400b0f1ff3f02d1daf8680060b9daf804004ff0ff31cdf8a018 {call_34:4} '
                        '012840f0ef80daf868004ff0ff34cdf8a048 {call_56:4} 002800f0ce80daf80400cdf8a048 '
                        '{call_74:4} 012840f0c5800df2a475daf808104ff0ff36daf868402846cdf8a068 {call_106:4} '
                        '20462946cdf8a068 {call_118:4} daf86800cdf8a068 {call_130:4} '
                        '002800f0f980daf86800cdf8a068 {call_148:4} 002800f06283'],
           'fire_gate': ['update',
                         10380,
                         34,
                         '9af82a1120ef1001002900f0a9829af82811002940f0a482daf84411002900f09f82'],
           'generation': ['constructor',
                          374,
                          652,
                          '204646f2a811 {call_6:4} 47f23051401a022140ec300b1098cded0c0b00681b9142f21071 '
                          '{call_36:4} 0f901098032100681b9146f2a811 {call_54:4} '
                          '0f9a42f21071511a44f62062104441ec1f1b042140ec300b1098cded0a0b00681b9146f2a811 '
                          '{call_96:4} 41f288310844052140ec1a0b109800681b9142f21071 {call_122:4} '
                          '0f901098062100681b9146f2a811 {call_140:4} '
                          '0f9a42f21071511a44f62062104441ec1e1b072140ec1c0b109800681b9146f2a811 {call_178:4} '
                          '41f288310844082140ec180b109800681b9142f21071 {call_204:4} '
                          '0f901098092100681b9146f2a811 {call_222:4} '
                          '0f9a42f21071511a4df2d862104441ec1b1b0a2140ec190b109800681b9146f2a811 {call_260:4} '
                          '47f23051401a0b2140ec1d0b109800681b9142f21071 {call_286:4} '
                          '0f9010980c2100681b9146f2a811 {call_304:4} '
                          'dded0c0bbbff0f66bbff2046dded0a0bbbff20560f9a42f21071bbff0816511a4df2d8621044bbff093641ec321b8ded334a40ec300b10988ded346abbff0a768ded355abbff0c06bbff0e260068bbff0b860d21bbff0d96bbff20468ded367abbff22568ded372a8ded380a8ded391a8ded3a8a8ded3b3a8ded3c9a8ded3d5a8ded3e4a1b91032120ef1001 '
                          '{call_448:4} '
                          '00eb40000022811d04200991a1fb000114920e221b92002918bf0121002918bf4ff0ff30 '
                          '{call_488:4} 0890099801283adb0023981c0c90581c0f930a9010980f2100681b910421 '
                          '{call_522:4} '
                          '14a9095c0029f4d114a901220f9b0a5400eb400033a901eb8000089a90ed000a02eb83010333bbff000781ed000a90ed010a0a99bbff000702eb810181ed000a90ed020a0c98bbff000702eb800080ed000a099820ef10018342c5db10201b901820 '
                          '{call_624:4} 1121169016981b910899099a {call_640:4} 16981599c1f84001'],
           'loop': ['loop', 0, 4, '01717047'],
           'near_gate': ['update', 9210, 20, 'daf84401002800f00f829af82811002940f00a82'],
           'policy': ['constructor',
                      1416,
                      118,
                      '15211598d0f840011b910121 {call_12:4} 41f65a601621c0f22400784400681b910121 {call_34:4} '
                      '47f61c60c0f22100159978440268002088661721109210681b91 {call_64:4} '
                      '292816d0079809280ad141f61c601821c0f22400784400681b91 {call_94:4} '
                      '06e015981921d0f840011b91 {call_110:4} 15998866'],
           'route': ['route',
                     0,
                     354,
                     'f0b503af2de9000dadf1400424f00f04a54604f9ed8204f9efc298b0039100210160059001710c200492 '
                     '{call_42:4} '
                     '4ff2c601634ac0f21f01079079440ba87a44096811915f49129241f0010113977944cdf854d0149101210c91 '
                     '{call_90:4} 0420 {call_96:4} '
                     '07990123079a5060079a936000220260079802600598c1604ff0ff300c900c20 {call_132:4} '
                     '089002200c900420 {call_144:4} '
                     '08990123089a5060089a93600022026008980260059801614ff0ff300c900c20 {call_180:4} '
                     '099003200c900420 {call_192:4} '
                     '089945f25654099ac5f25554099b01265860099b049d9e60002355fb04f403600998059e0360726104ebd4742046 '
                     '{call_242:4} 71692046 {call_250:4} 012d34464ff000052cdb4ff0ff3006950c904ff49a70 '
                     '{call_276:4} 0a9004260a98039a52f8251002eb8502d2e901230c960094 {call_304:4} '
                     '0a9c059ef5682868411ca96068688900 {call_324:4} '
                     '6860296840f8214034460699a8680331286004980d468142d2db'],
           'waypoint': ['update',
                        5320,
                        72,
                        'daf868004ff0ff34cdf8a048 {call_12:4} '
                        '90ed480abbff00068aed580adaf86800cdf8a04820ef1001 {call_40:4} '
                        '90ed490abbff00068aed590adaf86800cdf8a04820ef1001 {call_68:4} '],
           'waypoint_tail': ['update',
                             1986,
                             30,
                             ' {call_0:4} 90ed4a0abbff00068aed5a0a20ef100101208af82801 {call_26:4} '],
           'wrapper': ['wrapper', 0, 14, '90b5044601af {call_6:4} 204690bd']},
 'x86_64': {'advance': ['advance',
                        0,
                        301,
                        '554889e54156534989fe498b461049630e3b080f8df6000000498b5618488b520848833cca000f85e3000000488b4008488b3cc8f30f2a9f70010000f30f5cc3f30f101d '
                        '{ref_64:4} 0f2ed80f86be0000000f2e05 {ref_81:4} '
                        '0f86b1000000f30f2a8774010000f30f5cc8f30f1005 {ref_106:4} 0f2ec10f86940000000f2e0d '
                        '{ref_123:4} 0f8687000000f30f2a8778010000f30f5cd0f30f1005 {ref_148:4} '
                        '0f2ec2766e0f2e15 {ref_161:4} 766531f6e8 {call_172:4} '
                        '496306498b4e10488b4908488b3cc1e8 {call_192:4} '
                        '418b1effc341891e498b461041f646040174338b08ffc939cb7e2b41c7060000000031db833800741d4863db488b4008488b3cd8e8 '
                        '{call_249:4} '
                        'ffc3498b46103b1872e6418b1e3b187c055b415e5dc34863cb488b4008488b3cc8be010000005b415e5de9 '
                        '{call_296:4} '],
            'advance_wrapper': ['advance_wrapper',
                                0,
                                24,
                                '554889e5f30f105608f30f1006f30f104e045de9 {call_19:4} '],
            'copy_plain': ['copy',
                           394,
                           38,
                           'bf28000000e8 {call_5:4} 4989c54c89ef4c89e6488b55d0e8 {call_23:4} '
                           '418a4604240141884504'],
            'copy_points': ['copy',
                            14,
                            162,
                            '4989fe4d8b6e10458b7d00438d047f488945d0488d3c8500000000e8 {call_27:4} '
                            '4989c44585ff7442498b4508b90200000031d24863d2488b34d08bbe700100008d59fe41893c9c8bbe740100008d59ff41893c9c8bb678010000ffc289cf83c103418934bc4439fa72c9498b4e184885c90f84050100008b0185c00f84fb000000488b490830d231f648833cf1007402b20148ffc639c672f0f6c2010f84da000000'],
            'dispatch': ['update',
                         3595,
                         184,
                         '41c6867c0100000041837e54ff750c498bbe980000004885ff7518498b7e08e8 {call_31:4} '
                         '3c010f8543080000498bbe98000000e8 {call_51:4} 4885c00f8498070000498b7e08e8 '
                         '{call_69:4} 3c010f8587070000498b7e10498b9e98000000e8 {call_93:4} '
                         'f30f118db0fefffff30f1185a8feffff660f70c001f30f1185acfeffff488db5a8feffff4889dfe8 '
                         '{call_137:4} 498bbe98000000e8 {call_149:4} 4885c00f849c080000498bbe98000000e8 '
                         '{call_170:4} 4885c00f84bd060000'],
            'fire_gate': ['update',
                          11489,
                          42,
                          '41f6867e010000010f84ed01000041f6867c010000010f85df0100004983bea0010000000f84d1010000'],
            'generation': ['constructor',
                           507,
                           726,
                           '488b38bea8610000e8 {call_15:4} 898538ffffff488d05 {ref_26:4} '
                           '488b38be10270000e8 {call_41:4} 898534ffffff488d05 {ref_52:4} 488b38bea8610000e8 '
                           '{call_67:4} 898530ffffff488d05 {ref_78:4} 488b38bea8610000e8 {call_93:4} '
                           '89852cffffff488d05 {ref_104:4} 488b38be10270000e8 {call_119:4} '
                           '898528ffffff488d05 {ref_130:4} 488b38bea8610000e8 {call_145:4} '
                           '898524ffffff488d05 {ref_156:4} 488b38bea8610000e8 {call_171:4} '
                           '898520ffffff488d05 {ref_182:4} 488b38be10270000e8 {call_197:4} 4189c6488d05 '
                           '{ref_205:4} 488b38bea8610000e8 {call_220:4} 4189c7488d05 {ref_228:4} '
                           '488b38bea8610000e8 {call_243:4} 4189c5488d05 {ref_251:4} 488b38be10270000e8 '
                           '{call_266:4} 89c3488d05 {ref_273:4} 488b38bea8610000e8 {call_288:4} '
                           '8b8d38ffffff81c1d08afffff3440f2ac18b8d30ffffff81c1204e0000f3440f2ac98b8d34ffffff81c1f0d8fffff30f2ad18b8d2cffffff81c188130000f30f2ae18b8d24ffffff81c1204e0000f30f2ad98b8d28ffffff81c1f0d8fffff30f2af98b8d20ffffff81c188130000f30f2ae94181c7d8d60000f3410f2af74181c6f0d8fffff3410f2ac64181c5d08afffff3410f2acdf3440f1145a0f30f1155a4f3440f114da8f30f1165acf30f117db081c3f0d8ffff05d8d60000f30f115db4f30f2ad0f30f2adb488d05 '
                           '{ref_494:4} '
                           'f30f116db8f30f1145bcf30f1175c0f30f114dc4f30f115dc8f30f1155cc488b38be03000000e8 '
                           '{call_539:4} '
                           '448d7440064963c6b90400000048f7e148c7c7ffffffff480f41f8c7459c00000000e8 '
                           '{call_578:4} 4989c7498d8424c001000048898538ffffff31db4c8d2d {ref_603:4} '
                           'eb2dc644059c01488d0440f30f2c4c85a041890c9ff30f2c4c85a441894c9f04f30f2c4485a84189449f084883c3034439f37d24498b7d00be04000000e8 '
                           '{call_671:4} 4863c0f644059c0175e8ebb4eb004989c6e9 {call_693:4} bf28000000e8 '
                           '{call_703:4} 4989c54c89ef4c89fe4489f2e8 {call_720:4} 4d89ac2498010000'],
            'loop': ['loop', 0, 10, '554889e5408877045dc3'],
            'near_gate': ['update',
                          11121,
                          30,
                          '498b86a00100004885c00f84c300000041f6867c010000010f85b5000000'],
            'policy': ['constructor',
                       1827,
                       111,
                       '498bbc2498010000be01000000e8 {call_13:4} 488b3d {ref_18:4} be01000000e8 {call_30:4} '
                       '49c784249800000000000000488d05 {ref_47:4} 488b38e8 {call_57:4} '
                       '83f829742c83bd4cffffff09750e488b3d {ref_76:4} e8 {call_83:4} eb0d498bbc2498010000e8 '
                       '{call_98:4} 4989842498000000'],
            'route': ['route',
                      0,
                      331,
                      '554889e5415741564155415453508955d44989f64989ff41c7070000000041c6470400bf18000000e8 '
                      '{call_40:4} 4889c3bf08000000e8 {call_53:4} '
                      '48894308c743100100000048c70000000000c7030000000049895f10bf18000000e8 {call_91:4} '
                      '4889c3bf08000000e8 {call_104:4} '
                      '48894308c743100100000048c70000000000c7030000000049895f18bf18000000e8 {call_142:4} '
                      '4889c3bf04000000e8 {call_155:4} '
                      '48894308c7431001000000c70000000000c7030000000049895f20486345d44869d8565555554889d848c1e83f48c1eb2001c3498b771889dfe8 '
                      '{call_217:4} 498b772089dfe8 {call_228:4} 31db3b5dd47d67bf88010000e8 {call_245:4} '
                      '4989c4418b4c9e08418b549e04418b349e4c89e74d89f8e8 {call_273:4} '
                      '4d8b6f10418b7500ffc641897510498b7d0848c1e603e8 {call_300:4} '
                      '4883c30349894508418b4d004c8924c8418b451041894500eba0'],
            'waypoint': ['update',
                         5504,
                         100,
                         '498bbe98000000e8 {call_7:4} f30f2a8070010000f3410f1186cc010000498bbe98000000e8 '
                         '{call_36:4} f30f2a8074010000f3410f1186d0010000498bbe98000000e8 {call_65:4} '
                         'f30f2a8078010000f3410f1186d401000041c6867c01000001e9 {call_95:4} '],
            'wrapper': ['wrapper', 0, 10, '554889e55de9 {call_5:4} ']}}

LINKS = {'armv7': {'advance': ['advance_wrapper', 'call_10'],
           'advance_wrapper': ['dispatch', 'call_118'],
           'copy': ['policy', 'call_110'],
           'loop': ['policy', 'call_12'],
           'route': ['wrapper', 'call_6'],
           'wrapper': ['generation', 'call_640']},
 'x86_64': {'advance': ['advance_wrapper', 'call_19'],
            'advance_wrapper': ['dispatch', 'call_137'],
            'copy': ['policy', 'call_98'],
            'loop': ['policy', 'call_13'],
            'route': ['wrapper', 'call_5'],
            'wrapper': ['generation', 'call_720']}}

SAME_TARGETS = {'armv7': {'1789724': ['wrapper.call_6', 'copy_plain.call_32'],
           '1790852': ['policy.call_12', 'policy.call_34'],
           '1791044': ['dispatch.call_56',
                       'dispatch.call_130',
                       'waypoint.call_12',
                       'waypoint.call_40',
                       'waypoint_tail.call_0'],
           '1791512': ['policy.call_94', 'policy.call_110'],
           '1999776': ['advance.call_154', 'advance.call_240'],
           'random': ['generation.call_6',
                      'generation.call_36',
                      'generation.call_54',
                      'generation.call_96',
                      'generation.call_122',
                      'generation.call_140',
                      'generation.call_178',
                      'generation.call_204',
                      'generation.call_222',
                      'generation.call_260',
                      'generation.call_286',
                      'generation.call_304',
                      'generation.call_448',
                      'generation.call_522']},
 'x86_64': {'4296442192': ['wrapper.call_5', 'copy_plain.call_23'],
            '4296443266': ['policy.call_13', 'policy.call_30'],
            '4296443566': ['dispatch.call_51',
                           'dispatch.call_149',
                           'waypoint.call_7',
                           'waypoint.call_36',
                           'waypoint.call_65'],
            '4296444206': ['policy.call_83', 'policy.call_98'],
            '4296644252': ['advance.call_172', 'advance.call_296'],
            'random': ['generation.call_15',
                       'generation.call_41',
                       'generation.call_67',
                       'generation.call_93',
                       'generation.call_119',
                       'generation.call_145',
                       'generation.call_171',
                       'generation.call_197',
                       'generation.call_220',
                       'generation.call_243',
                       'generation.call_266',
                       'generation.call_288',
                       'generation.call_539',
                       'generation.call_671']}}

LITERALS = {'armv7': {'advance.ref_46': 2000.0, 'advance.ref_64': -2000.0},
 'x86_64': {'advance.ref_106': 2000.0,
            'advance.ref_123': -2000.0,
            'advance.ref_148': 2000.0,
            'advance.ref_161': -2000.0,
            'advance.ref_64': 2000.0,
            'advance.ref_81': -2000.0}}
