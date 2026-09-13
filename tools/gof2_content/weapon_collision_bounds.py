"""Recover ordinary weapon constructor bounds selection through its factory link."""
from .opening_loadout import template
from .ship_models import section_bytes
from .weapon_capacity import MAC_CALL,ARM_CALL

MAC_WRAPPER='554889e55de9 {constructor:4}'
ARM_WRAPPER='f0b503af4df8048d8ab00446fd6ad7f824e0d7f82090d7f81cc097ed050ab869be6a09950896cdf81ce0cdf81890cdf814c004902046d7f81080fd68be688ded030acdf808800195009620ef1001 {constructor:4} 20460ab05df8048bf0bd'
MAC_SELECTOR='4d8d742444f30f114db0f30f1145a8660f70c001f30f1145ac41f687ac00000001488b8590feffff490f44c6'
ARM_SELECTOR='9bf8680006f1400ab0460028504618bf0bf582700568'
MAC_DEFAULT='c683ac00000000'
ARM_DEFAULT='00245060129ac2f80880046012980460119e0a9dc6f8ac1006992846 {call_1c:4} 05992846 {call_24:4} 04992846 {call_2c:4} 03992846 {call_34:4} d6f8ac102846 {call_3e:4} 012d1ddb45f200004bf6c051c4f24370cff6f07100220023119ef668b0500c32119ef66b46f82310119e366cf454119ed6f8ac60766846f8234001339d42ebd111984ff0ff3180f84c401198c0f8b840119880f85440119880f84d401198c0f8b440119881651198c165119880f8f880119880f86840'


def extract_weapon_collision_bounds(mach,weapon):
    import capstone
    if mach.architecture not in ('x86_64','armv7'):return {}
    mac=mach.architecture=='x86_64';proof={}
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    def require(value):
        if not value:raise ValueError('Unsupported ordinary collision bounds')
    def address(span):return mach.text['address']+span['offset']-mach.slice_offset-mach.text['offset']
    def match(key,at,size,spec):
        row=section_bytes(mach,at,size,b'__text');require(row is not None)
        result=template(spec).fullmatch(row[0]);require(result is not None)
        proof[key]={'offset':row[1],'bytes':size};return result
    def call(m,key,at):
        if mac:return at+m.end(key)+int.from_bytes(m[key],'little',signed=True)
        rows=list(decoder.disasm(m[key],at+m.start(key)))
        require(len(rows)==1 and rows[0].mnemonic=='bl' and rows[0].size==4 and rows[0].operands[-1].type==capstone.arm.ARM_OP_IMM)
        return rows[0].operands[-1].imm
    try:
        construction=weapon['projectile_capacity']['provenance']['constructor_call']
        at=address(construction)
        caller=match('constructor_call',at,70 if mac else 72,MAC_CALL if mac else ARM_CALL)
        wrapper_at=call(caller,'ctor',at)
        wrapper=match('wrapper',wrapper_at,10 if mac else 92,MAC_WRAPPER if mac else ARM_WRAPPER)
        constructor=call(wrapper,'constructor',wrapper_at)
        match('constructor_entry',constructor,4,'554889e5' if mac else 'f0b503af')
        default_at=constructor+(0x349 if mac else 0x1e8)
        default=match('default',default_at,7 if mac else 184,MAC_DEFAULT if mac else ARM_DEFAULT)
        if not mac:
            # R4 is set to zero, preserved through ABI calls and never reassigned
            # before the bounds flag store. Repeated array constructors agree.
            require(len({call(default,key,default_at) for key in ['call_1c','call_24','call_2c','call_34']})==1)
            call(default,'call_3e',default_at)
        gate=weapon['ordinary_hit_policy']['provenance']['additional_gate']
        selector_at=address(gate)+(0x4d9 if mac else -0x26a)
        match('selector',selector_at,44 if mac else 22,MAC_SELECTOR if mac else ARM_SELECTOR)
        spans=sorted((r['offset'],r['offset']+r['bytes']) for r in proof.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        return {'mode':'target','provenance':proof}
    except (ValueError,KeyError,TypeError,IndexError,OverflowError):return {}
