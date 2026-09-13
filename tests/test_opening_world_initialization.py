"""Synthetic relocated fresh-world declarations; no proprietary fixtures."""
import copy
import struct
import unittest
from types import SimpleNamespace
from gof2_content import opening_world_initialization as reader
from test_font_selection import expand
from test_ship_models import branch


def fixture(mac, shift=0):
    origin=0x200000+shift; offset=256; bias=4096; arch='x86_64' if mac else 'armv7'
    data=bytearray(40500); positions={}; fields={}; mutations={}
    bases={'world':1000,'pre_group':3000,'special':4000,'equipment_group':5000,'companions':6000,
           'companion_getter':7500,'loadout':10500,'effect_setter':12000,'weapon':20000,
           'base_actor':26000,'hull_group':28000,'weapon_wrapper':30000,'weapon_inner':31000,
           'secondary_getter':33000}
    def write(at, raw): data[offset+at:offset+at+len(raw)]=raw
    def extent(at, n): return {'offset':bias+offset+at,'bytes':n}
    patterns={k:v[3] for k,v in reader.LAYOUTS[arch].items()}
    patterns.update(weapon_main=reader.WEAPON_LAYOUTS[arch]['main'][2],
                    selection=reader.GUIDANCE_LAYOUTS[arch]['selection'][3],
                    base_call=reader.MAC_BASE_CALL if mac else reader.ARM_BASE_CALL)
    for key,pattern in patterns.items():
        if key=='weapon_main': at=bases['weapon']
        elif key=='selection': at=34000
        elif key=='base_call': at=35000
        else:
            base,delta,_,_=reader.LAYOUTS[arch][key];at=bases[base]+delta
        positions[key]=at;raw,fields[key]=expand(pattern);write(at,raw)
        covered={i for p,n in fields[key].values() for i in range(p,p+n)}
        mutations[key]=at+next(i for i in range(len(raw)) if i not in covered)
    destinations={}
    for base,(key,field) in reader.LINKS[arch].items(): destinations[key+'.'+field]=bases[base]
    destinations.update({
        'base_call.base':bases['base_actor'],
        'weapon_main.'+('call_77' if mac else 'call_78'):bases['effect_setter'],
        'before.'+('call_37' if mac else 'call_30'):37000-(206 if mac else 246),
        'after.'+('call_4' if mac else 'call_2'):37500-(2814 if mac else 168),
        'after.'+('call_86' if mac else 'call_102'):bases['weapon']-(2560 if mac else 1244),
        'station_gate.'+('call_42' if mac else 'call_20'):37600,
        'effect_setter.'+('call_158' if mac else 'call_166'):36000,
        'selection.'+('call_33' if mac else 'call_3c'):36000,
    })
    for i,group in enumerate(reader.SAME_TARGETS[arch]):
        existing={destinations[name] for name in group if name in destinations}
        assert len(existing)<=1
        destination=existing.pop() if existing else 36016+i*16
        for name in group:destinations[name]=destination
    for name,destination in destinations.items():
        key,field=name.split('.');at=positions[key];p,n=fields[key][field]
        raw=struct.pack('<i',destination-at-p-n) if mac else branch(origin+at+p,origin+destination)
        if not mac and key=='weapon_wrapper':
            # The ARM wrapper uses BL; all validated Thumb links here do too.
            assert n==4
        write(at+p,raw)
    table=39000;at=positions['effect_setter']
    if mac:
        p,n=fields['effect_setter']['ref_3'];write(at+p,struct.pack('<i',table-at-p-n))
    else:
        value=table-at-14
        for field,imm,base in [('models_low',value&65535,0xf240),('models_high',value>>16,0xf2c0)]:
            p,_=fields['effect_setter'][field]
            write(at+p,struct.pack('<HH',base|((imm>>12)&15)|(((imm>>11)&1)<<10),(((imm>>8)&7)<<12)|(1<<8)|(imm&255)))
    for index,item in enumerate(reader.VALUES['weapon_item_sequence']):
        write(table+item*4,struct.pack('<i',reader.VALUES['weapon_effect_sequence'][index]))
        mutations['model_'+str(item)]=table+item*4
    text={'name':b'__text','segment':b'__TEXT','offset':offset,'address':origin,'length':38000}
    m=SimpleNamespace(architecture=arch,data=bytes(data),slice_offset=bias,text=text,sections=[text,
      {'name':b'__const','segment':b'__TEXT','offset':offset+39000,'address':origin+39000,'length':500}])
    primary={'item_id':19,'projectile_capacity':4,'provenance':{'main':extent(20000,len(expand(patterns['weapon_main'])[0]))}}
    actors={'actors':[{'actor_id':i,'actor_kind':8,'hull_catalogue_id':[2,23,2][i]} for i in range(3)],
      'provenance':{'declaration':extent(37500,100)},'npc_initialization':{
        'construction':{'available':True},'primary_weapon':primary,
        'guidance':{'provenance':{'selection':extent(34000,len(expand(patterns['selection'])[0]))}},
        'provenance':{'base_call':extent(35000,len(expand(patterns['base_call'])[0]))}}}
    opening={'ship_id':10,'station_id':78,'provenance':{'declaration':extent(10500,100)}}
    scenery={'provenance':{'count':extent(37000,100),'station_id':extent(37600,10)}}
    return m,actors,opening,scenery,positions,fields,mutations,offset


