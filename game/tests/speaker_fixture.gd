extends RefCounted

static func definition(mac := true) -> Dictionary:
	var portraits := []
	for i in 5:
		var row := {"speaker_id": i, "status": "unavailable" if i == 0 else ("procedural" if i == 3 else "fixed")}
		if row.status == "fixed":
			row.merge({"family": 2, "parts": [0, -1, 3, 4], "source_offset": 4000 + i * 20, "source_bytes": 20})
		portraits.append(row)
	return {"first_name_id": 200, "agent_speaker_start": 500, "fixed_speaker_count": 5, "procedural_speaker": 3, "portraits": portraits, "provenance": {
		"speaker_selection": {"offset": 100, "bytes": 285 if mac else 182},
		"name_selection": {"offset": 500, "bytes": 248 if mac else 264},
		"speaker_getter": {"offset": 1000, "bytes": 9 if mac else 4},
		"portrait_table": {"offset": 2000, "bytes": 40 if mac else 20}}}
