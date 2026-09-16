extends "res://tests/station_save.gd"
## Reuse the application's earned post-visit save for corruption, shopping
## and interrupted-write checks without replaying the journey.

func verify_save(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var file:=SaveFile.new();var archive:=Archive.new()
	var record:=file.load_document(OS.get_environment("GOF2_SOURCE_SAVE"),bindings,cat,library)
	if record.is_empty():check(false,file.error);return
	var station:=archive.restore(bindings,cat,library,record)
	if station==null:check(false,archive.error);return
	var original: Dictionary=station.snapshot()
	check(record.version==3 and original.campaign_cursor==19 and original.loadout.station_id in [56,57],"Use the application's earned Suttnar continuation")
	check(original.mission=={"kind":156,"station_id":55,"reward":0,"bonus":0,"source_parameter":0} and original.contracts.mission.kind==11 and original.contracts.mission.station_id==99 and original.contracts.passengers==3,"The retained pending story or accepted passengers changed")
	check(archive.capture(station,bindings)==record and not station.prepare_departure(bindings,cat).is_empty(),"The saved continuation cannot round-trip and depart")
	for mutation in [
		[["version"],1],[["version"],2],[["binding_id"],"0".repeat(64)],
		[["station","campaign_cursor"],18],[["career","campaign_cursor"],18],
		[["station","mission","station_id"],56],[["station","mission"],[]],
		[["station","acknowledged"],false],[["station","player_cache","values","hull"],0],
		[["inventory","cargo","used"],-1],[["career","progress","rank_score"],0],
		[["career","mission"],{}],[["locations","current_station_id"],55]]:
		var broken:=record.duplicate(true);var parent: Dictionary=broken
		for index in mutation[0].size()-1:parent=parent[mutation[0][index]]
		parent[mutation[0].back()]=mutation[1]
		check(archive.restore(bindings,cat,library,broken)==null and not archive.error.is_empty(),"Malformed continuation accepted: "+str(mutation[0]))
	var purchased: RefCounted=station.fork()
	if not purchased.open_equipment(bindings,cat,library,[1789100000,1789100000,1789100000]):check(false,purchased.error);return
	var selected:=-1
	for row in purchased.equipment_owner().snapshot().market_rows:
		if row.stock>0 and not row.mission and row.unit_price>0 and row.unit_price<=original.contracts.credits:selected=row.item_id;break
	if selected<0 or not purchased.equipment_action("buy",selected,bindings,cat) or not purchased.close_equipment():check(false,purchased.error);return
	var paid:=archive.capture(purchased,bindings)
	var loaded:=archive.restore(bindings,cat,library,paid)
	if loaded==null:check(false,archive.error);return
	check(loaded.snapshot()==purchased.snapshot() and loaded.snapshot().contracts.credits<original.contracts.credits,"The continuation lost a paid purchase or changed station stock")
	check(loaded.snapshot().contracts.mission==original.contracts.mission and loaded.snapshot().mission==original.mission,"Shopping after the visit changed the accepted delivery or story")
	check(station.snapshot()==original,"A failed restore or detached purchase changed the saved career")
	if failures:return
	verify_files(bindings,cat,library,station,purchased,record,paid)
