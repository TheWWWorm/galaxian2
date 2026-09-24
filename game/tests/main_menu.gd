extends SceneTree
## Isolated original-art title and menu control checks.
const MenuView=preload("res://src/presentation/main_menu_panel.gd")
const MenuBackground=preload("res://src/presentation/main_menu_background.gd")
const MenuAudio=preload("res://src/presentation/main_menu_audio.gd")
const Library=preload("res://src/content/library.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
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
	captures=args[3] if args.size()==4 else OS.get_environment("GOF2_CAPTURE_DIR")
	if not captures.is_empty():
		if not PrivatePath.private_path(captures+"/menu.png"):check(false,"Keep menu captures outside engine source");quit(1);return
		DirAccess.make_dir_recursive_absolute(captures)
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not visuals.open(args[2],library.manifest):check(false,library.error+bindings.error+visuals.error);quit(1);return
	var catalogues:=Catalogues.new()
	if not catalogues.open(library):check(false,catalogues.error);quit(1);return
	var background:=ColorRect.new();background.color=Color(.015,.026,.042);background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(background);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel=MenuView.new();root.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.action_requested.connect(func(action):requests.append(action))
	if not panel.configure(library,bindings,visuals):check(false,panel.error);quit(1);return
	panel.present(false,false);await process_frame
	var scene: Dictionary=panel.snapshot().background
	check(int(scene.get("station_id",-1)) in range(100) and int(scene.get("system_id",-1))>=0,"The title did not choose a source catalogue station")
	var sky_rows: Array=scene.sky
	var expected_star:=17852 if scene.station_id==int(bindings.first_flight.station_id) else 17850+int(scene.system_id)%3
	var expected_nebula:=17810 if scene.station_id==int(bindings.first_flight.station_id) else 17800+int(catalogues.tables.systems[scene.system_id].sky_index)
	# Compare the scene against its independently decoded system catalogue row.
	check(sky_rows[0].mesh_id==expected_star and sky_rows[0].texture_id==(10088 if scene.station_id==int(bindings.first_flight.station_id) else 10086+int(scene.system_id)%3) and sky_rows[1].mesh_id==expected_nebula and sky_rows[1].texture_id==expected_nebula-7735,"The menu sky selected another source mesh or texture")
	check(scene.scenery_count>=80 and scene.scenery_count<=159 and panel._background.scenery.objects.size()==scene.scenery_count,"The menu did not render its source-count scenery field")
	var center: Vector3=scene.scenery_center
	check(center==Vector3(-30000,0,30000) if scene.station_id==int(bindings.first_flight.station_id) else (center.x>=-50000 and center.x<=49999 and center.y>=-50000 and center.y<=49999 and center.z>=20000 and center.z<=119999),"The menu scenery center left its source placement bounds")
	var model_ids: Array=scene.station_models
	if scene.station_id==int(bindings.first_flight.station_id):check(model_ids.is_empty() and panel._background.station==null,"The fresh baseline station exterior was shown")
	else:
		var expected_ids: Array=[21000+int(scene.station_id),21800+int(scene.station_id),22000+int(scene.station_id)] if bindings.records.has(21000+int(scene.station_id)) else [16436,16439,16442]
		check(model_ids==expected_ids and panel._background.station!=null and is_equal_approx(panel._background.station.rotation.y,3.1415927410125732),"The menu exterior missed its dedicated or fallback source models")
	# The random selection rarely exercises these source-specific world branches.
	for forced in [int(bindings.first_flight.station_id),11,80]:
		var alternate:=MenuBackground.new();root.add_child(alternate)
		if not alternate.build(library,bindings,visuals,forced):check(false,"Forced menu station %d: %s"%[forced,alternate.error])
		else:
			var alternate_scene: Dictionary=alternate.selection
			if forced==int(bindings.first_flight.station_id) or forced==80:
				check(alternate.station==null and alternate_scene.station_models.is_empty() and alternate_scene.sky[0].mesh_id==17852 and alternate_scene.sky[1].mesh_id==17810 and alternate_scene.scenery_center==Vector3(-30000,0,30000),"The fresh baseline menu branch lost its special sky, center or absent exterior")
				if forced==80:check(alternate_scene.requested_station_id==80 and alternate_scene.station_id==int(bindings.first_flight.station_id),"The absent station80 light mesh blocked or corrupted the menu fallback")
			else:check(alternate.station!=null and alternate_scene.station_models==[16436,16439,16442] and alternate_scene.sky[1].mesh_id==17800+int(catalogues.tables.systems[alternate_scene.system_id].sky_index),"The missing-collision menu station missed its shared Vossk exterior")
		alternate.free()
	check(scene.camera_origin.x>=-20000 and scene.camera_origin.x<=-1 and scene.camera_origin.z>=40000 and scene.camera_origin.z<=99999 and scene.camera_fov==0.92 and scene.camera_near==200.0 and scene.camera_far==200000.0,"The title camera left its recovered projection or placement bounds")
	var initial_yaw: float=panel._background.selection.camera_yaw
	panel._background.advance(1000.0)
	check(is_equal_approx(panel._background.selection.camera_yaw,initial_yaw+1000.0*0.00005),"The menu camera missed its source rotation step")
	panel._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	panel._background._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var title_before: float=panel.snapshot().title_elapsed_ms;panel._process(0.1)
	check(panel.snapshot().title_elapsed_ms==title_before and panel._background.render_target_update_mode==SubViewport.UPDATE_DISABLED,"The title or background continued without focus")
	panel._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	panel._background._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(panel.snapshot().title_active and panel.snapshot().title_alpha==0.0 and not panel._title_prompt.visible,"The fresh title did not begin at transparent logo")
	for frame in 13:panel.advance_title(150.0)
	check(is_equal_approx(panel.snapshot().title_alpha,127.0/255.0) and not panel._title_prompt.visible,"The original title fade midpoint was lost")
	for frame in 13:panel.advance_title(150.0)
	check(panel.snapshot().title_alpha==1.0 and panel._title_prompt.visible and panel._title_prompt.text==library.strings[188],"The title prompt did not follow its full fade")
	check(is_equal_approx(panel._title_prompt.modulate.a,floorf(255.0*absf(sin(3900.0*0.003)))/255.0),"The title prompt pulse differs from its source timing")
	for frame in 5:panel.advance_title(150.0)
	await capture("main-title-desktop")
	var title_touch:=InputEventScreenTouch.new();title_touch.pressed=true
	panel._unhandled_input(title_touch)
	check(not panel.snapshot().title_active and panel._scroll.visible and not panel._title_prompt.visible,"The title did not yield to the menu")
	panel.show_background_only();panel._buttons.new_game.pressed.emit()
	check(panel.snapshot().background_only and panel.visible and not panel._logo.visible and not panel._scroll.visible and requests.is_empty(),"A details page exposed menu controls")
	panel.present(false,false)
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
	check(not panel._background._active,"The hidden menu kept rendering its 3D scene")
	panel.show();var accepted: Dictionary=panel.snapshot()
	var backdrop: SubViewport=panel._background
	check(not panel.configure(library,bindings,Visuals.new()) and panel.snapshot().identity==accepted.identity and panel.snapshot().background==accepted.background and panel._background==backdrop and panel._logo.texture!=null,"Failed menu preparation discarded its accepted artwork or scene")
	panel.present(true,true);await capture("main-menu-desktop")
	for language in library.manifest.languages:
		if not library.select_language(language) or not panel.configure(library,bindings,visuals):check(false,library.error+panel.error);continue
		panel.present(true,true);await process_frame
		check(panel._buttons.new_game.get_meta("source_text")==library.strings[28],"Menu language did not use its original text")
		check(panel._title_prompt.text==library.strings[188],"The title prompt was not localized")
		check(panel._background==backdrop,"Changing language rebuilt the menu scene")
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
