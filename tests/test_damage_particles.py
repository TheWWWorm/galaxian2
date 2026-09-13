"""Relocated, changed synthetic sprite declarations; no original content."""
import copy
import struct
import unittest
from types import SimpleNamespace
from gof2_content import damage_particles as reader
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch

def fbits(value):return struct.unpack('<I',struct.pack('<f',value))[0]

def immediate(kind,reg,value):
    value&=0xffffffff
    if kind=='vmov.i32':
        assert value==0
        return bytes.fromhex('80ef10a0' if reg==10 else '80ef5080')
    if kind=='movs':
        assert reg<8 and value<256
        return struct.pack('<H',0x2000|(reg<<8)|value)
    if kind in ['movw','movt']:return arm_wide(value,reg,kind=='movt')
    assert kind in ['mov.w','mvn']
    wanted=(~value)&0xffffffff if kind=='mvn' else value
    for code in range(4096):
        byte=code&255
        if code>>10==0:
            value=[byte,(byte<<16)|byte,(byte<<24)|(byte<<8),byte*0x1010101][(code>>8)&3]
        else:
            byte=128|(code&127);shift=(code>>7)&31
            value=((byte>>shift)|(byte<<(32-shift)))&0xffffffff
        if value==wanted:
            return struct.pack('<HH',(0xf06f if kind=='mvn' else 0xf04f)|((code>>11)<<10),((code>>8&7)<<12)|(reg<<8)|(code&255))
    raise AssertionError((kind,reg,hex(wanted)))

def words(preset):
    fire=preset==42
    return {0x10:0x2000021,0x14:9 if fire else 18,0x18:fbits(256 if fire else 128),
        0x1c:100 if fire else 120,0x2c:768 if fire else 777,0x30:fbits(8),
        0x34:1,0x38:0xffffff70 if fire else 0xffffffff,0x3c:0xffffffcc,
        0x40:64 if fire else 60,0x48:120 if fire else 1000,
        0x4c:64 if fire else 60,0x50:64 if fire else 60,0x54:0,
        0x68:fbits(-8),0x74:0,0x80:0,0x84:fbits(64 if fire else -32),
        0x88:fbits(64 if fire else 128),0x8c:0,0x90:0,
        0x94:fbits(0.5),0x98:fbits(0.5),0xa0:4}

def fixture(mac,shift=0):
    base=0x100000+shift;offset=128;data=bytearray(offset+4096)
    blocks={};locations={'presets':64,'smoke_material':1100,'fire_material':1300,'defaults':1600}
    prefix='MAC_' if mac else 'ARM_'
    for key,at in locations.items():
        name=prefix+key.upper();body,fields=expand(getattr(reader,name));values={}
        for destination,expression in reader.DATA_FIELDS.get(name,{}).items():
            preset,field=map(int,destination.split(':'));value=words(preset)[field]
            for index,hole in enumerate(expression):
                part=value if len(expression)==1 else (value>>16 if index else value&65535)
                assert hole not in values or values[hole]==part
                values[hole]=part
        for field,(where,size) in fields.items():
            if field=='material':value=410 if key=='smoke_material' else 420
            elif field in values:value=values[field]
            else:value=0
            if mac:
                raw=struct.pack('<i',3600-at-where-size) if field.startswith(('call','ref')) else struct.pack('<I',value)
            else:
                if field not in reader.ARM_FIELDS[name]:raw=bytes(size)
                else:
                    kind,register=reader.ARM_FIELDS[name][field]
                    if kind=='bl':raw=branch(base+at+where,base+3600)
                    else:raw=immediate(kind,int(register[1:]),value)
            assert len(raw)==size
            body[where:where+size]=raw
        data[offset+at:offset+at+len(body)]=body;blocks[key]=(at,body,fields)
    section={'name':b'__text','segment':b'__TEXT','address':base,'offset':offset,'length':4096}
    return SimpleNamespace(architecture='x86_64' if mac else 'armv7',data=bytes(data),slice_offset=8192,text=section,sections=[section]),blocks

