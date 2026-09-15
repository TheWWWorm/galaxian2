extends RefCounted
const Accounting=preload("res://src/simulation/npc_death_accounting.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")

static func progress(bindings: RefCounted,cursor: int,kills: int) -> Dictionary:
	# Explicit easy-difficulty opening fixture, without an intervening kill.
	var score:=cursor+3*kills
	var rank:=0
	for id in bindings.opening_handoff.rank_thresholds.size():
		if score>=int(bindings.opening_handoff.rank_thresholds[id]):rank=id
	var result:={"campaign_cursor":cursor,"rank":rank,"rank_score":score,"player_kills":kills,"pirate_kills":kills,"other_score":0}
	if Reputation.available(bindings):
		result.reputation=Reputation.initial(bindings);result.reputation.axes[1]=-kills
	return result

static func completed(bindings: RefCounted,player: RefCounted,credits: int) -> Dictionary:
	var accounting:=Accounting.new()
	if not accounting.configure(bindings):return {}
	var actors:=[]
	for id in 3:
		var actor:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"actor_id":id,"actor_kind":8,"actor_mode":1,"active":true,"hostile":true,"vitals":{"hull":0},"nonplayer_kill":id>=credits}
		actors.append(actor)
		if accounting.record(actor).is_empty():return {}
	var finished:=[];finished.resize(bindings.opening_dialogue.events.size());finished.fill(true)
	var live: Dictionary=player.snapshot();live.vitals.armor=0;live.vitals.shield=0.0
	var combat:={"actors":actors}
	# Synthetic completed-state fixture. Live lethal-hit retention is checked
	# separately through the combat group and the earned flight prerequisites.
	if Reputation.available(bindings):
		var history:=Reputation.new()
		if not history.configure(bindings,0,[8,8,8],0.5):return {}
		for actor in actors:
			if not history.record_lethal(actor):return {}
		combat.reputation=history.snapshot()
	return {"escape":{"boundary":"arrival_transition_required"},"radio":{"finished":finished},"combat":combat,
		"world_frame":{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"player":live,"player_cache":player.cache_snapshot(),"controller":{"death_accounting":accounting.snapshot()}}}
