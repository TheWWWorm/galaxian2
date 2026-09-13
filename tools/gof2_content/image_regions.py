"""Bounded image-region alias declarations; alternatives remain explicit."""
import re
import struct
from .opening_loadout import template
from .opening_dialogue import Declaration

MAC_RECORD = '''bf18000000e8 {allocate:4} 4889c3bf04000000e8 {payload:4}
66c700 {texture:2} 66c74002 {region:2} 66c703 {id:2}
c7430403000000c74308ffffffff488943104c89ef4889dee8 {insert:4}'''


def arm_record(mach, start, decoder):
    d = Declaration(mach,start,decoder,bound=160)
    d.take('movs','r0, #4'); allocate=d.call('blx')
    d.take('add','r6, sp, #0x2c');texture=d.number('r2')
    d.take('add.w','r1, r6, #0x4000')
    region=0
    ins=d.take()
    if ins.mnemonic=='movt' and ins.op_str.startswith('r2, #'):
        region=ins.operands[1].imm;ins=d.take()
    if ins.mnemonic not in ['movw','movs','mov.w'] or len(ins.operands)!=2 or ins.reg_name(ins.operands[0].reg)!='r3' or ins.operands[1].type!=2:
        raise ValueError('Unknown image region ID')
    identifier=ins.operands[1].imm
    d.take('mov.w','r5, #-1');d.take('mov','r4, r1')
    ins=d.take()
    if ins.mnemonic not in ['ldr','ldr.w'] or len(ins.operands)!=2 or ins.reg_name(ins.operands[0].reg)!='r1': raise ValueError('Unknown alias record pointer')
    op=ins.operands[1]
    if op.type!=3 or ins.reg_name(op.mem.base)!='r4' or op.mem.index or op.mem.disp<0 or op.mem.disp%4: raise ValueError('Unknown alias record slot')
    slot=op.mem.disp
    def member(mnemonic,register,base,offset):
        ins=d.take()
        if ins.mnemonic.removesuffix('.w')!=mnemonic or len(ins.operands)!=2 or ins.reg_name(ins.operands[0].reg)!=register: raise ValueError('Unsupported image alias record')
        o=ins.operands[1]
        if o.type!=3 or ins.reg_name(o.mem.base)!=base or o.mem.index or o.mem.disp!=offset: raise ValueError('Image alias pointer mismatch')
    member('str','r2','r0',0)
    member('ldr','r2','r4',slot);member('strh','r3','r2',0)
    d.take('movs','r3, #3');member('ldr','r2','r4',slot);member('str','r3','r2',4)
    member('ldr','r2','r4',slot);member('str','r5','r2',8)
    member('ldr','r2','r4',slot);member('str','r0','r2',12)
    d.take('str.w','r5, [r4, #0x570]');d.take('ldr','r0, [sp, #0x1c]');d.call('bl')
    end=d.end
    starts=[]
    for length in [18,20,22,24]:
        try:
            p=Declaration(mach,start-length,decoder,bound=32)
            p.take('movs','r0, #0x10');p.take('str.w','r5, [r4, #0x570]')
            if p.call('blx')!=allocate:continue
            ins=p.take()
            if ins.mnemonic not in ['str','str.w'] or ins.op_str!=('r0, [r4]' if slot==0 else f'r0, [r4, #{hex(slot)}]'):continue
            p.number('r0');p.take('str.w','r0, [r4, #0x570]')
            if p.end==start:starts.append(start-length)
        except (ValueError,StopIteration,IndexError):pass
    if len(starts)!=1:raise ValueError('Missing image alias allocation')
    return {'id':identifier,'texture_id':texture,'region':region,'source_offset':mach.slice_offset+mach.text['offset']+starts[0]-mach.text['address'],'source_bytes':end-starts[0]}