class DamageParticles(unittest.TestCase):
    def test_changed_data_and_relocation(self):
        for mac in [True,False]:
            for shift in [0,0x360000]:
                m,_=fixture(mac,shift);data=reader.extract_damage_particles(m)
                self.assertTrue(data,(mac,shift))
                self.assertEqual(data['scope'],'damage_particle_sprite_presets')
                for index,row in enumerate(data['presets']):
                    preset=[15,42][index];values=words(preset)
                    self.assertEqual(row['material_id'],[410,420][index])
                    for field,key in reader.INTEGER_FIELDS.items():self.assertEqual(row[key],values[field])
                    for field,key in reader.FLOAT_FIELDS.items():self.assertEqual(row[key],struct.unpack('<f',struct.pack('<I',values[field]))[0])
                    self.assertEqual(row['uv_rect'],[0,0,0.5,0.5])
                    self.assertEqual(row['end_rgba'],[255,255,255,204])
                self.assertEqual(set(data['provenance']),{'presets','smoke_material','fire_material','defaults'})
                self.assertEqual(data['emitter_defaults'],{'auxiliary_sizes':[0,0], 'velocity_size_factor':0,
                    'initial_fade_ms':0, 'velocity_base':[0,0,0], 'local_velocity_xy':[0,0],
                    'local_offset_x':0, 'minimum_squared_speed':0})
                for row in data['provenance'].values():self.assertEqual(set(row),{'offset','bytes'})

    def test_malformed_and_ambiguous_declarations(self):
        for mac in [True,False]:
            for problem in ['presets','smoke_material','fire_material','defaults','duplicate','truncate','link','material','architecture']:
                with self.subTest(mac=mac,problem=problem):
                    m,blocks=fixture(mac);data=bytearray(m.data)
                    if problem in blocks:data[128+blocks[problem][0]]^=255
                    elif problem=='duplicate':
                        body=blocks['presets'][1];data[128+2200:128+2200+len(body)]=body
                    elif problem=='truncate':m.text['length']=1320
                    elif problem=='architecture':m.architecture='unknown'
                    else:
                        at,_,fields=blocks['fire_material'];field='material' if problem=='material' else 'call_1d' if mac else 'call_12';where,size=fields[field]
                        if mac:raw=struct.pack('<I',410) if problem=='material' else struct.pack('<i',10)
                        else:raw=arm_wide(410,3) if problem=='material' else branch(m.text['address']+at+where,m.text['address']+3604)
                        data[128+at+where:128+at+where+size]=raw
                    m.data=bytes(data);self.assertEqual(reader.extract_damage_particles(m),{})

    def test_parameter_boundaries(self):
        row=reader.extract_damage_particles(fixture(True)[0])['presets'][0]
        for key,value in [('capacity',0),('lifetime_ms',0),('emission_per_second',0),('size',float('nan')),('flags',0),('animation_frames',5),('fade_in_ms',778),('size_jitter',32767),('uv_rect',[0,0,0,0.5])]:
            bad=copy.deepcopy(row);bad[key]=value
            self.assertFalse(reader.parameters(bad),key)

    def test_invalid_literal_values_do_not_create_a_capability(self):
        for mac in [True,False]:
            for field,value in [(0x10,0),(0x14,0),(0x2c,0),(0x18,0x7fc00000),(0x30,0),(0x94,fbits(2))]:
                with self.subTest(mac=mac,field=field):
                    m,blocks=fixture(mac);at,_,holes=blocks['presets'];data=bytearray(m.data)
                    name=('MAC_' if mac else 'ARM_')+'PRESETS'
                    expression=reader.DATA_FIELDS[name]['15:'+str(field)]
                    for index,hole in enumerate(expression):
                        where,size=holes[hole]
                        part=value if len(expression)==1 else (value>>16 if index else value&65535)
                        if mac:raw=struct.pack('<I',part)
                        else:
                            kind,register=reader.ARM_FIELDS[name][hole]
                            raw=immediate(kind,int(register[1:]),part)
                        data[128+at+where:128+at+where+size]=raw
                    m.data=bytes(data)
                    self.assertEqual(reader.extract_damage_particles(m),{})

    def test_changed_or_duplicate_defaults_are_unsupported(self):
        for mac in [True,False]:
            for duplicate in [True,False]:
                m,blocks=fixture(mac);data=bytearray(m.data);at,body,holes=blocks['defaults']
                if duplicate:data[128+3050:128+3050+len(body)]=body
                else:
                    where,size=holes['v_44' if mac else 'scalar_defaults']
                    data[128+at+where:128+at+where+size]=struct.pack('<I',1) if mac else immediate('movs',1,1)
                m.data=bytes(data)
                self.assertEqual(reader.extract_damage_particles(m),{})
