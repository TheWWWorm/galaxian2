extends SceneTree
## Isolated original-art menu control checks. The plain background is a fixture.
const MenuView=preload("res://src/presentation/main_menu_panel.gd")
const MenuAudio=preload("res://src/presentation/main_menu_audio.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const PrivatePath=preload("res://tests/fixtures/free_play_station_scenario.gd")
var checks:=0
var failures:=0
var requests: Array[String]=[]
var captures:=""
var panel: Control

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [3,4]:check(false,"Expected content, bindings, visuals and optional captures");quit(1);return
	if args.size()==4:
		captures=args[3]
		if not PrivatePath.private_path(captures+"/menu.png"):check(false,"Keep menu captures outside engine source");quit(1);return
		DirAccess.make_dir_recursive_absolute(captures)
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not visuals.open(args[2],library.manifest):check(false,library.error+bindings.error+visuals.error);quit(1);return
	var background:=ColorRect.new();background.color=Color(.015,.026,.042);background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(background);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel=MenuView.new();root.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.action_requested.connect(func(action):requests.append(action))
	if not panel.configure(library,bindings,visuals):check(false,panel.error);quit(1);return
	panel.present(false,false);await process_frame
	var music:=MenuAudio.new();root.add_child(music)
	if not music.configure(library,bindings):check(false,music.error)
	else:
		music.set_active(true)
		check(music.player.playing and music.player.bus=="GoF2 Music","Menu did not start its original music in the music category")
		music._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(music.player.stream_paused,"Menu music continued after focus loss")
		music.set_active(false);check(not music.player.playing,"Menu music survived leaving the menu")
	music.free()
	check(not panel._buttons.resume.visible and panel._buttons.load.disabled and panel._buttons.supernova.disabled,"A fresh menu offered a nonexistent resume/load or unfinished challenge")
	panel._buttons.supernova.pressed.emit();panel._buttons.load.pressed.emit();panel._buttons.resume.pressed.emit()
	check(requests.is_empty(),"An unavailable menu action was dispatched")
	panel.present(true,true);await process_frame
	var key:=InputEventKey.new();key.physical_keycode=KEY_1;key.pressed=true
	panel._unhandled_key_input(key)
	check(requests==["new_game"],"The numbered menu shortcut dispatched the wrong action")
	for action in ["resume","load","options","language","info"]:
		panel._buttons[action].pressed.emit();check(requests.back()==action,"A menu button dispatched another action: "+action)
	panel._exit.pressed.emit();check(requests.back()=="exit","The original Exit action was not connected")
	var previous:=requests.duplicate();panel.hide();panel._unhandled_key_input(key);panel._buttons.new_game.pressed.emit()
	check(requests==previous,"Hidden menu controls dispatched an action")
	panel.show();var accepted: Dictionary=panel.snapshot()
	check(not panel.configure(library,bindings,Visuals.new()) and panel.snapshot().identity==accepted.identity and panel._logo.texture!=null,"Failed menu preparation discarded its accepted artwork")
	panel.present(true,true);await capture("main-menu-desktop")
	for language in library.manifest.languages:
		if not library.select_language(language) or not panel.configure(library,bindings,visuals):check(false,library.error+panel.error);continue
		panel.present(true,true);await process_frame
		check(panel._buttons.new_game.get_meta("source_text")==library.strings[28],"Menu language did not use its original text")
		check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(panel.snapshot().logo_rect),"Localized logo escaped the landscape viewport")
	if not library.select_language("gb") or not panel.configure(library,bindings,visuals):check(false,library.error+panel.error)
	root.size=Vector2i(960,540);panel.set_mobile_layout(true);panel.present(true,true);await process_frame
	check(panel.snapshot().actions.all(func(row):return row.height>=44),"Landscape menu lost its larger touch targets")
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(panel.snapshot().menu_rect),"Landscape menu escaped its viewport")
	await capture("main-menu-mobile-landscape")
	panel.free();background.free()
	print("Main-menu controls: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func capture(label: String) -> void:
	if captures.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;RenderingServer.force_draw(false);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(captures.path_join(label+".png"))==OK,"Could not save menu capture")

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
