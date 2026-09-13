"""Synthetic relocated declarations; no game bytes or original strings stored."""
import importlib.util
import struct
from types import SimpleNamespace
import unittest
from test_ship_models import branch
from test_materials import arm_wide
from gof2_content.opening_dialogue import (MAC_SINGLE, MAC_RANGE, ARM_SINGLE, ARM_RANGE,
                                         extract_opening_dialogue)


def fixture(mac, relocation=0):
    base = (0x100000000 if mac else 0x10000) + relocation
    code = bytearray(16384)
    marks = {}
    pos = 256
    def raw(hexadecimal):
        nonlocal pos
        block = bytes.fromhex(hexadecimal); code[pos:pos+len(block)] = block; pos += len(block)
    def word(value):
        nonlocal pos
        code[pos:pos+4] = struct.pack('<I',value); pos += 4
    def rel(target):
        nonlocal pos
        code[pos:pos+4] = struct.pack('<i',target-pos-4); pos += 4
    def call(target, thumb=False):
        nonlocal pos
        if mac:
            raw('e8'); rel(target)
        else:
            block = bytearray(branch(base+pos-(pos%4 if thumb else 0),base+target))
            if thumb: block[3] &= ~0x10  # BLX immediate to aligned synthetic stub.
            code[pos:pos+4] = block; pos += 4
    def mov(reg, value):
        nonlocal pos
        if mac:
            raw({'edi':'bf','esi':'be','edx':'ba','ecx':'b9','r8d':'41b8','r9d':'41b9'}[reg]); word(value)
        else:
            number=int(reg[1:])
            if value < 256: raw(struct.pack('<H',0x2000 | number << 8 | value).hex())
            else:
                block=arm_wide(value,reg=number);code[pos:pos+4]=block;pos+=4
    if mac:
        raw('4989ff49c787b00100000000000081fea10000000f87');rel(12000)
        raw('89f0488d0d'); rel(7000);raw('486304814801c8ffe0')
        code[7000:7004]=struct.pack('<i',1024-7000)
    else:
        raw('a12c00f20080dfe814f0')
        code[pos:pos+2]=struct.pack('<H',(1024-pos)//2)
    pos=1024
    if mac:
        mov('edi',24);call(11000);raw('4889c3');mov('edi',8);call(11004)
        raw('48894308c743100100000048c70000000000c7030000000049899fb0010000')
        mov('edi',23);raw('4889de');call(11008)
    else:
        raw('4ff0ff30cdf8f0050c20');call(11000,True);raw('06900120cdf8f00504200595');call(11004,True)
        raw('06990123069a5060069a936000220260069802600598c0f814111720');call(11008)
    for i in range(23):
        marks[f'row{i}']=pos
        condition = 9 if i==9 else 27 if i==16 else 5
        value = 4 if i==9 else 80+i
        if mac:
            mov('edi',56);call(11000);raw('4889c34889df')
            marks[f'text{i}']=pos+1;mov('esi',1000+i);mov('edx',30+i);mov('ecx',condition);mov('r8d',value)
            if i==9: mov('r9d',4)
            marks[f'ctor{i}']=pos;call(8500 if i==9 else 8000)
            raw('498b87b0010000488b4008')
            if i==0: raw('488918')
            elif i*8<128: raw('488958'+bytes([i*8]).hex())
            else: raw('488998');word(i*8)
        else:
            raw('4ff0ff30cdf8f0052820');call(11000,True);mov('r1',i+2)
            raw(bytes([7+i,0x90,7+i,0x98]).hex());raw('cdf8f015')
            if i==9:
                mov('r2',value);mov('r1',4);raw('0092');mov('r2',30+i);raw('0191')
            else:
                mov('r1',value);mov('r2',30+i);raw('0091')
            marks[f'text{i}']=pos;mov('r1',1000+i);mov('r3',condition)
            marks[f'ctor{i}']=pos;call(8500 if i==9 else 8000)
            raw(bytes([7+i,0x98]).hex());raw('059ad2f81411' if i==22 else '0599d1f81411');raw('4968')
            raw(struct.pack('<H',0x6008 | i << 6).hex())
    if mac: raw('e9');rel(12000)
    else: call(12000);code[pos-1] &= ~0x40  # B.W instead of BL.
    marks['end']=pos
    def helper(at,spec):
        nonlocal pos
        pos=at
        for token in spec.split():
            if token.startswith('{'):
                if mac: rel(11004)
                else: call(11004,True)
            else:raw(token)
    helper(8000,MAC_SINGLE if mac else ARM_SINGLE)
    pos=8500
    if mac:raw('554889e55de9');rel(9000)
    else:raw('90b501af82b00446b868d7f80c908de801022046');call(9000);raw('204602b090bd')
    helper(9000,MAC_RANGE if mac else ARM_RANGE)
    pos=13000
    if mac:
        raw('488b45b049894528498b45106900d007000005dc0500004189453841c6453d01')
        pos=13100;raw('b8d0070000480343284839f0488975a80f8d');rel(13200);raw('f6433d01')
    else:
        raw('0e9a4ff4fa61109850610f98906190680068484300f2dc505062012082f82900')
        pos=13100;raw('3346002253f8140f596810f5fa6041f10001a0424ff0000028bf01205145a8bf012208bf0246002a40f00080')
    text=dict(address=base,offset=256,length=len(code),name=b'__text',segment=b'__TEXT')
    return SimpleNamespace(data=bytes(256)+code,sections=[text],text=text,slice_offset=4096,architecture='x86_64' if mac else 'armv7'),marks


@unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
class DialogueTests(unittest.TestCase):
    def test_relocated_changed_content(self):
        for mac in (False,True):
            for shift in (0,0x18000):
                m,_=fixture(mac,shift);result=extract_opening_dialogue(m)
                self.assertTrue(result,(mac,shift))
                self.assertEqual([e['text_id'] for e in result['events']],list(range(1000,1023)))
                self.assertEqual(result['events'][9]['values'],[4,5,6,7])
                self.assertEqual(result['events'][16]['values'],[96])
                self.assertEqual(result['timing']['display_delay_ms'],2000)
    def test_rejects_corrupt_layouts_and_links(self):
        for mac in (False,True):
            for bad in ('dispatch','constructor','link','range','record','tail','timing','truncated'):
                m,marks=fixture(mac);data=bytearray(m.data)
                at={'dispatch':256,'constructor':8000,'range':9000,'record':marks['row10'],'link':marks['ctor5'],'tail':marks['end']-(5 if mac else 4),'timing':13000}.get(bad)
                if bad=='truncated': m.text['length']=7000
                else:data[256+at]^=0x80
                m.data=bytes(data)
                self.assertEqual(extract_opening_dialogue(m),{},(mac,bad))
