extends Node3D
## A native stereo loop with source scalar envelopes and angular channel spread.
## The caller owns event fades, distance attenuation and accepted-frame timing.
const Parameters=preload("res://src/simulation/engine_audio.gd")
const Streams=preload("res://src/presentation/audio_stream_control.gd")
var error:=""
var volume_db: float=0.0:
	set(value):
		volume_db=value
		refresh_levels()
var pitch_scale: float=1.0:
	set(value):
		pitch_scale=value
		refresh_levels()
var stream_paused: bool=false:
	set(value):
		stream_paused=value
		for record in _channels:Streams.pause(record,value)
var playing: bool:
	get:
		return _channels.any(func(record):return record.node.playing or record.pending_resume)
var _program:={}
var _parameters: Array=[]
var _levels:={}
var _channels: Array[Dictionary]=[]
var _source:=Vector3.ZERO
var _listener:=Transform3D.IDENTITY

func configure(clip: Dictionary) -> bool:
	clear()
	if clip.get("kind")!="parameter_loop" or not clip.get("channels") is Array or clip.channels.size()!=2 or not clip.get("program") is Dictionary:return reject("Invalid parameter-controlled stereo clip")
	for channel in clip.channels:
		if not channel is AudioStreamWAV or channel.stereo or channel.format!=AudioStreamWAV.FORMAT_16_BITS or channel.loop_mode!=AudioStreamWAV.LOOP_FORWARD:return reject("Parameter loops require decoded mono PCM channels")
	var left: AudioStreamWAV=clip.channels[0];var right: AudioStreamWAV=clip.channels[1]
	if left.data.is_empty() or left.data.size()%2!=0 or left.data.size()!=right.data.size() or left.mix_rate!=right.mix_rate or left.loop_begin!=right.loop_begin or left.loop_end!=right.loop_end:return reject("Stereo loop channels must share their sample clock and loop")
	if left.loop_begin<0 or left.loop_end<=left.loop_begin or left.loop_end>left.data.size()/2:return reject("Invalid stereo loop range")
	var initial: Array=[0.0,0.0,0.0]
	var evaluated:=Parameters.evaluate(clip.program,initial)
	if evaluated.is_empty():return reject("Unsupported parameter loop envelopes")
	_program=clip.program.duplicate(true);_parameters=initial;_levels=evaluated
	# Positions are virtual speaker-space directions around the listener. Event
	# attenuation remains tied to the actual source in the owning audio scene.
	top_level=true;transform=Transform3D.IDENTITY
	for channel in clip.channels:
		var node:=Streams.player(channel,true)
		add_child(node)
		_channels.append({"node":node,"pending_resume":false,"resume_position":0.0})
	refresh_positions();refresh_levels()
	return true

func set_parameters(values: Array) -> bool:
	error=""
	var next:=Parameters.evaluate(_program,values)
	if next.is_empty():return reject("Invalid parameter loop values")
	_parameters=values.duplicate();_levels=next
	refresh_positions();refresh_levels()
	return true

static func valid_context(source: Vector3, listener: Transform3D) -> bool:
	return source.is_finite() and listener.is_finite() and absf(listener.basis.determinant())>0.000001

static func channel_positions(source: Vector3, listener: Transform3D, spread_degrees: float) -> Array:
	if not valid_context(source,listener) or not is_finite(spread_degrees) or spread_degrees<0 or spread_degrees>360:return []
	var local: Vector3=listener.basis.inverse()*(source-listener.origin)
	if not local.is_finite():return []
	# The native coincident-source policy faces forward. Stereo panning ignores
	# elevation; surround output uses Godot's own speaker-placement panner.
	var azimuth:=atan2(local.x,-local.z) if local.x!=0.0 or local.z!=0.0 else 0.0
	var half:=deg_to_rad(spread_degrees)*0.5
	var result: Array=[]
	for angle in [azimuth-half,azimuth+half]:
		var position: Vector3=listener.origin+listener.basis*Vector3(sin(angle),0,-cos(angle))
		if not position.is_finite():return []
		result.append(position)
	return result

func set_spatial(source: Vector3, listener: Transform3D) -> bool:
	error=""
	if _levels.is_empty() or channel_positions(source,listener,float(_levels.spread_degrees)).is_empty():return reject("Invalid parameter loop spatial context")
	_source=source;_listener=listener;refresh_positions()
	return true

func refresh_positions() -> void:
	if _channels.is_empty():return
	var positions:=channel_positions(_source,_listener,float(_levels.spread_degrees))
	for i in _channels.size():_channels[i].node.position=positions[i]

func refresh_levels() -> void:
	if _levels.is_empty():return
	var gain:=db_to_linear(volume_db)*float(_levels.gain)
	for record in _channels:
		record.node.volume_db=linear_to_db(gain) if gain>0 else -80.0
		record.node.pitch_scale=pitch_scale*float(_levels.pitch)

func play(from_position: float=0.0) -> void:
	for record in _channels:
		record.resume_position=from_position
		record.pending_resume=stream_paused
		if not stream_paused:record.node.play(from_position)

func stop() -> void:
	for record in _channels:
		record.node.stop();record.pending_resume=false;record.resume_position=0.0

func get_playback_position() -> float:
	if _channels.is_empty():return 0.0
	var record: Dictionary=_channels[0]
	return float(record.resume_position) if record.pending_resume else record.node.get_playback_position()

func snapshot() -> Dictionary:
	var channels: Array=[]
	for record in _channels:
		channels.append({"position":record.node.position,"cursor":record.node.get_playback_position(),"gain_db":record.node.volume_db,"pitch":record.node.pitch_scale,"pending_resume":record.pending_resume})
	return {"parameters":_parameters.duplicate(),"levels":_levels.duplicate(),"source_position":_source,"listener":_listener,"channels":channels,"playing":playing,"paused":stream_paused}

func clear() -> void:
	for record in _channels:
		record.node.stop();record.node.free()
	_channels=[];_program={};_parameters=[];_levels={};_source=Vector3.ZERO;_listener=Transform3D.IDENTITY
	volume_db=0.0;pitch_scale=1.0;stream_paused=false;error=""

func reject(message: String) -> bool:
	error=message;return false

func _exit_tree() -> void:stop()
