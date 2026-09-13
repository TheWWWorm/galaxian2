extends Node3D
## One native event with independently playing source sound instances.
const Sequence=preload("res://src/simulation/audio_sequence.gd")
const Streams=preload("res://src/presentation/audio_stream_control.gd")
var error := ""
var _definition := {}
var _sequence: RefCounted
var _voices := {}
var _history: Array[Dictionary]=[]
var _running := false
var _paused := false
var _volume_db := 0.0
var volume_db: float:
	get:return _volume_db
	set(value):
		_volume_db=value
		for voice in _voices.values():voice.node.volume_db=_volume_db+voice.gain_db
var stream_paused: bool:
	get:return _paused
	set(value):
		_paused=value
		for voice in _voices.values():Streams.pause(voice,value)
var playing: bool:
	get:return _running

func configure(definition: Dictionary, seed_value: int) -> void:
	_definition=definition
	_sequence=Sequence.new();_sequence.configure(definition,seed_value)

func play(_from_position: float=0.0) -> void:
	_running=true
	commit_step(_sequence.prepare_step(0))

func prepare_step(delta_ms: int) -> Dictionary:
	error=""
	if not _running or _paused:return {"repeat":true}
	var frame: Dictionary=_sequence.prepare_step(delta_ms)
	if frame.is_empty():error=_sequence.error
	return frame

func commit_step(frame: Dictionary) -> void:
	if frame.get("repeat",false) or not _sequence.commit_step(frame):return
	for op in frame.operations:
		stop_voice(op.key)
		if op.action=="start":
			var node:=Streams.player(op.sample.stream,_definition.spatial)
			var gain_db: float=linear_to_db(op.gain) if op.gain>0 else -80.0
			var voice:={"node":node,"gain_db":gain_db,"pending_resume":false,"resume_position":0.0,"source_bank":op.sample.source_bank,"source_index":op.sample.source_index,"pitch":op.pitch}
			add_child(node);_voices[op.key]=voice
			node.pitch_scale=op.pitch;node.volume_db=_volume_db+gain_db
			node.finished.connect(_voice_finished.bind(op.key,node))
			if _paused:voice.pending_resume=true
			else:node.play()
		var row: Dictionary=op.duplicate();row.erase("sample");row.elapsed_ms=_sequence.snapshot().elapsed_ms
		_history.append(row)
		if _history.size()>64:_history.pop_front()

func stop_voice(key: String) -> void:
	if not _voices.has(key):return
	var voice: Dictionary=_voices[key]
	voice.node.stop();voice.node.queue_free();_voices.erase(key)

func _voice_finished(key: String, node: Node) -> void:
	if _voices.has(key) and _voices[key].node==node:stop_voice(key)

func get_playback_position() -> float:
	return float(_sequence.snapshot().elapsed_ms)/1000.0 if _sequence!=null else 0.0

func stop() -> void:
	_running=false
	for key in _voices.keys():stop_voice(key)

func snapshot() -> Dictionary:
	var voices:={}
	for key in _voices:
		var voice: Dictionary=_voices[key]
		voices[key]={"source_bank":voice.source_bank,"source_index":voice.source_index,"pitch":voice.pitch,"gain_db":voice.node.volume_db,"paused":voice.node.stream_paused or voice.pending_resume,"playing":voice.node.playing}
	return {"sequence":_sequence.snapshot() if _sequence!=null else {},"voices":voices,"history":_history.duplicate(true),"paused":_paused,"playing":_running}

func _exit_tree() -> void:
	stop()
