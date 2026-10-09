extends Control
## Station Status screen: pilot, ship, reputation, statistics and the medal grid.
## Earned medals show their original description when selected.
signal close_requested
const Catalogues=preload("res://src/content/catalogues.gd")
const Atlas=preload("res://src/content/atlas_region.gd")
const OriginalUI=preload("res://src/presentation/original_ui.gd")
const Portraits=preload("res://src/presentation/portrait_compositor.gd")
const Medals=preload("res://src/simulation/base_medal_progress.gd")
const Elite=preload("res://src/simulation/elite_medal_progress.gd")
const Stats=preload("res://src/simulation/equipment_stats.gd")
const Weapons=preload("res://src/simulation/weapon_loadout.gd")
const ShipInstance=preload("res://src/simulation/ship_instance.gd")
const ITEM_ATLAS="resources/data/textures/gof2_items_ipad_1440.aei"
const ITEM_TEXTURE_ID:=10064
const ELITE_ATLAS="resources/data/textures/gof2_interface3_ipad_large.aei"
const ELITE_TEXTURE_ID:=10089
const MEDAL_ICON_BASE:=2376
const MEDAL_FRAME:=2412
## Ribbon per level: none, gold, silver, bronze.
const RIBBONS:=[2416,2414,2415,2413]
const TINTS:=[Color8(33,152,255,110),Color8(250,208,0),Color8(255,255,255),Color8(206,130,88)]
const SHIP_IMAGE_BASE:=2417
const TEXT:={"title":168,"medals":167,"back":169,"level":310,"fire_power":558,"defense":559,"reputation":565,"statistics":566,
	"missions":557,"kills":175,"asteroids":541,"salvaged":548,"stations":546,"jumpgates":553,"goods":547,"ore":549,"cores":550,"wingmen":556,"pilot":1586,"battleships":3224}
const MEDAL_NAME_BASE:=1496
const MEDAL_TEXT_BASE:=1541
const FACTION_TEXT_BASE:=395
var error:=""
var _identity:={}
var _ui: RefCounted
var _catalogues: RefCounted
var _bindings: RefCounted
var _ship_names:={}
var _strings: PackedStringArray
var _art:={}
var _faction_icons:=[]
var _portrait: Texture2D
var _mobile:=false
var _state:={}
var _levels:=[]
var _elite:=[]
var _selected:=-1
var _root: Control
var _header: Label
var _left: VBoxContainer
var _pilot_values: Label
var _ship_image: TextureRect
var _ship_text: Label
var _ship_values: Label
var _reputation_bars:=[]
var _stats_left: Label
var _stats_left_values: Label
var _stats_right: Label
var _stats_right_values: Label
var _hint: Label
var _medal_grid: GridContainer
var _medal_buttons:=[]
var _back: Button

