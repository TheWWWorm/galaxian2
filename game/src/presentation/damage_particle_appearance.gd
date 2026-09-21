extends RefCounted
## Pure sprite appearance. Emission, movement and world ownership are separate.
## Callers retain returned state; failed calculations never modify their input.
const Definitions=preload("res://src/content/damage_particle_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Random=preload("res://src/simulation/seeded_random.gd")

static func start(preset: Dictionary,slot: Variant,size_sample: Variant) -> Dictionary:
	if not Definitions.sprite_preset(preset) or not Numbers.integer(slot,0,int(preset.capacity)-1):return {"error":"Invalid damage particle preset or slot"}
	if not Numbers.integer(size_sample,0,maxi(0,int(preset.size_jitter)-1)):return {"error":"Invalid damage particle size sample"}
	return {"slot":int(slot),"age_ms":0,"size":int(single(single(preset.size)+float(size_sample)))}

static func advance(preset: Dictionary,state: Dictionary,delta_ms: Variant) -> Dictionary:
	if not valid_state(preset,state):return {"error":"Invalid damage particle appearance state"}
	if not (delta_ms is float or delta_ms is int) or not is_finite(delta_ms) or delta_ms<0 or delta_ms>60000:return {"error":"Invalid damage particle appearance interval"}
	var result:=state.duplicate(true)
	if int(state.age_ms)==-1:return result
	var delta:=single(delta_ms)
	result.age_ms=int(single(single(state.age_ms)+delta))
	if result.age_ms>int(preset.lifetime_ms):
		result.age_ms=-1;result.size=0
		return result
	# This renderer field is signed 16-bit size, not an angle. Truncation occurs
	# on every update, so accumulating a floating growth total changes behavior.
	var growth:=int(single(single(single(preset.size_growth_per_second)*delta)*single(0.001)))
	result.size=signed_short(int(state.size)+signed_short(growth))
	return result

static func sample(preset: Dictionary,state: Dictionary,fade_in_rgb:=false) -> Dictionary:
	if not Definitions.sprite_preset(preset):return {"error":"Invalid damage particle appearance preset"}
	return sample_prepared(preset,state,fade_in_rgb)

## Geometry validates and retains its immutable preset when building surfaces.
## Per-frame sampling still validates the changing slot, including inactive ones.
static func sample_prepared(preset: Dictionary,state: Dictionary,fade_in_rgb:=false) -> Dictionary:
	if not valid_slot(preset,state):return {"error":"Invalid damage particle appearance state"}
	if int(state.age_ms)==-1:return {"active":false}
	var fraction:=minf(1.0,single(single(state.age_ms)/single(preset.lifetime_ms)))
	var remaining:=single(1.0-fraction);var color:=[]
	for channel in 4:
		var value:=single(single(single(preset.start_rgba[channel])*remaining)+single(single(preset.end_rgba[channel])*fraction))
		color.append(single(value*single(1.0/255.0)))
	if state.age_ms<preset.fade_in_ms:
		var ramp:=single(single(state.age_ms)/single(preset.fade_in_ms))
		for channel in ([0,1,2] if fade_in_rgb else [3]):color[channel]=single(color[channel]*ramp)
	# The last animation tile lasts through the inclusive lifetime boundary.
	@warning_ignore("integer_division")
	var frame:=maxi(0,(int(state.age_ms)-1)*int(preset.animation_frames)/int(preset.lifetime_ms))
	var rect: Array=preset.uv_rect
	var width:=single(rect[2]-rect[0]);var height:=single(rect[3]-rect[1])
	var x:=single(single(single(frame)*width)+single(rect[0]))
	var row:=int(single(x+0.0009765625))
	var u:=single(x-single(row));var v:=single(single(single(row)*height)+single(rect[1]))
	var us:=[u,single(u+width)];var vs:=[v,single(v+height)]
	# Source sprite mirroring is stable per slot and independent of the emitter
	# and world RNG streams. Creating this local generator advances neither.
	var flip:=0
	if (int(preset.flags)&0x02000000)!=0:
		var random:=Random.new();random.seed_from(int(state.slot))
		flip=random.next_int(40000)
	var x_index:=flip&1;var y_index:=(flip>>1)&1
	# Unanimated EMP sprites retain their initial per-slot mirror. Nozzle sprites
	# have no mirror flag, so their zero-frame rectangle remains unchanged.
	var uv:=Vector4(us[x_index],vs[y_index],us[1-x_index],vs[1-y_index])
	return {"active":true,"size":state.size,"age_ms":state.age_ms,"frame":frame,
		"color":Color(color[0],color[1],color[2],color[3]),
		"uv_rect":uv}

static func valid_state(preset: Dictionary,state: Dictionary) -> bool:
	return Definitions.sprite_preset(preset) and valid_slot(preset,state)

static func valid_slot(preset: Dictionary,state: Dictionary) -> bool:
	return state.size()==3 and Numbers.integer(state.get("slot"),0,int(preset.capacity)-1) and Numbers.integer(state.get("age_ms"),-1,int(preset.lifetime_ms)) and Numbers.integer(state.get("size"),-32768,32767) and (state.age_ms!=-1 or state.size==0)

static func single(value: float) -> float:
	var bytes:=PackedByteArray();bytes.resize(4);bytes.encode_float(0,value);return bytes.decode_float(0)

static func signed_short(value: int) -> int:return ((value+32768)&65535)-32768
