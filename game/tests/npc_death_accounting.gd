extends SceneTree
const Accounting = preload("res://src/simulation/npc_death_accounting.gd")
const Definitions = preload("res://src/content/npc_death_accounting_definitions.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Pass content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): check_profile(args[i],args[i+1])
	print("NPC death accounting checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_profile(content: String, path: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(path,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var ledger := Accounting.new();var combat := Combat.new()
	if not combat.configure(bindings,catalogues,0.5): check(false,combat.error);return
	if bindings.opening_actors.npc_initialization.get("death_accounting",{}).is_empty():
		check(not ledger.configure(bindings) and ledger.snapshot().is_empty(),"Legacy pack invented counter declarations")
		var prior: Dictionary=combat.snapshot()
		check(combat.normal_hit(0,150,true).is_empty() and combat.snapshot()==prior,"Legacy pack accepted unsupported source attribution")
		check(not prior.actors[0].has("nonplayer_kill"),"Legacy pack invented attribution")
		return
	check(ledger.configure(bindings),ledger.error)
	for actor in combat.snapshot().actors:
		check(actor.nonplayer_kill==false and actor.vitals.hull==150,"Constructor attribution or authored hull changed")
	var original: Dictionary=combat.snapshot()
	check(not combat.normal_hit(0,150,true).accepted and combat.snapshot()==original,"Inactive hit retained kill attribution")
	var flags := [];flags.resize(bindings.opening_dialogue.events.size());flags.fill(false);flags[7]=true
	check(combat.update(original,3,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"finished":flags}),combat.error)
	for id in 3: check(combat.refresh_hostility(id),combat.error)
	for invalid in [null,0,1,"true",0.0]:
		var prior: Dictionary=combat.snapshot()
		check(combat.normal_hit(0,1,invalid).is_empty() and combat.snapshot()==prior,"Invalid attribution changed hull")
	check(combat.normal_hit(0,-1,true).is_empty() and not combat.snapshot().actors[0].nonplayer_kill,"Invalid damage changed attribution")
	check(combat.normal_hit(0,0,true).accepted and not combat.snapshot().actors[0].nonplayer_kill,"Zero damage changed attribution")
	check(not combat.normal_hit(0,49,true).destroyed_now and not combat.snapshot().actors[0].nonplayer_kill,"Nonlethal NPC hit stole player credit")
	check(combat.normal_hit(0,101,false).destroyed_now and not combat.snapshot().actors[0].nonplayer_kill,"Player lethal hit retained prior NPC credit")
	check(not combat.normal_hit(0,150,true).accepted and not combat.snapshot().actors[0].nonplayer_kill,"Postmortem hit stole player credit")
	check(not combat.normal_hit(1,149,false).destroyed_now,"Nonlethal player fixture died")
	check(combat.normal_hit(1,1,true).destroyed_now and combat.snapshot().actors[1].nonplayer_kill,"Final NPC hit was credited to player")
	check(combat.normal_hit(2,150,true).destroyed_now and combat.snapshot().actors[2].nonplayer_kill,"NPC lethal hit lost attribution")
	check(not combat.normal_hit(2,0,false).accepted and combat.snapshot().actors[2].nonplayer_kill,"Postmortem player hit stole credit")
	var bodies: Dictionary=combat.snapshot()
	check(combat.fork_for_frame().snapshot()==bodies,"Combat fork lost attribution")
	var base: Dictionary=ledger.snapshot()
	for field in ["base_content_id","binding_id","actor_id","actor_kind","hostile","active","actor_mode","nonplayer_kill","vitals"]:
		var bad: Dictionary=bodies.actors[0].duplicate(true);bad.erase(field)
		check(ledger.record(bad).is_empty() and ledger.snapshot()==base,"Incomplete death changed counters: "+field)
	for field in ["base_content_id","binding_id"]:
		var bad: Dictionary=bodies.actors[0].duplicate(true);bad[field]="0".repeat(64)
		check(ledger.record(bad).is_empty() and ledger.snapshot()==base,"Cross-identity death counted")
	for field in ["hostile","active"]:
		var bad: Dictionary=bodies.actors[0].duplicate(true);bad[field]=false
		check(ledger.record(bad).is_empty() and ledger.snapshot()==base,"Unsupported death path counted")
	var live: Dictionary=bodies.actors[0].duplicate(true);live.vitals.hull=1
	check(ledger.record(live).is_empty() and ledger.snapshot()==base,"Living ship counted as a kill")
	var candidate: RefCounted=ledger.fork_for_frame()
	for id in 3:
		var event: Dictionary=candidate.record(bodies.actors[id])
		check(not event.is_empty() and event.nonplayer_kill==(id!=0),"Incorrect retained lethal source")
		if not event.is_empty():
			check(event.counter_deltas.player_kills==(1 if id==0 else 0) and event.counter_deltas.pirate_kills==(1 if id==0 else 0),"Uncredited death granted player statistics")
	var done: Dictionary=candidate.snapshot()
	check(ledger.snapshot()==base,"Candidate committed counters to original ledger")
	check(done.counter_deltas=={"hostile_remaining":-3,"hostile_deaths":3,"world_player_kills":1,"world_other_kills":2,"player_kills":1,"pirate_kills":1},"Mixed-source death deltas disagree with source rules")
	for id in 3: check(candidate.record(bodies.actors[id]).is_empty() and candidate.snapshot()==done,"Duplicate death changed counters")
	done.events.clear();done.counter_deltas.player_kills=99
	check(candidate.snapshot().events.size()==3 and candidate.snapshot().counter_deltas.player_kills==1,"Counter/event snapshot aliases owner")
	var npc: Dictionary=bindings.opening_actors.npc_initialization
	var architecture: String="armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64"
	check(Definitions.validate(npc.death_accounting,10000000,architecture,npc).is_empty(),"Valid declaration rejected")
	for field in Definitions.VALUES:
		var bad: Dictionary=npc.death_accounting.duplicate(true);bad[field]=null
		check(not Definitions.validate(bad,10000000,architecture,npc).is_empty(),"Changed declaration accepted: "+field)
	for field in npc.death_accounting.provenance:
		var bad: Dictionary=npc.death_accounting.duplicate(true);bad.provenance[field].offset+=2
		check(not Definitions.validate(bad,10000000,architecture,npc).is_empty(),"Disconnected source span accepted")
	print(library.manifest.profile.edition,": lethal source, split credit, duplicate rejection and candidate rollback verified")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)
