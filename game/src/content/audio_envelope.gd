extends RefCounted
## Bounded FEV scalar envelopes. Curve type belongs to the segment's end point.
const Numbers=preload("res://src/content/audio_definitions.gd")
const TARGETS={12:"gain",20:"pitch",260:"spread_degrees"}

static func supported(envelope: Variant, parameter_count: int) -> bool:
	if not envelope is Dictionary or not Numbers.integer(envelope.get("flags"),0,65535) or not TARGETS.has(int(envelope.flags)):return false
	for key in ["dsp_parameter","flags2","trailing"]:
		if not Numbers.integer(envelope.get(key),0,0):return false
	if not envelope.get("dsp") is String or envelope.dsp!="" or not Numbers.integer(envelope.get("name_index"),65535,65535) or not Numbers.integer(envelope.get("parent_index"),65535,65535):return false
	if not Numbers.integer(envelope.get("parameter_index"),0,parameter_count-1):return false
	var points: Variant=envelope.get("points")
	if not points is Array or points.is_empty() or points.size()>64:return false
	var previous:=-1.0
	for point in points:
		if not point is Array or point.size()!=3 or not Numbers.number(point[0],0,1) or not Numbers.number(point[1],0,1) or not Numbers.integer(point[2],1,2) or point[0]<=previous:return false
		previous=float(point[0])
	return points[0][0]==0

static func evaluate(envelope: Dictionary, parameter: float) -> float:
	var points: Array=envelope.points
	var value: float=points[0][1]
	if parameter>=float(points[-1][0]):value=float(points[-1][1])
	elif parameter>float(points[0][0]):
		for i in range(1,points.size()):
			if parameter>float(points[i][0]):continue
			var left: Array=points[i-1];var right: Array=points[i]
			var t:=clampf((parameter-float(left[0]))/(float(right[0])-float(left[0])),0.0,1.0)
			# Source type1 uses a cubic with endpoint-height control points;
			# type2 is linear. Time is normalized directly, without solving x.
			if int(right[2])==1:t=t*t*(3.0-2.0*t)
			value=lerpf(float(left[1]),float(right[1]),t)
			break
	match int(envelope.flags):
		20:return pow(2.0,8.0*value-4.0)
		260:return 360.0*value
	return value
