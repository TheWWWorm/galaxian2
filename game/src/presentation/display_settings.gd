extends RefCounted
## Native-pixel rendering. Optional ratios letterbox without distorting geometry.
## Window/aspect handling adapts the GoF3D display component (Apache-2.0).
var _window: Window
var _values:={}
var _refreshing:=false
var _mobile:=false

func apply(window: Window,values: Dictionary,mobile: bool=false) -> void:
	if _window!=window:
		_window=window
		window.size_changed.connect(refresh_aspect)
	var resize: bool=_values.is_empty() or _values.resolution!=values.resolution or _values.window_mode!=values.window_mode
	_values=values.duplicate()
	_mobile=mobile
	Engine.max_fps=maxi(0,int(values.frame_rate))
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.frame_rate==-1 else DisplayServer.VSYNC_DISABLED,window.get_window_id())
		if resize and not mobile:
			window.min_size=Vector2i(960,540)
			if values.window_mode=="fullscreen":window.mode=Window.MODE_FULLSCREEN
			else:
				window.mode=Window.MODE_WINDOWED
				var usable:=DisplayServer.screen_get_usable_rect(window.current_screen)
				var requested:=resolution_size(values.resolution,native_size(window))
				window.size=fit_size(requested,Vector2i(maxi(960,usable.size.x-32),maxi(540,usable.size.y-72)))
				window.position=usable.position+(usable.size-window.size)/2
	refresh_aspect()

static func native_size(window: Window) -> Vector2i:
	var result:=DisplayServer.screen_get_size(window.current_screen)
	return result if result.x>0 and result.y>0 else window.size

static func resolution_size(value: String,native: Vector2i) -> Vector2i:
	if value=="native":return native
	var parts:=value.split("x")
	return Vector2i(int(parts[0]),int(parts[1]))

static func fit_size(requested: Vector2i,available: Vector2i) -> Vector2i:
	var scale:=minf(1.0,minf(float(available.x)/requested.x,float(available.y)/requested.y))
	return Vector2i(Vector2(requested)*scale)

static func aspect_size(size: Vector2i,value: String,native: Vector2i) -> Vector2i:
	if value=="auto":return Vector2i.ZERO
	var ratio:=float(native.x)/maxi(1,native.y)
	if value!="native":
		var parts:=value.split(":");ratio=float(parts[0])/float(parts[1])
	return Vector2i(mini(size.x,roundi(size.y*ratio)),mini(size.y,roundi(size.x/ratio)))

static func ui_factor(size: Vector2i,percent: int,mobile: bool=false) -> float:
	var automatic:=1.0 if mobile else maxf(1.0,roundf(float(size.y)/1080.0*4.0)/4.0)
	var requested:=automatic if percent==0 else percent/100.0
	# Keep options and their Back button reachable after a smaller window resize.
	var maximum:=maxf(0.75,minf(float(size.x)/960.0,float(size.y)/540.0))
	return clampf(requested,0.75,minf(3.0,maximum))

func refresh_aspect() -> void:
	if _window==null or _values.is_empty() or _refreshing:return
	_refreshing=true
	_window.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_window.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	_window.content_scale_size=aspect_size(_window.size,_values.aspect_ratio,native_size(_window))
	var area:=_window.content_scale_size if _window.content_scale_size!=Vector2i.ZERO else _window.size
	_window.content_scale_factor=ui_factor(area,int(_values.ui_scale),_mobile)
	_refreshing=false
