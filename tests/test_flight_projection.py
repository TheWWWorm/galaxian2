"""Relocatable, edition-independent perspective declarations and rejection."""
import importlib.util
import struct
import unittest
from types import SimpleNamespace
from gof2_content import flight_projection as reader
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch


def fixture(mac, relocation=0):
    base = 0x100000 + relocation
    text = {'segment': b'__TEXT', 'name': b'__text', 'address': base, 'offset': 256, 'length': 9000}
    const = {'segment': b'__TEXT', 'name': b'__const', 'address': base+10000, 'offset': 10000, 'length': 64}
    m = SimpleNamespace(architecture='x86_64' if mac else 'armv7', text=text, sections=[text,const], slice_offset=0)
    data = bytearray(11000); prefix = 'MAC_' if mac else 'ARM_'
    blocks = {k: expand(getattr(reader,prefix+k.upper())) for k in ['start','setter','predicate','compare','metrics']}
    addresses = {k:base+i*1024 for i,k in enumerate(blocks)}
    addresses.update(cursor=base+6000, other=base+7000)
    links = {('start','call_61' if mac else 'call_60'):'setter',('start','call_14' if mac else 'call_18'):'predicate',
             ('start','call_31' if mac else 'call_28'):'cursor',('predicate','call_12' if mac else 'jump_6'):'compare',
             ('setter','call_ab' if mac else 'call_bc'):'metrics'}
    jumps = {'start':{'jump_1b':0x27,'jump_25':0x4b},'compare':{'jump_9':0x14},'setter':{'jump_2f':0x3a,'jump_35':0xcf,'jump_bd':0xcf},'metrics':{'jump_2d':0x38,'jump_33':0x167}} if mac else {
             'start':{'jump_1e':0x3a,'jump_38':0x3e},'setter':{'jump_36':0x3a,'jump_38':0xd4,'jump_ca':0xd4},'metrics':{'jump_4c':0x50,'jump_4e':0x186}}
    def relative(site,target,size,kind):
        if mac: return int(target-site-size).to_bytes(size,'little',signed=True)
        delta=target-site-4
        if kind in ['b','bne','blo']: return struct.pack('<H',({'b':0xe000,'bne':0xd100,'blo':0xd300}[kind])|((delta//2)&(2047 if kind=='b' else 255)))
        raw=bytearray(branch(((site+4)&~3)-4 if kind=='blx' else site,target))
        if kind=='b.w': raw[3]&=~0x40
        if kind=='blx': raw[3]&=~0x10
        return raw
    # Modified values prove that the reader imports operands instead of defaults.
    scalars = {'fov':1.0, 'near':32.0, 'fallback':120000.0, 'far':120000.0, 'extended':240000.0}
    locations = {'fov':base+10000,'near':base+10004,'fallback':base+(10008 if mac else 512),'far':base+(10012 if mac else 516)}
    files = {k:(const['offset']+v-const['address'] if mac else 256+v-base) for k,v in locations.items()}
    for k in ['fov','near','fallback','far']:
        if mac or k in ['fallback','far']: struct.pack_into('<f',data,files[k],scalars[k])
    struct.pack_into('<f',data,files['far']+4,scalars['extended'])
    for key,(body,fields) in blocks.items():
        for field,(off,size) in fields.items():
            site=addresses[key]+off
            meta=reader.ARM_FIELDS.get(prefix+key.upper(),{}).get(field,{})
            if (key,field) in links: raw=relative(site,addresses[links[key,field]],size,meta.get('kind','bl'))
            elif field.startswith('call_'): raw=relative(site,addresses['other'],size,meta.get('kind','bl'))
            elif field.startswith('jump_'): raw=relative(site,addresses[key]+jumps[key][field],size,meta.get('kind','bl'))
            elif field.startswith('ref_'):
                target=locations[{'ref_1d':'fallback','ref_3f':'far','ref_4b':'fov','ref_53':'near'}[field]] if field in ['ref_1d','ref_3f','ref_4b','ref_53'] else base+8000
                raw=relative(site,target,size,'bl')
            elif field.startswith('word_'):
                bits=struct.unpack('<I',struct.pack('<f',scalars['near' if field=='word_4e' else 'fov']))[0]
                value=(bits >> 16 if meta['kind']=='movt' else bits&65535) if key=='start' and field in ['word_3e','word_4a','word_4e'] else 0
                raw=arm_wide(value,int(meta['register'][1:]),meta['kind']=='movt')
            elif field=='literal_3a': raw=struct.pack('<HH',0xed9f,0xa00+(locations['fallback']-((site+4)&~3))//4)
            elif field=='address_2c': raw=struct.pack('<H',0xa100+(locations['far']-((site+4)&~3))//4)
            else: raise AssertionError(field)
            body[off:off+size]=raw
        file=256+addresses[key]-base; data[file:file+len(body)]=body
    raw=bytes.fromhex('554889e58b87780200005dc3' if mac else 'd0f8d4017047')
    file=256+addresses['cursor']-base; data[file:file+len(raw)]=raw
    m.data=bytes(data)
    return m,blocks,addresses,files


@unittest.skipUnless(importlib.util.find_spec('capstone'),'optional static-reader dependency')
class FlightProjection(unittest.TestCase):
    def test_relocated_changed_parameters(self):
        for mac in [True,False]:
            for relocation in [0,0x90000]:
                m,*_=fixture(mac,relocation); result=reader.extract_flight_projection(m)
                self.assertTrue(result)
                self.assertEqual([result[k] for k in ['vertical_fov_radians','near','far','matching_location_early_far']], [1,32,120000,240000])
                self.assertEqual(result['early_cursor_limit'],80)

    def test_damaged_context(self):
        for mac in [True,False]:
            for bad in ['start','setter','predicate','compare','metrics','cursor','branch','link','nan','mismatch','near','duplicate','truncated']:
                with self.subTest(mac=mac,bad=bad):
                    m,blocks,addresses,files=fixture(mac); data=bytearray(m.data)
                    def file(key,field=None): return 256+addresses[key]-m.text['address']+(blocks[key][1][field][0] if field else 0)
                    if bad in addresses: data[file(bad)+(8 if bad=='start' and not mac else 0)]^=1
                    elif bad=='branch': data[file('start','jump_1b' if mac else 'jump_1e')]^=2
                    elif bad=='link': data[file('start','call_61' if mac else 'call_60')]^=2
                    elif bad=='nan': struct.pack_into('<f',data,files['far']+4,float('nan'))
                    elif bad=='mismatch': struct.pack_into('<f',data,files['fallback'],100)
                    elif bad=='near':
                        if mac: struct.pack_into('<f',data,files['near'],-1)
                        else:
                            off=file('start','word_4e');data[off:off+4]=arm_wide(0xbf80,3,True)
                    elif bad=='duplicate':
                        body=blocks['start'][0];data[8000:8000+len(body)]=body
                    elif bad=='truncated': data=data[:file('metrics')+5]
                    m.data=bytes(data)
                    self.assertEqual(reader.extract_flight_projection(m),{})

if __name__=='__main__': unittest.main()
