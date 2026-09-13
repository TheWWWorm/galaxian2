extends RefCounted
## Native parameter windows and playlist choices; preparation has no playback effects.
## Its random stream is independent of the game's world stream.
var error := ""
var _definition := {}
var _state := {}
var _identity: RefCounted
var _revision := 0
var _seed_value := 0

func configure(definition: Dictionary, seed_value: int) -> void:
	_definition=definition;_seed_value=seed_value
	_identity=RefCounted.new();_revision=0;error=""
	var random:=RandomNumberGenerator.new();random.seed=seed_value
	_state={"elapsed_ms":0,"parameter":0.0,"started":false,"windows":{},"last_samples":{},"rng_state":random.state}

func prepare_step(delta_ms: int) -> Dictionary:
	error=""
	if _identity==null or delta_ms<0 or delta_ms>1000:
		error="Layered audio requires an initialized, bounded frame interval";return {}
	var next:=_state.duplicate(true)
	next.elapsed_ms+=delta_ms
	# FEV velocity is in units/second. These supported parameters use range0..1.
	var phase:=f32(float(next.parameter)+f32(f32(float(delta_ms)/1000.0)*_definition.parameter.velocity))
	if phase>1.0:phase=f32(phase-1.0)
	next.parameter=phase
	var random:=RandomNumberGenerator.new();random.seed=_seed_value;random.state=next.rng_state
	var operations: Array[Dictionary]=[]
	for layer in _definition.layers:
		for sound in layer:
			var active: bool=phase>=sound.start and phase<=f32(sound.start+sound.width)
			var previous: bool=next.windows.get(sound.key,false)
			if active and not previous:
				var definition: Dictionary=sound.definition
				var last: int=next.last_samples.get(definition.id,-1)
				var choice:=sample(definition,random,last)
				next.last_samples[definition.id]=choice.playlist_index
				choice.merge({"action":"start","key":sound.key,"gain":f32(choice.gain*sound.volume),"looping":sound.looping},true)
				operations.append(choice)
			elif previous and not active and sound.looping:
				operations.append({"action":"stop","key":sound.key})
			# A one-shot continues to its sample end after its window is left.
			next.windows[sound.key]=active
	next.started=true;next.rng_state=random.state
	return {"identity":_identity,"revision":_revision+1,"state":next,"operations":operations}

func commit_step(frame: Dictionary) -> bool:
	if frame.get("identity")!=_identity or frame.get("revision")!=_revision+1:return false
	_state=frame.state;_revision=frame.revision
	return true

func snapshot() -> Dictionary:
	return _state.duplicate(true)

static func sample(definition: Dictionary, random: RandomNumberGenerator, previous: int) -> Dictionary:
	var index:=0
	if definition.samples.size()>1:
		if definition.playlist_flags in [8,9]:index=(previous+1)%definition.samples.size()
		else:index=weighted_choice(definition.weights,random.randi()&0x7fffffff,previous if definition.playlist_flags==0 else -1)
	var gain: float=definition.volume
	if definition.attenuation!=1.0:gain=random_gain(gain,definition.attenuation,random.randi()&0x7fffffff)
	var pitch: float=random_pitch(definition.pitch,definition.pitch_random,random.randi()&0x7fffffff) if definition.pitch_random!=0 else f32(pow(2.0,4.0*definition.pitch))
	return {"sample":definition.samples[index],"gain":gain,"pitch":pitch,"definition_id":definition.id,"playlist_index":index}

static func weighted_choice(weights: Array, draw: int, previous: int) -> int:
	var total:=0
	for weight in weights:total+=int(weight)
	var target:=draw%total
	var cumulative:=0
	for i in weights.size():
		cumulative+=int(weights[i])
		if target<cumulative:
			# Source random-no-repeat moves a repeated ordinary sample to its
			# successor. It is not a shuffle bag or a redraw with exclusion.
			return (i+1)%weights.size() if i==previous and weights.size()>1 else i
	return 0

static func random_gain(volume: float, attenuation: float, draw: int) -> float:
	var unit:=f32(f32(float(draw))*0.0000000004656612873077393)
	return f32(clampf(f32(volume*f32(attenuation+f32(f32(1.0-attenuation)*unit))),0.0,1.0))

static func random_pitch(base: float, deviation: float, draw: int) -> float:
	var unit:=f32(f32(float(draw))*0.0000000004656612873077393)
	var signed_unit:=f32(f32(2.0*unit)-1.0)
	var exponent:=f32(f32(4.0*base)+f32(f32(4.0*deviation)*signed_unit))
	return f32(pow(2.0,exponent))

static func f32(value: float) -> float:
	var word:=PackedByteArray();word.resize(4);word.encode_float(0,value)
	return word.decode_float(0)
