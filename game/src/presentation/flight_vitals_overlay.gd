extends Control
const HudStyle=preload("res://src/presentation/flight_hud_style.gd")
## Original corner art over accepted flight vitals and cargo. No flight input lives here.
const Catalogues=preload("res://src/content/catalogues.gd")
const OriginalUI=preload("res://src/presentation/original_ui.gd")
const SOURCE_IMAGES={"hull_badge":1195,"armor_badge":1194,"shield_badge":1196,
	"gauge_frame":1193,"hull_back":1191,"shield_back":1198,
	"hull_fill":1316,"armor_fill":1192,"shield_fill":1199,"throttle_frame":1352,
	"timer_frame":1221,"cargo_frame":1312,"shield_hit_badge":1197}
# A drop in the combined pools is a hit: the shield badge shows its red hit
# art for the original 500 ms while at least 2 shield points remain.
const SHIELD_HIT_MS:=500
# Supernova gamma row (badge, track, fill) on the third interface atlas.
const GAMMA_IMAGES={"gamma_badge":8025,"gamma_back":8026,"gamma_fill":8027}
const GAMMA_ATLAS:={"10089":"resources/data/textures/gof2_interface3_ipad_large.aei"}
# Remake presentation timing: the throttle reading appears after a change and
# then fades. The original display duration has not been recovered.
const THROTTLE_HOLD_MS:=1500
const THROTTLE_FADE_MS:=500
var error:=""
var _identity:={}
var _catalogues: RefCounted
var _art: RefCounted
var _sprites:={}
var _active:=true
var _has_state:=false
var _mobile:=false
var _touch_inset:=false
var _shield_visible:=false
var _readout_kind:=""
var _armor_visible:=false
var _hull_ratio:=1.0
var _armor_ratio:=0.0
var _shield_ratio:=0.0
var _gamma_visible:=false
var _gamma_ratio:=1.0
var _gamma_badge: TextureRect
var _gamma_frame: TextureRect
var _gamma_back: TextureRect
var _gamma_clip: Control
var _gamma_fill: TextureRect
## Volatile cargo instability (Supernova Mutagen / Red Plasma). Assumption:
## the gauge frame with a plain fill that turns from amber to red (the
## original's indicator art is not identified).
var _instability_visible:=false
var _instability_ratio:=0.0
var _instability_frame: TextureRect
var _instability_back: ColorRect
var _instability_fill: ColorRect
var _throttle_visible:=false
var _throttle_percent:=0
var _throttle_seen:=-1
var _throttle_changed_ms:=-THROTTLE_HOLD_MS-THROTTLE_FADE_MS
var _armor_label:=""
var _shield_label:=""
var _hull_badge: TextureRect
var _armor_badge: TextureRect
var _shield_badge: TextureRect
var _hull_frame: TextureRect
var _armor_frame: TextureRect
var _shield_frame: TextureRect
var _hull_back: TextureRect
var _armor_back: TextureRect
var _shield_back: TextureRect
var _hull_clip: Control
var _armor_clip: Control
var _shield_clip: Control
var _hull_fill: TextureRect
var _armor_fill: TextureRect
var _shield_fill: TextureRect
var _hull_text: Label
var _armor_text: Label
var _shield_text: Label
var _cargo_frame: TextureRect
var _cargo_text: Label
var _throttle_frame: TextureRect
var _throttle_text: Label
var _vital_total:=-1.0
var _shield_points:=0.0
var _shield_hit_ms:=-SHIELD_HIT_MS

func _init() -> void:
	visible=false;mouse_filter=Control.MOUSE_FILTER_IGNORE
	_hull_badge=_texture(self);_armor_badge=_texture(self);_shield_badge=_texture(self)
	_hull_frame=_texture(self);_armor_frame=_texture(self);_shield_frame=_texture(self)
	_hull_back=_texture(self);_armor_back=_texture(self);_shield_back=_texture(self)
	_hull_clip=Control.new();_hull_clip.mouse_filter=Control.MOUSE_FILTER_IGNORE;_hull_clip.clip_contents=true;add_child(_hull_clip)
	_hull_fill=_texture(_hull_clip)
	_armor_clip=Control.new();_armor_clip.mouse_filter=Control.MOUSE_FILTER_IGNORE;_armor_clip.clip_contents=true;add_child(_armor_clip)
	_armor_fill=_texture(_armor_clip)
	_shield_clip=Control.new();_shield_clip.mouse_filter=Control.MOUSE_FILTER_IGNORE;_shield_clip.clip_contents=true;add_child(_shield_clip)
	_shield_fill=_texture(_shield_clip)
	_hull_text=_value_label();_armor_text=_value_label();_shield_text=_value_label()
	_gamma_badge=_texture(self);_gamma_frame=_texture(self);_gamma_back=_texture(self)
	_gamma_clip=Control.new();_gamma_clip.mouse_filter=Control.MOUSE_FILTER_IGNORE;_gamma_clip.clip_contents=true;add_child(_gamma_clip)
	_gamma_fill=_texture(_gamma_clip)
	_instability_frame=_texture(self)
	_instability_back=ColorRect.new();_instability_back.mouse_filter=Control.MOUSE_FILTER_IGNORE;_instability_back.color=Color(0.1,0.05,0.02,0.8);add_child(_instability_back)
	_instability_fill=ColorRect.new();_instability_fill.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_instability_fill)
	_cargo_frame=_texture(self)
	_cargo_text=Label.new();_cargo_text.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_cargo_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;add_child(_cargo_text)
	_throttle_frame=_texture(self)
	_throttle_text=Label.new();_throttle_text.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_throttle_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;add_child(_throttle_text)
	resized.connect(_relayout)
	set_mobile_layout(false)

