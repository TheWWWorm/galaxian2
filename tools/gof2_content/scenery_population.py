"""Recover edition-local scenery counts and their linked station-seeded sampler."""
import struct
from .opening_loadout import template
from .ship_models import section_bytes


def import_symbol(mach, address):
    """Resolve a Mach-O symbol stub without executing its loader."""
    data=mach.data
    def unpack(fmt,at):
        size=struct.calcsize(fmt)
        if at<0 or at+size>len(data):raise ValueError('Invalid symbol extent')
        return struct.unpack_from(fmt,data,at)
    wide=mach.architecture=='x86_64'
    header=32 if wide else 28
    count,command_bytes=unpack('<2I',16);end=header+command_bytes;position=header
    if count>256 or end>len(data):return None
    symbols=indirect=None;stubs=[]
    for _ in range(count):
        command,size=unpack('<2I',position)
        if size<8 or position+size>end: return None
        if command==2:
            if size!=24 or symbols is not None:return None
            symbols=unpack('<4I',position+8)
        elif command==11:
            if size!=80 or indirect is not None:return None
            indirect=unpack('<2I',position+56)
        elif command==(0x19 if wide else 1):
            segment,section=(72,80) if wide else (56,68)
            if size<segment:return None
            n=unpack('<I',position+segment-8)[0]
            if n>4096 or segment+section*n!=size:return None
            for i in range(n):
                at=position+segment+section*i
                addr,length=unpack('<2Q' if wide else '<2I',at+32)
                flags,first,stride=unpack('<3I',at+(64 if wide else 56))
                if flags&255==8 and addr<=address<addr+length:stubs.append((addr,length,first,stride))
        position+=size
    if position!=end or symbols is None or indirect is None or len(stubs)!=1:return None
    addr,length,first,stride=stubs[0]
    if not stride or length%stride or (address-addr)%stride:return None
    index=first+(address-addr)//stride
    if index>=indirect[1]:return None
    index=unpack('<I',indirect[0]+4*index)[0]
    if index>=symbols[1]:return None
    string_index,kind=unpack('<IB',symbols[0]+(16 if wide else 12)*index)
    if kind&14 or string_index>=symbols[3] or symbols[2]+symbols[3]>len(data):return None
    begin=symbols[2]+string_index
    stop=data.find(b'\0',begin,min(begin+256,symbols[2]+symbols[3]))
    return data[begin:stop] if stop>=0 else None


# Kept for existing ARM reader callers.
arm_import = import_symbol

