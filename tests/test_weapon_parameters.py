"""Relocated synthetic declarations, altered bindings, and linked-scope failures."""
import struct
import unittest
from types import SimpleNamespace
from gof2_content import weapon_parameters as reader
from test_font_selection import expand
from test_ship_models import branch


def fixture(mac, shift=0):
    base=0x100000+shift;file_base=4352
    text={'name':b'__text','segment':b'__TEXT','address':base,'offset':256,'length':8000}
    const={'name':b'__const','segment':b'__TEXT','address':base+8000,'offset':8256,'length':1000}
    data=bytearray(9256)
    locations={'head':1000,'scale':1077 if mac else 1060,'tail':1224 if mac else 1240,
               'defaults':3000,'modifier':3400,'category_getter':5000,'id_getter':5020,
               'ship_getter':5040,'damage_getter':5060,'interval_getter':5080,
               'property_getter':5120,'type_getter':5200,'equipment_table':3800 if mac else 3320}
    if not mac: locations.update(defaults=3100,scale_tail=1170,constants=3240,scale_load=924)
    helper_specs={'category_getter':'554889e58b47045dc3' if mac else '40687047',
       'id_getter':'554889e58b075dc3' if mac else '00687047',
       'ship_getter':'554889e5488b87000200005dc3' if mac else 'd0f87c017047',
       'damage_getter':'554889e5f30f1047585dc3' if mac else '806d7047',
       'interval_getter':'554889e5f30f1047545dc3' if mac else '406d7047',
       'type_getter':'554889e58b47085dc3' if mac else '80687047',
       'property_getter':'554889e5488b4f388b3931d2eb044883c202b8257899c539fa730d488b410839349075ea8b4490045dc3' if mac else '026bd2f80090b9f1000f08d05268002352f82300884207d002334b45f8d347f62500ccf29950704702eb830040687047'}
    for key,raw in helper_specs.items(): data[256+locations[key]:256+locations[key]+len(bytes.fromhex(raw))]=bytes.fromhex(raw)
    expected={'damage_property':49,'interval_property':51,'lifetime_property':52,'speed_property':53,
              'interval_percent_property':79,'damage_percent_property':80,'low_damage_threshold':12}
    links= {'head':{'11':'property_getter','26':'property_getter','3c':'category_getter'},
            'tail':{'b':'id_getter','1b':'type_getter','30':'property_getter','45':'property_getter','73':'id_getter'},
            'modifier':{'11':'property_getter','5f':'property_getter'},
            'scale':{'a':'ship_getter','12':'damage_getter','40':'ship_getter','48':'interval_getter','6d':'ship_getter','75':'interval_getter'}} if mac else {
            'head':{'c':'property_getter','1e':'property_getter','2e':'category_getter'},
            'tail':{'a':'id_getter','1c':'type_getter','2c':'property_getter','3c':'property_getter','60':'id_getter'},
            'modifier':{'8':'property_getter','36':'property_getter'},
            'scale':{'a':'ship_getter','12':'damage_getter','36':'ship_getter','3e':'interval_getter'},
            'scale_tail':{'1a':'ship_getter','22':'interval_getter'}}
    jumps={'head':{'43':locations['scale'],'48':locations['tail']},
           'scale':{'1d':locations['scale']+0x24,'22':locations['scale']+0x60,'5e':locations['tail']},
           'modifier':{'43':locations['modifier']+0x48,'88':locations['modifier']+160,'8a':locations['modifier']+160,'94':locations['modifier']+160}} if mac else {
           'head':{'32':locations['scale'],'3a':locations['tail']},
           'scale':{'22':locations['scale_tail'],'28':locations['scale_tail'],'60':locations['scale_tail']+68},
           'modifier':{'5c':locations['modifier']+160}}
    # ARM literals must be within their PC-relative load's 1 KiB reach.
    values={'divisor':(8100 if mac else 3600,200.0),'default':(8104,1.0),
            'sentinel':(8108 if mac else 3604,-9999.0),'low':(8112 if mac else 1164,0.5),'unused':(3608,1000.0)}
    refs={'modifier':{'1a':'divisor','22':'default','31':'sentinel','6b':'divisor','73':'default','81':'sentinel'},'scale':{'82':'low'}} if mac else {'constants':{'4':'unused','8':'divisor','10':'sentinel'},'scale_load':{'0':'low'}}
    contexts={}
    for key in ['head','tail','modifier','defaults','scale']+([] if mac else ['constants','scale_tail','scale_load']):
        body,fields=expand(getattr(reader,('MAC_' if mac else 'ARM_')+key.upper()));at=locations[key]
        for field,(off,n) in fields.items():
            site=base+at+off
            if field in expected:
                value=expected[field]
                raw=value.to_bytes(n,'little',signed=True) if mac else struct.pack('<HH',0xf1bb,0x0f00|value) if field=='low_damage_threshold' else struct.pack('<H',0x2100|value)
            elif field.startswith('call_'):
                target=base+locations[links[key][field[5:]]]
                raw=struct.pack('<i',target-site-4) if mac else branch(site,target)
            elif field.startswith('jump_'):
                target=base+jumps[key][field[5:]]
                if mac: raw=(target-site-n).to_bytes(n,'little',signed=True)
                else:
                    delta=target-site-4
                    if key=='head' and field=='jump_32': raw=struct.pack('<H',0xb100|((delta&0x40)<<3)|((delta&0x3e)<<2))
                    else: raw=struct.pack('<H',(0xd500 if field=='jump_22' else 0xda00 if field=='jump_28' else 0xe000)|((delta//2)&(255 if field in ['jump_22','jump_28'] else 2047)))
            else:
                target=base+values[refs.get(key,{}).get(field[4:],'default')][0]
                if mac:raw=struct.pack('<i',target-site-4)
                else:
                    reg={'ref_4':16,'ref_8':20,'ref_10':24,'ref_0':16}[field]
                    delta=target-((site+4)&~3);raw=struct.pack('<HH',0xed9f|((reg&1)<<6),((reg//2)<<12)|0x0a00|(delta//4))
            body[off:off+n]=raw
        data[256+at:256+at+len(body)]=body;contexts[key]=(at,body,fields)
    for at,value in values.values():struct.pack_into('<f',data,256+at,value)
    table=locations['equipment_table'];rows=[table+120]*30;rows[26]=locations['modifier']
    raw=struct.pack('<30i',*(x-table for x in rows)) if mac else bytes((x-table)//2 for x in rows)
    data[256+table:256+table+len(raw)]=raw
    def extent(key,n=None):return {'offset':file_base+locations[key],'bytes':n if n is not None else len(bytes.fromhex(helper_specs[key]))}
    vehicle={'item_type_value_index':5,'provenance':{k:extent(k) for k in ['type_getter','property_getter']}}
    vehicle['provenance'].update(equipment_table=extent('equipment_table',120 if mac else 30),equipment_selector={'offset':file_base+(3120 if mac else 3310),'bytes':25 if mac else 14})
    opening={'item_category_value_index':3,'provenance':{'category_getter':extent('category_getter')}}
    mach=SimpleNamespace(data=bytes(data),text=text,sections=[text,const] if mac else [dict(text,length=9000)],slice_offset=4096,architecture='x86_64' if mac else 'armv7')
    return mach,vehicle,opening,contexts,expected


class WeaponParameters(unittest.TestCase):
    def test_item_specific_launch_modes(self):
        for mac in [True,False]:
            for shift in [0,0x400000]:
                mach,vehicle,opening,_,_=fixture(mac,shift)
                data=bytearray(mach.data);base=mach.text['address'];at=2000;selector=2200;target=2400 if mac else 2568
                body,fields=expand(reader.MAC_LAUNCH_MODE if mac else reader.ARM_LAUNCH_MODE)
                for name,(off,n) in fields.items():
                    if name=='single': raw=(128).to_bytes(n,'little') if mac else struct.pack('<H',0x2c80)
                    elif name=='first': raw=(-19).to_bytes(n,'little',signed=True) if mac else bytes.fromhex('a4f11300')
                    elif name=='count': raw=bytes([3]) if mac else bytes.fromhex('0328')
                    elif name=='getter': raw=struct.pack('<i',5120-at-off-4) if mac else branch(base+at+off,base+5120)
                    elif name=='address_low': raw=bytes.fromhex('40f20001')
                    elif name=='address_high': raw=bytes.fromhex('c0f20001')
                    else: raw=bytes(n)
                    body[off:off+n]=raw
                data[256+at:256+at+len(body)]=body
                gate=bytes.fromhex('41f68760010000010f85')+struct.pack('<i',target-selector-14) if mac else bytes.fromhex('93f80801002800f0b380d96b0868')
                data[256+selector:256+selector+len(gate)]=gate
                selected=bytes.fromhex('498b4f788339007e00') if mac else bytes.fromhex('98680028')
                data[256+target:256+target+len(selected)]=selected
                mach.data=bytes(data)
                result=reader.extract_weapon_parameters(mach,vehicle,opening)
                self.assertEqual(result['launch_modes']['alternate_item_ids'],[19,20,21,128])
                for corruption in ['declaration','selector','target','getter','duplicate','overlap']:
                    bad=bytearray(data)
                    if corruption=='declaration':bad[256+at+8]^=0x80
                    elif corruption=='selector':bad[256+selector]^=1
                    elif corruption=='target':bad[256+target]^=1
                    elif corruption=='getter':bad[256+at+fields['getter'][0]]^=4
                    elif corruption=='duplicate':bad[256+2700:256+2700+len(body)]=body
                    else:
                        off,n=fields['single'];bad[256+at+off:256+at+off+n]=(19).to_bytes(n,'little') if mac else struct.pack('<H',0x2c13)
                    mach.data=bytes(bad)
                    self.assertFalse(reader.extract_launch_modes(mach,result),(mac,shift,corruption))

    def test_relocated_changed_bindings(self):
        for mac in [True,False]:
            for shift in [0,0x400000]:
                mach,vehicle,opening,_,expected=fixture(mac,shift)
                result=reader.extract_weapon_parameters(mach,vehicle,opening)
                self.assertTrue(result,(mac,shift));self.assertEqual({key:result[key] for key in expected},expected)
                self.assertEqual(result['modifier_type'],26);self.assertEqual(result['percent_divisor'],200)
                self.assertEqual(result['low_damage_interval_scale'],0.5)

    def test_corrupt_or_unlinked_contexts(self):
        for mac in [True,False]:
            for bad in ['head','tail','scale','modifier','defaults','property_getter','category_getter','table','missing','duplicate','truncated','call','jump','nan']:
                with self.subTest(mac=mac,bad=bad):
                    mach,vehicle,opening,contexts,_=fixture(mac);data=bytearray(mach.data)
                    if bad in contexts:data[256+contexts[bad][0]]^=1
                    elif bad in ['property_getter','category_getter']:
                        row=vehicle['provenance'][bad] if bad=='property_getter' else opening['provenance'][bad];data[row['offset']-4096]^=1
                    elif bad=='table':data[vehicle['provenance']['equipment_table']['offset']-4096+(104 if mac else 26)]=0
                    elif bad=='missing':vehicle={}
                    elif bad=='duplicate':
                        at,body,_=contexts['head'];data[6256:6256+len(body)]=body
                    elif bad=='truncated':mach.text['length']=contexts['head'][0]+1
                    elif bad in ['call','jump']:
                        at,_,fields=contexts['head'];off,n=fields[('call_11' if mac else 'call_c') if bad=='call' else ('jump_43' if mac else 'jump_32')];data[256+at+off]^=2
                    elif bad=='nan':struct.pack_into('<f',data,256+(8100 if mac else 3600),float('nan'))
                    mach.data=bytes(data)
                    self.assertEqual(reader.extract_weapon_parameters(mach,vehicle,opening),{})