func _init() -> void:
	visible=false;mouse_filter=Control.MOUSE_FILTER_STOP
	var backdrop:=ColorRect.new();backdrop.color=Color(0.0,0.02,0.05,0.96);backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(backdrop);backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root=MarginContainer.new();add_child(_root);_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column:=VBoxContainer.new();_root.add_child(column)
	_header=_bar_label(column)
	var body:=HBoxContainer.new();body.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",10);column.add_child(body)
	_left=VBoxContainer.new();_left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_left.size_flags_stretch_ratio=1.0;body.add_child(_left)
	var right:=VBoxContainer.new();right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_child(right)
	# Pilot and ship.
	_bar_label(_left).set_meta("key","pilot")
	var top:=HBoxContainer.new();top.add_theme_constant_override("separation",8);_left.add_child(top)
	var portrait:=TextureRect.new();portrait.name="Portrait";portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT;portrait.custom_minimum_size=Vector2(72,84);top.add_child(portrait)
	_pilot_values=Label.new();_pilot_values.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;_pilot_values.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(_pilot_values)
	top.add_child(VSeparator.new())
	_ship_image=TextureRect.new();_ship_image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_ship_image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;_ship_image.custom_minimum_size=Vector2(64,32);top.add_child(_ship_image)
	_ship_text=Label.new();top.add_child(_ship_text)
	_ship_values=Label.new();_ship_values.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;_ship_values.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(_ship_values)
	# Reputation: two faction axes.
	_bar_label(_left).set_meta("key","reputation")
	var reputation:=HBoxContainer.new();reputation.add_theme_constant_override("separation",12);_left.add_child(reputation)
	for axis in 2:
		var row:=HBoxContainer.new();row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;reputation.add_child(row)
		var parts:={}
		for side in ["low","high"]:
			var box:=VBoxContainer.new();var icon:=TextureRect.new();icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.custom_minimum_size=Vector2(28,28)
			var label:=Label.new();box.add_child(icon);box.add_child(label);parts[side]=[icon,label]
			if side=="low":
				row.add_child(box)
				var bar:=HSlider.new();bar.min_value=-100;bar.max_value=100;bar.editable=false;bar.focus_mode=Control.FOCUS_NONE;bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
				bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bar.size_flags_vertical=Control.SIZE_SHRINK_CENTER
				row.add_child(bar);parts.bar=bar
			else:
				label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;row.add_child(box)
		_reputation_bars.append(parts)
	# Statistics.
	_bar_label(_left).set_meta("key","statistics")
	var stats:=HBoxContainer.new();stats.add_theme_constant_override("separation",12);_left.add_child(stats)
	for pair in [["_stats_left","_stats_left_values"],["_stats_right","_stats_right_values"]]:
		var names:=Label.new();names.size_flags_horizontal=Control.SIZE_EXPAND_FILL;stats.add_child(names);set(pair[0],names)
		var values:=Label.new();values.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;stats.add_child(values);set(pair[1],values)
	_hint=Label.new();_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_hint.size_flags_vertical=Control.SIZE_EXPAND_FILL;_hint.vertical_alignment=VERTICAL_ALIGNMENT_BOTTOM;_left.add_child(_hint)
	# Medals.
	_bar_label(right).set_meta("key","medals")
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.follow_focus=true;right.add_child(scroll)
	_medal_grid=GridContainer.new();_medal_grid.columns=3;_medal_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(_medal_grid)
	for id in Elite.TOTAL:
		var cell:=Button.new();cell.flat=true;cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL;cell.focus_mode=Control.FOCUS_ALL
		var box:=VBoxContainer.new();box.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.alignment=BoxContainer.ALIGNMENT_CENTER;cell.add_child(box);box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var ribbon:=TextureRect.new();ribbon.name="Ribbon";ribbon.mouse_filter=Control.MOUSE_FILTER_IGNORE;ribbon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;ribbon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;box.add_child(ribbon)
		var icon:=TextureRect.new();icon.name="Icon";icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;ribbon.add_child(icon)
		var frame:=TextureRect.new();frame.name="Frame";frame.mouse_filter=Control.MOUSE_FILTER_IGNORE;frame.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;frame.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;ribbon.add_child(frame);frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var label:=Label.new();label.name="Name";label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.clip_text=true;box.add_child(label)
		cell.pressed.connect(select_medal.bind(id))
		_medal_grid.add_child(cell);_medal_buttons.append(cell)
	var footer:=HBoxContainer.new();column.add_child(footer)
	_back=Button.new();_back.pressed.connect(func():close_requested.emit());footer.add_child(_back)
	resized.connect(_relayout)

func _bar_label(parent: Control) -> Label:
	var label:=Label.new();label.add_theme_color_override("font_color",Color(0.85,0.93,1.0))
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.07,0.2,0.36,0.9);style.content_margin_left=6;style.content_margin_top=1;style.content_margin_bottom=1
	label.add_theme_stylebox_override("normal",style);parent.add_child(label)
	return label

