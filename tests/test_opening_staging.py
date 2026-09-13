"""Synthetic relocatable staging with changed coordinates and broken links."""
import importlib.util
import struct
from types import SimpleNamespace
import unittest
from gof2_content import opening_staging as reader
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch


def fixture(mac, relocation=0):
    base = 0x10000 + relocation
    names = ['MAC_INITIAL', 'MAC_FORMATION'] if mac else ['ARM_INITIAL', 'ARM_FORMATION', 'ARM_INITIAL_DISPATCH', 'ARM_UPDATE_DISPATCH']
    specs = [getattr(reader, n) for n in names]
    blocks = [expand(s) for s in specs]
    addresses = [base + i * 1024 for i in range(len(blocks))]
    helper_names = ['player', 'actors', 'events', 'cursor', 'visibility', 'finished', 'camera_vector', 'camera_components', 'position', 'orientation', 'other']
    helpers = {name: base + 8192 + i * 128 for i, name in enumerate(helper_names)}
    raw_helpers = {
        'player': '554889e5488b87680100005dc3' if mac else 'd0f8f0007047',
        'actors': '554889e5488b87780100005dc3' if mac else 'd0f8f8007047',
        'events': '554889e5488b87b00100005dc3' if mac else 'd0f814017047',
        'cursor': '554889e58b87780200005dc3' if mac else 'd0f8d4017047',
        'visibility': '554889e540887758408877595dc3' if mac else '80f8481080f849107047',
        'finished': '554889e58a473124015dc3' if mac else '90f821007047',
        'camera_vector': '554889e5f30f104608f30f1016f30f104e04f30f115710f30f114f14f30f1147185dc3' if mac else '91ed000ad1ed010b80ed020ac0ed030b7047',
        'camera_components': '554889e5f30f114710f30f114f14f30f1157185dc3' if mac else '00f1080989e80e007047'}
    links = [
        {'player': ['41','56','9e','be'], 'actors': ['103','118','133','14d'], 'cursor':['a'], 'visibility':['12b'], 'camera_vector':['96'], 'position':['b6'], 'orientation':['f9']},
        {'player':['10'], 'actors':['1c'], 'events':['4'], 'cursor':['2e'], 'finished':['43'], 'visibility':['1dc'], 'camera_components':['b5'], 'position':['94'], 'orientation':['1c5']}
    ] if mac else [
        {'player':['1a','30','8a','a8'], 'actors':['e2','fa','116','12a'], 'visibility':['10c'], 'camera_vector':['80'], 'position':['9e'], 'orientation':['d6']},
        {'finished':['18'], 'visibility':['19e'], 'camera_components':['82'], 'position':['62'], 'orientation':['186']},
        {'player':['a'], 'cursor':['30']},
        {'events':['3e'], 'player':['46'], 'actors':['4e'], 'cursor':['62']}
    ]
    const_values = {'ref_72':321.0,'ref_7a':-234.0,'ref_82':-456.0,'ref_ad':-234.0,'ref_9d':512.0,'ref_a5':-640.0,'ref_dd':-234.0,'ref_e5':512.0,'ref_ed':-640.0,'ref_fa':-789.0,'ref_102':896.0,'ref_13a':-789.0,'ref_11e':-896.0,'ref_126':1234.0,'ref_15c':-789.0,'ref_148':-2304.0,'ref_164':512.0}
    const = bytearray(); scalar_offsets = {}
    def put(index, key, raw):
        body, fields = blocks[index]; at, size = fields[key]
        assert len(raw) == size, (key,len(raw),size)
        body[at:at+size] = raw
    def cond(at, dest, kind):
        d = dest-at-4
        if kind == 'bne': return struct.pack('<H',0xd100|((d//2)&255))
        d &= 0x1fffff; condition = 0 if kind == 'beq.w' else 1
        return struct.pack('<2H',0xf000|((d>>20)<<10)|(condition<<6)|((d>>12)&63),0x8000|(((d>>18)&1)<<13)|(((d>>19)&1)<<11)|((d>>1)&2047))
    for index, (_, fields) in enumerate(blocks):
        address = addresses[index]
        for key, (offset, size) in fields.items():
            if key.startswith('call_'):
                name = next((name for name, keys in links[index].items() if key[5:] in keys), 'other')
                dest = helpers[name]
                if mac: raw = struct.pack('<i',dest-address-offset-4)
                else:
                    blx = index==3 and key=='call_b0'
                    raw = bytearray(branch(((address+offset+4)&~3)-4 if blx else address+offset,dest))
                    if blx: raw[3] &= ~0x10
                put(index,key,raw)
            elif key.startswith('jump_'):
                if mac:
                    dest = address + ({'jump_16c':0x100}.get(key,800) if index==0 else {'jump_1e7':0x17f,'jump_4e':800,'jump_56':800}.get(key,900))
                    put(index,key,int(dest-address-offset-size).to_bytes(size,'little',signed=True))
                else:
                    dest,kind = [(address+0xdc,'bne'),(address+0x14c if key=='jump_1a6' else address+800,'bne' if key=='jump_1a6' else 'bne.w'),(addresses[0],'beq.w'),(addresses[1],'beq.w')][index]
                    put(index,key,cond(address+offset,dest,kind))
            elif key.startswith('ref_'):
                value = -90.0 if index==0 else const_values.get(key,1.0)
                off = len(const);const.extend(struct.pack('<f',value));scalar_offsets[(index,key)] = 20000+off
                put(index,key,struct.pack('<i',base+0x10000+off-address-offset-4))
            elif key.startswith('pointer_'):
                put(index,key,arm_wide(12,0,key in ('pointer_1e','pointer_8e','pointer_2a','pointer_58','pointer_6c')))
            elif key.startswith('literal_'): put(index,key,bytes.fromhex('dff80010'))
    if mac:
        for axis,value in zip('xyz',[12.0,-34.0,-56.0]): put(0,'camera_'+axis,struct.pack('<f',value))
    else:
        values = [dict(camera_x=(12.0,0),camera_y=(-34.0,0),camera_z=(-56.0,0),player_z=(-90.0,3)),
                  dict(player_x=(321.0,1),player_y=(-234.0,5),player_z=(-456.0,3),camera_y=(512.0,2),camera_z=(-640.0,6),actor_x=(-789.0,5),actor0_y=(896.0,2),actor1_y=(-896.0,2),actor1_z=(1234.0,3),actor2_y=(-2304.0,2))]
        for index,mapping in enumerate(values):
            for name,(value,reg) in mapping.items():
                bits=struct.unpack('<I',struct.pack('<f',value))[0]
                for top in [False,True]:
                    key=name+('_high' if top else '_low');size=blocks[index][1][key][1]
                    val=bits>>16 if top else bits&65535
                    put(index,key,arm_wide(val,reg,top) if size==4 else struct.pack('<H',0x2000|(reg<<8)|val))
    data=bytearray(24000)
    for address,(body,_) in zip(addresses,blocks):data[address-base+256:address-base+256+len(body)]=body
    for name,raw in raw_helpers.items():
        off=helpers[name]-base+256;data[off:off+len(bytes.fromhex(raw))]=bytes.fromhex(raw)
    data[20000:20000+len(const)]=const
    text={'name':b'__text','segment':b'__TEXT','address':base,'offset':256,'length':16000}
    section={'name':b'__const','segment':b'__TEXT','address':base+0x10000,'offset':20000,'length':len(const)}
    mach=SimpleNamespace(data=bytes(data),text=text,sections=[text,section],slice_offset=32768,architecture='x86_64' if mac else 'armv7')
    return mach,blocks,scalar_offsets,helpers


@unittest.skipUnless(importlib.util.find_spec('capstone'),'optional static-reader dependency')
class OpeningStaging(unittest.TestCase):
    def test_relocated_changed_coordinates(self):
        for mac in [True,False]:
            for relocation in [0,0x40000]:
                with self.subTest(mac=mac,relocation=relocation):
                    m,*_=fixture(mac,relocation);out=reader.extract_opening_staging(m)
                    self.assertEqual(out['initial']['player_position'],[0,0,-90])
                    self.assertEqual(out['initial']['camera_position_parameter'],[12,-34,-56])
                    self.assertEqual(out['formation']['player_position'],[321,-234,-456])
                    self.assertEqual(out['formation']['camera_position_parameter'],[-234,512,-640])
                    self.assertEqual([r['position'] for r in out['formation']['actors']],[[-789,896,0],[-789,-896,1234],[-789,-2304,512]])
                    self.assertEqual(out['formation']['after_event_finished'],2)
                    self.assertEqual(out['provenance']['initial']['offset'],33024)

    def test_arm_import_stub_is_bounded(self):
        for length in [16, 15]:
            m, blocks, _, _ = fixture(False)
            address = m.text['address'] + 0x20000
            at, size = blocks[3][1]['call_b0']; site = m.text['address'] + 3072 + at
            raw = bytearray(branch(((site+4)&~3)-4, address)); raw[3] &= ~0x10
            data = bytearray(m.data); data[256+3072+at:256+3072+at+size] = raw
            m.data = bytes(data)
            m.sections.append({'name': b'__picsymbolstub4', 'segment': b'__TEXT', 'address': address, 'offset': 22000, 'length': length})
            self.assertEqual(bool(reader.extract_opening_staging(m)), length == 16)

    def test_broken_context_and_coordinates_rejected(self):
        for mac in [True,False]:
            for bad in ['cursor','finished','visibility','camera','loop','dispatch','pose_link','unbacked_call','nan','truncated','duplicate','gate']:
                with self.subTest(mac=mac,bad=bad):
                    m,blocks,scalars,helpers=fixture(mac);data=bytearray(m.data)
                    if bad in ['cursor','finished','visibility','camera']:
                        name='camera_components' if bad=='camera' else bad
                        data[helpers[name]-m.text['address']+256]^=1
                    elif bad=='truncated':data=data[:300]
                    elif bad=='duplicate':data[256+4096:256+4096+len(blocks[0][0])]=blocks[0][0]
                    elif bad=='nan':
                        if mac:struct.pack_into('<f',data,scalars[(0,'ref_a3')],float('nan'))
                        else:
                            off=256+blocks[0][1]['player_z_high'][0];data[off:off+4]=arm_wide(0x7fc0,3,True)
                    elif bad=='gate':
                        # The fixed zero-phase/event-completed grammar must fail.
                        off=256+1024+(0x3f if mac else 0x12);data[off]^=1
                    else:
                        index=0;key={'loop':'jump_16c' if mac else 'jump_13e','dispatch':'jump_11' if mac else 'jump_36','pose_link':'call_b6' if mac else 'call_9e','unbacked_call':'call_4e' if mac else 'call_26'}[bad]
                        if not mac and bad=='dispatch':index=2
                        at,size=blocks[index][1][key];off=256+1024*index+at
                        if bad=='unbacked_call':data[off:off+size]=struct.pack('<i',0x70000000) if mac else branch(m.text['address']+1024*index+at,m.text['address']+0x100000)
                        elif mac and bad=='dispatch':data[off:off+size]=int(4-at-size).to_bytes(size,'little',signed=True)
                        else:data[off]^=0x10
                    m.data=bytes(data)
                    self.assertEqual(reader.extract_opening_staging(m),{})

if __name__=='__main__':unittest.main()
