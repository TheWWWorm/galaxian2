extends RefCounted
const Accounting=preload("res://src/simulation/npc_death_accounting.gd")

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
	return {"escape":{"boundary":"arrival_transition_required"},"radio":{"finished":finished},"combat":{"actors":actors},
		"world_frame":{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"player":live,"player_cache":player.cache_snapshot(),"controller":{"death_accounting":accounting.snapshot()}}}
