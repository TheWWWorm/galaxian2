"""Relocated synthetic declarations: no original executable fixture is shipped."""
import copy
import struct
import unittest
from types import SimpleNamespace
from gof2_content import player_initialization as reader
from test_font_selection import expand
from test_ship_models import branch


def fixture(mac, shift=0):
    arch='x86_64' if mac else 'armv7'; origin=0x200000+shift; offset=256; bias=4096
    data=bytearray(8256); selector=3000; table=5000 if mac else 3030
    positions={'factory':500,'shield_getter':1000,'armor_getter':1100,'shield_setter':1200,
               'armor_setter':1300,'active':1500,'damage_permission':1600,'damage_setter':1800,
               'shield_assignment':3800 if mac else table+180,'armor_assignment':3900 if mac else table+200}
    deltas={'reset':-175,'loop_initial':-37,'loop_next':713} if mac else {
        'zero_vector':-210,'reset':-166,'loop_offset':-102,'loop_initial':-68,'loop_next':426}
    positions.update({key:selector+delta for key,delta in deltas.items()})
    fields={};mutations={}
    def write(at,raw): data[offset+at:offset+at+len(raw)]=raw
    def extent(at,n=4): return {'offset':bias+offset+at,'bytes':n}
    for key,(size,spec) in reader.LAYOUTS[arch].items():
        raw,fields[key]=expand(spec);assert len(raw)==size;write(positions[key],raw)
        covered={j for p,n in fields[key].values() for j in range(p,p+n)}
        mutations[key]=positions[key]+next(j for j in range(size) if j not in covered)
    targets={'factory.'+('call_28' if mac else 'call_26'):2000,
             'factory.'+('call_43' if mac else 'call_42'):2100,
             'factory.'+('call_69' if mac else 'call_66'):2100,
             'factory.'+('call_51' if mac else 'call_48'):1000,
             'factory.'+('call_77' if mac else 'call_72'):1100,
             'factory.'+('call_61' if mac else 'call_58'):1200,
             'factory.'+('call_87' if mac else 'call_82'):1300,
             'shield_setter.'+('call_24' if mac else 'call_20'):2200,
             'armor_setter.'+('call_18' if mac else 'call_8'):2200,
             'shield_assignment.'+('call_18' if mac else 'call_8'):2300,
             'armor_assignment.'+('call_18' if mac else 'call_8'):2300,
             'damage_permission.'+('call_1' if mac else 'call_0'):2400,
             'damage_permission.'+('call_14' if mac else 'call_12'):1800}
    if mac:
        targets.update({'factory.ref_35':7500,'loop_initial.ref_13':7500,'loop_initial.ref_6':table,
                        'loop_initial.call_33':positions['loop_next']+4,'loop_next.call_16':selector-17})
    else:
        targets.update({'loop_initial.call_2':selector-10,'loop_next.call_10':selector-10})
    for key,slots in fields.items():
        for field,(p,n) in slots.items():
            at=positions[key]+p;destination=targets.get(key+'.'+field,2500)
            if mac: raw=(destination-at-n).to_bytes(n,'little',signed=True)
            elif n==2: raw=struct.pack('<H',0xe000|(((destination-at-4)//2)&2047))
            elif key=='loop_next':
                delta=(destination-at-4)&0x1fffff
                raw=struct.pack('<HH',0xf000|((delta>>20)<<10)|(3<<6)|((delta>>12)&63),
                                0x8000|(((delta>>18)&1)<<13)|(((delta>>19)&1)<<11)|((delta>>1)&2047))
            else:
                raw=branch(origin+at,origin+destination)
                if key.endswith('_setter'): raw=raw[:2]+struct.pack('<H',struct.unpack('<H',raw[2:])[0]&~0x4000)
            write(at,raw)
    rows=[0]*30
    for type_id,key in [(9,'shield_assignment'),(10,'armor_assignment')]:
        rows[type_id]=(positions[key]-table)//(1 if mac else 2)
    write(table,struct.pack('<30i',*rows) if mac else bytes(rows))
    text={'name':b'__text','segment':b'__TEXT','offset':offset,'address':origin,'length':8000}
    m=SimpleNamespace(architecture=arch,data=bytes(data),slice_offset=bias,text=text,sections=[text])
    actors={'npc_initialization':{'provenance':{'stats_wrapper':extent(2000),
        'active' if mac else 'flags':extent(1500 if mac else 1498,7 if mac else 88)}}}
    vehicle={'equipment_rule':'last_matching','item_type_value_index':5,'provenance':{
        'equipment_table':extent(table,120 if mac else 30),'equipment_selector':extent(selector),
        'property_getter':extent(2300)}}
    staging={'provenance':{'initial':extent(1600-(0x56 if mac else 0x30)), 'player_getter':extent(2400)}}
    return m,actors,vehicle,staging,positions,fields,mutations,offset,table


class PlayerInitializationTests(unittest.TestCase):
    def test_relocated_profiles(self):
        for mac in [False,True]:
            for shift in [0,0x800000]:
                args=fixture(mac,shift);m,a,v,s=args[:4]
                result=reader.extract_player_initialization(m,a,v,s)
                self.assertTrue(result,(mac,shift))
                self.assertEqual({k:v for k,v in result.items() if k!='provenance'},reader.VALUES)
                self.assertEqual(len(result['provenance']),14 if mac else 16)

    def test_reject_changed_declarations_and_type_table(self):
        for mac in [False,True]:
            m,a,v,s,positions,fields,mutations,offset,table=fixture(mac)
            for name,at in dict(mutations,shield_type=table+9*(4 if mac else 1),armor_type=table+10*(4 if mac else 1)).items():
                changed=copy.copy(m);raw=bytearray(m.data);raw[offset+at]^=1;changed.data=bytes(raw)
                self.assertEqual(reader.extract_player_initialization(changed,a,v,s),{},(mac,name))
            # A second matching factory is ambiguous even with the same body.
            raw=bytearray(m.data);size=reader.LAYOUTS[m.architecture]['factory'][0]
            raw[offset+6000:offset+6000+size]=raw[offset+positions['factory']:offset+positions['factory']+size]
            changed=copy.copy(m);changed.data=bytes(raw)
            self.assertEqual(reader.extract_player_initialization(changed,a,v,s),{})

    def test_reject_redirected_links_and_foreign_anchors(self):
        for mac in [False,True]:
            m,a,v,s,positions,fields,_,offset,table=fixture(mac)
            for key,field in [('factory','call_28' if mac else 'call_26'),
                              ('armor_setter','call_18' if mac else 'call_8'),
                              ('shield_assignment','call_18' if mac else 'call_8'),
                              ('damage_permission','call_1' if mac else 'call_0'),
                              ('loop_next','call_16' if mac else 'call_10')]:
                p,_=fields[key][field];raw=bytearray(m.data);raw[offset+positions[key]+p]^=2
                changed=copy.copy(m);changed.data=bytes(raw)
                self.assertEqual(reader.extract_player_initialization(changed,a,v,s),{},(mac,key))
            for index,key in [(0,'stats_wrapper'),(1,'equipment_table'),(2,'initial')]:
                args=copy.deepcopy([a,v,s]);data=args[index]['npc_initialization'] if index==0 else args[index]
                data['provenance'][key]['offset']+=2
                self.assertEqual(reader.extract_player_initialization(m,*args),{},(mac,key))
            for cut in [0,offset+positions['factory']+20,offset+table+15]:
                changed=copy.copy(m);changed.data=m.data[:cut]
                self.assertEqual(reader.extract_player_initialization(changed,a,v,s),{})
            self.assertEqual(reader.extract_player_initialization(m,{},v,s),{})
            self.assertEqual(reader.extract_player_initialization(m,a,{},s),{})