func _texture(parent: Control) -> TextureRect:
	var node:=TextureRect.new();node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	node.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;node.stretch_mode=TextureRect.STRETCH_SCALE
	parent.add_child(node);return node

func _value_label() -> Label:
	var label:=Label.new();label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color",Color(0.84,0.94,0.99))
	add_child(label);return label

func configure(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> bool:
	error=""
	if library==null or bindings==null or visuals==null or library.manifest.get("content_id")!=bindings.base_content_id or visuals.base_content_id!=bindings.base_content_id:return reject("Flight gauges require matching content and artwork")
	var cat:=Catalogues.new()
	if not cat.open(library):return reject(cat.error)
	var art:=OriginalUI.new()
	if not art.configure(library,bindings,visuals):return reject(art.error)
	var sprites:={}
	var images:=art.load_regions(library,bindings,visuals,SOURCE_IMAGES.values(),bindings.mido_travel.map.ui.atlas_resources)
	if images.is_empty():return reject(art.error)
	for key in SOURCE_IMAGES:
		sprites[key]=images[SOURCE_IMAGES[key]]
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language}
	_catalogues=cat;_art=art;_sprites=sprites
	_armor_label=library.strings[Catalogues.SHIP_LABEL_IDS[library.manifest.profile.edition][0]]
	_shield_label=library.strings[219] if library.manifest.profile.edition=="mac-full-hd" else ""
	_hull_badge.texture=sprites.hull_badge;_armor_badge.texture=sprites.armor_badge;_shield_badge.texture=sprites.shield_badge
	for node in [_hull_frame,_armor_frame,_shield_frame]:node.texture=sprites.gauge_frame
	_hull_back.texture=sprites.hull_back;_armor_back.texture=sprites.hull_back;_shield_back.texture=sprites.shield_back
	_hull_fill.texture=sprites.hull_fill;_armor_fill.texture=sprites.armor_fill;_shield_fill.texture=sprites.shield_fill
	_cargo_frame.texture=sprites.cargo_frame
	# Packs without the third atlas simply have no gamma row.
	var atlases: Dictionary=bindings.mido_travel.map.ui.atlas_resources.duplicate()
	atlases.merge(GAMMA_ATLAS)
	var gamma:=art.load_regions(library,bindings,visuals,GAMMA_IMAGES.values(),atlases)
	_gamma_badge.texture=gamma.get(8025);_gamma_back.texture=gamma.get(8026);_gamma_fill.texture=gamma.get(8027)
	_gamma_frame.texture=sprites.gauge_frame if not gamma.is_empty() else null
	_instability_frame.texture=sprites.gauge_frame
	_throttle_frame.texture=sprites.get("throttle_frame")
	var theme:=Theme.new();theme.default_font=art.font;self.theme=theme
	set_mobile_layout(_mobile)
	return true

