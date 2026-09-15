extends Node
## Original state1 music selector2 resolves to the imported event145.
const Resources=preload("res://src/content/audio_resources.gd")
const Streams=preload("res://src/presentation/audio_stream_control.gd")
const EVENT_ID=145
var error:=""
var player: Node
var _active:=false
var _focused:=true

func _ready() -> void:_focused=get_window().has_focus()

func configure(library: RefCounted,bindings: RefCounted) -> bool:
	var resources:=Resources.new()
	if not resources.configure(library,bindings):error=resources.error;return false
	var clip: Dictionary=resources.prepare(EVENT_ID)
	if clip.has("unsupported") or not clip.get("stream") is AudioStream or clip.get("voice",false) or clip.get("spatial",true) or not clip.get("looping",false):
		error="The original menu music is unavailable: "+str(clip.get("unsupported","unsupported event shape"));return false
	var candidate:=Streams.player(clip.stream,false,"Music");candidate.volume_db=linear_to_db(clip.gain)
	if player!=null:player.free()
	player=candidate;add_child(player);error="";return true

func set_active(value: bool) -> void:
	_active=value
	if player==null:return
	if value:
		if not player.playing:player.play()
		player.stream_paused=not _focused
	else:player.stop()

func _notification(what: int) -> void:
	if what not in [MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN,MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT]:return
	_focused=what==MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN
	if player!=null and _active:player.stream_paused=not _focused
