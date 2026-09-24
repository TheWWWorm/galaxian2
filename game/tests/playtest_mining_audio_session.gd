extends "res://tests/player_reports_mining_audio.gd"
## Actual first-trip audio presenter, using the established close-placement fixture.
var active_drill_frames:=0

func mine_trip(args: PackedStringArray) -> bool:
	var first_history: int=host.session.flight_audio.snapshot().history.size()
	super.mine_trip(args)
	var audio: Dictionary=host.session.flight_audio.snapshot()
	var source: Array=audio.history.slice(first_history).filter(func(op):return op.get("source_id") in [1,2,3,26])
	check(source.map(func(op):return {"action":op.action,"source_id":op.source_id})==observed_cues,"Audio presenter changed accepted mining cue order")
	for event in [{"action":"start","source_id":26},{"action":"start","source_id":1},{"action":"stop","source_id":1},{"action":"stop","source_id":3}]:
		check(source.filter(func(op):return op.get("action")==event.action and op.get("source_id")==event.source_id).size()==2,"Accepted mining sound did not play twice: "+str(event)+" history="+str(source))
	check(source.filter(func(op):return op.get("action")=="start" and op.get("source_id")==2).size()>=2,"Mining approach did not play the source landing cue")
	check(active_drill_frames>0,"Drill sound never retained an active source loop")
	return false

func observe_audio() -> void:
	super.observe_audio()
	var state: Dictionary=host.session.snapshot()
	if state.mining_session.drill.is_empty():return
	var audio: Dictionary=host.session.flight_audio.snapshot()
	check(audio.active.has(1),"Live mining did not retain the original drill event")
	if not audio.active.has(1):return
	active_drill_frames+=1
	var layer: int=int(state.mining_session.drill.layer_index)
	var expected: float=(float(bindings.mining_drill.spin_rates[layer])-5.0)/33.0
	check(absf(float(audio.active[1].layers.sequence.parameter)-expected)<0.00001,"Live drill parameter differs from its source layer")
