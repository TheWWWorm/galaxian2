extends "res://tests/ordinary_contracts.gd"
## Save/load checks begin with the actual earned opening career.
const Archive=preload("res://src/simulation/station_archive.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")

class InterruptedSave extends "res://src/simulation/station_save_file.gd":
	func _write(path: String,bytes: PackedByteArray) -> bool:
		var file:=FileAccess.open(path,FileAccess.WRITE)
		if file!=null:file.store_buffer(bytes.slice(0,12));file.close()
		return reject("Simulated interrupted write")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify_save(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Station saves: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_save(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var station: RefCounted
	var source_save:=OS.get_environment("GOF2_SOURCE_SAVE")
	if source_save.is_empty():
		var checkpoint:=Checkpoint.new()
		station=checkpoint.open(OS.get_environment("GOF2_FREE_PLAY_STATION_SCENARIO"),bindings)
		if station==null:check(false,checkpoint.error);return
	else:
		var file:=SaveFile.new();var loader:=Archive.new()
		var document:=file.load_document(source_save,bindings,cat,library)
		if document.is_empty():check(false,file.error);return
		station=loader.restore(bindings,cat,library,document)
		if station==null:check(false,loader.error);return
	var original: Dictionary=station.snapshot();var archive:=Archive.new()
	var record:=archive.capture(station,bindings)
	if record.is_empty():check(false,archive.error);return
	var restored:=archive.restore(bindings,cat,library,record)
	if restored==null:check(false,archive.error);return
	check(restored.snapshot()==original,"Restoring the earned station changed its career or inventory")
	check(archive.capture(restored,bindings)==record,"The restored station changed its persistent record")
	check(restored.prepare_departure(bindings,cat)==station.prepare_departure(bindings,cat),"The loaded station prepares a different departure")
	check(station.snapshot()==original,"Detached save restoration changed the running station")
	for mutation in [
		[["version"],2],[["binding_id"],"0".repeat(64)],[["station","mission","station_id"],98],[["station","mission"],[]],
		[["station","acknowledged"],false],[["station","player_cache","values","hull"],0],
		[["inventory","loadout","slots"],[{"item_id":-1}]],[["inventory","cargo","used"],99],
		[["inventory","prices","installed"],[]],[["inventory","transactions"],-1],
		[["career","credits"],-1],[["career","progress","rank"],99],
		[["career","passengers"],3],[["career","pending_result"],{"serial":99}],
		[["locations","current_station_id"],56],[["locations","locations"],[]]]:
		var broken:=record.duplicate(true);var parent: Dictionary=broken
		for index in mutation[0].size()-1:parent=parent[mutation[0][index]]
		parent[mutation[0].back()]=mutation[1]
		check(archive.restore(bindings,cat,library,broken)==null and not archive.error.is_empty(),"Malformed save accepted: "+str(mutation[0]))
	for key in ["active_offer_id","accepted_contact","pending_result"]:
		var broken:=record.duplicate(true);broken.career.erase(key)
		check(archive.restore(bindings,cat,library,broken)==null,"Missing career field accepted: "+key)
	check(not Archive.data_tree(RefCounted.new()),"The save format accepted an executable object")
	var accepted: RefCounted=station.fork();var selected:=-1
	for id in original.contracts.offers:
		var quote: Dictionary=original.contracts.offers[id].offer
		if quote.mission.kind==0 and accepted.contract_preview(id,bindings).get("can_accept",false):selected=id;break
	if selected<0 or not accepted.accept_contract(selected,false,bindings):check(false,accepted.error);return
	var active:=archive.capture(accepted,bindings)
	var loaded_active:=archive.restore(bindings,cat,library,active)
	if loaded_active==null:check(false,archive.error);return
	check(loaded_active.snapshot()==accepted.snapshot(),"Saving an accepted courier lost its cargo, consumed contact or pending story")
	check(not loaded_active.accept_contract(selected,false,bindings),"Loading made the accepted contact available again")
	var overfilled: RefCounted=accepted.fork()
	if not overfilled.open_equipment(bindings,cat,library,[1789100000,1789100000,1789100000]):check(false,overfilled.error);return
	var purchased:=-1
	for row in overfilled.equipment_owner().snapshot().market_rows:
		if row.stock>0 and not row.mission and row.unit_price>0 and row.unit_price<=overfilled.snapshot().contracts.credits:purchased=row.item_id;break
	if purchased<0 or not overfilled.equipment_action("buy",purchased,bindings,cat) or not overfilled.close_equipment():check(false,overfilled.error);return
	var loaded_full:=archive.restore(bindings,cat,library,archive.capture(overfilled,bindings))
	if loaded_full==null:check(false,archive.error);return
	check(loaded_full.snapshot()==overfilled.snapshot(),"Loading lost a paid purchase or its changed station stock")
	check(loaded_full.snapshot().cargo.used>loaded_full.snapshot().cargo.capacity and loaded_full.prepare_departure(bindings,cat).is_empty(),"An overfilled saved station bypassed the departure guard")
	var unarmed: RefCounted=station.fork()
	if not unarmed.open_equipment(bindings,cat,library,[1789100000,1789100000,1789100000]):check(false,unarmed.error);return
	var slots: Array=unarmed.equipment_owner().snapshot().loadout.slots
	for index in slots.size():
		if slots[index]!=null and not unarmed.equipment_action("unmount",int(slots[index].item_id),bindings,cat,index):check(false,unarmed.error);return
	check(archive.capture(unarmed,bindings).is_empty(),"A save discarded the open fitting session")
	if not unarmed.close_equipment():check(false,unarmed.error);return
	var naked:=archive.restore(bindings,cat,library,archive.capture(unarmed,bindings))
	if naked==null:check(false,archive.error);return
	check(naked.snapshot()==unarmed.snapshot() and naked.snapshot().loadout.equipment_ids.is_empty(),"Restore replaced the actual unarmed inventory")
	var construction:=Construction.new()
	check(construction.prepare_free(bindings,cat,naked,4096,1789100000),construction.error)
	if failures:return
	verify_files(bindings,cat,library,station,accepted,record,active)

func verify_files(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted,accepted: RefCounted,original: Dictionary,active: Dictionary) -> void:
	var directory:=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if directory.is_empty() or not Checkpoint.private_path(directory+"/save.bin"):check(false,"Set a private save-test directory");return
	var path:=SaveFile.path_for(directory.path_join(str(Time.get_ticks_usec())),bindings)
	var file:=SaveFile.new()
	if not file.save(path,station,bindings,cat,library):check(false,file.error);return
	check(file.load_document(path,bindings,cat,library)==original and not file.recovered_backup,"The first save did not reload exactly")
	if not file.save(path,accepted,bindings,cat,library):check(false,file.error);return
	check(file.load_document(path,bindings,cat,library)==active,"The accepted contract did not persist through the file")
	check(file.read_document(path+".bak")==original,"Saving discarded the previous viable station")
	var before:=FileAccess.get_file_as_bytes(path)
	var interrupted:=InterruptedSave.new()
	check(not interrupted.save(path,station,bindings,cat,library) and FileAccess.get_file_as_bytes(path)==before,"An interrupted write replaced the accepted save")
	check(file.load_document(path,bindings,cat,library)==active,"A partial temporary file interfered with loading")
	var corrupt:=FileAccess.open(path,FileAccess.WRITE);corrupt.store_buffer(before.slice(0,12));corrupt.close()
	check(file.load_document(path,bindings,cat,library)==original and file.recovered_backup,"A truncated save did not recover its valid previous station")
	if not file.save(path,accepted,bindings,cat,library):check(false,file.error);return
	check(file.read_document(path+".bak")==original,"A damaged primary overwrote the viable backup")
	var damaged:=FileAccess.get_file_as_bytes(path);damaged[damaged.size()-1]^=1
	corrupt=FileAccess.open(path,FileAccess.WRITE);corrupt.store_buffer(damaged);corrupt.close()
	check(file.load_document(path,bindings,cat,library)==original and file.recovered_backup,"A damaged payload bypassed the checksum or viable backup")
	print("Private save round trip: ",path)
