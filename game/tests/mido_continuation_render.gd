extends "res://tests/mido_arrival.gd"
## The inherited arrival component supplies an acknowledged native station.
## A detached lethal-hit fixture then exercises the full rendered freighter
## lifecycle and sound. This is separate from the surviving application journey.
const Session=preload("res://src/presentation/first_flight_session.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var _packet:={}
var _equipment: RefCounted
var _bindings: RefCounted
var _library: RefCounted
var _cat: RefCounted
var _session: Node
var _now:=0

func _initialize() -> void:call_deferred("run_render")

func after_local_visit(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> void:
	_packet=station.prepare_departure(bindings,cat)
	check(not _packet.is_empty(),station.error)
	_equipment=station.equipment_owner();_bindings=bindings;_library=library;_cat=cat

func run_render():
	root.size=Vector2i(1280,720)
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected explicit Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:verify(args.slice(0,3))
	if failures==0 and not _packet.is_empty():await verify_render(args)
	if is_instance_valid(_session):_session.free()
	print("Mido continuation render: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_render(args: PackedStringArray):
	var visuals:=Visuals.new()
	if not visuals.open(args[2],_library.manifest):check(false,visuals.error);return
	_session=Session.new();root.add_child(_session)
	if not _session.configure(_library,_bindings,visuals,_packet,true,0,4096,1789100000,false,_equipment):check(false,_session.error);return
	if not _session.activate():check(false,_session.error);return
	for tick in 71:
		if not step_session():return
	var before: Dictionary=_session.snapshot()
	var freighters: Array=before.encounter.combat.actors.filter(func(actor):return actor.get("population_group")=="freighter")
	if freighters.is_empty():check(false,"The rendered fixture omitted freighters");return
	check(_session.scene.geometry.player.engine_glow!=null,"The next flight lost Betty's original nozzle glow")
	var id: int=freighters[0].actor_id
	var node: Dictionary=_session.scene.encounter.actors[id]
	check(node.freighter and node.hull.get_meta("source_ship_id")==15 and node.hull.levels.size()==2,"The full scene lost the original freighter assembly")
	var branch: RefCounted=_session.flight_owner()
	if not branch._encounter._combat.begin_contact_pass(branch.snapshot().random_state,true):check(false,branch._encounter._combat.error);return
	if branch._encounter._combat.normal_hit(id,int(freighters[0].max_hull)).is_empty():check(false,branch._encounter._combat.error);return
	branch._random=branch._encounter._combat.contact_random_state()
	var dead: RefCounted=branch.evaluate(0)
	if dead==null:check(false,branch.error);return
	if not _session._commit(dead,false):check(false,_session.error);return
	var initial: Dictionary=_session.snapshot().encounter.controller.destruction[id]
	check(initial.phase=="animation" and node.explosion.is_built() and node.explosion.visible and not node.hull.visible,"Lethal entry did not replace the intact freighter with its animation")
	var sounds: Array=_session.flight_audio.snapshot().history.filter(func(event):return event.get("actor_id")==id and event.get("action")=="start_spatial")
	check(sounds.size()==2 and sounds[0].source_id==20 and sounds[1].source_id in [18,19],"Freighter initial sounds were omitted or replaced")
	for tick in 300:
		if not step_session():return
		if tick%10==0:await process_frame
		if _session.snapshot().encounter.controller.destruction[id].phase=="wreck":break
	var wreck: Dictionary=_session.snapshot().encounter.controller.destruction[id]
	check(wreck.phase=="wreck" and node.explosion.visible and node.explosion.cargo.visible==wreck.cargo.model_exists,"Freighter did not retain its animated wreck and salvage")
	sounds=_session.flight_audio.snapshot().history.filter(func(event):return event.get("actor_id")==id and event.get("action")=="start_spatial")
	check(sounds.size()==3 and sounds[2].source_id in [18,19],"The final freighter explosion lost its original sound")
	check(_session.snapshot().progress.player_kills==before.progress.player_kills+1 and _session.snapshot().progress.pirate_kills==before.progress.pirate_kills,"A freighter kill used pirate or repeated credit")
	check(_session.snapshot().campaign_cursor==11 and _session.snapshot().cargo==before.cargo,"The damage fixture completed the mission or granted salvage")
	if args.size()==4:
		DirAccess.make_dir_recursive_absolute(args[3])
		for tick in 3:await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(args[3].path_join("live-freighter-wreck.png"))==OK,"Freighter capture failed")

func step_session() -> bool:
	_now+=100000
	if not _session.step(_now):check(false,_session.error);return false
	return true
