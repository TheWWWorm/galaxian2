extends SceneTree
const Tracks = preload("res://src/content/animation_tracks.gd")
var failures := 0
func _initialize() -> void:
	check(Tracks.has_identity_tracks([{"tracks":{}}]),"Missing keys must be static")
	var identity := {"translation":[track(1,[1150,0]),track(1,[1150,-0.0]),track(1,[])],
		"rotation":[track(3,[-100,0,0,0,1150,0,0,0])],"scale":[track(3,[1150,1,1,1])],
		"uv":[track(1,[]),track(1,[])],"scalar":[track(1,[])]}
	check(Tracks.has_identity_tracks([{"tracks":identity}]),"Identity transforms require no animation clock")
	for time in [-10000.0,0.0,1150.0,20000.0]:
		check(Tracks.vector(identity.translation,time,Vector3.ZERO)==Vector3.ZERO and Tracks.vector(identity.rotation,time,Vector3.ZERO)==Vector3.ZERO and Tracks.vector(identity.scale,time,Vector3.ONE)==Vector3.ONE,"Identity sampling changed across time")
	for scenario in ["translate","rotate","scale","uv","scalar","unknown","width","incomplete","nonfinite","order"]:
		var bad := identity.duplicate(true)
		if scenario=="translate":bad.translation[0].keys[1]=0.01
		elif scenario=="rotate":bad.rotation[0].keys[2]=1.0
		elif scenario=="scale":bad.scale[0].keys[1]=0.0
		elif scenario=="uv":bad.uv[0]=track(1,[0,0])
		elif scenario=="scalar":bad.scalar[0]=track(1,[0,0])
		elif scenario=="unknown":bad.extra=[]
		elif scenario=="width":bad.translation[0].dimensions=3
		elif scenario=="incomplete":bad.scale[0].keys=PackedFloat32Array([0,1])
		elif scenario=="nonfinite":bad.rotation[0].keys[0]=NAN
		else:bad.rotation[0].keys[4]=-200
		check(not Tracks.has_identity_tracks([{"tracks":bad}]),"Unsafe static track accepted: "+scenario)
	print("Static identity tracks: %d failures" % failures)
	quit(1 if failures else 0)
func track(width: int, keys: Array) -> Dictionary:
	return {"dimensions":width,"keys":PackedFloat32Array(keys)}
func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)
