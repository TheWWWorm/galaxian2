extends "res://tests/opening_handoff.gd"
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const Combat=preload("res://src/simulation/opening_combat_group.gd")
const Timeline=preload("res://src/simulation/opening_timeline.gd")
const Accounting=preload("res://src/simulation/npc_death_accounting.gd")
const Objective=preload("res://src/simulation/mining_objective.gd")
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")

func run():
	var unconfigured:=Objective.new()
	check(not unconfigured.observe_combat(Encounter.new()) and unconfigured.snapshot().is_empty(),"Unconfigured objective accepted a combat observation")
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify_profile(args[0],args[1])
	print("Faction reputation: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify_profile(content: String, pack: String):
	super.verify_profile(content,pack)
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(content) or not bindings.open(pack,lib.manifest) or not cat.open(lib) or not lib.select_language("gb"):check(false,lib.error+bindings.error+cat.error);return
	if not Reputation.available(bindings):
		check(not Reputation.new().configure(bindings,0,[8,8,8],0.5),"Older profile invented exact reputation")
		return
	var timeline:=Timeline.new()
	var durations:=[];durations.resize(23);durations.fill(1)
	if not timeline.configure(bindings,cat,lib,durations,0.5):check(false,timeline.error);return
	var scene: Dictionary=timeline.snapshot().scene
	var radio: Dictionary=timeline.snapshot().radio;radio.finished[7]=true
	for difficulty in [0.5,1.0,1.5,1.4999999]:
		var combat:=Combat.new()
		if not combat.configure(bindings,cat,difficulty):check(false,combat.error);return
		var initial:=Reputation.initial(bindings)
		check(initial=={"axes":[30,0],"override":-1},"Fresh campaign reputation changed")
		check(not combat.normal_hit(0,999).accepted and combat.reputation_after(initial)==initial,"Inactive actor altered reputation")
		check(combat.update(scene,3,radio),combat.error)
		for id in 3:check(combat.refresh_hostility(id),combat.error)
		check(combat.normal_hit(0,149).accepted and combat.snapshot().reputation.events.is_empty(),"Nonlethal damage altered reputation")
		var held:=combat.snapshot();var fork: RefCounted=combat.fork_for_frame()
		check(fork.normal_hit(0,1).destroyed_now and combat.snapshot()==held,"Prospective lethal hit changed accepted reputation")
		var multiplier:=2 if difficulty==1.5 else 1
		check(fork.reputation_after(initial)=={"axes":[30,-multiplier],"override":-1},"Pirate reputation lost exact difficulty or faction mapping")
		combat=fork
		check(combat.normal_hit(1,150,true).destroyed_now,"NPC lethal fixture failed")
		check(combat.reputation_after(initial).axes[1]==-multiplier and combat.snapshot().reputation.events[1].change==0,"NPC kill changed player reputation")
		check(combat.normal_hit(2,100000).destroyed_now,"Overkill fixture failed")
		held=combat.snapshot()
		check(not combat.normal_hit(0,100000).accepted and combat.snapshot()==held,"Repeated hit on a dead actor repeated reputation")
		check(combat.normal_hit(0,-1).is_empty() and combat.snapshot()==held,"Rejected hit partially committed reputation")
		check(combat.reputation_after(initial)=={"axes":[30,-2*multiplier],"override":-1},"Three actual lethal hits lost their attribution")
		check(combat.reputation_after({"axes":[30,-100],"override":-1}).axes[1]==-100,"Pirate reputation crossed the source clamp")
		var retained:=Reputation.new()
		check(retained.restore(bindings,held.reputation) and retained.apply_to(initial)==combat.reputation_after(initial),retained.error)
		var history:=retained.snapshot()
		for kind in ["duplicate","change","identity","affiliation","difficulty","cursor"]:
			var bad:=history.duplicate(true)
			match kind:
				"duplicate":bad.events.append(bad.events[0])
				"change":bad.events[0].change=99
				"identity":bad.binding_id="foreign"
				"affiliation":bad.actor_kinds[0]=3
				"difficulty":bad.difficulty=1.0 if difficulty==1.5 else 1.5
				"cursor":bad.campaign_cursor=7
			check(not retained.restore(bindings,bad) and retained.snapshot()==history,"Malformed reputation history changed its retained owner: "+kind)
		# The synthetic completed-scene fixture supplies death accounting; the
		# actual group above supplies all three normal hits and their difficulty.
		var player:=Player.new();check(player.configure(bindings,cat),player.error)
		var opening:=Fixture.completed(bindings,player,2);opening.combat=combat.snapshot()
		var accounting:=Accounting.new();check(accounting.configure(bindings),accounting.error)
		for actor in opening.combat.actors:check(not accounting.record(actor).is_empty(),accounting.error)
		opening.world_frame.controller.death_accounting=accounting.snapshot()
		var handoff:=Handoff.new();var packet:=handoff.prepare(bindings,cat,opening)
		check(not packet.is_empty(),handoff.error)
		if not packet.is_empty():check(packet.progress.reputation==combat.reputation_after(initial),"Rescue handoff reconstructed reputation from death counters")
		var malformed:=opening.duplicate(true);malformed.combat.reputation.events.pop_back()
		check(handoff.prepare(bindings,cat,malformed).is_empty(),"Rescue accepted an incomplete actual hit history")
	verify_clamping(bindings)

func verify_clamping(bindings: RefCounted):
	# Declared terminal-state fixtures isolate order: clamp each hit rather than
	# applying a summed death-counter delta. Live Gunant hits are covered by the
	# combat-training destruction check, including his initial actor mode.
	for order in [[3,0],[0,3]]:
		var history:=Reputation.new();check(history.configure(bindings,7,[8,8,8,3],0.5),history.error)
		for id in order:
			var actor:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"actor_id":id,"actor_kind":3 if id==3 else 8,"vitals":{"hull":0},"nonplayer_kill":false}
			check(history.record_lethal(actor),history.error)
		var prior:={"axes":[30,99],"override":-1}
		var expected:=99 if order[0]==3 else 100
		check(history.apply_to(prior).axes[1]==expected and prior.axes[1]==99,"Reputation lost per-hit ordering at the clamp or mutated its prior state")
		var before:=history.snapshot()
		for state in [{"axes":[30,0],"override":3},{"axes":[30,101],"override":-1},{"axes":[30,0.5],"override":-1},{}]:
			check(history.apply_to(state).is_empty() and history.snapshot()==before,"Unsupported reputation input changed the accepted hit history")
