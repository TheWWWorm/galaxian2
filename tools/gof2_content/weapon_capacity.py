"""Recover the ordinary type-zero projectile pool capacity, without running code."""
import struct
from .opening_loadout import template
from .ship_models import section_bytes

MAC_RANGE = '''488b45d08d40 {first:1} bb0100000083f8 {count:1} 7217b801000000488b4dd081f9 {single:4} bb {slots:4} 0f44d8'''
ARM_RANGE = '''{first:4} {count:2} 1e462946 {single_branch:4} 0d914ff0010a {join:2}'''
ARM_SINGLE = '''{slots:4} {single:2} 0d9108bf4ff0010a'''
MAC_CALL = '''44897dac8b45108904244c89f74589e74489fe8b55c489d94589e8448b4d180f57c90f57d20f57db0f57e4e8 {ctor:4} 4c89f7488b75d0e8 {item:4} 8b45ac418986a0000000'''
ARM_CALL = '''03220c9611980021289204915a4605915346069107910891099179698ded038a029401912946cdf8008020ef1001 {ctor:4} 4ff0ff35119c28950d992046 {item:4} 11980c99c165'''


def extract_weapon_capacity(mach, weapon, factory):
    import capstone
    if not weapon.get('launch_modes'): return {}
    mac=mach.architecture=='x86_64';section=mach.text;base=section['address']
    code=mach.data[section['offset']:section['offset']+section['length']]
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    provenance={}
    def require(test):
        if not test: raise ValueError('Unsupported weapon capacity')
    def record(key,address,size):
        row=section_bytes(mach,address,size,b'__text');require(row is not None)
        provenance[key]={'offset':row[1],'bytes':size};return row[0]
    def one(key,spec):
        matches=[m for m in template(spec).finditer(code) if mac or m.start()%2==0]
        require(len(matches)==1);m=matches[0];record(key,base+m.start(),len(m[0]));return m
    def instruction(m,key,name,registers):
        rows=list(decoder.disasm(m[key],base+m.start(key)))
        require(len(rows)==1 and rows[0].size==len(m[key]))
        i=rows[0];require(i.mnemonic==name and i.operands[-1].type==capstone.arm.ARM_OP_IMM)
        require([i.reg_name(op.reg) for op in i.operands[:-1]]==registers)
        return i.operands[-1].imm
    def call(m,key):
        return base+m.end(key)+int.from_bytes(m[key],'little',signed=True) if mac else instruction(m,key,'bl',[])
    try:
        require(record('factory_entry',factory,4)==bytes.fromhex('554889e5' if mac else 'f0b503af'))
        selection=one('range',MAC_RANGE if mac else ARM_RANGE)
        construction=one('constructor_call',MAC_CALL if mac else ARM_CALL)
        if mac:
            first=-int.from_bytes(selection['first'],'little',signed=True)
            count=selection['count'][0];singleton=int.from_bytes(selection['single'],'little')
            slots=int.from_bytes(selection['slots'],'little')
            selector=record('type_selector',factory+57,22)
            m=template('4489f8488d0d {table:4} 486304814801c84531edffe0').fullmatch(selector);require(m is not None)
            table=factory+57+m.end('table')+int.from_bytes(m['table'],'little',signed=True)
            zero=table+struct.unpack('<i',record('kind_zero',table,4))[0]
            require(zero==base+selection.start()-31 and construction.start()==selection.start()+253)
            item_prefix=17
        else:
            single=one('single',ARM_SINGLE)
            first=instruction(selection,'first','sub.w',['r1','r5'])
            count=instruction(selection,'count','cmp',['r1'])
            singleton=instruction(single,'single','cmp',['r1'])
            slots=instruction(single,'slots','mov.w',['sl'])
            require(instruction(selection,'single_branch','bhs.w',[])==base+single.start())
            require(instruction(selection,'join','b',[])==base+single.end())
            require(construction.start()==single.start()+188)
            require(record('type_selector',factory+112,4)==bytes.fromhex('dfe813f0'))
            table=factory+116
            zero=table+2*struct.unpack('<H',record('kind_zero',table,2))[0]
            require(zero==base+selection.start()-26)
            item_prefix=78
        require(0<=first<=65535 and 1<=count<=64 and first+count<=65536 and 0<=singleton<=65535 and 1<=slots<=4096)
        require(list(range(first,first+count))+[singleton]==weapon['launch_modes']['alternate_item_ids'])
        classification=weapon['launch_modes']['provenance']['classification']
        expected=base+classification['offset']-mach.slice_offset-section['offset']-item_prefix
        require(call(construction,'item')==expected)
        require(section_bytes(mach,call(construction,'ctor'),4,b'__text') is not None)
        require(0<base+selection.start()-factory<1024 and 0<base+construction.start()-factory<2048)
        provenance['factory_call']=dict(weapon['provenance']['tail'])
        provenance['item_classification']=dict(classification)
        spans=sorted((r['offset'],r['offset']+r['bytes']) for r in provenance.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        return {'slots':slots,'provenance':provenance}
    except (ValueError,KeyError,TypeError,IndexError,OverflowError,struct.error):return {}
