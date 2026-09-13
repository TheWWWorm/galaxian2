"""Synthetic relocated repair declarations; no proprietary fixture bytes."""
import copy
import struct
import unittest
from types import SimpleNamespace
from gof2_content import player_repair as reader
from gof2_content.player_initialization import LAYOUTS as PLAYER_LAYOUTS
from test_font_selection import expand
from test_ship_models import branch


def fixture(mac,shift=0):
    arch='x86_64' if mac else 'armv7';origin=0x200000+shift;offset=256;bias=4096
    positions={k:1000 if k=='update' else 2500+i*500 for i,k in enumerate(reader.LAYOUTS[arch])}
    positions.update(factory=17000,clone_wrapper=17400,hull_current=19000,periods=20000 if mac else 1424)
    data=bytearray(21300);fields={}
    def write(at,raw):data[offset+at:offset+at+len(raw)]=raw
    def span(at,n):return {'offset':bias+offset+at,'bytes':n}
    def call(at,dest,kind='bl'):
        if mac:return struct.pack('<i',dest-at-4)
        raw=bytearray(branch(((origin+at+4)&~3)-4 if kind=='blx' else origin+at,origin+dest))
        if kind=='b.w':raw[3]&=~0x40
        if kind=='blx':raw[3]&=~0x10
        return raw
    update={('call_12' if mac else 'call_c'):'device_getter',('call_85' if mac else 'call_92'):'hull_max',
            ('call_cd' if mac else 'call_ee'):'hull_max',('call_91' if mac else 'call_a0'):'hull_add',
            ('call_d9' if mac else 'call_fc'):'armor_current',('call_e3' if mac else 'call_108'):'armor_max',
            ('call_ef' if mac else 'call_11a'):'armor_add'}
    for k in (['call_26','call_7b','call_c3'] if mac else ['call_22','call_86','call_e2']):update[k]='hull_current'
    targets={'update':update,'device_assignment':{('call_c' if mac else 'call_6'):'item_id'},
             'ship_clone':{('call_5f' if mac else 'call_a6'):'ship_ctor'},
             'factory':{('call_4' if mac else 'call_0'):'hull_source'}}
    layouts=dict(reader.LAYOUTS[arch],factory=PLAYER_LAYOUTS[arch]['factory'])
    for key,(size,spec) in layouts.items():
        at=positions[key];raw,masks=expand(spec);fields[key]=masks
        for field,destination in targets.get(key,{}).items():
            p,n=masks[field];raw[p:p+n]=call(at+p,positions[destination])
        if key in ['hull_add','armor_add']:
            field=('call_1e' if key=='hull_add' else 'call_24') if mac else 'call_10'
            p,n=masks[field];raw[p:p+n]=call(at+p,19400,'b.w')
        if key=='update':
            if not mac:
                for field in ['call_64','call_be']:
                    p,n=masks[field];raw[p:p+n]=call(at+p,19200,'blx')
            for field,extra in [('ref_60' if mac else 'ref_34',0),('ref_a8',8)]:
                p,n=masks[field];target=positions['periods']+extra
                if mac:raw[p:p+n]=struct.pack('<i',target-at-p-n)
                else:
                    delta=target-((at+p+4)&~3);reg=2 if extra==0 else 0
                    raw[p:p+n]=struct.pack('<HH',0xf20f|((delta>>11)<<10),(((delta>>8)&7)<<12)|(reg<<8)|(delta&255))
        write(at,raw)
    at=positions['clone_wrapper'];write(at+(8 if mac else 6),(b'\xe8'+call(at+9,positions['ship_clone'])) if mac else call(at+6,positions['ship_clone']))
    table=18000 if mac else positions['device_assignment']-100
    entries=[0]*30;entries[15]=positions['device_assignment']-table if mac else 50
    write(table,struct.pack('<30i',*entries) if mac else bytes(entries))
    write(positions['periods'],struct.pack('<4f',420,600,700,1000))
    text={'segment':b'__TEXT','name':b'__text','address':origin,'offset':offset,'length':19900}
    const={'segment':b'__TEXT','name':b'__const','address':origin+20000,'offset':offset+20000,'length':1000}
    if not mac:
        # Synthetic Mach-O import metadata identifies the existing ABI helper.
        struct.pack_into('<7I',data,0,0xfeedface,12,0,2,3,228,0)
        struct.pack_into('<2I',data,28,1,124);struct.pack_into('<I',data,76,1)
        struct.pack_into('<3I',data,116,origin+19200,16,offset+19200)
        struct.pack_into('<3I',data,140,8,0,16)
        names=b'\0___floatdisf\0'
        struct.pack_into('<6I',data,152,2,24,21000,1,21100,len(names))
        struct.pack_into('<2I',data,176,11,80);struct.pack_into('<2I',data,232,21200,1)
        struct.pack_into('<IB',data,21000,1,1);data[21100:21100+len(names)]=names
        struct.pack_into('<I',data,21200,0)
    m=SimpleNamespace(architecture=arch,data=bytes(data),slice_offset=bias,text=text,sections=[text,const])
    rp={'recharge':span(positions['update']-(94 if mac else 110),94 if mac else 110),
        'clock_zero':span(positions['timers_zero']+(22 if mac else 8),11 if mac else 8),
        'hull_getter':span(positions['hull_current'],12 if mac else 4)}
    player={'recharge':{'provenance':rp},'provenance':{'equipment_table':span(table,120 if mac else 30),
        'reset':span(positions['device_zero']+(31 if mac else 40),8 if mac else 12),
        'factory':span(positions['factory'],PLAYER_LAYOUTS[arch]['factory'][0])}}
    actors={'player_initialization':player,'npc_initialization':{'provenance':{'stats_entry':span(positions['stats_capacity']-(173 if mac else 112),4)}}}
    vehicle={'equipment_rule':'last_matching'};loadout={'provenance':{'ship_clone':span(at,27 if mac else 18)}}
    return m,actors,vehicle,loadout,positions,fields,offset


