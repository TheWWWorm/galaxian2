"""Relocated opening drift declarations and malformed helper rejection."""
import importlib.util
import struct
import unittest
from test_opening_camera import camera_fixture
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch
from gof2_content import opening_drift as reader
from gof2_content.opening_camera import extract_opening_camera
from gof2_content.opening_staging import extract_opening_staging


def fixture(mac, relocation=0):
    m,parents,parent_addresses,parent_scalars,helpers=camera_fixture(mac,relocation)
    data=bytearray(m.data);base=m.text['address'];prefix='MAC_' if mac else 'ARM_'
    blocks={k:expand(getattr(reader,prefix+k.upper())) for k in ['wave','sine','translate']}
    addresses={k:base+30000+i*1024 for i,k in enumerate(blocks)}
    addresses['getter']=base+34000
    def link(site,dest,size,kind='bl'):
        if mac:return int(dest-site-size).to_bytes(size,'little',signed=True)
        raw=bytearray(branch(((site+4)&~3)-4 if kind=='blx' else site,dest))
        if kind=='blx':raw[3]&=~0x10
        return raw
    def patch_parent(field,dest):
        off,size=parents['cut'][1][field];site=parent_addresses['cut']+off
        data[256+site-base:256+site-base+size]=link(site,dest,size)
    patch_parent('call_22' if mac else 'call_30',addresses['wave'])
    patch_parent('call_56' if mac else 'call_5e',addresses['translate'])
    frequency=0.03125
    if mac:
        struct.pack_into('<f',data,parent_scalars['cut','ref_1a'],frequency)
        struct.pack_into('<f',data,parent_scalars['cut','ref_27'],-0.25)
    else:
        bits=struct.unpack('<I',struct.pack('<f',frequency))[0]
        for field,high in [('word_c',False),('word_24',True)]:
            off,size=parents['cut'][1][field];file=256+parent_addresses['cut']+off-base
            parent_scalars['drift',field]=file
            data[file:file+size]=arm_wide(bits>>16 if high else bits&65535,1,high)
    const=m.sections[1];next_constant=const['offset']+const['length'];sign_file=None
    for key,(body,fields) in blocks.items():
        for field,(off,size) in fields.items():
            site=addresses[key]+off
            meta=reader.ARM_FIELDS.get(prefix+key.upper(),{}).get(field,{})
            if field.startswith('call_'):
                if key=='wave' and field in (['call_15','call_34'] if mac else ['call_1a','call_36']): dest=addresses['getter']
                elif key=='wave' and field in (['call_27','call_46'] if mac else ['call_2e','call_4e']): dest=addresses['sine']
                else: dest=helpers['other']
                raw=link(site,dest,size,meta.get('kind','bl'))
            elif field.startswith('jump_'):raw=link(site,addresses[key]+0x5f,size)
            elif field.startswith('ref_'):
                dest=const['address']+next_constant-const['offset'];raw=link(site,dest,size)
                data[next_constant:next_constant+4]=bytes.fromhex('00000080') if field=='ref_58' else bytes(4)
                if field=='ref_58':sign_file=next_constant
                next_constant+=4
            elif field.startswith('word_'):raw=arm_wide(1,0,meta['kind']=='movt')
            else:raise ValueError(field)
            assert len(raw)==size
            body[off:off+size]=raw
        file=256+addresses[key]-base;data[file:file+len(body)]=body
    getter=bytes.fromhex('554889e5488b87480200005dc3' if mac else 'd0e969017047')
    file=256+addresses['getter']-base;data[file:file+len(getter)]=getter
    const['length']=next_constant-const['offset'];m.data=bytes(data)
    return m,blocks,addresses,sign_file,parent_scalars


@unittest.skipUnless(importlib.util.find_spec('capstone'),'optional static-reader dependency')
class OpeningDrift(unittest.TestCase):
    def test_changed_relocated_frequency(self):
        for mac in [True,False]:
            for relocation in [0,0x90000]:
                m,*_=fixture(mac,relocation)
                camera=extract_opening_camera(m,extract_opening_staging(m));self.assertTrue(camera)
                result=reader.extract_opening_drift(m,camera);self.assertTrue(result)
                self.assertEqual(result['frequency_per_millisecond'],0.03125)
                self.assertEqual(result['bias'],-0.25 if mac else -0.5)
                self.assertEqual(result['actor_ids'],[0,1,2])
                self.assertEqual(result['application'],'per_update_world_y')

    def test_damaged_scopes(self):
        for mac in [True,False]:
            for bad in ['wave','sine','translate','getter','link','branch','frequency','missing','provenance','truncated']+(['sign'] if mac else ['register']):
                with self.subTest(mac=mac,bad=bad):
                    m,blocks,addresses,sign,scalars=fixture(mac);data=bytearray(m.data);base=m.text['address']
                    file=lambda k,f=None:256+addresses[k]-base+(blocks[k][1][f][0] if f else 0)
                    if bad in ['wave','sine','translate','getter']:data[file(bad)]^=1
                    elif bad=='link':data[file('wave','call_34' if mac else 'call_36')]^=4
                    elif bad=='branch':data[file('wave','jump_56') if mac else file('wave')+0x5e]^=1
                    elif bad=='frequency':
                        if mac:struct.pack_into('<f',data,scalars['cut','ref_1a'],float('nan'))
                        else:
                            lo=scalars['drift','word_c'];hi=scalars['drift','word_24']
                            data[lo:lo+4]=arm_wide(0,1,False)
                            data[hi:hi+4]=arm_wide(0x7fc0,1,True)
                    elif bad=='sign':data[sign+3]=0
                    elif bad=='register':
                        f=file('wave','word_8');data[f:f+4]=arm_wide(1,1,False)
                    elif bad=='truncated':data=data[:file('translate')+5]
                    m.data=bytes(data)
                    camera=extract_opening_camera(m,extract_opening_staging(m))
                    if bad=='missing':camera={}
                    if bad=='provenance':camera['provenance']['cut']['offset']+=2
                    self.assertEqual(reader.extract_opening_drift(m,camera),{})

if __name__=='__main__':unittest.main()
