"""Recover scenery ore/resource declarations, preserving edition-local bindings.

Bounded static recognition only. Native availability and sampling live in Godot;
no original instructions or executable bytes enter the resulting content pack.
"""
import struct
from .opening_loadout import template
from .ship_models import section_bytes
from .scenery_population import import_symbol


def extract_scenery_resources(mach, population):
    if not population or mach.architecture not in ('x86_64','armv7'):return {}
    import capstone
    mac=mach.architecture=='x86_64';prefix='MAC_' if mac else 'ARM_'
    md=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);md.detail=True
    text=mach.text;code=mach.data[text['offset']:text['offset']+text['length']]
    file_base=mach.slice_offset+text['offset'];base=text['address'];proof={}
    def require(value):
        if not value:raise ValueError('Unsupported scenery resources')
    def read(key,at,size,spec):
        row=section_bytes(mach,at,size,b'__text');require(row is not None)
        match=template(spec).fullmatch(row[0]);require(match is not None)
        check_fields(match)
        proof[key]={'offset':row[1],'bytes':size};return match
    def unique(key,low=0,high=None):
        matches=[m for m in template(globals()[prefix+key.upper()]).finditer(code,low,len(code) if high is None else high) if mac or m.start()%2==0]
        require(len(matches)==1);m=matches[0];check_fields(m);proof[key]={'offset':file_base+m.start(),'bytes':len(m[0])};return template(globals()[prefix+key.upper()]).fullmatch(m[0]),base+m.start()
    def check_fields(match):
        if mac:return
        for name,value in match.groupdict().items():
            if not name.startswith(('call_','word_')):continue
            rows=list(md.disasm(value,0));require(len(rows)==1 and rows[0].size==4)
            ins=rows[0]
            require(ins.mnemonic in ('bl','blx') if name.startswith('call_') else ins.mnemonic in ('movw','movt') and ins.reg_name(ins.operands[0].reg)=='r0')
    def instruction(m,key,at):
        ins=list(md.disasm(m[key],at+m.start(key)));require(len(ins)==1 and ins[0].size==4);return ins[0]
    def target(m,key,at,kind='bl'):
        if mac:return at+m.end(key)+int.from_bytes(m[key],'little',signed=True)
        ins=instruction(m,key,at);require(ins.mnemonic==kind and ins.operands[-1].type==capstone.arm.ARM_OP_IMM);return ins.operands[-1].imm
    try:
        at=base+population['provenance']['count']['offset']-file_base
        predecessor=read('entry',at-(12 if mac else 6),12 if mac else 6,'e8 {call:4} 48898520ffffff' if mac else '{call:4} 0a90')
        origin=target(predecessor,'call',at-(12 if mac else 6))
        probability=read('probability',origin,710 if mac else 538,globals()[prefix+'PROBABILITY'])
        for name,keys,signature in [
            ('station_system',('call_e2','call_101') if mac else ('call_a4','call_b8'),'554889e58b47145dc3' if mac else 'c0687047'),
            ('system_x',('call_f6','call_139') if mac else ('call_b0','call_de'),'554889e58b472c5dc3' if mac else '006a7047'),
            ('system_y',('call_111','call_168') if mac else ('call_c4','call_100'),'554889e58b47305dc3' if mac else '406a7047'),
            ('item_origin',('call_129','call_158') if mac else ('call_d2','call_ea'),'554889e58b47105dc3' if mac else '00697047')]:
            address=target(probability,keys[0],origin);require(address==target(probability,keys[1],origin))
            read(name,address,len(bytes.fromhex(signature)),signature)
        item,item_at=unique('item')
        require(item_at+(0x118 if mac else 0xb0)==base+proof['item_origin']['offset']-file_base)
        sqrt_at=target(probability,'call_188' if mac else 'call_11c',origin)
        wrapper=read('sqrt_wrapper',sqrt_at,10 if mac else 6,'554889e55de9 {call:4}' if mac else '0846 {call:4}')
        body_at=target(wrapper,'call',sqrt_at,'b.w')
        sqrt=read('sqrt',body_at,33 if mac else 34,globals()[prefix+'SQRT'])
        if mac:
            # The imported stub must name sqrt; ARM performs hardware double sqrt.
            stub=target(sqrt,'sqrt',body_at)
            row=section_bytes(mach,stub,6,b'__stubs');require(row is not None)
            require(row[0][:2]==b'\xff\x25' and import_symbol(mach,stub)==b'_sqrt')
        selector,selector_at=unique('selector',at-base,at-base+4096)
        require(target(selector,'call_30' if mac else 'call_3e',selector_at)==base+population['provenance']['draw']['offset']-file_base)
        models,models_at=unique('models',at-base,at-base+4096)
        if mac:table_at=models_at+models.end('ref_51')+int.from_bytes(models['ref_51'],'little',signed=True)
        else:
            low=instruction(models,'word_14',models_at);high=instruction(models,'word_18',models_at)
            require(low.mnemonic=='movw' and high.mnemonic=='movt' and low.reg_name(low.operands[0].reg)=='r0' and high.reg_name(high.operands[0].reg)=='r0')
            table_at=models_at+0x20+low.operands[1].imm+(high.operands[1].imm<<16)
        table=section_bytes(mach,table_at,16,b'__const');require(table is not None)
        ids=list(struct.unpack('<4i',table[0]));require(all(0<=v<=65532 for v in ids))
        proof['model_table']={'offset':table[1],'bytes':16}
        if mac:
            first=int.from_bytes(probability['ore_first'],'little');weight_base=int.from_bytes(probability['weight_base'],'little');minimum=int.from_bytes(probability['weight_min'],'little')
        else:
            first_i=instruction(probability,'ore_first',origin);weight_i=instruction(probability,'weight_base',origin)
            require(first_i.mnemonic=='mov.w' and first_i.reg_name(first_i.operands[0].reg)=='fp' and weight_i.mnemonic=='rsb.w')
            first=first_i.operands[-1].imm;weight_base=weight_i.operands[-1].imm;minimum=int.from_bytes(probability['weight_min'],'little')
        fallback=int.from_bytes(probability['fallback'],'little');override=int.from_bytes(probability['override_item'],'little')
        require(first==154 and fallback==164 and override==217 and 1<=weight_base<=100 and 1<=minimum<=weight_base)
        spans=sorted((v['offset'],v['offset']+v['bytes']) for v in proof.values());require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        return {'ore_item_ids':list(range(first,fallback)),'fallback_item_id':fallback,'override_item_id':override,
                'weight_base':weight_base,'weight_minimum':minimum,'location_weight':100,'rank_discount':2,
                'sample_rows':6,'draw_bound':100,'override_cursor':90,'item_origin_index':9,'system_position_indices':[3,4],
                'model_ids':ids,'provenance':proof}
    except (ValueError,TypeError,KeyError,IndexError,OverflowError,struct.error):return {}