func present(state: Dictionary,show_hull_value:=true) -> bool:
	error=""
	if _identity.is_empty() or _catalogues==null:return reject("Configure the flight gauges before presenting them")
	for key in ["base_content_id","binding_id"]:
		if state.get(key)!=_identity[key]:return reject("Flight gauges belong to another content session")
	var player: Variant=state.get("player")
	var cargo: Variant=state.get("cargo",{})
	if not player is Dictionary or not cargo is Dictionary or not player.get("vitals") is Dictionary or not player.get("capacities") is Dictionary:return reject("Flight gauges need accepted player pools and cargo")
	var has_throttle:=state.has("control_throttle")
	var throttle: Variant=state.get("control_throttle")
	if has_throttle and (not (throttle is float or throttle is int) or not is_finite(float(throttle)) or float(throttle)<0.0 or float(throttle)>1.0):return reject("Flight throttle must be a finite fraction")
	var readout: Variant=state.get("mission_readout",{})
	var readout_text: Variant=_mission_text(readout)
	if readout_text==null:return reject("Flight readout requires accepted time or encounter counters")
	var ship_id: int=int(player.get("ship_id",-1))
	if ship_id<0 or ship_id>=_catalogues.tables.ships.size():return reject("Flight gauges selected an unknown ship")
	var hull_max: int=int(player.get("max_hull",_catalogues.tables.ships[ship_id].stats.armor))
	var hull: int=int(player.vitals.get("hull",-1))
	var armor_max: int=int(player.capacities.get("armor",-1))
	var armor: int=int(player.vitals.get("armor",-1))
	var shield_max: int=int(player.capacities.get("shield",-1))
	var shield: float=float(player.vitals.get("shield",-1))
	var used: int=0 if cargo.is_empty() else int(cargo.get("used",-1))
	var capacity: int=0 if cargo.is_empty() else int(cargo.get("capacity",-1))
	if hull_max<=0 or hull<0 or armor_max<0 or armor<0 or shield_max<0 or shield<0 or used<0 or capacity<0:return reject("Flight gauges received invalid pool totals")
	var total:=float(hull)+float(armor)+shield
	if _vital_total>=0.0 and total<_vital_total-0.001:_shield_hit_ms=Time.get_ticks_msec()
	_vital_total=total;_shield_points=shield
	_hull_ratio=clampf(float(hull)/float(hull_max),0,1)
	_armor_ratio=clampf(float(armor)/float(maxi(1,armor_max)),0,1)
	_shield_ratio=clampf(shield/float(maxi(1,shield_max)),0,1)
	_armor_visible=armor_max>0
	_shield_visible=shield_max>0
	_gamma_visible=float(state.get("gamma_rate",0.0))>0.0 and _gamma_frame.texture!=null
	_gamma_ratio=clampf(float(player.get("gamma",100.0))/100.0,0,1)
	_instability_visible=bool(state.get("volatile",false))
	_instability_ratio=clampf(float(state.get("instability",0.0)),0,1)
	_hull_back.tooltip_text="%d / %d"%[hull,hull_max] if show_hull_value else ""
	_armor_back.tooltip_text="%s %d / %d"%[_armor_label,armor,armor_max]
	_shield_back.tooltip_text="%s %d / %d"%[_shield_label,roundi(shield),shield_max]
	_hull_text.text="%d/%d"%[hull,hull_max]
	_hull_text.visible=show_hull_value
	_armor_text.text="%s %d/%d"%[_armor_label,armor,armor_max]
	_shield_text.text="%s %d/%d"%[_shield_label,roundi(shield),shield_max]
	_readout_kind=readout.get("kind","")
	_cargo_text.text="%d / %dt"%[used,capacity] if readout.is_empty() else readout_text
	_cargo_frame.texture=_sprites.timer_frame if _readout_kind=="countdown" else _sprites.cargo_frame
	# Guiding a Liberator: only the bars stay (no cargo/timer box or throttle).
	var guiding: bool=state.get("guided_missile",false)
	_cargo_frame.visible=(not cargo.is_empty() or not readout.is_empty()) and not guiding;_cargo_text.visible=_cargo_frame.visible
	_throttle_visible=has_throttle and _throttle_frame.texture!=null and not guiding
	_throttle_percent=roundi(float(throttle)*100.0) if has_throttle else 0
	_throttle_text.text=str(_throttle_percent) if has_throttle else ""
	_throttle_frame.tooltip_text="Throttle %d%%"%_throttle_percent if has_throttle else ""
	# The first reading of a flight is its baseline; only later changes show.
	if has_throttle and _throttle_percent!=_throttle_seen:
		if _throttle_seen>=0:_throttle_changed_ms=Time.get_ticks_msec()
		_throttle_seen=_throttle_percent
	_apply_shield_badge(Time.get_ticks_msec())
	_has_state=true;visible=_active;_relayout()
	return true

static func _mission_text(readout: Variant) -> Variant:
	if not readout is Dictionary:return null
	if readout.is_empty():return ""
	match readout.get("kind"):
		"countdown":
			if not readout.get("remaining_ms") is int or readout.remaining_ms<=0:return null
			var seconds:=int(readout.remaining_ms/1000)
			var hours:=int(seconds/3600)
			var clock:="%02d:%02d"%[int(seconds/60)%60,seconds%60]
			return "%02d:"%hours+clock if hours>0 else clock
		"contest":
			if not readout.get("player") is int or not readout.get("other") is int or readout.player<0 or readout.other<0:return null
			return "%d : %d"%[readout.player,readout.other]
		"score":
			if not readout.get("score") is int or readout.score<0:return null
			return "%07d"%readout.score
	return null

