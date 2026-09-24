extends "res://tests/first_flight_session.gd"
## Source event transport through real session operations. Close placement is
## the established mining fixture; no new earned save or campaign is claimed.
var observed_cues: Array=[]
var observed_serial:=-1

func mine_trip(_args: PackedStringArray) -> bool:
	observed_cues=[];observed_serial=int(host.session.snapshot().mining_audio.serial)
	for manual_stop in [true,false]:
		var flight: RefCounted=host.session.flight_owner()
		var asteroid:={}
		for body in flight.snapshot().scenery.bodies.objects:
			if body.source_size_value==7 and not body.get("mined",false):asteroid=body;break
		if asteroid.is_empty():check(false,"No source core asteroid for mining audio");return false
		place_for_mining(flight,asteroid)
		flight._targeting.clear_selection()
		if not host.session._commit(flight,false):check(false,host.session.error);return false
		for tick in 10:key(KEY_SLASH)
		for tick in 100:
			if not step():return false
			if host.session.snapshot().mining_targeting.selected_object_index>=0:break
		check(host.session.snapshot().mining_targeting.selected_object_index>=0,"Native acquisition did not select the mining fixture")
		if failures:return false
		key(KEY_F)
		for tick in 200:
			if not step():return false
			if not host.session.snapshot().mining_session.drill.is_empty():break
		var accepted: Dictionary=host.session.snapshot()
		check(not accepted.mining_session.drill.is_empty(),"Audio regression never reached the source drill")
		if failures:return false
		if manual_stop:
			var owner: RefCounted=host.session.flight_owner()
			var before: Dictionary=owner.snapshot()
			var candidate: RefCounted=owner.stop_mining()
			check(candidate!=null and owner.snapshot()==before,"Preparing a stop changed the accepted audio or mining state")
			key(KEY_F)
			observe_audio()
			check(host.session.snapshot().world_elapsed_ms==accepted.world_elapsed_ms,"Manual stop advanced simulation time")
		else:
			for tick in 200:
				if not step(Vector2.ONE):return false
				if host.session.snapshot().mining_session.drill.is_empty():break
		var finished: Dictionary=host.session.snapshot()
		check(finished.mining_session.drill.is_empty(),"Mining did not stop")
		check(finished.mining_audio.serial>accepted.mining_audio.serial and finished.mining_audio.events==[{"action":"stop","source_id":1},{"action":"stop","source_id":3}],"Mining finish lost its ordered stop batch")
		if failures:return false
	check(observed_cues.count({"action":"start","source_id":26})==2,"Acquisition audio was omitted or repeated")
	check(observed_cues.count({"action":"start","source_id":1})==2,"Drill-start audio was omitted or repeated")
	check(observed_cues.has({"action":"start","source_id":2}),"Mining alignment omitted its source sound")
	check(observed_cues.count({"action":"stop","source_id":1})==2 and observed_cues.count({"action":"stop","source_id":3})==2,"Manual/automatic stops did not each publish once")
	# Stop this focused diagnostic before tutorial acknowledgement or station return.
	return false

func step(command:=Vector2(INF,INF)) -> bool:
	if not super.step(command):return false
	observe_audio()
	return true

func observe_audio() -> void:
	var batch: Dictionary=host.session.snapshot().get("mining_audio",{})
	if batch.is_empty():check(false,"Mining world omitted its audio batch");return
	if int(batch.serial)==observed_serial:return
	if int(batch.serial)<observed_serial:check(false,"Mining audio serial went backwards");return
	observed_serial=int(batch.serial)
	observed_cues.append_array(batch.events)
