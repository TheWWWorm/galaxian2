extends "res://tests/player_station_departure.gd"
## Continue the actual old Mac Gunant save into ordinary flight and fire the
## earned Microgun through the player session and its audio presenter.

func verify_departure(app: Control) -> void:
	await super.verify_departure(app)
	if failures:return
	var host: Control=app.game
	var session: Node=host.session
	check(session is Flight and session.can_control(),"Earned Gunant save did not reach controllable flight")
	if failures:return
	session.rebase_time(0)
	var fired:=false
	for tick in 8:
		check(session.step((tick+1)*100000,Vector2.ZERO,true),session.error)
		if failures:return
		var shot: Dictionary=session.snapshot().encounter.primary_fire
		if not shot.is_empty() and shot.weapons.size()==1 and shot.weapons[0].result.fired:
			check(shot.weapons[0].audio_events.size()==1 and shot.weapons[0].audio_events[0].source_id==66,"Saved player loadout fired without its original Microgun cue")
			var audio: Dictionary=session.flight_audio.snapshot()
			check(audio.active.has(66) and audio.unsupported.is_empty() and audio.history.any(func(row):return row.get("source_id")==66 and row.get("mount_id")==shot.weapons[0].mount_id),"Saved ordinary flight omitted the accepted Microgun playback")
			fired=true
			break
	check(fired,"Saved ordinary flight never launched the earned Microgun")
	if failures:return
	check(session.step(900000,Vector2.ZERO,false),session.error)
	check(not session.flight_audio.snapshot().active.has(66) and session.flight_audio._retiring.any(func(row):return row.get("release_tail",false)),"Releasing ordinary flight fire left the cannon loop active")
	check(session.step(1100000,Vector2.ZERO,false),session.error)
	check(session.step(1300000,Vector2.ZERO,false),session.error)
	check(not session.flight_audio.snapshot().active.has(66) and session.flight_audio._retiring.is_empty(),"Released ordinary flight cannon continued after its sample end")