func _process(_delta: float) -> void:
	if _throttle_visible:_apply_throttle_alpha(Time.get_ticks_msec())
	if _shield_visible and not _sprites.is_empty():_apply_shield_badge(Time.get_ticks_msec())

func shield_hit_shown(now_ms: int) -> bool:
	var age:=now_ms-_shield_hit_ms
	return _shield_points>=2.0 and age>=0 and age<SHIELD_HIT_MS

func _apply_shield_badge(now_ms: int) -> void:
	var badge: Texture2D=_sprites.shield_hit_badge if shield_hit_shown(now_ms) else _sprites.shield_badge
	if _shield_badge.texture!=badge:_shield_badge.texture=badge

func throttle_alpha(now_ms: int) -> float:
	var age:=now_ms-_throttle_changed_ms
	if not _throttle_visible or age<0 or age>=THROTTLE_HOLD_MS+THROTTLE_FADE_MS:return 0.0
	return 1.0 if age<=THROTTLE_HOLD_MS else 1.0-float(age-THROTTLE_HOLD_MS)/float(THROTTLE_FADE_MS)

func _apply_throttle_alpha(now_ms: int) -> void:
	var alpha:=throttle_alpha(now_ms)
	for node in [_throttle_frame,_throttle_text]:
		node.visible=alpha>0.0;node.modulate.a=alpha

func set_active(value: bool) -> void:
	_active=value;visible=value and _has_state

func set_mobile_layout(value: bool) -> void:
	_mobile=value
	_cargo_text.add_theme_font_size_override("font_size",HudStyle.font_size(20 if value else 15))
	_throttle_text.add_theme_font_size_override("font_size",HudStyle.font_size(17 if value else 12))
	for label in [_hull_text,_armor_text,_shield_text]:label.add_theme_font_size_override("font_size",13 if value else 11)
	_relayout()

func set_touch_inset(value: bool) -> void:
	if _touch_inset==value:return
	_touch_inset=value;_relayout()