class WorldInitializationTests(unittest.TestCase):
    def test_independent_relocated_layouts(self):
        for mac in [False,True]:
            for shift in [0,0x600000]:
                m,a,o,s,*_=fixture(mac,shift)
                result=reader.extract_opening_world_initialization(m,a,o,s)
                self.assertTrue(result,(mac,shift))
                self.assertEqual({k:v for k,v in result.items() if k!='provenance'},reader.VALUES)
                self.assertEqual(len(result['provenance']),27 if mac else 31)

    def test_changed_shapes_models_and_links(self):
        for mac in [False,True]:
            m,a,o,s,positions,fields,mutations,offset=fixture(mac)
            for key,at in mutations.items():
                changed=copy.copy(m);data=bytearray(m.data);data[offset+at]^=255;changed.data=bytes(data)
                self.assertFalse(reader.extract_opening_world_initialization(changed,a,o,s),(mac,key))
            links=[group[0].split('.') for group in reader.SAME_TARGETS[m.architecture]]+list(reader.LINKS[m.architecture].values())
            for key,field in links:
                changed=copy.copy(m);data=bytearray(m.data);at=positions[key]+fields[key][field][0]
                data[offset+at:offset+at+4]=struct.pack('<i',1000) if mac else branch(m.text['address']+at,m.text['address']+36500)
                changed.data=bytes(data)
                self.assertFalse(reader.extract_opening_world_initialization(changed,a,o,s),(mac,key,field))

    def test_fresh_context_and_bounded_provenance(self):
        for mac in [False,True]:
            m,a,o,s,*_=fixture(mac)
            for key in ['construction','guidance','primary_weapon']:
                changed=copy.deepcopy(a);changed['npc_initialization'][key]={}
                self.assertFalse(reader.extract_opening_world_initialization(m,changed,o,s))
            for key,value in [('ship_id',45),('station_id',112)]:
                changed=copy.deepcopy(o);changed[key]=value
                self.assertFalse(reader.extract_opening_world_initialization(m,a,changed,s))
            changed=copy.deepcopy(a);changed['actors'].reverse()
            self.assertFalse(reader.extract_opening_world_initialization(m,changed,o,s))
            changed=copy.deepcopy(m);changed.sections.append(copy.copy(m.text))
            self.assertFalse(reader.extract_opening_world_initialization(changed,a,o,s))
            changed=copy.copy(m);changed.data=m.data[:39200]
            self.assertFalse(reader.extract_opening_world_initialization(changed,a,o,s))
            changed=copy.copy(m);changed.architecture='unsupported'
            self.assertFalse(reader.extract_opening_world_initialization(changed,a,o,s))


if __name__=='__main__':unittest.main()
