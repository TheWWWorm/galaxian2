extends RefCounted
## Lossless channel separation for decoded PCM. Loop sample coordinates survive.
const MAX_BYTES=128*1024*1024

static func split_stereo(stream: Variant) -> Array:
	if not stream is AudioStreamWAV or stream.format!=AudioStreamWAV.FORMAT_16_BITS or not stream.stereo:return []
	var data: PackedByteArray=stream.data
	if data.is_empty() or data.size()>MAX_BYTES or data.size()%4!=0:return []
	if stream.loop_mode!=AudioStreamWAV.LOOP_FORWARD or stream.loop_begin<0 or stream.loop_end<=stream.loop_begin or stream.loop_end>data.size()/4:return []
	var left:=PackedByteArray();var right:=PackedByteArray()
	left.resize(data.size()/2);right.resize(data.size()/2)
	for frame in data.size()/4:
		var source:=frame*4;var target:=frame*2
		left[target]=data[source];left[target+1]=data[source+1]
		right[target]=data[source+2];right[target+1]=data[source+3]
	var result: Array=[]
	for channel in [left,right]:
		var mono:=AudioStreamWAV.new()
		mono.format=stream.format;mono.stereo=false;mono.mix_rate=stream.mix_rate
		mono.loop_mode=stream.loop_mode;mono.loop_begin=stream.loop_begin;mono.loop_end=stream.loop_end
		mono.data=channel;result.append(mono)
	return result
