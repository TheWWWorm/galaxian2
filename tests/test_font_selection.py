"""Synthetic font setup layouts with relocated references and changed font IDs."""
import importlib.util
import struct
from types import SimpleNamespace
import unittest
from gof2_content.font_selection import (MAC, MAC_ALTERNATE, ARM, MAC_REFS, MAC_CALLS, ARM_FIELDS,
                                         ARM_REFS, ARM_CALLS, extract_font_selection)
from gof2_content.font_bindings import MAC_RECORD, font_records
from test_materials import arm_wide
from test_ship_models import branch


def expand(spec):
    code = bytearray(); fields = {}
    for token in spec.split():
        if token.startswith('{'):
            name, size = token[1:-1].split(':'); size = int(size)
            fields[name] = (len(code), size); code.extend(bytes(size))
        else: code.extend(bytes.fromhex(token))
    return code, fields


def selection_fixture(mac, relocation=0, alternate=False):
    body, fields = expand((MAC_ALTERNATE if alternate else MAC) if mac else ARM)
    address = 0x100000 + relocation + 128
    def put(key, data):
        at, size = fields[key]
        assert len(data) == size
        body[at:at+size] = data
    font_keys = ['2e','90','e2','f7','111','14e','1d2','203'] if mac else ['1a','f2','110','12e','6e','94','1ce','1f8']
    if mac:
        for key, (at, size) in fields.items():
            if key.startswith('value_'): put(key, (1).to_bytes(size, 'little'))
        for index, key in enumerate(font_keys): put('value_'+key, (100+index).to_bytes(4, 'little'))
        for index, group in enumerate(MAC_REFS + MAC_CALLS):
            target = address + len(body) - 24 if group[0][0] == 'ref_10' else address + 1800 + index * 8
            for key, end in group: put(key, struct.pack('<i', target-address-end))
    else:
        values = {}
        for key, (mnemonic, register) in ARM_FIELDS.items(): values[key] = 1 if mnemonic in ['mvn','mvnne'] else 65534 if key in ['value_4e','value_15a'] else 0
        for index, key in enumerate(font_keys): values['value_'+key] = 100+index
        for index, group in enumerate(ARM_REFS):
            target = address + 1800 + index * 8
            for lo, hi, pc in group:
                delta = target-address-pc
                values[lo], values[hi] = delta & 65535, delta >> 16
        for key, (mnemonic, register) in ARM_FIELDS.items():
            reg = int(register[1:]); value = values[key]
            put(key, struct.pack('<HH',0xf06f,(reg<<8)|value) if mnemonic.startswith('mvn') else arm_wide(value,reg,top=mnemonic=='movt'))
        for index, group in enumerate(ARM_CALLS):
            for key, at, mnemonic in group:
                data = bytearray(branch(address+at,address+3000+index*8))
                if mnemonic=='b.w': data[3] &= ~0x40
                put(key,data)
    code = bytes(128)+body+bytes(4096-128-len(body))
    text = {'address':address-128,'offset':64,'length':len(code),'name':b'__text','segment':b'__TEXT'}
    return SimpleNamespace(data=bytes(64)+code,text=text,sections=[text],slice_offset=4096,architecture='x86_64' if mac else 'armv7'), fields


