extends SceneTree
## Earned rescue departure with a detached lethal-contact diagnostic. This test
## never advances the saved career or creates a successful rescue checkpoint.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
const Archive=preload("res://src/simulation/station_archive.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Resources=preload("res://src/content/npc_destruction_resources.gd")
const Death=preload("res://src/simulation/player_destruction.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Kappa player destruction: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var file:=SaveFile.new();var archive:=Archive.new()
	var record:=file.load_document(OS.get_environment("GOF2_SOURCE_SAVE"),bindings,cat,library)
	if record.is_empty():check(false,file.error);return
	var station:=archive.restore(bindings,cat,library,record)
	if station==null:check(false,archive.error);return
	var retained: Dictionary=station.snapshot()
	check(retained.campaign_cursor==21 and retained.loadout.station_id==55,"Use the actual fitted rescue station save")
	if failures:return
	var construction:=Construction.new();var resources:=Resources.new();var death:=Death.new()
	if not construction.prepare_kappa_rescue(bindings,cat,station,4096,1789100000) or not resources.configure(library,bindings) or not death.configure(bindings,resources,construction,cat):check(false,construction.error+resources.error+death.error);return
	var entry: Dictionary=construction.snapshot();var player: RefCounted=construction.player_owner()
	var initial: Dictionary=death.snapshot()
	check(not death.start(player,entry.player_pose,Vector3.ZERO,entry.camera_view.pose,22) and death.snapshot()==initial,"The appended return cursor destroyed a living player")
	# Only a detached flight player receives this lethal diagnostic. Keep the
	# earned station, original construction and acknowledgement state intact.
	player._state.vitals.hull=0
	for cursor in [20,23,24,null,true,22.0,"22"]:
		check(not death.start(player,entry.player_pose,Vector3.ZERO,entry.camera_view.pose,cursor) and death.snapshot()==initial,"An unrelated or malformed story cursor started destruction: "+str(cursor))
	for cursor in [21,22]:
		var branch: RefCounted=death.fork_for_frame()
		check(branch.start(player,entry.player_pose,Vector3.ZERO,entry.camera_view.pose,cursor),branch.error)
		check(branch.snapshot().campaign_cursor==cursor and branch.snapshot().phase=="tumble" and branch.snapshot().elapsed_ms==0,"Allowed story cursor lost its initial destruction state")
		check(death.snapshot()==initial,"A detached death branch mutated its retained owner")
	check(station.snapshot()==retained and archive.capture(station,bindings)==record and construction.snapshot()==entry,"Death validation changed the earned save, career or prepared departure")

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(message)
