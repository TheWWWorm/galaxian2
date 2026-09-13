"""Read the opening activation cue and its linked ordinary actor activity setter."""
import struct
from .opening_loadout import template
from .opening_camera import MAC_PAN2, ARM_PAN2
from .npc_initialization import MAC_ACTOR_WRAPPER, ARM_ACTOR_WRAPPER

MAC_TABLE = '488d05 {table:4} 49890424'
ARM_TABLE = '{low:4} {high:4} c0ef5000794408310160'
MAC_ACTIVATE = '554889e553504889fbc783bc00000001000000488b7b08be01000000e8 {setter:4}'
ARM_ACTIVATE = 'b0b504460125c4f884500121606802af {setter:4}'


def extract_npc_activation(mach, actors, camera):
    import capstone
    mac=mach.architecture=='x86_64'
    if not mac and mach.architecture!='armv7': return {}
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    proof={}
    def require(value):
        if not value: raise ValueError('Unsupported NPC activation')
    def address(span):
        offset=span['offset']-mach.slice_offset
        sections=[s for s in mach.sections if s['offset']<=offset and offset+span['bytes']<=s['offset']+s['length']]
        require(len(sections)==1)
        return sections[0]['address']+offset-sections[0]['offset']
    def read(key,at,size,segment=b'__TEXT',name=b'__text'):
        sections=[s for s in mach.sections if s['segment']==segment and s['name']==name and s['address']<=at and at+size<=s['address']+s['length']]
        require(len(sections)==1)
        section=sections[0];offset=section['offset']+at-section['address']
        raw=mach.data[offset:offset+size];require(len(raw)==size)
        proof[key]={'offset':offset+mach.slice_offset,'bytes':size}
        return raw
    def match(key,at,size,spec):
        row=template(spec).fullmatch(read(key,at,size));require(row is not None);return row
    def instruction(row,key,at,mnemonic,register=None):
        instructions=list(decoder.disasm(row[key],at+row.start(key)))
        require(len(instructions)==1 and instructions[0].size==len(row[key]))
        i=instructions[0];require(i.mnemonic==mnemonic and i.operands[-1].type==capstone.arm.ARM_OP_IMM)
        if register:require(i.reg_name(i.operands[0].reg)==register)
        return i.operands[-1].imm
    def target(row,key,at):
        return at+row.end(key)+int.from_bytes(row[key],'little',signed=True) if mac else instruction(row,key,at,'bl')
    try:
        initial=actors['npc_initialization']
        require(initial and camera and not initial['initial_active'])
        require([a['actor_id'] for a in actors['actors']]==[0,1,2])
        pan_address=address(camera['provenance']['pan2'])
        pan=match('cue',pan_address,189 if mac else 190,
                  MAC_PAN2.replace('50c30000',' {spatial:4} ') if mac else ARM_PAN2)
        # The recognized cue has phase 3, an ascending three-actor loop and the
        # ordinary class virtual activation slot (+18/+0C). The camera reader
        # independently verifies its event-7 finished getter and dispatch.
        require(camera['pan']['engagement_after_event_finished']==7)
        spatial=int.from_bytes(pan['spatial'],'little',signed=True) if mac else instruction(pan,'word_5a',pan_address,'movw','sl')
        require(1<=spatial<=10000000)
        wrapper_address=address(initial['provenance']['actor_wrapper'])
        wrapper=match('actor_wrapper',wrapper_address,14 if mac else 60,MAC_ACTOR_WRAPPER if mac else ARM_ACTOR_WRAPPER)
        constructor=target(wrapper,'constructor',wrapper_address)
        table_address=constructor+(0x51 if mac else 0x62)
        table=match('table_initializer',table_address,11 if mac else 18,MAC_TABLE if mac else ARM_TABLE)
        if mac: vtable=target(table,'table',table_address)
        else:
            low=instruction(table,'low',table_address,'movw','r1')
            high=instruction(table,'high',table_address,'movt','r1')
            vtable=low+(high<<16)+table_address+16+8
        pointer=read('virtual_activation',vtable+(24 if mac else 12),8 if mac else 4,b'__DATA',b'__const')
        activation=int.from_bytes(pointer,'little')
        if not mac:
            require(activation&1==1)
            activation &= ~1
        method=match('activation',activation,33 if mac else 20,MAC_ACTIVATE if mac else ARM_ACTIVATE)
        setter=target(method,'setter',activation)
        require(setter==address(initial['provenance']['activity_setter']))
        require(read('activity_setter',setter,13 if mac else 6)==bytes.fromhex('554889e54088b7c80000005dc3' if mac else '80f8c0107047'))
        spans=sorted((r['offset'],r['offset']+r['bytes']) for r in proof.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        return {'after_event_finished':7,'phase':3,'actor_ids':[0,1,2],'active':True,
                'actor_mode':1,'spatial_half_extent':spatial,'provenance':proof}
    except (ValueError,TypeError,KeyError,IndexError,OverflowError,struct.error):return {}
