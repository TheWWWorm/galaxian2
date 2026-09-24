extends SceneTree
## Native starter death from an accepted cursor-2 construction, without a save.
const Death=preload("res://src/simulation/player_destruction.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Resources=preload("res://src/content/npc_destruction_resources.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected Mac content, bindings and visuals triple")
	if args.size()==3:verify(args[0],args[1])
	print("First-mining player death: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String, pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new()
	if not library.open(content) or not library.select_language("gb") or not bindings.open(pack,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	check(bindings.player_destruction.scope=="mac_starter_player_destruction" and int(bindings.player_destruction.departure_cursor)==4 and bindings.player_destruction.story_cursors.map(func(value):return int(value))==[4,5],"Imported global starter death declaration changed")
	var original:=Player.new();var handoff:=Handoff.new()
	if not original.configure(bindings,catalogues):check(false,original.error);return
	var rescue: Dictionary=handoff.prepare(bindings,catalogues,Fixture.completed(bindings,original,3))
	var arrival:=Arrival.new()
	if not arrival.configure(bindings,catalogues,library,rescue,[1,1,1],1789100000):check(false,arrival.error);return
	for tick in 500:
		var next: RefCounted=arrival.evaluate(100)
		if next==null:check(false,arrival.error);return
		arrival=next
		if not arrival.snapshot().boundary.is_empty():break
	var station:=Station.new()
	if not station.configure(bindings,catalogues,library,arrival.prepare_station()):check(false,station.error);return
	for line in 19:
		if not station.acknowledge():check(false,station.error);return
	var departure: Dictionary=station.prepare_departure(bindings,catalogues)
	check(departure.get("campaign_cursor")==2,"Earned station handoff did not select first mining")
	var construction:=Construction.new()
	if not construction.prepare(bindings,catalogues,departure,4096,1789100000):check(false,construction.error);return
	var prepared: Dictionary=construction.snapshot()
	check(prepared.campaign_cursor==2 and prepared.departure.loadout.ship_id==0 and prepared.player.ship_id==0 and prepared.player.equipment_ids==[90,81],"First-mining construction changed Betty's starter loadout")
	var resources:=Resources.new()
	if not resources.configure(library,bindings):check(false,resources.error);return
	var death:=Death.new()
	if not death.configure(bindings,resources,construction):check(false,death.error);return
	check(death.snapshot().departure_cursor==2 and death.snapshot().equipment_ids==[90,81] and death.snapshot().phase=="ready","Shared starter death rejected its first-mining construction")
	check(not death.request_exit().size() and death.snapshot().phase=="ready","First-mining exit was available before death")
	var player: RefCounted=construction.player_owner()
	check(player.set_permissions(true,true),player.error)
	for impact in 100:
		if player.snapshot().vitals.hull==0:break
		if player.normal_hit(20).is_empty():check(false,player.error);return
	check(player.snapshot().vitals.hull==0,"Source 20-point contacts did not exhaust the detached starter player")
	var pose: Transform3D=prepared.player_pose
	var camera: Transform3D=prepared.camera_view.pose
	check(not death.start(player,pose,Vector3.ZERO,camera,4) and death.snapshot().phase=="ready","Cursor-4 story was accepted on the cursor-2 departure")
	if not death.start(player,pose,Vector3.ZERO,camera,2,Basis.IDENTITY,pose):check(false,death.error);return
	check(death.snapshot().phase=="tumble" and not death.snapshot().statistics_active and not death.snapshot().hud_visible,"Lethal first-mining contact did not enter native death")
	check(construction.snapshot()==prepared and int(bindings.player_destruction.departure_cursor)==4,"Death changed prepared progress or imported source policy")
	var fork: RefCounted=death.fork_for_frame()
	var started: Dictionary=death.snapshot()
	var random_state: Dictionary=prepared.random_state
	var seen_breakup:=0;var seen_failure:=0
	for tick in 250:
		var result: Dictionary=fork.advance(100,pose,random_state)
		if result.is_empty():check(false,fork.error);return
		random_state=result.random_state
		if result.events.breakup:seen_breakup+=1
		if result.events.failed:seen_failure+=1
		if fork.snapshot().phase=="game_over":break
	check(fork.snapshot().phase=="game_over" and fork.snapshot().continue_enabled and fork.snapshot().game_over_visible,"First-mining death did not reach acknowledged game over")
	check(seen_breakup==1 and seen_failure==1 and fork.snapshot().effect.models.size()==2,"First-mining death skipped or repeated breakup/failure effects")
	check(death.snapshot()==started and construction.snapshot()==prepared,"Detached death lifetime mutated its parent or construction")
	var exit: Dictionary=fork.request_exit()
	check(exit.get("source_state")==1 and exit.get("campaign_cursor")==2 and fork.snapshot().exit_requested,"First-mining game over did not return its source state")
	check(fork.request_exit().is_empty() and death.snapshot()==started,"Game-over exit repeated or changed the retained death")
	var after_ack:=Death.new()
	if not after_ack.configure(bindings,resources,construction):check(false,after_ack.error);return
	check(after_ack.start(player,pose,Vector3.ZERO,camera,3,Basis.IDENTITY,pose) and after_ack.snapshot().campaign_cursor==3,"Acknowledged first-mining return cursor was rejected")
	check(construction.snapshot()==prepared and station.prepare_departure(bindings,catalogues)==departure,"Death component altered the earned departure packet")

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