class RepairTests(unittest.TestCase):
    def test_relocated_source_links_and_values(self):
        for mac in [False,True]:
            for shift in [0,0x800000]:
                m,a,v,l,*_=fixture(mac,shift);result=reader.extract_player_repair(m,a,v,l)
                self.assertTrue(result,(mac,shift))
                self.assertEqual({k:x for k,x in result.items() if k!='provenance'},reader.VALUES)
                self.assertEqual(len(result['provenance']),16)

    def test_changed_layouts_and_disconnected_links(self):
        for mac in [False,True]:
            m,a,v,l,positions,fields,offset=fixture(mac)
            for key in reader.LAYOUTS[m.architecture]:
                changed=copy.copy(m);raw=bytearray(m.data);raw[offset+positions[key]+(0 if key!='ship_ctor' else 4)]^=255;changed.data=bytes(raw)
                self.assertFalse(reader.extract_player_repair(changed,a,v,l),(mac,key))
            for key,field in [('update','call_cd' if mac else 'call_ee'),('device_assignment','call_c' if mac else 'call_6'),('ship_clone','call_5f' if mac else 'call_a6')]:
                changed=copy.copy(m);raw=bytearray(m.data);raw[offset+positions[key]+fields[key][field][0]]^=2;changed.data=bytes(raw)
                self.assertFalse(reader.extract_player_repair(changed,a,v,l),(mac,key,field))
            changed=copy.copy(m);raw=bytearray(m.data);raw[offset+positions['periods']]^=1;changed.data=bytes(raw)
            self.assertFalse(reader.extract_player_repair(changed,a,v,l))
            if not mac:
                changed=copy.copy(m);raw=bytearray(m.data);raw[offset+positions['update']+fields['update']['ref_34'][0]+3]^=1;changed.data=bytes(raw)
                self.assertFalse(reader.extract_player_repair(changed,a,v,l),'Changed ARM literal register')
                changed=copy.copy(m);raw=bytearray(m.data);raw[21104]^=1;changed.data=bytes(raw)
                self.assertFalse(reader.extract_player_repair(changed,a,v,l),'Changed ARM conversion import')

    def test_missing_anchors_table_alias_and_truncation(self):
        for mac in [False,True]:
            m,a,v,l,positions,_,offset=fixture(mac)
            changed=copy.deepcopy(a);changed['player_initialization']['recharge']={}
            self.assertFalse(reader.extract_player_repair(m,changed,v,l))
            self.assertFalse(reader.extract_player_repair(m,a,{},l))
            changed=copy.copy(m);changed.data=m.data[:offset+positions['hull_source']+2]
            self.assertFalse(reader.extract_player_repair(changed,a,v,l))
            changed=copy.copy(m);raw=bytearray(m.data);at=offset+(18000 if mac else positions['device_assignment']-100)
            raw[at:at+(4 if mac else 1)]=struct.pack('<i',positions['device_assignment']-18000) if mac else bytes([50]);changed.data=bytes(raw)
            self.assertFalse(reader.extract_player_repair(changed,a,v,l))
