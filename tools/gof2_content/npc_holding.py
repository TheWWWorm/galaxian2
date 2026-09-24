"""Recognize fresh NPC holding-mode declarations without emitting original code."""
import copy
from .opening_loadout import template

VALUES = {'actor_mode':5,'spatial_half_extent':50000,'initial_targeting_blocked':True,
          'selection_elapsed_ms':0,'boost_elapsed_ms':0}


def extract_npc_holding(mach, actors, projection):
    import capstone
    mac=mach.architecture=='x86_64'
    if mach.architecture not in LAYOUTS:return {}
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    proof={}
    def require(value):
        if not value:raise ValueError('Unsupported fresh NPC holding declaration')
    def address(span):
        offset=span['offset']-mach.slice_offset
        rows=[s for s in mach.sections if s['offset']<=offset and offset+span['bytes']<=s['offset']+s['length']]
        require(len(rows)==1)
        return rows[0]['address']+offset-rows[0]['offset']
    def read(key,at,size,segment=b'__TEXT',section=b'__text'):
        rows=[s for s in mach.sections if s['segment']==segment and s['name']==section and s['address']<=at and at+size<=s['address']+s['length']]
        require(len(rows)==1)
        offset=rows[0]['offset']+at-rows[0]['address']
        raw=mach.data[offset:offset+size];require(len(raw)==size)
        proof[key]={'offset':offset+mach.slice_offset,'bytes':size}
        return raw
    def target(row,field,at):
        if mac:return at+row.end(field)+int.from_bytes(row[field],'little',signed=True)
        instructions=list(decoder.disasm(row[field],at+row.start(field)))
        require(len(instructions)==1 and instructions[0].mnemonic=='bl' and instructions[0].size==4)
        require(instructions[0].operands[-1].type==capstone.arm.ARM_OP_IMM)
        return instructions[0].operands[-1].imm
    try:
        initial=actors['npc_initialization'];flight=initial['flight']
        require(initial['guidance'] and initial['activation'] and not initial['initial_active'])
        require([r['actor_kind'] for r in actors['actors']]==[8,8,8])
        require([r['hull_catalogue_id'] for r in actors['actors']]==[2,23,2])
        pointer=int.from_bytes(read('virtual_update',address(flight['provenance']['virtual_update']),8 if mac else 4,b'__DATA',b'__const'),'little')
        if not mac:require(pointer&1)
        bases={'constructor':address(flight['provenance']['bank'])-(2272 if mac else 1794),
               'update':pointer if mac else pointer&~1,
               'activation':address(initial['activation']['provenance']['activation'])}
        code=mach.data[mach.text['offset']:mach.text['offset']+mach.text['length']]
        found=[m for m in template(LAYOUTS[mach.architecture]['world_order'][3]).finditer(code) if mac or m.start()%2==0]
        require(len(found)==1);bases['world']=mach.text['address']+found[0].start()
        for key,(base,delta,size,pattern) in LAYOUTS[mach.architecture].items():
            if mac and key=='activation':pattern=(pattern,MAC_ACTIVATION_ALTERNATE)
            at=bases[base]+delta;row=template(pattern).fullmatch(read(key,at,size));require(row is not None)
            if key=='range':require(target(row,'getter',at)==address(projection['provenance']['predicate']))
        deactivation=address(initial['provenance']['opening_deactivation'])
        pattern=('554889e553504889fbc783bc00000005000000488b7b0831f6e8 {setter:4}' if mac else
                 '90b504460520c4f884000021606801af {setter:4} 012084f8ad0090bd')
        row=template(pattern).fullmatch(read('deactivation',deactivation,30 if mac else 28));require(row is not None)
        require(target(row,'setter',deactivation)==address(initial['provenance']['activity_setter']))
        opening=actors['provenance']['declaration']
        # The authored player suppression flag prevents holding-mode self-activation.
        at=address(opening)+opening['bytes']-(19 if mac else 22)
        expected=bytes.fromhex('498b8768010000488b00c6406201' if mac else '1498012100684466d5f8f000006880f85e10')
        require(read('player_suppression',at,len(expected))==expected)
        spans=sorted((s['offset'],s['offset']+s['bytes']) for s in proof.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        result=copy.deepcopy(VALUES);result['provenance']=proof;return result
    except (ValueError,KeyError,TypeError,IndexError,OverflowError):return {}

LAYOUTS = {'x86_64': {'timers': ['constructor', 1609, 24, '49c78424280200000000000049c784242002000000000000'],
            'range': ['constructor',
                      2032,
                      38,
                      '488d05 {global:4} 488b38e8 {getter:4} b9a086010084c0b850c300000f45c14189842478010000'],
            'clock_step': ['update', 101, 14, '4501ae280200004501ae20020000'],
            'activation': ['activation',
                           0,
                           82,
                           '554889e553504889fbc783bc00000001000000488b7b08be01000000e8 {call_28:4} '
                           '4889dfbe01000000e8 {call_41:4} '
                           'c6834101000001488b7b184885ff7504488b7b10be010000004883c4085b5de9805aebff'],
            'world_order': ['world',
                            0,
                            71,
                            '498b87780100004885c0743b833800743631db488b4008488b3cd8488b074489f6ff5068498b8778010000488b4008488b3cd8488b07ff504848ffc3498b87780100003b1872cc']},
 'armv7': {'timers': ['constructor',
                      1134,
                      200,
                      '15984ff0ff314ff6f672c0ef5000c3f6f93297ed030ac0f82c1120eff0811598c0f830111598c0f834114ff080411598c0f8a0111598c0f8a4211598c0f8a81140f2dc511598c0f8ac114cf250311598c0f8241105211598c0f8b01100201599159a01f5a2715063159a82f83901159a159b159cc4f83c01159c84f82901159c84f82a01159c84f83a01159cc4f8f001159cc4f8d400159c84f82b01159c84f8f401159c41f98f0a02f5e27141f98f0a02f5da7141f98f0a03f5ee71c2f8d501c2f8d10141f98f0a'],
           'range': ['constructor',
                     1616,
                     36,
                     '10981e2100681b91 {getter:4} 15994cf2503200281cbf48f2a062c0f201021f20c1f82421'],
           'clock_step': ['update',
                          174,
                          32,
                          'daf8bc014feae6780df507644ff0ff353044caf8bc01daf8b4013044caf8b401'],
           'activation': ['activation',
                          0,
                          50,
                          'b0b504460125c4f884500121606802af {call_16:4} 20460121 {call_24:4} '
                          '84f8f1500121e068002808bfa068bde8b0406ff6afbf'],
           'world_order': ['world',
                           0,
                           58,
                           'd4f8f80000281cbf0168002915d00026406850f8260001684a6b29469047d4f8f800406850f826000168496a8847d4f8f800013601688e42ead3']}}

# The same model-visibility tail remains linked in this complete compiler layout.
MAC_ACTIVATION_ALTERNATE = LAYOUTS['x86_64']['activation'][3].replace('e9805aebff', 'e95441ebff')