func _relayout() -> void:
	if size.x<=0 or size.y<=0:return
	var margin:=16.0 if _mobile else 12.0
	var badge:=32.0 if _mobile else 27.0
	var track_left:=margin+badge
	var frame_size:=Vector2.ZERO
	var track_size:=Vector2.ZERO
	if _hull_frame.texture!=null:
		# Keep the badge's painted connectors joined to the original long frame.
		var artwork_scale:=badge/_hull_frame.texture.get_height()
		frame_size=_hull_frame.texture.get_size()*artwork_scale
		track_size=_hull_back.texture.get_size()*artwork_scale
	var width:=track_size.x
	var track_height:=track_size.y
	var track_top:=(badge-track_height)*0.5
	var spacing:=34.0 if _mobile else 29.0
	var armor_y:=margin+(spacing if _shield_visible else 0.0)
	var hull_y:=armor_y+(spacing if _armor_visible else 0.0)
	_hull_badge.position=Vector2(margin,hull_y);_hull_badge.size=Vector2.ONE*badge
	_hull_frame.position=Vector2(track_left,hull_y);_hull_frame.size=frame_size
	_hull_back.position=Vector2(track_left,hull_y+track_top);_hull_back.size=track_size
	_hull_clip.position=_hull_back.position;_hull_clip.size=Vector2(width*_hull_ratio,track_height)
	_hull_fill.position=Vector2.ZERO;_hull_fill.size=Vector2(width,track_height)
	_armor_badge.visible=_armor_visible;_armor_frame.visible=_armor_visible;_armor_back.visible=_armor_visible;_armor_clip.visible=_armor_visible;_armor_text.visible=_armor_visible
	_armor_badge.position=Vector2(margin,armor_y);_armor_badge.size=Vector2.ONE*badge
	_armor_frame.position=Vector2(track_left,armor_y);_armor_frame.size=frame_size
	_armor_back.position=Vector2(track_left,armor_y+track_top);_armor_back.size=track_size
	_armor_clip.position=_armor_back.position;_armor_clip.size=Vector2(width*_armor_ratio,track_height)
	_armor_fill.position=Vector2.ZERO;_armor_fill.size=Vector2(width,track_height)
	_shield_badge.visible=_shield_visible;_shield_frame.visible=_shield_visible;_shield_back.visible=_shield_visible;_shield_clip.visible=_shield_visible
	_shield_text.visible=_shield_visible
	_shield_badge.position=Vector2(margin,margin);_shield_badge.size=Vector2.ONE*badge
	_shield_frame.position=Vector2(track_left,margin);_shield_frame.size=frame_size
	_shield_back.position=Vector2(track_left,margin+track_top);_shield_back.size=track_size
	_shield_clip.position=_shield_back.position;_shield_clip.size=Vector2(width*_shield_ratio,track_height)
	_shield_fill.position=Vector2.ZERO;_shield_fill.size=Vector2(width,track_height)
	var gamma_y:=hull_y+spacing
	for node in [_gamma_badge,_gamma_frame,_gamma_back,_gamma_clip]:node.visible=_gamma_visible
	_gamma_badge.position=Vector2(margin,gamma_y);_gamma_badge.size=Vector2.ONE*badge
	_gamma_frame.position=Vector2(track_left,gamma_y);_gamma_frame.size=frame_size
	_gamma_back.position=Vector2(track_left,gamma_y+track_top);_gamma_back.size=track_size
	_gamma_clip.position=_gamma_back.position;_gamma_clip.size=Vector2(width*_gamma_ratio,track_height)
	_gamma_fill.position=Vector2.ZERO;_gamma_fill.size=Vector2(width,track_height)
	var instability_y:=gamma_y+(spacing if _gamma_visible else 0.0)
	for node in [_instability_frame,_instability_back,_instability_fill]:node.visible=_instability_visible
	_instability_frame.position=Vector2(track_left,instability_y);_instability_frame.size=frame_size
	_instability_back.position=Vector2(track_left,instability_y+track_top);_instability_back.size=track_size
	_instability_fill.position=_instability_back.position;_instability_fill.size=Vector2(width*_instability_ratio,track_height)
	_instability_fill.color=Color(1.0,0.75,0.1).lerp(Color(1.0,0.12,0.0),_instability_ratio)
	for row in [[_hull_text,hull_y],[_armor_text,armor_y],[_shield_text,margin]]:
		row[0].position=Vector2(track_left+width+4,float(row[1])+badge*0.20)
		row[0].size=Vector2(110,badge*0.8)
	var counter_height:=(32.0 if _mobile else 26.0)*HudStyle.multiplier
	var counter_width:=counter_height*_cargo_frame.texture.get_width()/_cargo_frame.texture.get_height() if _cargo_frame.texture!=null else 146.0
	_cargo_frame.position=Vector2(maxf(0,size.x-counter_width-margin-(60.0 if _touch_inset else 0.0)),margin)
	_cargo_frame.size=Vector2(counter_width,counter_height)
	_cargo_frame.texture_filter=HudStyle.filtering()
	_cargo_text.position=_cargo_frame.position;_cargo_text.size=_cargo_frame.size
	var throttle_size: Vector2=_throttle_frame.texture.get_size()*(1.0 if _mobile else 0.7)*HudStyle.multiplier if _throttle_frame.texture!=null else Vector2.ZERO
	_apply_throttle_alpha(Time.get_ticks_msec())
	_throttle_frame.size=throttle_size
	_throttle_frame.position=Vector2((size.x-throttle_size.x)*0.5,size.y*0.5-(19.0 if _mobile else 14.0))
	_throttle_text.position=_throttle_frame.position+Vector2(0,throttle_size.y*0.54)
	_throttle_text.size=Vector2(throttle_size.x,21 if _mobile else 16)

func clear() -> void:
	_has_state=false;visible=false;_cargo_text.text="";_readout_kind="";_throttle_text.text="";_throttle_visible=false;_throttle_seen=-1
	_throttle_changed_ms=-THROTTLE_HOLD_MS-THROTTLE_FADE_MS
	_vital_total=-1.0;_shield_hit_ms=-SHIELD_HIT_MS
	if not _sprites.is_empty():_shield_badge.texture=_sprites.shield_badge
	_throttle_frame.hide();_throttle_text.hide()
	for label in [_hull_text,_armor_text,_shield_text]:label.text=""

## The top-right counter plate (cargo, timer, contest or score), global coordinates.
func counter_rect() -> Rect2:
	return _cargo_frame.get_global_rect() if visible and _cargo_frame.visible else Rect2()

func top_inset() -> float:
	var bottom: Control=_instability_frame if _instability_visible else (_gamma_badge if _gamma_visible else _hull_badge)
	return bottom.position.y+bottom.size.y+8.0 if visible else 0.0

func reject(message: String) -> bool:error=message;return false