func configure(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> bool:
	error=""
	if library==null or bindings==null or visuals==null or library.manifest.get("content_id")!=bindings.base_content_id or visuals.base_content_id!=bindings.base_content_id:return reject("Status requires matching imported content and artwork")
	var identity:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language}
	if identity==_identity:return true
	var map_rules: Dictionary=bindings.mido_travel.get("map",{}).get("ui",{})
	if map_rules.is_empty():return reject("Status has no verified interface mapping")
	var cat:=Catalogues.new()
	if not cat.open(library):return reject(cat.error)
	var ui:=OriginalUI.new()
	if not ui.configure(library,bindings,visuals):return reject(ui.error)
	var ids:=[MEDAL_FRAME]+RIBBONS
	for id in Medals.BASE_COUNT:ids.append(MEDAL_ICON_BASE+id)
	ids.append_array([Elite.FRAME_EARNED,Elite.FRAME_NONE])
	for id in range(Elite.FIRST,Elite.TOTAL):ids.append(Elite.icon_id(id))
	var resources: Dictionary=map_rules.atlas_resources.duplicate();resources[str(ITEM_TEXTURE_ID)]=ITEM_ATLAS
	# Add-on medal frames and icons live on the third interface atlas.
	resources[str(ELITE_TEXTURE_ID)]=ELITE_ATLAS
	var art: Dictionary=ui.load_regions(library,bindings,visuals,ids,resources)
	if art.is_empty():return reject(ui.error)
	var ship_ids:=[]
	for ship in cat.tables.ships.size():
		# Ship pictures share the item atlas; a ship without one shows no picture.
		if int(bindings.resolve_image_region(SHIP_IMAGE_BASE+ship).get("texture_id",-1))==ITEM_TEXTURE_ID:ship_ids.append(SHIP_IMAGE_BASE+ship)
	# One request cuts every picture from a single atlas texture. Asked for one
	# by one, each picture loaded and kept its own copy of the whole atlas; that
	# remains the fallback so one bad picture cannot hide the others.
	var pictures: Dictionary=ui.load_regions(library,bindings,visuals,ship_ids,resources)
	if not pictures.is_empty():art.merge(pictures)
	else:
		for id in ship_ids:
			var picture: Dictionary=ui.load_regions(library,bindings,visuals,[id],resources)
			if not picture.is_empty():art.merge(picture)
	var icons:=[]
	var faction_art: Dictionary=ui.load_regions(library,bindings,visuals,map_rules.faction_image_ids,map_rules.atlas_resources)
	if faction_art.is_empty():return reject(ui.error)
	for id in map_rules.faction_image_ids:icons.append(faction_art[int(id)])
	# The reputation marker reuses the original slider track and thumb.
	var slider_art: Dictionary=ui.load_regions(library,bindings,visuals,[1305,1306],map_rules.atlas_resources)
	for parts in _reputation_bars:
		if slider_art.is_empty():break
		var track:=StyleBoxTexture.new();track.texture=slider_art[1305];track.content_margin_top=5;track.content_margin_bottom=5
		parts.bar.add_theme_stylebox_override("slider",track)
		for area in ["grabber_area","grabber_area_highlight"]:parts.bar.add_theme_stylebox_override(area,StyleBoxEmpty.new())
		for state in ["grabber","grabber_highlight","grabber_disabled"]:parts.bar.add_theme_icon_override(state,slider_art[1306])
	var definition: Dictionary=bindings.station_presentation.portraits.get("0",{})
	if definition.is_empty():definition=bindings.resolve_speaker_portrait(0)
	var composed: Dictionary={} if definition.is_empty() else Portraits.new().compose_definition(library,bindings,visuals,0,"large",definition)
	_portrait=null if composed.is_empty() else ImageTexture.create_from_image(composed.image)
	_strings=library.strings;_catalogues=cat;_bindings=bindings;_ui=ui;_art=art;_faction_icons=icons;_identity=identity
	var ship_base: int=902 if int(bindings.station_equipment.item_text_offset)==1263 else 900 if int(bindings.station_equipment.item_text_offset)==1255 else -1
	_ship_names={}
	for ship in cat.tables.ships.size():
		if ship_base>=0 and ship_base+ship<_strings.size():_ship_names[ship]=_strings[ship_base+ship]
	var font_theme:=Theme.new();font_theme.default_font=ui.font;theme=font_theme
	_header.text=_text("title");_back.text=_text("back")
	for label in _find_bars():label.text=_strings[1586] if label.get_meta("key")=="pilot" else _text(label.get_meta("key"))
	_stats_left.text="\n".join(["missions","kills","asteroids","salvaged","stations","battleships"].map(func(key):return _text(key)+":"))
	_stats_right.text="\n".join(["jumpgates","goods","ore","cores","wingmen"].map(func(key):return _text(key)+":"))
	(_left.find_child("Portrait",true,false) as TextureRect).texture=_portrait
	for axis in 2:
		for side in ["low","high"]:
			var faction: int=axis*2+(0 if side=="low" else 1)
			_reputation_bars[axis][side][0].texture=icons[faction] if faction<icons.size() else null
			_reputation_bars[axis][side][1].text=_strings[FACTION_TEXT_BASE+faction]
	for id in Elite.TOTAL:
		var cell: Button=_medal_buttons[id]
		(cell.find_child("Icon",true,false) as TextureRect).texture=art[medal_art(id,0).icon]
		(cell.find_child("Name",true,false) as Label).text=_strings[MEDAL_NAME_BASE+id]
	ui.apply_button(_back,_mobile,true)
	_relayout()
	return true

