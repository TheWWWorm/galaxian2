extends RefCounted
## Shared native stream setup and the queued-3D-play pause workaround.

static func player(stream: AudioStream, spatial: bool) -> Node:
	var node: Node=AudioStreamPlayer3D.new() if spatial else AudioStreamPlayer.new()
	node.stream=stream
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
