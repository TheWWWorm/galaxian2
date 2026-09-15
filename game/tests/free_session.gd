extends SceneTree
## Earned ordinary flight through the shared scene, session clock and audio.
## Station menus and local travel are not exposed by this presentation check.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Checkpoint=preload("res://tests/fixtures/free_play_station_scenario.gd")
const Session=preload("res://src/presentation/first_flight_session.gd")
var checks:=0
var failures:=0
var live: Node3D

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	var args:=OS.get_cmdline_user_args()
	if args.size() in [3,4]:await verify(args)
	else:check(false,"Expected explicit content, bindings, visuals and optional captures")
	if is_instance_valid(live):live.free()
	print("Earned ordinary session: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not visuals.open(args[2],library.manifest):check(false,library.error+bindings.error+visuals.error);return
	var checkpoint:=Checkpoint.new();var station: RefCounted=checkpoint.open(OS.get_environment("GOF2_FREE_PLAY_STATION_SCENARIO"),bindings)
	if station==null:check(false,checkpoint.error);return
	var before: Dictionary=station.snapshot()
	live=Session.new();root.add_child(live)
	if not live.configure_free(library,bindings,visuals,station,0,4096,1789100000):check(false,live.error);return
	if not live.activate():check(false,live.error);return
	check(live.status=="running" and is_instance_valid(live.flight_audio) and live.scene.encounter.actors.size()==live.snapshot().actors.size(),"Ordinary session omitted audio or original NPC geometry")
	check(live.scene.portal==null and not live.scene.dialogue.visible,"Ordinary entry retained Alioth's mission portal or dialogue")
	if args.size()==4:await capture(args[3],"free-entry-desktop")
	var now:=0
	for tick in 85:
		now+=100000
		if not live.step(now,Vector2.ZERO,tick>71):check(false,live.error);return
		if tick%25==0:await process_frame
	var state: Dictionary=live.snapshot()
	check(state.entry_released and state.player.damage_allowed and state.camera_view.mode=="follow" and not state.dialogue.visible,"Ordinary session failed to release live flight without a modal")
	check(state.contracts.credits==7850 and state.contracts.completed_side_missions==4 and state.mission==before.mission,"Presented ordinary flight lost its earned career or pending story")
	check(live.flight_audio._flight_serial==state.flight_audio.serial,"Ordinary scene and sound did not commit the same accepted frame")
	if args.size()==4:
		await capture(args[3],"free-flight-desktop")
		root.size=Vector2i(960,540);live.scene.set_mobile_layout(true)
		for frame in 2:await process_frame
		# Source aim smooths against its preceding pixel position. Capture after
		# ordinary frames have settled the resize, without replacing that sample.
		for frame in 25:
			now+=100000
			if not live.step(now):check(false,live.error);return
		check(live.snapshot().player_aim.viewport_size==Vector2i(960,540),"Mobile aiming retained the desktop viewport")
		await capture(args[3],"free-flight-mobile-landscape")
		root.size=Vector2i(1280,720);live.scene.set_mobile_layout(false)
		for frame in 2:await process_frame
		for frame in 25:
			now+=100000
			if not live.step(now):check(false,live.error);return
	var flight: RefCounted=live.flight_owner();var dock: RefCounted=flight.start_station_autopilot()
	if dock==null:check(false,flight.error);return
	if not live._commit(dock,false):check(false,live.error);return
	var outbound_seen:=false
	for tick in 1200:
		if live.status!="running":break
		now+=100000
		if not live.step(now):check(false,live.error);return
		if live.snapshot().actors.any(func(actor):return actor.get("population_group")=="travel" and actor.actor_mode==6):outbound_seen=true
		if tick%100==0:await process_frame
	check(live.status=="station_transition_required", "Ordinary session did not accept actual station guidance and contact")
	if args.size()==4:check(outbound_seen,"The longer rendered flight did not exercise ordinary traffic departure")
	state=live.snapshot()
	check(state.campaign_cursor==18 and state.mission==before.mission and state.cargo==before.cargo and state.contracts.credits==7850,"Presented docking changed earned cargo, story or credits")
	check(station.snapshot()==before,"Presented flight mutated its departure station")
	if args.size()==4:await capture(args[3],"free-docking-desktop")
	print("Ordinary session docked at ",state.world_elapsed_ms,"ms with ",state.actors.size()," actors")

func capture(directory: String,name: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	for frame in 3:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Could not capture "+name)

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(message)
