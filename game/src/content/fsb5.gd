extends RefCounted
## Native FSB5 v1 sample reader. FMOD is never loaded.
## Container/Xbox IMA/MPEG framing: vgmstream format research, ISC attribution.
const MAX_BYTES := 192 * 1024 * 1024
const MAX_PCM_BYTES := 64 * 1024 * 1024
const RATES := [4000,8000,11000,11025,16000,22050,24000,32000,44100,48000,96000]
const STEPS := [7,8,9,10,11,12,13,14,16,17,19,21,23,25,28,31,34,37,41,45,50,55,60,66,73,80,88,97,107,118,130,143,157,173,190,209,230,253,279,307,337,371,408,449,494,544,598,658,724,796,876,963,1060,1166,1282,1411,1552,1707,1878,2066,2272,2499,2749,3024,3327,3660,4026,4428,4871,5358,5894,6484,7132,7845,8630,9493,10442,11487,12635,13899,15289,16818,18500,20350,22385,24623,27086,29794,32767]
const INDEX_CHANGE := [-1,-1,-1,-1,2,4,6,8]
const MPEG1_BITRATES := [0,32,40,48,56,64,80,96,112,128,160,192,224,256,320]
const MPEG2_BITRATES := [0,8,16,24,32,40,48,56,64,80,96,112,128,144,160]
var error := ""
var samples: Array[Dictionary] = []
var hash_prefix := ""
var codec := 0
var _data := PackedByteArray()

func open(data: PackedByteArray) -> bool:
	error="";samples.clear();_data=PackedByteArray();hash_prefix="";codec=0
	if data.size()<60 or data.size()>MAX_BYTES or data.slice(0,4)!=PackedByteArray([70,83,66,53]):return reject("Unsupported FSB5 envelope")
	if data.decode_u32(4)!=1:return reject("Unsupported FSB5 version")
	var count:=data.decode_u32(8)
	var header_size:=data.decode_u32(12)
	var name_size:=data.decode_u32(16)
	var data_size:=data.decode_u32(20)
	var format:=data.decode_u32(24)
	if count<1 or count>20000 or header_size<count*8 or name_size<count*4:return reject("Invalid FSB5 table sizes")
	if 60+header_size+name_size+data_size!=data.size():return reject("FSB5 size mismatch")
	if format not in [2,7,11] or data.decode_u32(32)!=0:return reject("Unsupported FSB5 codec or flags")
	var names:=60+header_size
	var start:=names+name_size
	var pos:=60
	var rows: Array[Dictionary]=[]
	for index in count:
		if pos+8>names:return reject("Truncated FSB5 sample header")
		var bits:=data.decode_u64(pos)
		pos+=8
		var rate_index: int=(bits>>1)&15
		var channels: int=[1,2,6,8][(bits>>5)&3]
		if rate_index>=RATES.size():return reject("Unsupported FSB5 sample rate")
		var rate: int=RATES[rate_index]
		var offset:=start+((bits>>7)&0x7ffffff)*32
		var length: int=(bits>>34)&0x3fffffff
		var more: int=bits&1
		var loop_start:=0
		var loop_end:=length
		var has_loop:=false
		var seen:={}
		while more!=0:
			if pos+4>names:return reject("Truncated FSB5 metadata")
			var chunk:=data.decode_u32(pos);pos+=4
			var kind:=chunk>>25
			var size: int=(chunk>>1)&0xffffff
			more=chunk&1
			if seen.has(kind) or pos+size>names:return reject("Invalid FSB5 metadata extent")
			seen[kind]=true
			match kind:
				1:
					if size!=1:return reject("Invalid FSB5 channel metadata")
					channels=data[pos]
				2:
					if size!=4:return reject("Invalid FSB5 frequency metadata")
					rate=data.decode_u32(pos)
				3:
					if size!=8:return reject("Unsupported FSB5 loop metadata")
					loop_start=data.decode_u32(pos);loop_end=data.decode_u32(pos+4)+1;has_loop=true
				_:return reject("Unsupported FSB5 metadata type %d"%kind)
			pos+=size
		if channels not in [1,2] or rate<1000 or rate>192000 or length<1 or length*channels*2>MAX_PCM_BYTES:return reject("FSB5 sample exceeds its decode budget")
		if offset<start or offset>=data.size() or (index>0 and offset<=rows[-1].offset):return reject("Invalid FSB5 sample offset")
		if loop_start<0 or loop_start>=loop_end or loop_end>length:return reject("Invalid FSB5 loop range")
		var name_offset:=data.decode_u32(names+4*index)
		if name_offset<count*4 or name_offset>=name_size:return reject("Invalid FSB5 name offset")
		var name_end:=names+name_offset
		while name_end<mini(start,names+name_offset+512) and data[name_end]!=0:name_end+=1
		if name_end>=mini(start,names+name_offset+512):return reject("Unterminated FSB5 sample name")
		var raw:=data.slice(names+name_offset,name_end)
		var name:=raw.get_string_from_utf8()
		if name.to_utf8_buffer()!=raw:return reject("Invalid FSB5 UTF-8 name")
		rows.append({"index":index,"name":name,"offset":offset,"samples":length,"channels":channels,"rate":rate,"has_loop":has_loop,"loop_start":loop_start,"loop_end":loop_end})
	if pos!=names:return reject("Unexpected FSB5 sample-header tail")
	for index in rows.size():rows[index].bytes=(rows[index+1].offset if index+1<rows.size() else data.size())-rows[index].offset
	_data=data;samples=rows;codec=format;hash_prefix=data.slice(36,44).hex_encode()
	return true

