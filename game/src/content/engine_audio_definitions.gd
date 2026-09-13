extends RefCounted
## Verified player-engine selection and source control indices.
const Numbers=preload("res://src/content/audio_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const VALUES={"selection_input":"handling_before_equipment","event_ids":[42,43,44,45],"ship_overrides":[[42,1104],[43,1106],[40,1107]],"steering_parameter":0,"horizontal_parameter":1,"steering_rule":"max_absolute_source_commands","horizontal_input":"source_yaw_command","horizontal_offset":0.5,"update_order":"before_manual_motion"}
const SPANS={"x86_64":{"handling_setup":[0,13],"selection":[13,229],"ship_getter":[177230,8],"equipment_after_selection":[242,79],"control_owner":[12602,25],"controls":[12627,175],"rotation_anchor":[12859,24],"instance_getter":[-7270,12],"parameter_wrapper":[-1212274,72],"threshold_high":[1035820,4],"threshold_middle":[1035824,4],"threshold_low":[1030588,4],"horizontal_scale":[993628,4],"horizontal_offset":[992632,4]},"armv7":{"handling_setup":[0,8],"selection":[8,170],"ship_getter":[152118,4],"equipment_after_selection":[178,56],"control_owner":[10616,24],"controls":[10640,148],"rotation_anchor":[10920,90],"instance_getter":[-5806,6],"parameter_wrapper":[-1513694,66],"threshold_high":[542,4],"threshold_middle":[546,4],"threshold_low":[550,4],"horizontal_scale":[11554,4]}}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+3 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not equivalent(data.get(key),VALUES[key]):return false
	var thresholds: Variant=data.get("thresholds")
	if not thresholds is Array or thresholds.size()!=3:return false
	var previous:=0.0
	for value in thresholds:
		if not Numbers.number(value,0.000001,99.999999) or value<=previous:return false
		previous=float(value)
	return Numbers.number(data.get("horizontal_scale"),0.000001,99.999999)

static func equivalent(value: Variant, expected: Variant) -> bool:
	if expected is Array:
		if not value is Array or value.size()!=expected.size():return false
		for i in expected.size():
			if not equivalent(value[i],expected[i]):return false
		return true
	if expected is int:return Numbers.integer(value,expected,expected)
	if expected is float:return Numbers.number(value,expected,expected)
	return typeof(value)==typeof(expected) and value==expected

static func validate(data: Variant, executable_bytes: int, architecture: String, vehicle: Dictionary, rotation: Dictionary, audio: Dictionary) -> String:
	if not data is Dictionary:return "Invalid player engine audio declarations"
	if data.is_empty():return ""
	if not parameters(data) or not SPANS.has(architecture):return "Unsupported player engine audio declarations"
	var anchor: Variant=vehicle.get("provenance",{}).get("handling_setup")
	if not anchor is Dictionary or anchor!=data.provenance.get("handling_setup"):return "Engine selection lacks its handling owner"
	var source_rotation: Variant=rotation.get("provenance")
	if not source_rotation is Array or source_rotation.is_empty() or source_rotation[0]!=data.provenance.get("rotation_anchor"):return "Engine controls belong to another manual motion owner"
	if data.provenance.size()!=SPANS[architecture].size():return "Invalid engine audio provenance"
	for key in SPANS[architecture]:
		var rule: Array=SPANS[architecture][key]
		var row: Variant=data.provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[rule[1]],executable_bytes) or int(row.offset)!=int(anchor.offset)+int(rule[0]):return "Disconnected engine audio source extent"
	var events: Variant=audio.get("events")
	if not events is Array:return "Engine selection lacks the source event catalogue"
	var ids: Array=data.event_ids.duplicate()
	for pair in data.ship_overrides:ids.append(pair[1])
	for id in ids:
		if int(id)>=events.size():return "Engine event is absent from this edition"
	return ""
