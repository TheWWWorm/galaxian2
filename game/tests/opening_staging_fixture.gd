extends RefCounted

static func definition(mac := true) -> Dictionary:
	var sizes := {"initial": 366, "formation": 489, "player_getter": 13, "actor_getter": 13, "event_getter": 13, "cursor_getter": 12, "visibility": 14, "event_finished": 11, "camera_vector": 35, "camera_components": 21, "initial_ref_a3": 4}
	if mac:
		for key in ["72", "7a", "82", "ad", "9d", "a5", "dd", "e5", "ed", "fa", "102", "13a", "11e", "126", "15c", "148", "164"]:
			sizes["formation_ref_" + key] = 4
	else:
		sizes = {"initial": 320, "formation": 424, "initial_dispatch": 58, "update_dispatch": 186, "player_getter": 6, "actor_getter": 6, "event_getter": 6, "cursor_getter": 6, "visibility": 10, "event_finished": 6, "camera_vector": 18, "camera_components": 10}
	var provenance := {}
	var offset := 100
	for key in sizes:
		provenance[key] = {"offset": offset, "bytes": sizes[key]}
		offset += sizes[key] + 16
	return {"initial": {"player_position": [0, 0, -90], "player_forward": [0, 0, 1], "player_up": [0, 1, 0], "camera_position_parameter": [12, -34, -56], "hidden_actor_ids": [0, 1, 2]},
		"formation": {"after_event_finished": 2, "player_position": [321, -234, -456], "camera_position_parameter": [-234, 512, -640], "actors": [
			{"actor_id": 0, "position": [-789, 896, 0], "forward": [1, 0, 0], "up": [0, 1, 0], "visible": true},
			{"actor_id": 1, "position": [-789, -896, 1234], "forward": [1, 0, 0], "up": [0, 1, 0], "visible": true},
			{"actor_id": 2, "position": [-789, -2304, 512], "forward": [1, 0, 0], "up": [0, 1, 0], "visible": true}]}, "provenance": provenance}

static func dialogue() -> Dictionary:
	var rows := []
	for i in 23:
		rows.append({"text_id": i, "speaker_id": 0, "condition": 5 if i == 0 else 6, "values": [0 if i == 0 else i - 1]})
	return {"campaign_cursor": 0, "events": rows, "timing": {"display_delay_ms": 2000, "base_duration_ms": 1500, "per_line_ms": 2000}}
