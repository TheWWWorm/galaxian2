extends "res://tests/combat_training_destruction.gd"
## The same component assertions as the full integration path, starting from an
## earned, private equipment capture. No application/session coverage is claimed.
const Scenario=preload("res://tests/fixtures/equipment_scenario.gd")

func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Combat-training components: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not lib.select_language("gb") or not cat.open(lib) or not visuals.open(args[2],lib.manifest):
		check(false,lib.error+bindings.error+cat.error+visuals.error);return
	var path:=OS.get_environment("GOF2_SCENARIO_INPUT")
	if path.is_empty():check(false,"Capture an equipment scenario through station_equipment before this focused run");return
	var scenario:=Scenario.new()
	var equipment: RefCounted=scenario.open(path,bindings,cat)
	if equipment==null:check(false,scenario.error);return
	var before: Dictionary=equipment.snapshot()
	var data:=scenario.document.duplicate(true)
	verify_training_construction(args,equipment)
	verify_training_control(args,equipment)
	verify_training_weapons(args,equipment)
	verify_training_destruction(args,equipment)
	check(equipment.snapshot()==before,"Focused component checks changed their equipment prerequisite")
	for key in ["base_content_id","binding_id","producers","station_before","equipment"]:
		var bad:=data.duplicate(true);bad[key]={} if key in ["producers","station_before","equipment"] else "invalid"
		check(Scenario.new().restore(bad,bindings,cat)==null,"Invalid scenario accepted: "+key)
	var unearned:=data.duplicate(true);unearned.station_after.equipment_acknowledged=false
	check(Scenario.new().restore(unearned,bindings,cat)==null,"Unacknowledged scenario entered component checks")
