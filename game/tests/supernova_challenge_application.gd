extends SceneTree
## Supernova Challenge in the real game: the main menu entry, its confirm
## window, the flight with the score HUD and combo voice lines, the end
## window, the stored highscore and Play again; the career save beside it
## stays byte-identical and still resumes afterwards.
const Frontend=preload("res://src/presentation/player_frontend.gd")
const Pilot=preload("res://tests/fixtures/bakka_flight_pilot.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
const Rules=preload("res://src/content/supernova_challenge_definitions.gd")
const FIGHT_TICKS:=900
var failures:=0
var checks:=0
var frontend: Control
var capture_dir:=""

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var directory:=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	capture_dir=OS.get_environment("GOF2_CAPTURE_DIR")
	check(args.size()>=3 and not directory.is_empty() and not FileAccess.file_exists(directory.path_join("profile/player.json")),"Use prepared content and a fresh isolated profile")
	if failures:quit(1);return
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	frontend=Frontend.new();root.add_child(frontend);frontend.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await play(args,directory.path_join("profile"))
	frontend.free();await process_frame
	print("Supernova Challenge application: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func play(args: PackedStringArray,directory: String) -> void:
	frontend.boot(PackedStringArray(),directory)
	var selection:=Frontend.Preferences.defaults()
	selection.content=args[0];selection.bindings=args[1];selection.visuals=args[2];selection.language="gb"
	if not frontend.select_content(selection):check(false,frontend.error);return
	var bindings: RefCounted=frontend.bindings;var manifest: Dictionary=frontend.library.manifest
	# A current import carries these itself; only an older import attaches them.
	for key in ["GOF2_DEKATO_SOURCE_ARGS","GOF2_NEHMA_SOURCE_ARGS"]:
		if OS.get_environment(key).is_empty():continue
		var supplement: Variant=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment(key)))
		if not supplement is Array or supplement.size()!=3:check(false,"Missing "+key);return
		if not (bindings.attach_dekato_source(supplement[1],manifest) if key=="GOF2_DEKATO_SOURCE_ARGS" else bindings.attach_nehma_source(supplement[1],manifest)):check(false,bindings.error);return
	if not OS.get_environment("GOF2_IMPORT_UPDATE").is_empty() and not bindings.attach_import_update(OS.get_environment("GOF2_IMPORT_UPDATE"),manifest,frontend.library):check(false,bindings.error);return
	# A career save beside the challenge; it must come out byte-identical.
	var save_path:=SaveFile.path_for(frontend._save_directory,bindings)
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	check(DirAccess.copy_absolute(OS.get_environment("GOF2_SOURCE_SAVE"),save_path)==OK,"Cannot stage the career save")
	var save_hash:=FileAccess.get_sha256(save_path)
	var save_files:=DirAccess.get_files_at(save_path.get_base_dir())
	frontend.show_menu()
	var enter:=InputEventKey.new();enter.physical_keycode=KEY_ENTER;enter.pressed=true
	frontend.menu._unhandled_input(enter)
	var entry: Button=frontend.menu._buttons.supernova
	check(entry.is_visible_in_tree() and not entry.disabled,"The Supernova Challenge entry is not playable")
	await capture("01-menu")
	if failures:return
	entry.pressed.emit()
	check(frontend.phase=="confirm" and frontend._detail_title.text==frontend.library.strings[Rules.TEXT.title],"The challenge did not ask to start")
	check(frontend._body.get_children().any(func(node):return node is Label and node.text.begins_with(frontend.library.strings[Rules.TEXT.highscore])),"The confirm window lacks the highscore")
	await capture("02-confirm")
	var ok: Button=frontend._body.get_children().filter(func(node):return node is Button)[0]
	ok.pressed.emit()
	if not frontend.has_session():check(false,"The challenge did not start: "+frontend.error);return
	var app: Control=frontend.game
	check(frontend.phase=="game" and app._save_directory.is_empty(),"The challenge host may write saves")
	var start: Dictionary=app.session.snapshot()
	check(start.player_pose.origin.distance_to(Rules.PLAYER_POSITION)<2000.0 and int(start.player.ship_id)==Rules.SHIP_ID,"The challenge ship is not at its fixed start")
	var actors: Array=app.session.flight_owner()._encounter.combat_snapshot().actors
	check(actors.size()==8 and actors.all(func(actor):return actor.hostile and int(actor.vitals.hull)==Rules.VOID_MAX_HULL),"The challenge cast is not eight hostile 300-hull Voids")
	# Fight like a player, then let the clock run out.
	app.set_process(false)
	var pilot:=Pilot.new();var now_us:=Time.get_ticks_usec();var voices:=[];var combo_seen:=false;var respawned:=false
	var dead:={};var finished:={};var combo_kills:=0;var before: Dictionary={};var targeted:=false
	for tick in 2000:
		var state: Dictionary=app.session.snapshot()
		var score: Dictionary=state.get("kill_score",{})
		if score.get("finished",false):finished=score;break
		actors=app.session.flight_owner()._encounter.combat_snapshot().actors
		for id in actors.size():
			if int(actors[id].vitals.hull)<=0:dead[id]=true
			elif dead.has(id):respawned=true;dead.erase(id)
		check(not app.session.flight_owner().death_active(),"The challenge ship was destroyed")
		var targets:=range(actors.size()).filter(func(id):return int(actors[id].vitals.hull)>0)
		var input: Dictionary=pilot.controls(state,tick,targets if tick<FIGHT_TICKS else [],true)
		for adjustment in 10:
			var current: float=app.session.snapshot().input_throttle
			if absf(current-float(input.throttle))<.01 or not app.session.can_control():break
			app.session.action("throttle_up" if current<float(input.throttle) else "throttle_down")
		now_us+=100000
		if not app.session.step(now_us,input.commands,input.fire and tick<FIGHT_TICKS,false,input.strafe):check(false,app.session.error);return
		voices.append_array(app.session.flight_owner().snapshot().get("kill_score_voice",[]))
		app.present_session()
		var shown: Dictionary=app.session.snapshot().get("kill_score",{})
		# The score is in the top-right counter plate, clear of the target panel (#38).
		check(app.flight_vitals._cargo_text.text=="%07d"%int(shown.get("score",-1)),"The kill score is not in the counter plate")
		var markers: Control=app.session.scene.npc_markers
		var panel: Rect2=markers.information_rect()
		if panel.has_area() and app._challenge_hud!=null:
			targeted=true
			# The panel is drawn in the flight viewport, the plate in the host UI: compare screen fractions.
			var view: Vector2=markers.get_viewport().get_visible_rect().size;var host: Vector2=app.get_viewport().get_visible_rect().size
			var target:=Rect2((panel.position+markers.global_position)/view,panel.size/view)
			var plate: Rect2=app.flight_vitals.counter_rect();var rows: Rect2=app._challenge_hud._column.get_global_rect()
			check(plate.has_area() and not Rect2(plate.position/host,plate.size/host).intersects(target) and not Rect2(rows.position/host,rows.size/host).intersects(target),"The kill score overlaps the target panel")
		# A kill while the combo clock still runs earns a combo voice line.
		if not before.is_empty() and int(shown.kills)>int(before.kills) and int(before.combo_clock_ms)>0:combo_kills+=1
		before=shown
		if tick==30:await capture("03-flight")
		if not combo_seen and int(shown.get("combo",0))>1:combo_seen=true;await capture("04-combo")
		if tick%20==0:await process_frame
		if tick%200==0:print("CHALLENGE ",tick," ",shown)
		if failures:return
	print("CHALLENGE end ",finished," voices ",voices," respawned ",respawned)
	check(not finished.is_empty() and finished.remaining_ms==0,"The 151 s run did not end")
	check(int(finished.get("kills",0))>=2 and int(finished.get("score",0))>=2000,"The run scored too few kills")
	check(voices.size()>=combo_kills and voices.all(func(id):return int(id)>=2282 and int(id)<=2291),"Combo kills %d but voice lines %s"%[combo_kills,str(voices)])
	check(respawned,"No destroyed Void came back")
	check(targeted,"No target panel appeared to test the score layout against")
	# The host reports the end; the frontend shows the result window.
	for frame in 4:await process_frame
	var score:=int(finished.get("score",0))
	var texts: Array=frontend._body.get_children().filter(func(node):return node is Label).map(func(node):return node.text)
	check(frontend.phase=="challenge_result" and not frontend.has_session(),"The end window did not replace the flight")
	check(texts.has("%s: %d"%[frontend.library.strings[Rules.TEXT.your_score],score]) and texts.has(frontend.library.strings[Rules.TEXT.new_highscore]) and texts.has(frontend.library.strings[Rules.TEXT.play_again]),"The end window differs: "+str(texts))
	check(frontend.challenge_highscore()==score,"The highscore was not stored")
	await capture("05-result")
	# Play again starts a fresh run; leaving it returns to the menu.
	frontend._body.get_children().filter(func(node):return node is Button)[0].pressed.emit()
	check(frontend.has_session() and frontend.phase=="game" and int(frontend.game.session.snapshot().get("kill_score",{}).get("score",-1))==0,"Play again did not start a fresh run")
	if failures:return
	frontend.show_menu()
	if frontend.phase=="pause":frontend._flight_pause_action("main_menu")
	check(frontend.phase=="menu" and not frontend.has_session(),"Leaving the run did not return to the menu")
	await capture("06-menu-after")
	check(FileAccess.get_sha256(save_path)==save_hash and DirAccess.get_files_at(save_path.get_base_dir())==save_files,"The challenge changed the career save")
	frontend.menu._buttons.resume.pressed.emit()
	check(frontend.has_session() and frontend.game.session.has_method("station_owner"),"The career save no longer resumes after the challenge")
	if frontend.has_session():await capture("07-resumed")

func capture(name: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	if capture_dir.is_empty():return
	var image:=root.get_texture().get_image()
	if image!=null:image.save_png(capture_dir.path_join("supernova-challenge-"+name+".png"))

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures+=1;printerr(message)
