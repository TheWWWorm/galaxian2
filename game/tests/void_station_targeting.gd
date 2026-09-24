extends SceneTree
## Detached Void29 slot0 targeting; no campaign progress or source runtime.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Probe=preload("res://src/content/void_probe_definitions.gd")
const VoidWorld=preload("res://src/simulation/void_environment.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Target=preload("res://src/simulation/void_station_targeting.gd")

var checks:=0
var failures:=0
var library: RefCounted
var bindings: RefCounted
var catalogues: RefCounted
var environment: RefCounted
var camera:=Transform3D(Basis.IDENTITY,Vector3(0,0,10000))

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected content, bindings and visuals");finish();return
	library=Library.new();bindings=Bindings.new();catalogues=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);finish();return
	var random:=Random.new();random.seed_from(29)
	environment=VoidWorld.new()
	if not Probe.parameters(bindings.mido_travel.get("void_probe",{})):
		check(environment.configure(bindings,random.snapshot(),25),environment.error)
		var absent:=Target.new()
		check(not absent.configure(bindings,catalogues,loadout([81]),environment,Vector2(160,90)) and absent.snapshot().is_empty(),"Earlier pack invented mission29 station lock")
		finish();return
	check(environment.configure(bindings,random.snapshot(),29),environment.error)
	verify_admission()
	verify_scanners()
	verify_windows_and_clock()
	verify_interruptions()
	finish()

func loadout(equipment_ids: Array) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":0,"equipment_ids":equipment_ids.duplicate()}

func fresh(equipment_ids: Array=[81]) -> RefCounted:
	var owner:=Target.new()
	check(owner.configure(bindings,catalogues,loadout(equipment_ids),environment,Vector2(160,90)),owner.error)
	return owner

func observation(delta:=100) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":29,
		"delta_ms":delta,"viewport_size":Vector2i(960,540),"camera_pose":camera,"aim_point":Vector3(480,270,0),
		"station":{"environment_slot":0,"pose":environment.object_state(0).pose,"active":true},
		"controller_enabled":true,"held_primary":false,"other_selected_target":false,
		"mining_approach_active":false,"alternate_operation_active":false,"selected_target_active":false}

func verify_admission() -> void:
	var absent:=Target.new()
	check(absent.snapshot().is_empty() and not absent.advance(observation()),"Unconfigured target acquired the mother ship")
	var owner:=fresh();var initial: Dictionary=owner.snapshot()
	check(initial.duration_ms==4000 and initial.scanner_id==81 and initial.found_index==-1 and not initial.mother_ship_locked,"Source scanner81 initialization failed")
	for change in [{"binding_id":"foreign"},{"campaign_cursor":25},{"delta_ms":-1},{"delta_ms":1.0},
		{"viewport_size":Vector2i.ZERO},{"camera_pose":Transform3D(Basis.IDENTITY,Vector3(INF,0,0))},
		{"aim_point":Vector3(NAN,270,0)},
		{"station":{"environment_slot":1,"pose":Transform3D.IDENTITY,"active":true}},
		{"station":{"environment_slot":2,"pose":Transform3D.IDENTITY,"active":true}},
		{"station":{"environment_slot":3,"pose":Transform3D.IDENTITY,"active":true}},
		{"station":{"environment_slot":0,"pose":Transform3D.IDENTITY,"active":1}},
		{"controller_enabled":1}]:
		var invalid:=observation();invalid.merge(change,true)
		check(not owner.advance(invalid) and owner.snapshot()==initial,"Invalid observed station frame changed the target: "+str(change))
	var bad_loadout: Dictionary=loadout([81]);bad_loadout.binding_id="foreign"
	check(not owner.configure(bindings,catalogues,bad_loadout,environment,Vector2(160,90)) and owner.snapshot()==initial,"Rejected equipment changed the accepted lock")
	bad_loadout=loadout([81,81])
	check(not owner.configure(bindings,catalogues,bad_loadout,environment,Vector2(160,90)) and owner.snapshot()==initial,"Duplicate installed scanner changed the lock")
	check(not owner.configure(bindings,catalogues,loadout([81]),environment,Vector2.ZERO) and owner.snapshot()==initial,"Invalid projection frame changed the lock")
	var detached: Dictionary=owner.snapshot();detached.found_index=0
	check(owner.snapshot().found_index==-1,"Target snapshot exposed its mutable state")