@unittest.skipUnless(importlib.util.find_spec('capstone'), 'optional static-reader dependency')
class FontSelection(unittest.TestCase):
    def test_alternate_mac_alignment_retains_dispatch_links(self):
        for relocation in (0, 0x20000):
            mach, fields = selection_fixture(True, relocation, alternate=True)
            result = extract_font_selection(mach)
            self.assertEqual(result['source_bytes'], 576)
            self.assertEqual(result['default_font_id'], 105)
            data = bytearray(mach.data)
            data[192 + fields['ref_10'][0]] += 2
            mach.data = bytes(data)
            self.assertEqual(extract_font_selection(mach), {})

    def test_relocated_changed_parameters(self):
        for mac in [False,True]:
            for relocation in [0,0x20000]:
                mach, fields = selection_fixture(mac,relocation)
                result = extract_font_selection(mach)
                self.assertEqual(result['default_font_id'],105)
                self.assertEqual(result['secondary_font_id'],106)
                self.assertEqual(result['overrides'][1],{'language_id':10,'font_id':101})
                self.assertEqual(result['source_offset'],4288)
                self.assertEqual(result['spacing']['default'],[1]*4 if mac else [-2]*4)

    def test_rejects_layout_and_reference_corruption(self):
        for mac in [False,True]:
            for mutation in ['shape','reference','call','duplicate','truncated','font_id']:
                mach, fields = selection_fixture(mac)
                data = bytearray(mach.data)
                if mutation=='shape': data[192] ^= 1
                elif mutation=='reference':
                    key = 'ref_27' if mac else 'value_28'; data[192+fields[key][0]] ^= 1
                elif mutation=='call':
                    key = MAC_CALLS[0][0][0] if mac else ARM_CALLS[0][0][0]; data[192+fields[key][0]] ^= 1
                elif mutation=='duplicate':
                    n=578 if mac else 544;data[1024:1024+n]=data[192:192+n]
                elif mutation=='truncated': data=data[:600]
                elif mutation=='font_id':
                    key='value_14e' if mac else 'value_94';at,n=fields[key];data[192+at:192+at+n]=struct.pack('<I',65535) if mac else arm_wide(65535,1)
                mach.data=bytes(data)
                self.assertEqual(extract_font_selection(mach),{},(mac,mutation))
        mach, fields = selection_fixture(True)
        data=bytearray(mach.data);data[192+fields['ref_10'][0]] ^= 1;mach.data=bytes(data)
        self.assertEqual(extract_font_selection(mach),{},'Unlinked language switch table accepted')


class FontRecords(unittest.TestCase):
    def test_record_fields_and_allocation_link(self):
        code,fields=expand(MAC_RECORD)
        for key,value in [('id',401),('texture',777),('group',3)]:
            at,n=fields[key];code[at:at+n]=value.to_bytes(n,'little')
        for key in ['record_allocate','payload_allocate']:
            at,n=fields[key];code[at:at+n]=struct.pack('<i',512-at-4)
        text={'address':0x10000,'offset':64,'length':len(code),'name':b'__text','segment':b'__TEXT'}
        mach=SimpleNamespace(data=bytes(64)+code,text=text,sections=[text],slice_offset=4096,architecture='x86_64')
        result=font_records(mach)
        self.assertEqual([(r['id'],r['texture_id'],r['font_group']) for r in result],[(401,777,3)])
        code[fields['payload_allocate'][0]] ^= 1;mach.data=bytes(64)+code
        self.assertEqual(font_records(mach),[])



