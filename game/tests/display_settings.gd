extends SceneTree
const Preferences=preload("res://src/content/player_preferences.gd")
const DisplaySettings=preload("res://src/presentation/display_settings.gd")
const Frontend=preload("res://src/presentation/player_frontend.gd")
const PathGuard=preload("res://tests/fixtures/free_play_station_scenario.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var directory:=OS.get_environment("GOF2_DISPLAY_TEST_DIRECTORY")
	if directory.is_empty() or not PathGuard.private_path(directory+"/player.json"):
		check(false,"Supply a private display test directory");quit(1);return
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("player.json")
	check(not FileAccess.file_exists(path),"Use a fresh display test directory")
	var original:=Preferences.defaults();original.schema=1
	for key in Preferences.DISPLAY_KEYS+["mouse_steering","mouse_sensitivity"]:original.erase(key)
	original.content="/example/content";original.import_record="/example/installation.json";original.music=0.4;original.invert_pitch=true
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(original));file.close()
	var prefs:=Preferences.new();check(prefs.read_file(path),prefs.error)
	for key in original:
		if key!="schema":check(prefs.values[key]==original[key],"Preferences upgrade lost "+key)
	check(prefs.values.schema==2 and prefs.values.mouse_steering,"Preferences upgrade omitted desktop controls")
	for pair in [["resolution","0x0"],["aspect_ratio","portrait"],["frame_rate",true],["frame_rate",61],["mouse_sensitivity",NAN],["mouse_sensitivity",0],["window_mode","invalid"]]:
		var invalid:=prefs.values.duplicate();invalid[pair[0]]=pair[1]
		check(not Preferences.valid(invalid),"Invalid display/input preference accepted: "+pair[0])
	var settings:=DisplaySettings.new()
	root.unfocusable=true
	settings.apply(root,prefs.values)
	for rate in Preferences.FRAME_RATES:
		prefs.values.frame_rate=rate;settings.apply(root,prefs.values)
		check(Engine.max_fps==maxi(0,rate),"Frame cap was not applied")
		if DisplayServer.get_name()!="headless":check(DisplayServer.window_get_vsync_mode()==(DisplayServer.VSYNC_ENABLED if rate==-1 else DisplayServer.VSYNC_DISABLED),"Frame choice did not update V-Sync")
	prefs.values.frame_rate=0;prefs.values.resolution="native";prefs.values.aspect_ratio="native";prefs.values.mouse_sensitivity=1.7
	check(prefs.save_file(path,prefs.values),prefs.error)
	var restarted:=Preferences.new();check(restarted.read_file(path) and restarted.values==prefs.values,"Restart lost display or mouse settings")
	for native in [Vector2i(1920,1080),Vector2i(3024,1964),Vector2i(3440,1440),Vector2i(8000,5120)]:
		check(DisplaySettings.resolution_size("native",native)==native,"Native resolution was reduced to a preset")
		check(DisplaySettings.aspect_size(native,"native",native)==native,"Native aspect ratio added bars")
	check(DisplaySettings.aspect_size(Vector2i(1600,900),"16:10",Vector2i(1920,1080))==Vector2i(1440,900),"Fixed aspect ratio distorted geometry")
	check(DisplaySettings.fit_size(Vector2i(3840,2160),Vector2i(1600,900))==Vector2i(1600,900),"Oversized window escaped the screen")
	root.size_changed.disconnect(settings.refresh_aspect)
	var args:=OS.get_cmdline_user_args()
	if args.size()>=3:await check_options(args,directory)
	Engine.max_fps=0
	print("Display/settings: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func check_options(args: PackedStringArray,directory: String) -> void:
	var app:=Frontend.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.boot(PackedStringArray(),directory.path_join("ui"))
	var selection:=Preferences.defaults();selection.content=args[0];selection.bindings=args[1];selection.visuals=args[2]
	if not app.select_content(selection):check(false,app.error);app.free();return
	app.show_options()
	app._settings_controls.frame_rate.select(Preferences.FRAME_RATES.find(0))
	app._settings_controls.frame_rate.item_selected.emit(Preferences.FRAME_RATES.find(0))
	check(app.preferences.values.frame_rate==0 and Engine.max_fps==0,"Unlimited option did not reach the renderer")
	for size in [Vector2i(1280,800),Vector2i(1440,600)]:
		root.size=size
		app.change_preference("aspect_ratio","auto")
		await process_frame;await process_frame;await process_frame
		check(root.content_scale_size==Vector2i.ZERO and Vector2i(app.size)==root.size,"Automatic aspect did not fill the window at native pixels")
		check(app.get_global_rect().encloses(app._details.get_global_rect()),"Options escaped the resized window")
		if args.size()>3 and DisplayServer.get_name()!="headless":
			DirAccess.make_dir_recursive_absolute(args[3]);RenderingServer.force_draw(false);await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(args[3].path_join("options-%dx%d.png"%[size.x,size.y]))==OK,"Could not capture options")
	app.change_preference("aspect_ratio","16:10");await process_frame;await process_frame
	check(absf(app.size.x/app.size.y-1.6)<0.002,"Fixed aspect ratio stretched the UI")
	app.free();await process_frame

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
