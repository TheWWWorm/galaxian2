extends Control
## Normal player entry; resource inspectors remain an explicit development mode.
const PlayerFrontend=preload("res://src/presentation/player_frontend.gd")
const DevelopmentLauncher=preload("res://src/presentation/development_launcher.gd")
const INSPECTOR_OPTIONS=["--inspect","--asset","--resource-id","--station-id","--ship-id","--radio-preview","--opening-preview"]
var frontend: Control

func _ready() -> void:
	get_tree().auto_accept_quit=false
	get_window().close_requested.connect(_request_close)
	var args:=OS.get_cmdline_user_args()
	if INSPECTOR_OPTIONS.any(func(option):return option in args):
		frontend=DevelopmentLauncher.new();add_child(frontend)
		frontend.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	frontend=PlayerFrontend.new();add_child(frontend)
	frontend.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frontend.exit_requested.connect(func():get_tree().quit())
	frontend.boot(args)

func _request_close() -> void:
	if frontend.has_method("request_close"):frontend.request_close()
	else:get_tree().quit()
