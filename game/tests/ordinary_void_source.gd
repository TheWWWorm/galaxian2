extends SceneTree
## Detached source-selection vectors only. No earned career, save, location,
## mission completion, portal contact or campaign admission is constructed here.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Navigation=preload("res://src/simulation/contract_navigation.gd")
const Source=preload("res://src/simulation/ordinary_void_source.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
var checks:=0
var failures:=0
var library: RefCounted
var bindings: RefCounted
var catalogues: RefCounted

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3 and args.size()!=6:
		check(false,"Expected source196 triple and optional source195 control triple")
	else:
		library=Library.new();bindings=Bindings.new();catalogues=Catalogues.new()
		if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not catalogues.open(library):
			check(false,library.error+bindings.error+catalogues.error)
		else:
			verify_selection()
		if args.size()==6:verify_missing_capability(args[3],args[4])
	print("Ordinary Void source: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func retained(system_id: int=18,station_id: int=91,counter: int=0) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"source_system_id":system_id,"source_station_id":station_id,"eligible_selection_count":counter}

func seeded(seed: int) -> RefCounted:
	var stream:=Random.new()
	check(stream.seed_from(seed),stream.error)
	return stream

func access_flags() -> Array:
	var flags: Array=Navigation.initial_availability(bindings,catalogues,false)
	for i in flags.size():flags[i]=i in [10,15,18]
	return flags

func verify_selection() -> void:
	check(bindings.mido_travel.has("void_access"),"Source196 lacks Void access declarations")
	if not bindings.mido_travel.has("void_access"):return
	var flags:=access_flags()
	check(flags.size()==34 and not catalogues.tables.systems[18].station_ids.is_empty(),"Incomplete Void source catalogue")
	var fresh:=Source.new()
	check(fresh.configure_fresh(bindings,catalogues,flags) and fresh.snapshot()==retained(),"Fresh native source did not start at the imported location with zero observed selections")
	var fresh_random:=seeded(311)
	check(fresh.select(31,98,10,false,fresh_random).source==retained(),"Native initialization counted a pre32 location")
	var owner:=Source.new()
	check(owner.configure(bindings,catalogues,flags,retained(18,91,9)),owner.error)
	if owner.snapshot().is_empty():return
	var initial: Dictionary=owner.snapshot()
	flags[18]=false
	var stream:=seeded(311)
	var random_before: Dictionary=stream.snapshot()
	var before:=owner.select(31,98,10,false,stream)
	check(before.event=="unchanged" and before.source==initial and before.random_state==random_before,"Cursor31 changed the carried source")
	var counted:=owner.select(32,98,10,false,stream)
	check(counted.event=="counted" and counted.source.eligible_selection_count==10 and counted.source.source_station_id==91 and counted.random_state==random_before,"Qualifying selection did not count once")
	check(owner.snapshot()==initial and stream.snapshot()==random_before,"Prospective counter change mutated its owners")
	var repeated:=owner.select(32,98,10,false,stream)
	check(repeated==counted,"Selection depended on elapsed time or hidden state")
	var fork: RefCounted=owner.fork()
	check(fork.restore(counted.source),fork.error)
	check(owner.snapshot()==initial and fork.snapshot()==counted.source,"Fork and restore did not detach retained state")
	var skip_target: Dictionary=fork.select(32,10,10,true,stream)
	var skip_source: Dictionary=fork.select(33,91,10,false,stream)
	check(skip_target.event=="skipped" and skip_target.source==counted.source and skip_source.event=="skipped" and skip_source.source==counted.source,"Story target or current source added a counter call")
	var at_threshold: Dictionary=fork.select(32,98,10,false,stream)
	# Independent Java48 oracle for seed311: system draws 10,15,19,3,18;
	# 10/15 are excluded, 19/3 inaccessible, then station index3 of [90..94].
	check(at_threshold.event=="rerolled" and at_threshold.source.eligible_selection_count==0 and at_threshold.source.source_system_id==18 and at_threshold.source.source_station_id==93 and at_threshold.random_state=={"state":271975036150248},"Threshold11 source or exact RNG order changed")
	check(stream.snapshot()==random_before and fork.snapshot()==counted.source,"Reroll consumed caller randomness or committed state")
	var later: Dictionary=fork.select(44,98,29,false,stream)
	check(later.event=="rerolled" and later.source==at_threshold.source and later.random_state==at_threshold.random_state,"Cursor44 changed the reroll boundary")
	var disabled: Dictionary=fork.select(45,98,-1,false,stream)
	check(disabled.event=="disabled" and disabled.source.source_system_id==-10 and disabled.source.source_station_id==-10 and disabled.source.eligible_selection_count==10 and disabled.random_state==random_before,"Cursor45 did not disable both source fields")
	check(fork.restore(disabled.source) and fork.select(46,98,-1,false,stream).source==disabled.source,"Disabled source did not remain disabled")
	check(fork.select(44,98,-1,false,stream).is_empty() and fork.snapshot()==disabled.source and stream.snapshot()==random_before,"Earlier cursor revived a disabled source")
	check(owner.restore(retained(6,10,10)),owner.error)
	var old_source: Dictionary=owner.snapshot()
	var old_target:=owner.select(32,98,10,false,stream)
	check(old_target.event=="rerolled" and old_target.source.source_system_id==18 and owner.snapshot()==old_source,"Unselected story target equal to old source blocked a coherent reroll")
	check(owner.select(32,98,10,true,stream).is_empty() and owner.snapshot()==old_source and stream.snapshot()==random_before,"Incoherent selected-story retry entered a source loop")
	verify_refusals(stream,random_before,at_threshold)

func verify_refusals(stream: RefCounted,random_before: Dictionary,at_threshold: Dictionary) -> void:
	var owner:=Source.new()
	var flags:=access_flags()
	check(owner.configure(bindings,catalogues,flags,retained(18,91,10)),owner.error)
	var original:=owner.snapshot()
	for changed in [{"eligible_selection_count":-1},{"eligible_selection_count":11},{"eligible_selection_count":10.0},{"source_station_id":10},{"source_system_id":22},{"source_system_id":-10},{"binding_id":"foreign"},{"base_content_id":"foreign"}]:
		var invalid:=original.duplicate(true);invalid.merge(changed,true)
		check(not owner.restore(invalid) and owner.snapshot()==original,"Invalid retained source replaced current state: "+str(changed))
	var missing:=original.duplicate();missing.erase("eligible_selection_count")
	check(not owner.restore(missing) and owner.snapshot()==original,"Missing bootstrap counter was invented")
	var returned:=owner.select(32,98,10,false,stream)
	var changed_output: Dictionary=returned.source
	changed_output.source_station_id=-999
	check(owner.snapshot()==original and stream.snapshot()==random_before,"Returned mutable result aliased its owner")
	check(not owner.restore(returned.source) and owner.snapshot()==original,"Mutated result bypassed restore validation")
	var valid: Dictionary=at_threshold.source.duplicate(true)
	check(owner.restore(valid) and owner.snapshot()==valid,"A valid prospective source did not restore")
	valid.source_station_id=-999
	check(owner.snapshot().source_station_id!=-999,"Restore retained caller-owned mutable state")
	check(owner.restore(original),owner.error)
	for args in [[32.0,98,10,false],[32,-1,10,false],[32,98.0,10,false],[32,98,135,false],[32,98,10,1],[33,10,10,true],[32,98,29,false]]:
		check(owner.select(args[0],args[1],args[2],args[3],stream).is_empty() and owner.snapshot()==original and stream.snapshot()==random_before,"Invalid selection changed state or RNG: "+str(args))
	var unseeded:=Random.new()
	check(owner.select(32,98,10,false,unseeded).is_empty() and owner.snapshot()==original,"Unseeded random stream was accepted")
	var impossible:=flags.duplicate()
	for i in impossible.size():impossible[i]=i in [10,15]
	var no_candidate:=Source.new()
	check(no_candidate.configure(bindings,catalogues,impossible,original),no_candidate.error)
	check(no_candidate.select(32,98,10,false,stream).is_empty() and no_candidate.snapshot()==original and stream.snapshot()==random_before,"Unavailable/excluded systems entered the source draw")
	var invalid_configuration:=original.duplicate();invalid_configuration.binding_id="foreign"
	check(not owner.configure(bindings,catalogues,flags,invalid_configuration) and owner.snapshot()==original,"Invalid configuration discarded the current source")
	var invalid_flags:=flags.duplicate();invalid_flags[18]=1
	check(not owner.configure(bindings,catalogues,invalid_flags,original) and owner.snapshot()==original,"Nonboolean career access was admitted")
	var foreign_catalogue: String=catalogues.content_id
	catalogues.content_id="foreign"
	check(not owner.configure(bindings,catalogues,flags,original) and owner.snapshot()==original,"Foreign catalogue identity was admitted")
	catalogues.content_id=foreign_catalogue

func verify_missing_capability(content: String,pack: String) -> void:
	var old_library:=Library.new();var old_bindings:=Bindings.new();var old_catalogues:=Catalogues.new()
	if not old_library.open(content) or not old_bindings.open(pack,old_library.manifest) or not old_catalogues.open(old_library):
		check(false,old_library.error+old_bindings.error+old_catalogues.error);return
	check(not old_bindings.mido_travel.has("void_access"),"Control binding unexpectedly has Void access")
	var source:=Source.new()
	var flags:=Navigation.initial_availability(old_bindings,old_catalogues,false)
	var state:={"base_content_id":old_bindings.base_content_id,"binding_id":old_bindings.binding_id,
		"source_system_id":18,"source_station_id":91,"eligible_selection_count":0}
	check(not source.configure(old_bindings,old_catalogues,flags,state) and source.snapshot().is_empty(),"Earlier binding admitted an unsupported Void source")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