func _find_bars() -> Array:
	return find_children("*","Label",true,false).filter(func(node):return node.has_meta("key"))

func _text(key: String) -> String:
	var id: int=TEXT[key]
	return _strings[id] if id<_strings.size() else ""

## state: the station snapshot (career in `contracts`, ship in `loadout`).
func present(state: Dictionary) -> bool:
	error=""
	if _identity.is_empty():return reject("Configure Status before presenting it")
	var career: Variant=state.get("contracts")
	var loadout: Variant=state.get("loadout")
	if not career is Dictionary or not loadout is Dictionary:return reject("Status needs the docked career and ship")
	_state=state
	var play_ms: int=int(career.get("stats",{}).get("play_ms",0))
	var minutes: int=play_ms/60000
	_pilot_values.text="%d$\n%s %d\n%02d:%02d"%[int(career.get("credits",0)),_text("level"),int(career.get("rank",0)),minutes/60,minutes%60]
	var ship_id: int=int(loadout.get("ship_id",0))
	_ship_image.texture=_art.get(SHIP_IMAGE_BASE+ship_id)
	_ship_text.text="%s\n%s:\n%s:"%[_ship_names.get(ship_id,""),_text("fire_power"),_text("defense")]
	var ship_stats:=ship_values(loadout)
	_ship_values.text="\n%.1f\n%d"%[ship_stats.fire_power,ship_stats.defense]
	var axes: Array=career.get("reputation",{}).get("axes",[0,0])
	for axis in 2:_reputation_bars[axis].bar.value=float(axes[axis]) if axis<axes.size() else 0.0
	var progress: Dictionary=career.get("progress",{})
	var travel: Dictionary=career.get("travel_statistics",{})
	var goods:=0
	for row in career.get("blueprints",{}).get("entries",[]):
		if row is Dictionary:goods+=int(row.get("completed",0))
	_stats_left_values.text="%d\n%d\n%d\n%d\n%d\n%d"%[int(career.get("completed_side_missions",0)),int(progress.get("player_kills",0)),int(progress.get("asteroids_destroyed",0)),int(progress.get("cargo_recovered",0)),travel.get("visited_station_ids",[]).size(),int(progress.get("capital_ship_kills",0))]
	_stats_right_values.text="%d\n%d\n%d\n%d\n%d"%[int(travel.get("jumpgates_used",0)),goods,int(progress.get("mined_ore_tons",0)),int(progress.get("mined_cores",0)),int(career.get("wingmen",{}).get("hired_total",0))]
	_levels=career.get("base_medals",{}).get("levels",[])
	_elite=Elite.earned(career)
	for id in Elite.TOTAL:
		var look:=medal_art(id,maxi(0,_level(id)))
		var cell: Button=_medal_buttons[id]
		(cell.find_child("Ribbon",true,false) as TextureRect).texture=_art[look.ribbon]
		(cell.find_child("Icon",true,false) as TextureRect).modulate=look.tint
		(cell.find_child("Frame",true,false) as TextureRect).texture=_art[MEDAL_FRAME] if id==_selected else null
	if _selected>=0 and not _selectable(_selected):_selected=-1
	_hint.text="" if _selected<0 else medal_text(_selected)
	visible=true;_relayout()
	return true

func _level(id: int) -> int:
	if Elite.is_elite(id):return Elite.GOLD if id in _elite else 0
	return int(_levels[id]) if id<_levels.size() else 0

## Add-on medals are always selectable; base medals once earned.
func _selectable(id: int) -> bool:return Elite.is_elite(id) or _level(id)>0

## Ribbon art, icon art and icon tint for a medal at a level (0 = not earned).
func medal_art(id: int,level: int) -> Dictionary:
	if Elite.is_elite(id):
		return {"ribbon":Elite.FRAME_EARNED if level>0 else Elite.FRAME_NONE,"icon":Elite.icon_id(id),"tint":Color.WHITE if level>0 else TINTS[0]}
	return {"ribbon":RIBBONS[level],"icon":MEDAL_ICON_BASE+id,"tint":TINTS[level]}

## Original description with the threshold of the earned (or, for an
## add-on medal, its only) tier.
func description(id: int,level: int) -> String:
	var value: int=int(Elite.THRESHOLDS[id]) if Elite.is_elite(id) else Medals.description_value(id,level)
	return _strings[MEDAL_TEXT_BASE+id].replace("#",str(value))

