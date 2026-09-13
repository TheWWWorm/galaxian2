extends SceneTree
const Bank=preload("res://src/content/fsb5.gd")
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func run():
	var reader:=Bank.new()
	var block:=PackedByteArray();block.resize(36);block.fill(0x77);block.encode_u32(0,0)
	var result:=reader.decode_ima(block,64,1)
	# Independent IMA shift/add golden prefix; includes predictor and clipping.
	var expected:=[0,11,41,104,240,533,1164,2521,5431,11667,25039,32767]
	check(result.size()==128,"Mono Xbox IMA block must have 64 samples")
	for i in expected.size():check(result.decode_s16(i*2)==expected[i],"IMA predictor/step or clipping mismatch at %d"%i)
	block[35]=0xf7
	check(reader.decode_ima(block,64,1)==result,"Xbox IMA decoded the discarded high nibble")
	block[2]=89
	check(reader.decode_ima(block,64,1).is_empty(),"Invalid IMA step state was accepted")
	check(reader.decode_ima(PackedByteArray(),64,2).is_empty(),"Truncated stereo IMA was accepted")
	var bytes:=pcm_fixture()
	check(reader.open(bytes),reader.error)
	var stream: AudioStreamWAV=reader.stream(0,true)
	check(stream!=null and stream.data==PackedByteArray([0,0,0xff,0x7f,0,0x80]) and stream.mix_rate==44100 and stream.loop_end==3,"PCM source samples or full loop changed")
	var broken:=bytes.duplicate();broken.encode_u32(20,1)
	check(not reader.open(broken) and reader.samples.is_empty(),"FSB5 size mismatch retained the previous bank")
	broken=bytes.duplicate();broken.encode_u32(60+8,0xffffffff)
	check(not reader.open(broken),"Out-of-bounds FSB5 sample name was accepted")
	var args:=OS.get_cmdline_user_args()
	for i in range(0,args.size(),3):verify_source(args[i])
	print("FSB5: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
func pcm_fixture() -> PackedByteArray:
	var data:=PackedByteArray();data.resize(80);data.fill(0)
	for i in 4:data[i]=[70,83,66,53][i]
	data.encode_u32(4,1);data.encode_u32(8,1);data.encode_u32(12,8);data.encode_u32(16,6);data.encode_u32(20,6);data.encode_u32(24,2)
	data.encode_u64(60,(3<<34)|(8<<1));data.encode_u32(68,4);data[72]=120
	data[76]=0xff;data[77]=0x7f;data[79]=0x80
	return data
func verify_source(root_path: String):
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(root_path.path_join("manifest.json")))
	var banks:=0;var total:=0
	for name in manifest.files:
		if not name.ends_with(".fsb"):continue
		var reader:=Bank.new()
		if not reader.open(FileAccess.get_file_as_bytes(root_path.path_join(name))):check(false,name+": "+reader.error);continue
		banks+=1;total+=reader.samples.size()
		if name=="resources/FMOD_GOF2_MUSIC.fsb":
			for index in [0,5]:
				var stream: AudioStreamMP3=reader.stream(index,true)
				check(stream!=null,reader.error)
				if stream!=null:check(absf(stream.get_length()-float(reader.samples[index].samples)/reader.samples[index].rate)<0.0001,"MPEG framing changed duration")
		if name=="resources/FMOD_GOF2_SFX_SPACE.fsb":
			for index in [23,24,25,38,39]:
				var stream: AudioStreamWAV=reader.stream(index)
				check(stream!=null,reader.error)
				if stream!=null:check(stream.data.size()==reader.samples[index].samples*reader.samples[index].channels*2,"IMA decode sample count changed")
	check(banks==22 and total==4416,"Source audio inventory incomplete")
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