def extract_image_regions(mach):
    if mach.architecture not in ['x86_64','armv7']:return []
    text=mach.text;code=mach.data[text['offset']:text['offset']+text['length']];rows=[]
    if mach.architecture=='x86_64':
        for m in template(MAC_RECORD).finditer(code):
            if m.end('allocate')+struct.unpack('<i',m['allocate'])[0] != m.end('payload')+struct.unpack('<i',m['payload'])[0]:continue
            rows.append({'id':int.from_bytes(m['id'],'little'),'texture_id':int.from_bytes(m['texture'],'little'),'region':int.from_bytes(m['region'],'little'),
                         'source_offset':mach.slice_offset+text['offset']+m.start(),'source_bytes':len(m[0])})
    else:
        import capstone
        decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
        for m in re.finditer(bytes.fromhex('0420'),code):
            if m.start()%2:continue
            try:rows.append(arm_record(mach,text['address']+m.start(),decoder))
            except (ValueError,StopIteration,IndexError):continue
    if len(rows)>10000 or any(not 0<=r['id']<65535 or not 0<=r['texture_id']<65535 or not 0<=r['region']<65535 for r in rows):return []
    return sorted(rows,key=lambda r:(r['id'],r['source_offset']))
MAC_RANGE = """
4531ff498b46404c8b284181ff
{count_d:4}
0f8f
{outside_13:4}
bf18000000e8
{call_1d:4}
4889c3bf04000000e8
{call_2a:4}
418d8f
{base_31:4}
66890866c740020000418d8f
{base_41:4}
66890bc7430403000000c74308ffffffff488943104c89ef4889dee8
{call_61:4}
41ffc7eba0
"""

ARM_RANGE = """
00260068079010200696c8f87055
{call_e:4}
caf8580d
{value_16:4}
c8f870050420
{call_20:4}
0df12c0e
{value_28:4}
0ef54056
{value_30:4}
4ff0ff350df12c0bb246daf8581d069e32440280002233444280daf8582d13800323daf8582d5360daf8582d9560daf8582dd0600bf580400446c4f870550798
{call_74:4}
0136a046
{count_7c:1}
2ec2db
"""


def extract_image_range(mach):
    if mach.architecture not in ['x86_64','armv7']: return {}
    mac=mach.architecture=='x86_64';text=mach.text
    code=mach.data[text['offset']:text['offset']+text['length']]
    matches=[m for m in template(MAC_RANGE if mac else ARM_RANGE).finditer(code) if mac or m.start()%2==0]
    if len(matches)!=1:return {}
    m=matches[0];start=text['address']+m.start()
    try:
        if mac:
            def target(key):return text['address']+m.end(key)+struct.unpack('<i',m[key])[0]
            if target('call_1d')!=target('call_2a'):return {}
            if not start+len(m[0])<=target('outside_13')<text['address']+text['length']:return {}
            count=int.from_bytes(m['count_d'],'little',signed=True)+1
            first=int.from_bytes(m['base_41'],'little',signed=True)
            texture=int.from_bytes(m['base_31'],'little',signed=True)
        else:
            import capstone
            decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
            def immediate(key,mnemonic,register=None):
                ins=list(decoder.disasm(m[key],text['address']+m.start(key)))
                if len(ins)!=1 or ins[0].mnemonic!=mnemonic or ins[0].operands[-1].type!=2:raise ValueError('Invalid image range declaration')
                if register is not None and (len(ins[0].operands)!=2 or ins[0].reg_name(ins[0].operands[0].reg)!=register):raise ValueError('Image range register mismatch')
                return ins[0].operands[-1].imm
            if immediate('call_e','blx')!=immediate('call_20','blx'):return {}
            immediate('call_74','bl');immediate('value_16','movw','r0')
            texture=immediate('value_28','movw','r2');first=immediate('value_30','movw','r3')
            count=int.from_bytes(m['count_7c'],'little')
        if not 1<=count<=1024 or not 0<=first<=65535-count or not 0<=texture<=65535-count:return {}
        return {'first_id':first,'first_texture_id':texture,'count':count,'region':0,
                'source_offset':mach.slice_offset+text['offset']+m.start(),'source_bytes':len(m[0])}
    except (ValueError,IndexError,struct.error):return {}


def extract_image_bindings(mach):
    records=extract_image_regions(mach);sequence=extract_image_range(mach)
    if not records and not sequence:return {}
    return {'records':records,'ranges':[sequence] if sequence else []}
