extends "res://tests/opening_application.gd"
## Reuse the controlled primary-contact fixture, then run the actual opening
## scene at a desktop frame cadence through tumble, breakup and escape. This
## isolates lifecycle/presentation; it does not produce an earned campaign save.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")

func verify_source(content: String,pack: String,textures: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(content) or not library.select_language("gb") or not bindings.open(pack,library.manifest) or not visuals.open(textures,library.manifest):
		check(false,library.error+bindings.error+visuals.error);return
	root.size=Vector2i(1280,720)
	var session:=Session.new();root.add_child(session)
	if not session.configure(library,bindings,visuals,0,0.5,1789100000,true,true,true):
		check(false,session.error);session.free();return
	check(session.request_cinematic_skip(),session.error)
	var now:=0
	for tick in 300:
		if not session.cinematic_skipping():break
		now+=16667
		if not advance_session(session,now):session.free();return
	check(session.can_control(),"Opening did not reach its ordinary pirate fight")
	if failures:session.free();return
	complete_encounter_fixture(session)
	if failures:session.free();return
	now=100000
	var breakups:={};var retired:={}
	# The earlier integration used 100 ms ticks, which did not exercise the
	# hundreds of per-frame tumble rotations seen at a 144 Hz desktop setting.
	for tick in 1600:
		now+=6944
		if not advance_session(session,now):
			print("Opening damage failure after ",tick," high-rate frames")
			session.free();return
		var state: Dictionary=session.snapshot()
		for row in state.world_frame.controller.actors:
			var life: Dictionary=row.destruction
			if life.phase in ["explosion","retired"]:breakups[int(row.actor_id)]=true
			if life.phase=="retired":retired[int(row.actor_id)]=true
		if tick==100:await capture_scene("pirate-tumble")
		if retired.size()==3:break
	check(breakups.size()==3 and retired.size()==3,"Opening pirates did not finish breakup and retirement at the desktop frame cadence")
	if failures:session.free();return
	await capture_scene("pirate-fight-complete")
	for tick in 1200:
		if session.can_skip_cinematic():break
		now+=100000
		if not advance_session(session,now):session.free();return
	check(session.can_skip_cinematic(),"Completed pirate deaths did not release the escape cinematic")
	if failures:session.free();return
	check(session.request_cinematic_skip(),session.error)
	for tick in 300:
		if not session.cinematic_skipping():break
		now+=16667
		if not advance_session(session,now):session.free();return
	var state: Dictionary=session.snapshot()
	check(session.status=="arrival_transition_required","Opening did not reach its rescue handoff after the pirate deaths")
	check(state.world_frame.controller.death_accounting.counter_deltas.player_kills==3,"Repeated destruction frames changed opening kill credit")
	print("Opening pirate damage: three breakups and retirements at 144 Hz; rescue status=",session.status)
	session.free()

func advance_session(session: Node3D,now: int) -> bool:
	if session.step(now):return true
	check(false,session.error)
	return false

func capture_scene(name: String) -> void:
	var directory:=OS.get_environment("GOF2_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(directory)
	check(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Could not capture "+name)
