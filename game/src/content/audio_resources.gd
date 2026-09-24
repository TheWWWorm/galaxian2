extends RefCounted
## Original clips, static playlists and verified parameter-controlled layers.
const Bank=preload("res://src/content/fsb5.gd")
const Definitions=preload("res://src/content/audio_definitions.gd")
const RadioVoice=preload("res://src/content/radio_audio_definitions.gd")
const Dialogue=preload("res://src/content/dialogue_definitions.gd")
const EngineParameters=preload("res://src/simulation/engine_audio.gd")
const Channels=preload("res://src/content/audio_channels.gd")
const StationPresentation=preload("res://src/content/station_presentation_definitions.gd")
const MiningStory=preload("res://src/content/ordinary_flight_definitions.gd")
const StationReturn=preload("res://src/content/ordinary_flight_definitions.gd")
const StationEquipment=preload("res://src/content/station_equipment_definitions.gd")
const TrainingStory=preload("res://src/content/combat_training_story_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
var error := ""
var unsupported := {}
var _library: RefCounted
var _definitions := {}
var _banks := {}
var _clips := {}
var _sound_cache := {}
var _channel_cache := {}
var _decoded_bytes := 0
var _language_index := 0
var _voice_ids := {}

func configure(library: RefCounted, bindings: RefCounted, campaign_cursor: int = 0) -> bool:
	error="";unsupported.clear();_banks.clear();_clips.clear();_sound_cache.clear();_channel_cache.clear();_decoded_bytes=0;_definitions={};_library=null
	_language_index=0;_voice_ids.clear()
	if library==null or bindings==null or bindings.base_content_id!=library.manifest.get("content_id"):return reject("Audio requires matching base content and bindings")
	if campaign_cursor not in [0,1,7,14,16,21,24,25,28,29]:return reject("Unsupported radio scene")
	var message:=Definitions.validate(bindings.audio,library.manifest.files)
	if not message.is_empty():return reject(message)
	if bindings.audio.is_empty():return reject("This binding pack has no audio declarations")
	_definitions=Definitions.normalized(bindings.audio);_library=library
	_language_index=int(_definitions.default_language)
	var dialogue: Dictionary=Dialogue.select(bindings,campaign_cursor)
	if campaign_cursor!=0 and not Dialogue.valid_parameters(dialogue,campaign_cursor):return reject("Scene radio is unavailable")
	var voice: Dictionary=dialogue.get("voice",{})
	if not voice.is_empty():
		if not RadioVoice.parameters(voice,dialogue.events.size()):return reject("Invalid radio voice capability")
		_language_index=_definitions.languages.find(RadioVoice.language(voice,library.active_language))
		if _language_index<0:return reject("The selected voice language is absent from the source event project")
		for id in voice.event_ids:
			if id>=0:_voice_ids[int(id)]=true
	return true

func prepare(id: int) -> Dictionary:
	error=""
	if id<0 or id>=_definitions.get("events",[]).size():reject("Audio event is absent from this content profile");return {}
	if _clips.has(id):return _clips[id]
	if unsupported.has(id):return {"unsupported":unsupported[id],"id":id}
	var event: Dictionary=_definitions.events[id]
	var p: Dictionary=event.properties
	if _voice_ids.has(id) and (event.categories!=["voice"] or p.mode!=0x180008 or p.max_playbacks!=1):return unavailable(id,"This radio mapping requires another voice event layout")
	if (event.has("sound") and event.get("simple_flags")!=1) or not compatible_category(event.categories,id):return unavailable(id,"This event needs additional native category or instance behavior")
	# The opening owner uses the source's cached handle per event. The authored
	# maximum across separately acquired instances does not create extra voices.
	if int(p.mode) not in [0x180008,0x280010] or p.pitch!=0 or not Definitions.number(p.pitch_random,0,1) or p.volume_random!=0 or not Definitions.integer(p.max_playbacks,1,3) or p.max_playbacks_behavior!=1 or int(p.flags) not in [0,0x80000]:return unavailable(id,"This event needs additional native playback behavior")
	for key in ["distance_filter","speaker_spread","position_random_min","position_random_max","spawn_random"]:
		if p.get(key)!=0:return unavailable(id,"This event needs additional native spatial behavior")
	# A unity outside volume leaves the entire cone unattenuated, including the
	# fourth ordinary engine's authored zero-degree inner cone.
	if not Definitions.number(p.get("cone_inside"),0,360) or p.get("cone_outside")!=360 or p.get("cone_outside_volume")!=1 or p.get("pan_level")!=1 or p.get("spawn_intensity")!=1:return unavailable(id,"Unsupported event cone, pan or spawn settings")
	if p.volume<0 or p.volume>4 or p.min_distance<0 or p.max_distance<=p.min_distance or p.fade_in_ms>60000 or p.fade_out_ms>60000:return unavailable(id,"Unsupported event level, range or fade")
	if not event.has("sound") and not event.parameters.is_empty():
		if p.pitch_random!=0:return unavailable(id,"Parameter-controlled event pitch variation is unsupported")
		if not EngineParameters.read_program(event).is_empty():return prepare_engine(id,event)
		if id==1:return prepare_mining_drill(id,event)
		return prepare_layered(id,event)
	return prepare_static(id,event)

func configure_station(library: RefCounted, bindings: RefCounted) -> bool:
	if not configure(library,bindings):return false
	if not StationPresentation.parameters(bindings.station_presentation):return reject("Station voice declarations are unavailable")
	_voice_ids.clear()
	for id in bindings.station_presentation.dialogue.voice_event_ids:_voice_ids[int(id)]=true
	return true

func configure_local_traffic(library: RefCounted, bindings: RefCounted) -> bool:
	if not configure(library,bindings):return false
	if not Travel.parameters(bindings.mido_travel):return reject("Local traffic voice declarations are unavailable")
	_voice_ids.clear()
	var radio: Dictionary=bindings.mido_travel.traffic_combat.radio
	for id in radio.warning_voice_ids+radio.response_voice_ids:_voice_ids[int(id)]=true
	return true

func configure_mining_briefing(library: RefCounted, bindings: RefCounted, campaign_cursor:=2) -> bool:
	if not configure(library,bindings):return false
	var rules:=MiningStory.briefing_presentation(bindings,campaign_cursor)
	if rules.is_empty():return reject("Mining voice declarations are unavailable")
	_voice_ids.clear()
	for event in rules.events:
		if event.voice_event_id>=0:_voice_ids[int(event.voice_event_id)]=true
	return true

func configure_mining_objective(library: RefCounted, bindings: RefCounted, campaign_cursor:=2) -> bool:
	if not configure(library,bindings):return false
	var rules:=MiningStory.objective(bindings,campaign_cursor)
	if rules.is_empty():return reject("Mining return voice declarations are unavailable")
	_voice_ids.clear()
	for event in rules.events:
		if event.voice_event_id>=0:_voice_ids[int(event.voice_event_id)]=true
	return true

func configure_campaign_visit(library: RefCounted,bindings: RefCounted,cursor: int,mission: Dictionary,station_only:=false) -> bool:
	var rules: Dictionary=load("res://src/content/free_campaign_definitions.gd").dialogue_rules(bindings,cursor,mission,station_only)
	return _configure_campaign(library,bindings,rules)

func configure_campaign_result(library: RefCounted,bindings: RefCounted,cursor: int,mission: Dictionary,failed:=false) -> bool:
	var rules: Dictionary=load("res://src/content/free_campaign_definitions.gd").result_presentation(bindings,cursor,mission,failed)
	return _configure_campaign(library,bindings,rules)

func _configure_campaign(library: RefCounted,bindings: RefCounted,rules: Dictionary) -> bool:
	if not configure(library,bindings):return false
	if rules.is_empty():return reject("Campaign voices are unavailable")
	_voice_ids.clear()
	for event in rules.events:
		if event.voice_event_id>=0:_voice_ids[int(event.voice_event_id)]=true
	return true

func configure_training_completion(library: RefCounted, bindings: RefCounted) -> bool:
	if not configure(library,bindings) or not TrainingStory.parameters(bindings.combat_training_story):return reject("Training completion voice is unavailable")
	_voice_ids.clear()
	for event in bindings.combat_training_story.completion_events:_voice_ids[int(event.voice_event_id)]=true
	return true

func configure_station_return(library: RefCounted, bindings: RefCounted, campaign_cursor:=3) -> bool:
	if not configure(library,bindings):return false
	var rules:=StationReturn.station_conversation(bindings,campaign_cursor)
	if rules.is_empty():return reject("Station return voice declarations are unavailable")
	_voice_ids.clear()
	for event in rules.events:
		if event.voice_event_id>=0:_voice_ids[int(event.voice_event_id)]=true
	return true

func configure_station_equipment(library: RefCounted, bindings: RefCounted) -> bool:
	if not configure(library,bindings):return false
	if not StationEquipment.parameters(bindings.station_equipment):return reject("Equipment tutorial voice is unavailable")
	_voice_ids.clear()
	for event in bindings.station_equipment.events:_voice_ids[int(event.voice_event_id)]=true
	return true

func prepare_engine(id: int, event: Dictionary) -> Dictionary:
	var program:=EngineParameters.read_program(event)
	if program.is_empty() or event.properties.mode!=0x280010 or event.properties.doppler!=0 or event.properties.max_playbacks!=1 or event.properties.flags!=0:return unavailable(id,"This engine needs additional spatial or instance behavior")
	var definition:=cached_playlist(int(program.sound_definition),true)
	if definition.is_empty():return {}
	if definition.has("unsupported"):return unavailable(id,definition.unsupported)
	if definition.samples.size()!=1 or definition.volume!=1 or definition.attenuation!=1 or definition.pitch!=0 or definition.pitch_random!=0:return unavailable(id,"This engine needs additional sample-selection behavior")
	var loaded: Dictionary=definition.samples[0]
	if not loaded.stream is AudioStreamWAV:return unavailable(id,"This engine needs decoded stereo PCM for speaker spread")
	var channels: Array=_channel_cache.get(int(program.sound_definition),[])
	if channels.is_empty():
		var bytes: int=loaded.stream.data.size()
		if _decoded_bytes+bytes>128*1024*1024:return unavailable(id,"The current decoded audio budget is full")
		channels=Channels.split_stereo(loaded.stream)
		if channels.is_empty():return unavailable(id,"This engine has unsupported channel or loop data")
		_decoded_bytes+=bytes;_channel_cache[int(program.sound_definition)]=channels
	var result:=event_header(event)
	result.merge(loaded);result.merge({"kind":"parameter_loop","program":program,"channels":channels,"looping":true})
	_clips[id]=result
	return result

func prepare_static(id: int, event: Dictionary) -> Dictionary:
	var sound: Dictionary
	if event.has("sound"):sound=event.sound
	else:
		if event.type!=8 or event.layers.size()!=1:return unavailable(id,"This event needs additional native layer behavior")
		var layer: Dictionary=event.layers[0]
		if layer.flags!=2 or layer.priority!=65535 or layer.parameter!=65535 or not layer.envelopes.is_empty() or layer.sounds.size()!=1:return unavailable(id,"This static event needs additional native layer behavior")
		sound=layer.sounds[0]
	# Terran exploration music is a simple, parameter-free event whose source
	# box ends at 0.995. With no parameter cursor that width cannot schedule it.
	var terran_music_box: bool=id==134 and event.get("type")==16 and event.get("categories")==["music"] and absf(float(sound.width)-0.9950000047683716)<0.0000001
	# Designer mode 2 loops while the firing event is held, then plays the
	# current sample to its end. The supplied cannon events use this mode.
	if int(sound.flags) not in [0,1,2] or sound.flags2!=0 or sound.loop_count!=-1 or sound.auto_pitch!=0 or sound.fine_tune!=0 or sound.volume<0 or sound.volume>4 or float(sound.fade_in) not in [-1.0,0.0] or float(sound.fade_out) not in [-1.0,0.0] or sound.x!=0 or (sound.width!=1 and not terran_music_box):return unavailable(id,"This sound requires native scheduling or parameter automation")
	if sound.flags==0 and event.properties.max_playbacks!=1:return unavailable(id,"This loop needs additional native instance behavior")
	var looping: bool=sound.flags!=1
	var definition:=cached_playlist(int(sound.sound_def),looping)
	if definition.is_empty():return {}
	if definition.has("unsupported"):return unavailable(id,definition.unsupported)
	var result:=event_header(event)
	result.gain*=float(sound.volume);result.looping=looping
	if sound.flags==2:
		if definition.samples.size()!=1:return unavailable(id,"Play-to-end loops require one authored sample")
		result.release_at_sample_end=true
	if definition.samples.size()==1 and definition.volume==1 and definition.attenuation==1 and definition.pitch==0 and definition.pitch_random==0:
		result.merge(definition.samples[0])
	else:result.merge({"kind":"playlist","definition":definition})
	_clips[id]=result
	return result

func load_sample(entry: Dictionary, looping: bool) -> Dictionary:
	var variant: Dictionary=_definitions.banks[int(entry.bank)].variants[_language_index]
	var bank: RefCounted=_banks.get(variant.resource)
	if bank==null:
		var bytes: PackedByteArray=_library.read_resource(variant.resource,Bank.MAX_BYTES)
		if bytes.is_empty():reject(_library.error);return {}
		bank=Bank.new()
		if not bank.open(bytes):reject(bank.error);return {}
		if _banks.size()>=4:return {"unsupported":"The current audio session bank budget is full"}
		_banks[variant.resource]=bank
	if bank.hash_prefix!=variant.hash_prefix:reject("The FEV event refers to another sound bank");return {}
	if int(entry.index)>=bank.samples.size():reject("Audio sample is absent from the selected bank");return {}
	var sample: Dictionary=bank.samples[int(entry.index)]
	# MP3 supports a start offset; a partial authored loop end requires a separate
	# bounded decoder. Do not silently turn it into a full-file loop.
	if looping and bank.codec==11 and sample.loop_end!=sample.samples:return {"unsupported":"Partial MPEG loop endpoints are not connected yet"}
	var decoded_size: int=int(sample.samples)*int(sample.channels)*2 if bank.codec!=11 else 0
	if _decoded_bytes+decoded_size>128*1024*1024:return {"unsupported":"The current decoded audio budget is full"}
	var stream: AudioStream
	if bank.codec==7:
		var pcm: PackedByteArray=_library.cached_audio_pcm(variant.resource,int(entry.index),decoded_size)
		if not pcm.is_empty():
			var wav:=AudioStreamWAV.new()
			wav.format=AudioStreamWAV.FORMAT_16_BITS
			wav.stereo=sample.channels==2;wav.mix_rate=sample.rate;wav.data=pcm
			wav.loop_mode=AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
			wav.loop_begin=sample.loop_start;wav.loop_end=sample.loop_end
			stream=wav
	if stream==null:
		stream=bank.stream(int(entry.index),looping)
		if stream!=null and bank.codec==7:_library.remember_audio_pcm(variant.resource,int(entry.index),(stream as AudioStreamWAV).data)
	if stream==null:reject(bank.error);return {}
	_decoded_bytes+=decoded_size
	return {"stream":stream,"source_bank":variant.resource,"source_index":int(entry.index),"sample":sample.duplicate(true)}

func event_header(event: Dictionary) -> Dictionary:
	var p: Dictionary=event.properties
	var result:={"id":int(event.id),"name":event.path,"gain":float(p.volume),
		"spatial":p.mode==0x280010,"min_distance":float(p.min_distance),"max_distance":float(p.max_distance),
		"fade_in_ms":int(p.fade_in_ms),"fade_out_ms":int(p.fade_out_ms),
		"voice":_voice_ids.has(int(event.id)) and event.categories==["voice"]}
	if p.pitch_random!=0:result.event_pitch_random=float(p.pitch_random)
	return result

func prepare_layered(id: int, event: Dictionary) -> Dictionary:
	if event.get("type")!=8 or event.properties.flags!=0 or event.parameters.size()!=1 or event.layers.is_empty() or event.layers.size()>8:return unavailable(id,"This event needs additional native layer or parameter behavior")
	var parameter: Variant=event.parameters[0]
	if not parameter is Dictionary or parameter.get("flags")!=9 or parameter.get("min")!=0 or parameter.get("max")!=1 or not Definitions.number(parameter.get("velocity"),0.000001,1) or parameter.get("seek_speed")!=0 or parameter.get("envelopes")!=0 or parameter.get("sustain_points")!=[]:return unavailable(id,"This event needs additional native parameter behavior")
	var layers: Array=[]
	var count:=0
	for layer in event.layers:
		if layer.get("flags")!=2 or layer.get("priority")!=65535 or layer.get("parameter")!=0 or not layer.envelopes.is_empty():return unavailable(id,"This event needs layer effects or additional control parameters")
		var sounds: Array=[]
		var previous_end:=-1.0
		for sound in layer.sounds:
			count+=1
			if count>32 or not Definitions.number(sound.x,0,1) or not Definitions.number(sound.width,0.000001,1) or sound.x<previous_end or sound.x+sound.width>1.0000001:return unavailable(id,"Overlapping or unbounded audio parameter windows are unsupported")
			previous_end=sound.x+sound.width
			if int(sound.flags) not in [0,1] or sound.flags2!=0 or sound.loop_count!=-1 or sound.auto_pitch!=0 or sound.fine_tune!=0 or sound.volume<0 or sound.volume>1 or float(sound.fade_in) not in [-1.0,0.0] or float(sound.fade_out) not in [-1.0,0.0]:return unavailable(id,"This layer requires additional instance automation")
			var prepared:=cached_playlist(int(sound.sound_def),sound.flags==0)
			if prepared.is_empty():return {}
			if prepared.has("unsupported"):return unavailable(id,prepared.unsupported)
			sounds.append({"key":str(layers.size())+":"+str(sounds.size()),"start":float(sound.x),"width":float(sound.width),"volume":float(sound.volume),"looping":sound.flags==0,"definition":prepared})
		layers.append(sounds)
	var result:=event_header(event)
	result.merge({"kind":"layered","parameter":{"velocity":float(parameter.velocity)},"layers":layers,"looping":true})
	_clips[id]=result
	return result

func prepare_mining_drill(id: int, event: Dictionary) -> Dictionary:
	# Both Mac projects use the same four-layer, externally controlled drill.
	# Its parameter windows are stored normalized even though drill_speed is 0..3.
	if event.get("name")!="Mining_Drill" or event.get("type")!=8 or event.properties.flags!=0 or event.properties.mode!=0x180008 or event.properties.max_playbacks!=1 or event.parameters.size()!=1 or event.layers.size()!=4:
		return unavailable(id,"The original drill event has an unsupported instance layout")
	var parameter: Variant=event.parameters[0]
	if not parameter is Dictionary or parameter.get("name")!="drill_speed" or parameter.get("flags")!=3 or parameter.get("min")!=0 or parameter.get("max")!=3 or parameter.get("velocity")!=0 or parameter.get("seek_speed")!=0 or parameter.get("envelopes")!=3 or parameter.get("sustain_points")!=[]:
		return unavailable(id,"The original drill parameter differs from its recovered range")
	var layers: Array=[]
	for layer_index in event.layers.size():
		var layer: Variant=event.layers[layer_index]
		if not layer is Dictionary or layer.get("flags")!=2 or layer.get("priority")!=65535 or layer.get("parameter")!=0 or not layer.get("sounds") is Array or not layer.get("envelopes") is Array:
			return unavailable(id,"The original drill layer has unsupported controls")
		if layer.sounds.size()!=(3 if layer_index==3 else 1) or layer.envelopes.size()!=(0 if layer_index==2 else 1):
			return unavailable(id,"The original drill layer count changed")
		var effect: Dictionary={}
		if not layer.envelopes.is_empty():
			effect=layer.envelopes[0]
			var target: int=12 if layer_index==3 else 20
			if effect.get("flags")!=target or effect.get("parameter_index")!=0 or effect.get("dsp")!="" or effect.get("dsp_parameter")!=0 or effect.get("flags2")!=0 or effect.get("trailing")!=0 or effect.get("name_index")!=65535 or effect.get("parent_index")!=65535 or not effect.get("points") is Array or effect.points.is_empty() or effect.points.size()>8:
				return unavailable(id,"The original drill envelope uses another effect")
			var previous:=-1.0
			for point in effect.points:
				if not point is Array or point.size()!=3 or not Definitions.number(point[0],0,1) or not Definitions.number(point[1],0,1) or point[2]!=2 or point[0]<previous:
					return unavailable(id,"The original drill envelope has unsupported points")
				previous=float(point[0])
			if effect.points[0][0]!=0:return unavailable(id,"The original drill envelope has no starting value")
		var sounds: Array=[]
		for sound in layer.sounds:
			if not Definitions.number(sound.get("x"),0,1) or not Definitions.number(sound.get("width"),0.000001,2) or not Definitions.number(sound.get("volume"),0,1) or int(sound.get("flags",-1))!=(1 if layer_index==3 else 0) or sound.get("flags2")!=0 or sound.get("loop_count")!=-1 or sound.get("auto_pitch")!=0 or sound.get("fine_tune")!=0 or float(sound.get("fade_in",0))!=-1 or float(sound.get("fade_out",0))!=-1:
				return unavailable(id,"The original drill sound needs another scheduling behavior")
			var prepared:=cached_playlist(int(sound.sound_def),layer_index!=3)
			if prepared.is_empty():return {}
			if prepared.has("unsupported"):return unavailable(id,prepared.unsupported)
			var row:={"key":str(layer_index)+":"+str(sounds.size()),"start":float(sound.x),"width":float(sound.width),"volume":float(sound.volume),"looping":layer_index!=3,"definition":prepared}
			if not effect.is_empty():row["envelope"]=effect
			sounds.append(row)
		layers.append(sounds)
	var result:=event_header(event)
	result.merge({"kind":"layered","parameter":{"control":"external","min":0.0,"max":3.0},"layers":layers,"looping":true})
	_clips[id]=result
	return result

func cached_playlist(id: int, looping: bool) -> Dictionary:
	var key:=str(id)+":"+str(looping)
	if _sound_cache.has(key):return _sound_cache[key]
	var result:=prepare_playlist(id,looping)
	if not result.is_empty() and not result.has("unsupported"):_sound_cache[key]=result
	return result

func prepare_playlist(id: int, looping: bool) -> Dictionary:
	var definition: Dictionary=_definitions.sound_definitions[id]
	var settings: Dictionary=_definitions.sound_settings[int(definition.settings)]
	if definition.entries.is_empty() or definition.entries.size()>32 or int(settings.playlist_flags) not in [0,3,8,9] or not Definitions.integer(settings.maximum_polyphony,1,4):return {"unsupported":"This playlist needs additional selection or polyphony behavior"}
	for key in ["spawn_min_ms","spawn_max_ms","pitch_min","pitch_max","pitch_recalc","position_random_min","position_random_max","trigger_delay_min","trigger_delay_max","spawn_count"]:
		if settings.get(key)!=0:return {"unsupported":"This playlist needs additional spawning or automation"}
	for key in ["volume_min","volume_max","volume_random_method","pitch_random_method"]:
		if settings.get(key)!=1:return {"unsupported":"This playlist needs another randomization method"}
	if not Definitions.number(settings.volume,0,1) or not Definitions.number(settings.volume_random,0,1) or not Definitions.number(settings.pitch,-1,1) or not Definitions.number(settings.pitch_random,0,1):return {"unsupported":"Unsupported playlist level or pitch range"}
	var samples: Array=[]
	var weights: Array=[]
	for entry in definition.entries:
		if entry.type!=0 or not Definitions.integer(entry.weight,1,10000):return {"unsupported":"Only positive-weight sample playlists are connected"}
		var loaded:=load_sample(entry,looping)
		if loaded.is_empty() or loaded.has("unsupported"):return loaded
		samples.append(loaded);weights.append(int(entry.weight))
	return {"id":id,"playlist_flags":int(settings.playlist_flags),"samples":samples,"weights":weights,"volume":float(settings.volume),"attenuation":float(settings.volume_random),"pitch":float(settings.pitch),"pitch_random":float(settings.pitch_random)}

func compatible_category(names: Array, id: int) -> bool:
	# Ordinary effects use neutral categories. Only source-bound opening lines
	# join the verified two-voice category with immediate oldest-instance stealing.
	if names.size()!=1:return false
	var master: Dictionary=_definitions.categories
	if master.name!="master" or master.volume!=1 or master.pitch!=0 or master.max_playbacks!=0 or master.flags!=0:return false
	for category in master.children:
		if category.name==names[0]:
			var limit:=2 if category.name=="voice" and _voice_ids.has(id) else 0
			return category.volume==1 and category.pitch==0 and category.max_playbacks==limit and category.flags==0 and category.children.is_empty()
	return false

func unavailable(id: int, message: String) -> Dictionary:
	unsupported[id]=message
	return {"unsupported":message,"id":id}

func reject(message: String) -> bool:
	error=message
	return false
