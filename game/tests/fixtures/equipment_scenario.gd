extends RefCounted
## Private, test-only capture of an earned equipment tutorial transition.
## Replaying the recorded transactions never restores or changes a player save.
const Equipment=preload("res://src/simulation/station_equipment.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const MAX_BYTES=4*1024*1024
const PRODUCERS=["res://src/simulation/station_equipment.gd",
	"res://src/simulation/station_entry.gd",
	"res://src/presentation/station_session.gd",
	"res://src/simulation/opening_loadout.gd",
	"res://src/content/station_equipment_definitions.gd",
	"res://src/content/full_hold_return_definitions.gd",
	"res://src/content/station_return_definitions.gd"]
const TRANSACTIONS=[["buy",0],["sell",0],["buy",0],["mount",0],["unmount",0],
	["buy",22],["mount",22],["buy",55],["mount",55]]
var error:=""
var document:={}

static func producer_hashes() -> Dictionary:
	var result:={}
	for path in PRODUCERS:result[path]=FileAccess.get_sha256(path)
	return result

static func capture(path: String, bindings: RefCounted, before: Dictionary, after: Dictionary, equipment: RefCounted) -> String:
	var project:=ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()+"/"
	var target:=path.simplify_path()
	if not target.is_absolute_path() or target.begins_with(project):return "Keep captured scenarios outside the source repository"
	if after.get("campaign_cursor")!=7 or not after.get("equipment_acknowledged",false) or not equipment.requirements().satisfied:return "Scenario requires acknowledged equipment completion"
	var data:={"schema":1,"scenario":"equipped_combat_training","base_content_id":bindings.base_content_id,
		"binding_id":bindings.binding_id,"producers":producer_hashes(),"station_before":before.duplicate(true),
		"station_after":after.duplicate(true),"equipment":equipment.snapshot()}
	var file:=FileAccess.open(target,FileAccess.WRITE)
	if file==null:return "Cannot write equipment scenario"
	file.store_var(data);file.close()
	return ""

func open(path: String, bindings: RefCounted, catalogues: RefCounted) -> RefCounted:
	error="";document={}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>MAX_BYTES:return fail("Missing or oversized equipment scenario")
	var data: Variant=file.get_var(false);file.close()
	return restore(data,bindings,catalogues)

func restore(data: Variant, bindings: RefCounted, catalogues: RefCounted) -> RefCounted:
	error="";document={}
	if not data is Dictionary or data.get("schema")!=1 or data.get("scenario")!="equipped_combat_training":return fail("Unsupported equipment scenario")
	if data.get("base_content_id")!=bindings.base_content_id or data.get("binding_id")!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id:return fail("Equipment scenario belongs to different content or bindings")
	if data.get("producers")!=producer_hashes():return fail("Equipment prerequisite code changed; capture the integration scenario again")
	if not data.get("station_before") is Dictionary or not data.get("station_after") is Dictionary or not data.get("equipment") is Dictionary:return fail("Equipment scenario lacks its earned states")
	var after: Dictionary=data.station_after
	if after.get("campaign_cursor")!=7 or after.get("phase")!="combat_departure_required" or not after.get("equipment_acknowledged",false):return fail("Equipment scenario has not acknowledged its transition")
	var equipment:=Equipment.new()
	if not equipment.configure(bindings,catalogues,data.station_before):return fail(equipment.error)
	for action in TRANSACTIONS:
		if not equipment.transact(action[0],action[1]):return fail(equipment.error)
	var state:=equipment.snapshot()
	if state!=data.equipment or not equipment.requirements().satisfied:return fail("Scenario transactions differ from the captured equipment")
	if after.get("equipment")!=state or after.get("loadout")!=state.loadout or after.get("cargo")!=state.cargo:return fail("Scenario equipment differs from the earned station state")
	document=data.duplicate(true)
	return equipment

func fail(message: String) -> RefCounted:
	error=message
	return null

func station_owner(bindings: RefCounted, catalogues: RefCounted) -> RefCounted:
	# Restore only a capture already checked against the real tutorial producer
	# and replay every equipment transaction again. This helper never writes a save.
	var data:=document.duplicate(true)
	var equipment:=restore(data,bindings,catalogues)
	if equipment==null:return null
	var station:=Station.new()
	station._state=data.station_after.duplicate(true)
	for key in ["dialogue","equipment","boundary"]:station._state.erase(key)
	station._rules=bindings.station_entry.duplicate(true)
	station._progress_rules=bindings.opening_handoff.duplicate(true)
	station._return_rules=bindings.full_hold_return.duplicate(true)
	station._equipment_rules=bindings.station_equipment.duplicate(true)
	station._equipment=equipment
	# The acknowledged line list is retained so a snapshot does not change its
	# recorded index/count. No new dialogue or acknowledgement is introduced.
	station._lines=bindings.station_equipment.events.duplicate(true)
	station._equipment_lines=station._lines.duplicate(true)
	return station