def extract_scenery_population(mach):
    import capstone
    mac=mach.architecture=='x86_64'
    if not mac and mach.architecture!='armv7':return {}
    md=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);md.detail=True
    proof={};text=mach.text;code=mach.data[text['offset']:text['offset']+text['length']]
    def require(value):
        if not value:raise ValueError('Unsupported scenery population')
    def match(key,at,size,spec):
        choices = [(size, spec)] + (MAC_ALTERNATES.get(key, []) if mac else [])
        matches = []
        for length, layout in choices:
            row = section_bytes(mach, at, length, b'__text')
            if row is not None and (result := template(layout).fullmatch(row[0])):
                matches.append((row, result, length))
        require(len(matches) == 1)
        row, result, length = matches[0]
        proof[key]={'offset':row[1],'bytes':length};return result
    def target(m,key,at,kind='bl'):
        if mac:return at+m.end(key)+int.from_bytes(m[key],'little',signed=True)
        rows=list(md.disasm(m[key],at+m.start(key)))
        require(len(rows)==1 and rows[0].mnemonic==kind and rows[0].size==4 and rows[0].operands[-1].type==capstone.arm.ARM_OP_IMM)
        return rows[0].operands[-1].imm
    try:
        spec=MAC_COUNT if mac else ARM_COUNT
        sites=[m for m in template(spec).finditer(code) if mac or m.start()%2==0]
        require(len(sites)==1)
        at=text['address']+sites[0].start()
        count=match('count',at,66 if mac else 70,spec)
        if not mac:
            for key,kind in [('low','movw'),('high','movt')]:
                rows=list(md.disasm(count[key],at+count.start(key)))
                require(len(rows)==1 and rows[0].mnemonic==kind and rows[0].reg_name(rows[0].operands[0].reg)=='r0')
        base=int.from_bytes(count['base'],'little',signed=mac)
        bound=int.from_bytes(count['bound'],'little',signed=mac)
        require(0<=base<=4096 and 1<=bound<=4096 and base+bound<=8192)
        match('station',target(count,'station',at),13 if mac else 6,'554889e5488b87180200005dc3' if mac else 'd0f888017047')
        match('station_id',target(count,'station_id',at),9 if mac else 4,'554889e58b47105dc3' if mac else '80687047')
        match('seed',target(count,'seed',at),69 if mac else 72,MAC_SEED if mac else ARM_SEED)
        draw_at=target(count,'draw',at)
        draw=match('draw',draw_at,171 if mac else 114,MAC_DRAW if mac else ARM_DRAW)
        bits_at=target(draw,'first',draw_at)
        require(bits_at==target(draw,'repeat',draw_at))
        match('bits',bits_at,93 if mac else 126,MAC_BITS if mac else ARM_BITS)
        if not mac:require(arm_import(mach,target(draw,'modulo',draw_at,'blx'))==b'___modsi3')
        spans=sorted((row['offset'],row['offset']+row['bytes']) for row in proof.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        return {'count_base':base,'count_bound':bound,'provenance':proof}
    except (ValueError,TypeError,KeyError,IndexError,OverflowError,struct.error):return {}
MAC_COUNT='4c8d3d {random:4} 498b1f498b3ee8 {station:4} 4889c7e8 {station_id:4} 4863f04889dfe8 {seed:4} 498b3fbe {bound:4} e8 {draw:4} 8d78 {base:1} 498bb42480010000e8 {resize:4}'
ARM_COUNT='{low:4} {high:4} 78440668286814963468cdf8b880 {station:4} cdf8b880 {station_id:4} 01462046ca17cdf8b880 {seed:4} 3068 {bound:1} 21cdf8b880 {draw:4} dbf8fc10 {base:1} 30 {resize:4}'
MAC_SEED='554889e548897df8488975f0488b75f848c745e8e6ecde05488b7de848c1e7084881cf6d00000048897de8488b7df048337de848b8ffffffffffff00004821f84889065dc3'
ARM_SEED='90b501af85b06c4624f00704a5460490039202910498002101914ef6e641c0f2de510091052101914ef26d61cdf6ec610091029a039b514083f0050292b2016042603c1fa54690bd'
MAC_DRAW='554889e54883ec4048897df08975ec488b7df08b75ecb8000000002b45ec21f03b45ec48897dd80f852f000000be1f000000486345ec488b7dd8488945d0e8 {first:4} 4863f8488b4dd0480faff948c1ff1f89f88945fce946000000be1f000000488b7dd8e8 {repeat:4} 8945e88b75ec8945cc99f7fe8b45cc8955e48945c88b45e82b45e48b4dec81e90100000001c181f9000000000f8cc0ffffff8b45e48945fc8b45fc4883c4405dc3'
ARM_DRAW='80b56f4687b00022c0f200020590049105980499049bd21a1140049a914201900ed104981f21019a00901046 {first:4} 009981fb0001c00f40ea4100069015e01f21c0f200010198 {repeat:4} 039003980499 {modulo:4} 029003980299401a0499013908440028ebdb02980690069807b080bd'
MAC_BITS='554889e548897df88975f4488b7df848c745e8e6ecde05488b45e848c1e008480d6d000000488945e8488b07480faf45e848050b00000048b9ffffffffffff00004821c148890f488b07be300000002b75f489f148d3f889c689f05dc3'
ARM_BITS='90b501af85b06c4624f00704a546049003910498002101914ef6e641c0f2de510091052101914ef26d61cdf6ec61009102684368a2fb019c02eb8202624403fb012119f10b0241f1000189b2026041600398c0f13003c0f1100021fa00f9c3f1200c01fa0cf122fa03f241ea02010028a8bf49460846a7f10404a54690bd'

# Equivalent register allocations around the same 48-bit seed/multiplier and
# bounded rejection sampler. Keep complete alternatives to reject mixed layouts.
MAC_ALTERNATES = {
    'seed': [(69, MAC_SEED.replace('4821f8488906', '4821c748893e'))],
    'draw': [(170, MAC_DRAW.replace('21f03b45ec', '21c63b75ec')
                          .replace('480faff948c1ff1f89f8', '480fafcf48c1f91f89c8')
                          .replace('e946000000', 'e945000000')
                          .replace('01c181f9000000000f8cc0ffffff', '01c83d000000000f8cc1ffffff'))],
    'bits': [(93, MAC_BITS.replace('4821c148890f', '4821c8488907'))],
}