func medal_text(id: int) -> String:
	if not _selectable(id):return ""
	return "%s\n%s"%[_strings[MEDAL_NAME_BASE+id],description(id,_level(id))]

func select_medal(id: int) -> void:
	if id<0 or id>=Elite.TOTAL or not _selectable(id):return
	_selected=id
	if not _state.is_empty():present(_state)

## Fire power sums each gun's damage per second; defense adds hull,
## shield and armour, as on the original status screen.
func ship_values(loadout: Dictionary) -> Dictionary:
	var ids: Array=loadout.get("equipment_ids",[])
	var ship_id: int=int(loadout.get("ship_id",0))
	var repair: Dictionary=_bindings.opening_actors.player_initialization.repair
	var hull:=Stats.resolve_ship_hull(_catalogues.tables.ships[ship_id].fields[int(repair.base_hull_field)],ShipInstance.upgrades(loadout),repair)
	var pools:=Stats.resolve_capacities(_catalogues.tables.items,ids,_bindings.opening_actors.player_initialization)
	var defense:=maxi(0,hull)+maxi(0,int(pools.get("shield",0)))+maxi(0,int(pools.get("armor",0)))
	var fire_power:=0.0
	var resolver:=Weapons.new()
	if resolver.configure(_bindings,_catalogues,_bindings.base_content_id):
		for slot in loadout.get("slots",[]):
			if not slot is Dictionary or int(slot.get("category",-1)) not in [0,2]:continue
			var gun:=resolver.resolve(int(slot.item_id),ids)
			if not gun.is_empty() and int(gun.interval_ms)>0:fire_power+=float(gun.damage)/float(gun.interval_ms)*1000.0
	return {"fire_power":fire_power,"defense":defense}

func handle_event(event: InputEvent) -> bool:
	if not visible:return false
	if event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_B):
		close_requested.emit();return true
	# Nothing is focused when Status opens: the first arrow, D-pad or stick move
	# enters the medal grid, which then scrolls with the focus.
	var focused:=get_viewport().gui_get_focus_owner()
	if (focused==null or not is_ancestor_of(focused)) and ["ui_up","ui_down","ui_left","ui_right"].any(func(action):return event.is_action_pressed(action)):
		_medal_buttons[0].grab_focus();return true
	return false

func set_mobile_layout(value: bool) -> void:
	_mobile=value
	if _ui!=null:_ui.apply_button(_back,value,true)
	_relayout()

func _relayout() -> void:
	if size.x<=0 or size.y<=0:return
	var scale:=size.y/1080.0*(1.4 if _mobile else 1.0)
	var font_size:=clampi(roundi(28*scale),12,26)
	for label in find_children("*","Label",true,false):label.add_theme_font_size_override("font_size",font_size)
	_root.add_theme_constant_override("margin_left",roundi(8*scale));_root.add_theme_constant_override("margin_right",roundi(8*scale))
	_root.add_theme_constant_override("margin_top",roundi(6*scale));_root.add_theme_constant_override("margin_bottom",roundi(6*scale))
	var ribbon:=Vector2(160,59)*scale*1.5
	for cell in _medal_buttons:
		var r: TextureRect=cell.find_child("Ribbon",true,false);r.custom_minimum_size=ribbon
		var icon: TextureRect=cell.find_child("Icon",true,false);var side:=38.0*scale*1.5
		icon.set_anchors_preset(Control.PRESET_CENTER);icon.offset_left=-side*0.5;icon.offset_right=side*0.5;icon.offset_top=-side*0.5-2*scale;icon.offset_bottom=side*0.5-2*scale
		cell.custom_minimum_size=Vector2(0,ribbon.y+font_size+8*scale)
	(_left.find_child("Portrait",true,false) as TextureRect).custom_minimum_size=Vector2(150,180)*scale
	_ship_image.custom_minimum_size=Vector2(125,60)*scale

func clear() -> void:
	visible=false;_state={};_selected=-1;_hint.text=""

func snapshot() -> Dictionary:
	return {"visible":visible,"selected":_selected,"hint":_hint.text,"pilot":_pilot_values.text,"stats_left":_stats_left_values.text,"stats_right":_stats_right_values.text,"ship":_ship_values.text}

func reject(message: String) -> bool:error=message;return false