MAC_PROBABILITY = '554889e54157415641554154534883ec38488975b04989ff488d1d {ref_18:4} 488b3be8 {call_22:4} 8845cb488b3be8 {call_2d:4} 4885c074204889c7e8 {call_3a:4} 3db70000007511488d05 {ref_46:4} 488b38e8 {call_50:4} eb0f488d05 {ref_57:4} 488b38e8 {call_61:4} 8845ca4531f6807dcb00b800000000488945c07508498b4708488945c0488d05 {ref_83:4} 488b00488945a8bf2c000000e8 {call_96:4} 4989c74c897da0bf2c000000e8 {call_a7:4} 4989c54c896db831c04863d0418d8e {ore_first:4} 41894c9500807dcb01750d41c7049700000000e9d7000000488b5db04889df488955d0e8 {call_e2:4} 4863c04c8b7dc0498b4f08488b3cc1e8 {call_f6:4} 4189c54889dfe8 {call_101:4} 4863c0498b4f08488b3cc1e8 {call_111:4} 8945cc488b5da8488b43084a8bbcf0d0040000e8 {call_129:4} 4863c0498b4f08488b3cc1e8 {call_139:4} 4189c44529ec4c8b6db8488b43084a8bbcf0d0040000450fafe4e8 {call_158:4} 4863c0498b4f08488b3cc1e8 {call_168:4} 2b45cc0fafc04401e04c8b7da0f30f2ac0488d05 {ref_17e:4} 488b38e8 {call_188:4} 488b75d08d4601f30f2cd0b9 {weight_base:4} 29d183f9 {weight_min:1} ba000000000f4cca41890cb749ffc64183fe0a0f85fafeffff41c74528 {fallback:4} 4531c0807dcb00b864000000410f44c041894728b901000000b201eb354863f1418b3cb78d41ff4863c0418b1c8739fb7d1e418b54850041893c87418b7cb50041897c850041891cb7418954b50030d2ffc183f90a7ec6b901000000f6c201b20174ef4c89f98b0185c07e054401c089014883c1044183c0fe4183f8ea75e7bf58000000e8 {call_247:4} 4989c431db4c8d35 {ref_251:4} 89d8c1e81f01d8d1f84863c0418b4c850041890c9c807dca01418b04874189449c047515498b3ee8 {call_27f:4} 83f85a7c0841c7049c {override_item:4} 4883c30283fb167cbe4c89ff4885ff7405e8 {call_2a2:4} 4d85ed74084c89efe8 {call_2af:4} 4c89e04883c4385b415c415d415e415f5dc3'
ARM_PROBABILITY = 'f0b503af2de9000d8ab003910546 {word_e:4}  {word_12:4} 784404682068 {call_1c:4} 09902068 {call_24:4} 38b1 {call_2a:4} b72803d12068 {call_34:4} 02e02068 {call_3c:4} 08900998009400284ff00000049004bf68680490 {word_54:4}  {word_58:4} 78440068006802902c20 {call_66:4} 05462c20 {call_6e:4} 0446 {ore_first:4} 0594 {word_7a:4}  {word_7e:4} ddf810807844002600680190099844f826b0012803d1002045f826004ee0039c2046 {call_a4:4} d8f8041051f82000 {call_b0:4} 07902046 {call_b8:4} d8f8041051f82000 {call_c4:4} 029c0690606850f82b00 {call_d2:4} d8f8041051f82000 {call_de:4} 8246606850f82b00 {call_ea:4} d8f80410079a51f82000aaeb020202fb02f4 {call_100:4} 0699401a00fb004040ec300b0198bbff2006006810ee101a {call_11c:4} 40ec300b059cbbff200710ee100a {weight_base:4}  {weight_min:1} 28b8bf002045f8260001360bf1010bbbf1a40fa2d1 {fallback:1} 200121a0620998002818bf6420ddf800b0a862012000e001300a2814dc421e55f8206055f82230b342f5da45f8226054f8221054f8206044f8226044f82010002145f82030e7e711f0010f4ff001004ff00101e1d000200021059455f82120012aa4bf024445f82120013102380b29f4d15820 {call_1bc:4} 059a044600266ff0030806ebd67008ea4000115844f8261004eb860128584860089801280ad1dbf800009246 {call_1ec:4} 52465a28a4bf {override_item:1} 2044f826000236162ee3db28461546 {call_206:4} 2846 {call_20c:4} 20460ab0bde8000df0bd'
MAC_SELECTOR = '4589e64584ed74164589f4448bb550ffffff488b9d48ffffffe9eafdffff488d05 {ref_1e:4} 488b384889f3be64000000e8 {call_30:4} 4889de418d4e014863c94531e43b048e7db94d63e6428b14a6899550ffffff4183c4024183fc0ab800000000440f4fe081fad90000000f94c181faa40000000f9cc2b00108ca75034488f8488b9d48ffffff48899d48ffffff4188c74588fd4180e501e963ffffff'
ARM_SELECTOR = '0a9e0021ddf850b00d9810e056f8241000201891d92908bf0120a4294ff00001b8bf01210143a01c0a28c8bf0020044611f0010f0ed1dbf8000064212e95 {call_3e:4} 06eb84014a68002190424ff00000eddadbe70d94189d'
MAC_MODELS = '84c08b9508ffffffb8010000000f45d04181fed9000000b8030000000f44d0899510ffffff488b8d18ffffff3b8d2cffffff89d0baa086010089d7ba60ea00000f4cfa410f9cc085c94989cd0f9fc230c9488d35 {ref_51:4} 8b0486'
ARM_MODELS = '0f99002818bf0121d92d08bf03214ff0ff3a1191 {word_14:4}  {word_18:4} 784450f821001790'
MAC_ITEM = '554889e5488b47384885c0747d488b48088b4904890f488b48088b490c894f04488b48088b4914894f08488b48088b491c894f0c488b48088b4934894f1c488b48088b493c894f20488b50088b5244895724488b70088b7624897710488b40088b402c89471429ca89d0c1e81f01d0d1f801c8894718c647500048c747480000000048c74740000000005dc3'
ARM_ITEM = '016b002908bf70474968c0ef50004a680260ca6842604a698260ca69c2604a6bc261ca6b02624b6c4362d1f82490c0f81090c96a4161991a01ebd17102eb6101816100f1340141f98f0a002180f844107047'
MAC_SQRT = '554889e54883ec10f30f1145fcf30f5a45fce8 {sqrt:4} f20f5ac04883c4105dc3'
ARM_SQRT = '81b040ec100bb0ee402a8ded002ab7eec20ab1eec00bb7eec02b12ee100a01b07047'
