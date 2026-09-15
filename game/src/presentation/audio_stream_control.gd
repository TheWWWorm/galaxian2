extends RefCounted
## Shared native stream setup and the queued-3D-play pause workaround.

const BUSES={"Music":"GoF2 Music","FX":"GoF2 FX","Voice":"GoF2 Voice"}

static func ensure_buses() -> void:
	for name in BUSES.values():
		if AudioServer.get_bus_index(name)<0:
			AudioServer.add_bus();AudioServer.set_bus_name(AudioServer.bus_count-1,name)

static func set_levels(music: float,fx: float,voice: float) -> void:
	ensure_buses()
	var levels:={"Music":music,"FX":fx,"Voice":voice}
	for category in levels:
		var index:=AudioServer.get_bus_index(BUSES[category]);var level: float=clampf(levels[category],0.0,1.0)
		AudioServer.set_bus_mute(index,level==0.0)
		AudioServer.set_bus_volume_db(index,linear_to_db(level) if level>0 else -80.0)

static func player(stream: AudioStream, spatial: bool, category: String="FX") -> Node:
	ensure_buses()
	var node: Node=AudioStreamPlayer3D.new() if spatial else AudioStreamPlayer.new()
	node.stream=stream;node.bus=BUSES.get(category,BUSES.FX)
	if spatial:
		node.attenuation_model=AudioStreamPlayer3D.ATTENUATION_DISABLED
		node.attenuation_filter_cutoff_hz=20500
		node.attenuation_filter_db=0
		node.max_distance=0
		node.doppler_tracking=AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	return node

static func pause(record: Dictionary, value: bool) -> void:
	if value:
		record.node.stream_paused=true
		# A pending 3D play request has no registered playback to pause yet.
		if record.node.playing and not record.node.stream_paused:
			record.resume_position=record.node.get_playback_position()
			record.node.stop();record.pending_resume=true
	else:
		if record.pending_resume:
			record.node.play(record.resume_position);record.pending_resume=false
		record.node.stream_paused=false