func verify_scanners() -> void:
	for case in [{"ids":[],"scanner":-1,"duration":8000},
		{"ids":[81],"scanner":81,"duration":4000},
		{"ids":[82],"scanner":82,"duration":3000},
		{"ids":[83],"scanner":83,"duration":1800},
		{"ids":[84],"scanner":84,"duration":1800},
		{"ids":[82,81],"scanner":82,"duration":3000},
		{"ids":[81,82],"scanner":81,"duration":4000}]:
		var owner:=fresh(case.ids);var state: Dictionary=owner.snapshot()
		check(state.scanner_id==case.scanner and state.duration_ms==case.duration,"Source scanner order/property29 changed: "+str(case.ids))
	for case in [{"ids":[],"duration":8000},{"ids":[84],"duration":1800}]:
		var owner:=fresh(case.ids)
		for i in int(case.duration/100):check(owner.advance(observation()),owner.error)
		check(owner.snapshot().elapsed_ms==case.duration and not owner.snapshot().mother_ship_locked,"Scanner locked at the inclusive source duration: "+str(case.ids))
		check(owner.advance(observation(1)) and owner.snapshot().mother_ship_locked,"Scanner failed after strict duration: "+str(case.ids))

func verify_windows_and_clock() -> void:
	var owner:=fresh()
	for i in 40:check(owner.advance(observation()),owner.error)
	var before: Dictionary=owner.snapshot()
	check(before.station_pixels==Vector2i(480,270) and before.station_in_view and before.outer_window and before.inner_window,"Station slot0 projection missed the source center")
	check(before.found_index==0 and before.aimed_index==0 and before.locked_index==-1 and before.elapsed_ms==4000 and not before.mother_ship_locked,"Lock ignored strict 4000ms boundary")
	check(owner.advance(observation(1)) and owner.snapshot().locked_index==0 and owner.snapshot().mother_ship_locked,"Station lock failed strictly after scanner81 duration")
	var locked: Dictionary=owner.snapshot()
	var disabled:=observation(100);disabled.controller_enabled=false;disabled.station.active=false;disabled.other_selected_target=true
	check(owner.advance(disabled) and owner.snapshot()==locked,"Disabled target controller changed the retained phase1 lock")
	var lost:=observation(1);lost.aim_point=Vector3(680,270,0)
	check(owner.advance(lost) and owner.snapshot().found_index==0 and owner.snapshot().aimed_index==-1 and owner.snapshot().locked_index==-1 and owner.snapshot().elapsed_ms==0,"Off-center aim moved the viewport-centered outer window or retained the lock")
	check(not owner._inside(Vector2i(600,270),Vector3(480,270,0),Vector2i(960,540),8) and owner._inside(Vector2i(599,270),Vector3(480,270,0),Vector2i(960,540),8),"Outer viewport-width/8 border is not strict")
	var outer:=observation(1);outer.aim_point=Vector3(599,270,0)
	check(owner.advance(outer) and owner.snapshot().found_index==0 and owner.snapshot().aimed_index==-1,"Outer candidate incorrectly passed the inner aim window")
	var inner_border:=observation(1);inner_border.aim_point=Vector3(533,270,0)
	check(owner.advance(inner_border) and owner.snapshot().found_index==0 and owner.snapshot().aimed_index==-1,"Strict inner-width/18 border acquired")
	var inner:=observation(1);inner.aim_point=Vector3(532,270,0)
	check(owner.advance(inner) and owner.snapshot().aimed_index==0 and owner.snapshot().elapsed_ms==1,"Inside aim box did not restart acquisition")
	inner.aim_point=Vector3(531,270,0)
	check(owner.advance(inner) and owner.snapshot().elapsed_ms==2,"Moving aim within the same station reset pointer-based acquisition")
	var vertical:=observation(1);vertical.aim_point=Vector3(480,323,0)
	check(owner.advance(vertical) and owner.snapshot().aimed_index==-1,"Strict vertical inner border acquired")
	var inactive:=observation(1);inactive.station.active=false
	check(owner.advance(inactive) and owner.snapshot().found_index==-1 and owner.snapshot().locked_index==-1,"Inactive station gained a target pointer")

func verify_interruptions() -> void:
	for key in ["other_selected_target","held_primary","mining_approach_active","alternate_operation_active","selected_target_active"]:
		var owner:=fresh();check(owner.advance(observation(100)),owner.error)
		var blocked:=observation(100);blocked[key]=true
		check(owner.advance(blocked) and owner.snapshot().found_index==0 and owner.snapshot().aimed_index==-1 and owner.snapshot().elapsed_ms==0 and not owner.snapshot().mother_ship_locked,"Source owner gate failed: "+key)
		check(owner.advance(observation(100)) and owner.snapshot().elapsed_ms==100,"Interrupted station did not restart its clock: "+key)
	var owner:=fresh();check(owner.advance(observation(100)),owner.error)
	var previous: Dictionary=owner.snapshot();var fork: RefCounted=owner.fork_for_frame()
	check(fork.snapshot()==previous and fork.advance(observation(100)) and owner.snapshot()==previous and fork.snapshot().elapsed_ms==200,"Detached station lock fork changed its parent")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func finish() -> void:
	print("Void station targeting: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)