@unittest.skipUnless(importlib.util.find_spec('capstone'), 'optional static-reader dependency')
class FontAtlasBranches(unittest.TestCase):
    def fixture(self, mac):
        from gof2_content.font_bindings import MAC_GUARDS, ARM_GUARDS
        specs = MAC_GUARDS if mac else ARM_GUARDS
        base=0x10000; data=bytearray(8192); flags={'medium':base+9000,'large':base+9001}
        for index,(kind,start,other) in enumerate([('medium',128,1024 if mac else 1022),('large',1024,2048)]):
            body,fields=expand(specs[kind])
            if mac:
                at,n=fields['flag'];body[at:at+n]=struct.pack('<i',flags[kind]-base-start-7)
                at,n=fields['other'];body[at:at+n]=struct.pack('<i',other-start-len(body))
            else:
                ptr=base+4096+index*4;delta=ptr-base-start-12
                for key,value,top in [('low',delta&65535,False),('high',delta>>16,True)]:
                    at,n=fields[key];body[at:at+n]=arm_wide(value,0,top)
                struct.pack_into('<I',data,4096+index*4,flags[kind])
                # BEQ.W has S/J1/J2 all zero for this short forward branch.
                delta=other-(start+len(body))
                at,n=fields['other'];body[at:at+n]=struct.pack('<HH',0xf000 | ((delta>>12)&0x3f),0x8000|((delta>>1)&0x7ff))
                if kind=='large':
                    at,n=fields['allocate'];call=bytearray(branch(base+start+at,base+3500));call[3] &= ~0x10;body[at:at+n]=call
                    at,n=fields['record'];body[at:at+n]=struct.pack('<HH',0xf8ca,0x40)
            data[start:start+len(body)]=body
        text={'address':base,'offset':64,'length':4096,'name':b'__text','segment':b'__TEXT'}
        section={'address':base+4096,'offset':4160,'length':256,'name':b'__data','segment':b'__DATA'}
        mach=SimpleNamespace(data=bytes(64)+data,text=text,sections=[text,section],slice_offset=4096,architecture='x86_64' if mac else 'armv7')
        rows=[{'id':900,'kind':'texture','registration_type':2,'resource':'resources/data/'+name+'.aei','source_offset':4160+offset} for name,offset in [('unrelated_alpha',256),('unrelated_beta',1200),('unrelated_gamma',2300)]]
        return mach,rows,flags

    def test_choices_follow_source_branches(self):
        from gof2_content.font_bindings import font_texture_choices
        for mac in [False,True]:
            mach,rows,flags=self.fixture(mac)
            result=font_texture_choices(mach,[{'texture_id':900}],rows,flags)
            self.assertEqual(result['rows'][0]['variants'],{'medium':rows[0]['resource'],'large':rows[1]['resource'],'baseline':rows[2]['resource']})
            flags['medium']+=100
            self.assertEqual(font_texture_choices(mach,[{'texture_id':900}],rows,flags),{})

    def test_missing_or_conflicting_choices_rejected(self):
        from gof2_content.font_bindings import font_texture_choices
        for mac in [False,True]:
            mach,rows,flags=self.fixture(mac)
            self.assertEqual(font_texture_choices(mach,[{'texture_id':900}],rows[:2],flags),{})
            rows[1]['source_offset']=rows[0]['source_offset']
            self.assertEqual(font_texture_choices(mach,[{'texture_id':900}],rows,flags),{})

@unittest.skipUnless(importlib.util.find_spec('capstone'), 'optional static-reader dependency')
class FontLanguageDispatch(unittest.TestCase):
    def test_language_file_order_comes_from_dispatch(self):
        from gof2_content.font_bindings import MAC_LANGUAGE, MAC_LANGUAGE_ALTERNATE
        for spec in (MAC_LANGUAGE, MAC_LANGUAGE_ALTERNATE):
            self.check_language_dispatch(spec)

    def check_language_dispatch(self, spec):
        from gof2_content.font_bindings import language_files
        body,fields=expand(spec);data=bytearray(4096);start=128;table=512
        at,n=fields['table'];body[at:at+n]=struct.pack('<i',table-start-at-4)
        data[start:start+len(body)]=body
        for i in range(16):
            case=1024+i*32;string=2048+(15-i)*16
            struct.pack_into('<i',data,table+4*i,case-table)
            # Variable file order deliberately differs from cstring order.
            name=('a'+chr(97+15-i)+'.lang\0').encode();data[string:string+len(name)]=name
            block=bytes.fromhex('488d7dc031d2488d35')+struct.pack('<i',string-case-13)+b'\xe8'+struct.pack('<i',3000-case-18)
            data[case:case+len(block)]=block
        text={'address':0x10000,'offset':64,'length':2048,'name':b'__text','segment':b'__TEXT'}
        strings={'address':0x10800,'offset':2112,'length':256,'name':b'__cstring','segment':b'__TEXT'}
        mach=SimpleNamespace(data=bytes(64)+data,text=text,sections=[text,strings],slice_offset=4096,architecture='x86_64')
        result=language_files(mach)
        self.assertEqual([r['file'] for r in result['rows']],['a'+chr(97+15-i)+'.lang' for i in range(16)])
        data[table:table+4]=struct.pack('<i',2047-table);mach.data=bytes(64)+data
        self.assertEqual(language_files(mach),{})

if __name__=='__main__': unittest.main()
