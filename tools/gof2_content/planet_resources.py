"""Import sun/planet resource tables through linked static selection contexts.

Only resource IDs and bounded provenance leave this reader. The native engine
owns placement and rendering; original instructions are never runtime data.
"""
import struct
from .opening_loadout import template
from .ship_models import section_bytes

COUNTS = {"sun_textures": 19, "near_textures": 27, "far_textures": 27}

def extract_planet_resources(mach, sky, colors):
    if not sky or not colors or mach.architecture not in ["x86_64", "armv7"]: return {}
    import capstone
    mac=mach.architecture=="x86_64"; prefix="MAC_" if mac else "ARM_"
    sec=mach.text; base=sec["address"]; file_base=mach.slice_offset+sec["offset"]
    code=mach.data[sec["offset"]:sec["offset"]+sec["length"]]
    md=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB); md.detail=True
    provenance={}
    def require(ok):
        if not ok: raise ValueError("Unsupported planet resource selector")
    def instruction(m,key):
        rows=list(md.disasm(m[key],base+m.start(key)))
        require(len(rows)==1 and rows[0].size==len(m[key]));return rows[0]
    def match(key):
        name=prefix+key.upper()
        rows=[m for m in template(globals()[name]).finditer(code) if mac or m.start()%2==0]
        require(len(rows)==1);m=rows[0]
        if not mac:
            for field,(kind,register) in ARM_FIELDS[name].items():
                i=instruction(m,field);require(i.mnemonic==kind)
                if register:require(i.reg_name(i.operands[0].reg)==register)
        provenance[key]={"offset":file_base+m.start(),"bytes":len(m[0])};return m
    def target(m,key):
        return base+m.end(key)+int.from_bytes(m[key],"little",signed=True) if mac else instruction(m,key).operands[0].imm
    def getter(key,address,raw,upstream):
        expected=upstream["provenance"][key]
        require(address==base+expected["offset"]-file_base)
        found=section_bytes(mach,address,len(raw),b"__text")
        require(found is not None and found[0]==raw)
        provenance[key]={"offset":found[1],"bytes":len(raw)}
    def arm_table(m,low,high,pc):
        lo=instruction(m,low).operands[1].imm;hi=instruction(m,high).operands[1].imm
        return (base+m.start()+pc+lo+(hi<<16))&0xffffffff
    try:
        sun,current,near,far,mesh=[match(key) for key in ["sun","current","near","far","mesh"]]
        require(max(m.end() for m in [sun,current,near,far,mesh])-min(m.start() for m in [sun,current,near,far,mesh])<4096)
        require(sun.end()<=min(current.start(),near.start()) and max(current.end(),near.end())<=far.start()<mesh.start())
        getter("system",target(sun,"call_a" if mac else "bl_a"),bytes.fromhex("554889e5488b87280200005dc3" if mac else "d0f890017047"),sky)
        getter("sky_index",target(sun,"call_12" if mac else "bl_10"),bytes.fromhex("554889e58b473c5dc3" if mac else "006b7047"),colors)
        getter("cursor",target(current,"call_3" if mac else "bl_8"),bytes.fromhex("554889e58b87780200005dc3" if mac else "d0f8d4017047"),sky)
        getter("planet_type",target(near,"call_14" if mac else "bl_14"),bytes.fromhex("554889e58b471c5dc3" if mac else "40697047"),colors)
        require(target(near,"call_14" if mac else "bl_14")==target(far,"call_14" if mac else "bl_12"))
        register=target(sun,"call_38" if mac else "bl_2c")
        require(register==target(current,"call_3b" if mac else "bl_34")==target(far,"call_3d" if mac else "bl_36"))
        if not mac:require(register==target(near,"bl_38"))
        pointers=([target(sun,"ref_1a"),target(near,"ref_2d"),target(far,"ref_2d")] if mac else
                  [arm_table(sun,"movw_16","movt_1a",0x22),arm_table(near,"movw_20","movt_24",0x30),arm_table(far,"movw_1e","movt_22",0x2e)])
        result={"scope":"fresh_opening_planet_resources"}
        for (key,count),ptr in zip(COUNTS.items(),pointers):
            found=section_bytes(mach,ptr,count*4,b"__const");require(found is not None)
            values=list(struct.unpack("<"+str(count)+"I",found[0]));require(all(v<=65533 for v in values))
            result[key]=values;provenance[key]={"offset":found[1],"bytes":count*4}
        for key,m,field in [("mesh_id",mesh,"id_1a" if mac else "movw_a"),("opening_texture_id",current,"id_34" if mac else "movw_2a")]:
            value=int.from_bytes(m[field],"little") if mac else instruction(m,field).operands[1].imm
            require(0<=value<=65533);result[key]=value
        spans=sorted((v["offset"],v["offset"]+v["bytes"]) for v in provenance.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        return dict(result,provenance=provenance)
    except (ValueError,KeyError,IndexError,TypeError,OverflowError,struct.error):return {}

MAC_SUN = """
4c8d35
{ref_0:4}
498b3ee8
{call_a:4}
4889c7e8
{call_12:4}
4863c0488d0d
{ref_1a:4}
0fb73481488b8518feffff488b00488b50084889df31c9e8
{call_38:4}
"""

MAC_CURRENT = """
498b3fe8
{call_3:4}
85c0754383bdf8fdffff03753a488b8528feffff8b8d20feffff894878488b4018488b50084c01e2498b7d00be
{id_34:4}
31c9e8
{call_3b:4}
"""

MAC_NEAR = """
488b8508feffff488b40084a8b7c60f8498b5d00e8
{call_14:4}
488b8d18feffff488b09488b51084c01e24863c0488d0d
{ref_2d:4}
0fb734814889dfebad
"""

MAC_FAR = """
4c8bb508feffff498b46084a8b7c60f8498b5d00e8
{call_14:4}
488b8d18feffff488b09488b51084c01e24863c0488d0d
{ref_2d:4}
0fb734814889df31c9e8
{call_3d:4}
"""

MAC_MESH = """
bfe8000000e8
{call_5:4}
4889c3488d05
{ref_d:4}
488b104889dfbe
{id_1a:4}
31c9e8
{call_21:4}
498b4628488b40084a891cf8
"""

ARM_SUN = """
ff34d0f8008028686794
{bl_a:4}
6794
{bl_10:4}
7169
{movw_16:4}
{movt_1a:4}
7b444a6833f82010404600236794
{bl_2c:4}
"""

ARM_CURRENT = """
d8f80000cdf89ca1
{bl_8:4}
002804bf11980328bed1179c0023ddf85880c4f850806069416815984a19
{movw_2a:4}
0068cdf89ca1
{bl_34:4}
"""

ARM_NEAR = """
d8461599d8f80400d1f800b050f82600cdf89ca1
{bl_14:4}
179c002361694a68
{movw_20:4}
{movt_24:4}
cdf89ca179442a4431f820105846c346
{bl_38:4}
"""

ARM_FAR = """
dbf804001599139650f826000e68cdf89ca1
{bl_12:4}
179c002361694a68
{movw_1e:4}
{movt_22:4}
cdf89ca179442a4431f820103046139e
{bl_36:4}
"""

ARM_MESH = """
5c9815990a680a216791
{movw_a:4}
0023
{bl_10:4}
5c984ff0ff38179e139d149cf169496841f82500
"""

ARM_FIELDS = {'ARM_SUN': {'bl_a': ('bl', None), 'bl_10': ('bl', None), 'movw_16': ('movw', 'r3'), 'movt_1a': ('movt', 'r3'), 'bl_2c': ('bl', None)}, 'ARM_CURRENT': {'bl_8': ('bl', None), 'movw_2a': ('movw', 'r1'), 'bl_34': ('bl', None)}, 'ARM_NEAR': {'bl_14': ('bl', None), 'movw_20': ('movw', 'r1'), 'movt_24': ('movt', 'r1'), 'bl_38': ('bl', None)}, 'ARM_FAR': {'bl_12': ('bl', None), 'movw_1e': ('movw', 'r1'), 'movt_22': ('movt', 'r1'), 'bl_36': ('bl', None)}, 'ARM_MESH': {'movw_a': ('movw', 'r1'), 'bl_10': ('bl', None)}}
