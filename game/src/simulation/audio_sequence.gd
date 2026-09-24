extends RefCounted
## Native parameter windows and playlist choices; preparation has no playback effects.
const Envelopes=preload("res://src/content/audio_envelope.gd")
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
	_state={"elapsed_ms":0,"parameter":0.0,"started":false,"windows":{},"levels":{},"last_samples":{},"rng_state":random.state}

func prepare_step(delta_ms: int, external_value: Variant=null) -> Dictionary:
	error=""
	if _identity==null or delta_ms<0 or delta_ms>1000:
		error="Layered audio requires an initialized, bounded frame interval";return {}
	var next:=_state.duplicate(true)
	next.elapsed_ms+=delta_ms
	var previous_phase: float=float(next.parameter)
	var phase: float
	if _definition.parameter.get("control")=="external":
		if external_value!=null and (not (external_value is float or external_value is int) or not is_finite(float(external_value)) or float(external_value)<float(_definition.parameter.min) or float(external_value)>float(_definition.parameter.max)):
			error="Layered audio received an invalid source parameter";return {}
		phase=f32(float(next.parameter) if external_value==null else float(external_value)/float(_definition.parameter.max))
	else:
		if external_value!=null:error="Autonomous layered audio cannot take an external parameter";return {}
		# FEV velocity is in units/second. These supported parameters use range0..1.
		phase=f32(float(next.parameter)+f32(f32(float(delta_ms)/1000.0)*_definition.parameter.velocity))
		if phase>1.0:phase=f32(phase-1.0)
	next.parameter=phase
	var random:=RandomNumberGenerator.new();random.seed=_seed_value;random.state=next.rng_state
	var operations: Array[Dictionary]=[]
	for layer in _definition.layers:
		for sound in layer:
			var active: bool=phase>=sound.start and phase<=f32(sound.start+sound.width)
			var previous: bool=next.windows.get(sound.key,false)
			var crossed: bool=next.started and not sound.looping and phase>previous_phase and previous_phase<sound.start and phase>=sound.start
			var levels:=sound_levels(sound,phase)
			if (active or crossed) and not previous:
				var definition: Dictionary=sound.definition
				var last: int=next.last_samples.get(definition.id,-1)
				var choice:=sample(definition,random,last)
				next.last_samples[definition.id]=choice.playlist_index
				var base_gain:=f32(choice.gain*sound.volume)
				var base_pitch: float=choice.pitch
				choice.merge({"action":"start","key":sound.key,"gain":f32(base_gain*levels.gain),"pitch":f32(base_pitch*levels.pitch),"looping":sound.looping},true)
				operations.append(choice)
				next.levels[sound.key]={"gain":levels.gain,"pitch":levels.pitch,"base_gain":base_gain,"base_pitch":base_pitch}
			elif active and previous and next.levels.has(sound.key):
				var last_levels: Dictionary=next.levels[sound.key]
				if levels.gain!=last_levels.gain or levels.pitch!=last_levels.pitch:
					operations.append({"action":"update","key":sound.key,"gain":f32(last_levels.base_gain*levels.gain),"pitch":f32(last_levels.base_pitch*levels.pitch)})
					last_levels.gain=levels.gain;last_levels.pitch=levels.pitch
			elif previous and not active and sound.looping:
				operations.append({"action":"stop","key":sound.key})
				next.levels.erase(sound.key)
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

static func sound_levels(sound: Dictionary, phase: float) -> Dictionary:
	if not sound.has("envelope"):return {"gain":1.0,"pitch":1.0}
	var envelope: Dictionary=sound.envelope
	# The source drill has a repeated x position at its pitch step. At that
	# coordinate the later point wins; elsewhere the supplied linear segments
	# are evaluated by the same FEV scalar rules as the player engine.
	var points: Array=envelope.points
	for i in range(points.size()-1,0,-1):
		if phase==float(points[i][0]):
			var value:=float(points[i][1])
			return {"gain":value,"pitch":1.0} if int(envelope.flags)==12 else {"gain":1.0,"pitch":pow(2.0,8.0*value-4.0)}
	var value:=Envelopes.evaluate(envelope,phase)
	return {"gain":value,"pitch":1.0} if int(envelope.flags)==12 else {"gain":1.0,"pitch":value}

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

## Event variation is a separate raw-pitch offset, applied by the cached event's
## pitch setter. Supported flags use a continuous range without note quantization.
static func event_pitch(base: float, deviation: float, draw: int) -> float:
	var unit:=f32(f32(f32(float(draw))*2.0)*0.0000000004656612873077393)
	var offset:=f32(f32(unit*deviation)-deviation)
	return f32(pow(2.0,f32(f32(base+offset)*4.0)))

static func f32(value: float) -> float:
	var word:=PackedByteArray();word.resize(4);word.encode_float(0,value)
	return word.decode_float(0)