func stream(index: int, looping := false) -> AudioStream:
	error=""
	if index<0 or index>=samples.size():reject("FSB5 sample index outside the bank");return null
	var row: Dictionary=samples[index]
	var bytes:=_data.slice(row.offset,row.offset+row.bytes)
	if codec==11:
		var frames:=mpeg_frames(bytes,row)
		if frames.is_empty():return null
		var result:=AudioStreamMP3.new()
		result.data=frames
		if result.get_length()<=0:reject("MPEG decoder rejected the FSB5 sample");return null
		result.loop=looping;result.loop_offset=float(row.loop_start)/row.rate
		return result
	var pcm:=decode_ima(bytes,row.samples,row.channels) if codec==7 else pcm16(bytes,row.samples,row.channels)
	if pcm.is_empty():return null
	var result:=AudioStreamWAV.new()
	result.format=AudioStreamWAV.FORMAT_16_BITS
	result.stereo=row.channels==2;result.mix_rate=row.rate;result.data=pcm
	result.loop_mode=AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
	result.loop_begin=row.loop_start;result.loop_end=row.loop_end
	return result

func pcm16(data: PackedByteArray, count: int, channels: int) -> PackedByteArray:
	var size:=count*channels*2
	if size>data.size() or data.size()-size>=32:reject("Invalid FSB5 PCM extent");return PackedByteArray()
	return data.slice(0,size)

func decode_ima(data: PackedByteArray, count: int, channels: int) -> PackedByteArray:
	if count<1 or channels not in [1,2] or count*channels*2>MAX_PCM_BYTES:
		reject("Invalid IMA decode dimensions");return PackedByteArray()
	var blocks: int=(count+63)/64
	var needed:=blocks*36*channels
	if needed>data.size() or data.size()-needed>=32:reject("Invalid FSB5 IMA extent");return PackedByteArray()
	var pcm:=PackedByteArray();pcm.resize(count*channels*2)
	for block in blocks:
		var start:=block*36*channels
		for channel in channels:
			var predictor:=int(data.decode_s16(start+4*channel))
			var step_index:=int(data[start+4*channel+2])
			if step_index>88 or data[start+4*channel+3]!=0:reject("Invalid IMA block state");return PackedByteArray()
			pcm.encode_s16((block*64*channels+channel)*2,predictor)
			for frame in range(1,mini(64,count-block*64)):
				var nibble:=frame-1
				var at:=start+4*channels+(nibble/8)*4*channels+4*channel+(nibble%8)/2
				var code: int=(data[at]>>(4*(nibble&1)))&15
				var step: int=STEPS[step_index]
				var difference:=step>>3
				if code&1:difference+=step>>2
				if code&2:difference+=step>>1
				if code&4:difference+=step
				predictor=clampi(predictor+(-difference if code&8 else difference),-32768,32767)
				step_index=clampi(step_index+INDEX_CHANGE[code&7],0,88)
				pcm.encode_s16(((block*64+frame)*channels+channel)*2,predictor)
	return pcm

func mpeg_frames(data: PackedByteArray, row: Dictionary) -> PackedByteArray:
	var output:=PackedByteArray()
	var pos:=0
	var decoded:=0
	while decoded<int(row.samples):
		if pos+4>data.size():reject("Truncated FSB5 MPEG frame");return PackedByteArray()
		var bits: int=(int(data[pos])<<24)|(int(data[pos+1])<<16)|(int(data[pos+2])<<8)|data[pos+3]
		var version: int=(bits>>19)&3
		var bitrate_index: int=(bits>>12)&15
		var rate_index: int=(bits>>10)&3
		if (bits&0xffe00000)!=0xffe00000 or version==1 or ((bits>>17)&3)!=1 or bitrate_index in [0,15] or rate_index==3:
			reject("Unsupported FSB5 MPEG Layer III frame");return PackedByteArray()
		var rate: int=[44100,48000,32000][rate_index]
		if version==2:rate/=2
		elif version==0:rate/=4
		var channels:=1 if ((bits>>6)&3)==3 else 2
		if rate!=int(row.rate) or channels!=int(row.channels):reject("MPEG frame disagrees with its FSB5 sample");return PackedByteArray()
		var bitrate: int=(MPEG1_BITRATES if version==3 else MPEG2_BITRATES)[bitrate_index]
		var size: int=((144000 if version==3 else 72000)*bitrate)/rate+((bits>>9)&1)
		if size<4 or pos+size>data.size():reject("Truncated FSB5 MPEG payload");return PackedByteArray()
		output.append_array(data.slice(pos,pos+size))
		pos+=((size+3)/4)*4
		decoded+=1152 if version==3 else 576
	if decoded!=int(row.samples) or data.size()-pos<0 or data.size()-pos>=32:
		reject("FSB5 MPEG sample count or trailing extent mismatch");return PackedByteArray()
	return output

func reject(message: String) -> bool:
	error=message
	return false
