extends "res://tests/convoy_destruction_geometry.gd"
## Share the original-mesh GPU check; this is an isolated lethal/lighting fixture.
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	capture_prefix="alioth";camera_offset=Vector3(15000,9000,-18000)
	if args.size() in [3,4]:
		prepare_alioth(args)
		if not failures:await render_stages(args)
	else:check(false,"Expected content, bindings, visuals and optional captures")
	print("Alioth breakup geometry: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func prepare_alioth(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var seed:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":98,"system_id":19,"ship_id":0,"equipment_ids":[22,86,81,55]}
	var context:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":16,"station_id":98,"system_id":19,"rank":0,"difficulty":0.5,"mission_kind":4,"mission_story":true,"mission_completed":false}
	var construction:=Construction.new()
	if not construction.configure_alioth_attack(bindings,cat,seed,context,Vector3.ZERO) or construction.generate({"state":42}).is_empty():check(false,construction.error);return
	_resources=CapitalResources.new()
	var death:=CapitalDeath.new();var actor:=Actor.new()
	if not _resources.configure_alioth_attack(library,bindings) or not death.configure_alioth_attack(bindings,_resources,construction,0) or not actor.configure_alioth_attack(bindings,cat,construction,0):check(false,_resources.error+death.error+actor.error);return
	if not actor.enable_alioth_combat() or actor.normal_hit(actor.snapshot().vitals.hull,true).is_empty():check(false,actor.error);return
	var started:=death.advance(16,construction.snapshot().random_state,actor.snapshot())
	if started.is_empty():check(false,death.error);return
	var random: Dictionary=started.random_state
	_stages.append({"label":"entry","owner":death.fork_for_frame()})
	var midpoint: float=(death.snapshot().animation.start_ms+death.snapshot().animation.end_ms)/2.0
	while death.snapshot().phase=="animation":
		var result:=death.advance(100,random)
		if result.is_empty():check(false,death.error);return
		random=result.random_state
		if _stages.size()==1 and death.snapshot().animation.time_ms>=midpoint:_stages.append({"label":"middle","owner":death.fork_for_frame()})
	_stages.append({"label":"breakup","owner":death.fork_for_frame()})
	var wreck:=death.advance(150,random)
	if wreck.is_empty():check(false,death.error);return
	_stages.append({"label":"wreck","owner":death.fork_for_frame()})
	check(death.snapshot().material_id==33354 and death.snapshot().model_scale==1.0 and not death.snapshot().cargo.eligible,"Alioth freighter lost its original wreck or invented cleared cargo")
