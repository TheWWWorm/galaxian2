extends PanelContainer
## Compact flight reference beside the paused menu, using imported interface art.
const Controls=preload("res://src/input/flight_controls.gd")
var _mobile:=false
var _title: Label
var _scroll: ScrollContainer
var _grid: GridContainer
var _note: Label
var _rows: Array[Dictionary]=[]

func _init() -> void:
	var margins:=MarginContainer.new();add_child(margins)
	for side in ["left","right","top","bottom"]:margins.add_theme_constant_override("margin_"+side,8)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",4);margins.add_child(column)
	_title=Label.new();_title.text="Controls";column.add_child(_title)
	_scroll=ScrollContainer.new();_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(_scroll)
	_grid=GridContainer.new();_grid.columns=2;_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation",8);_grid.add_theme_constant_override("v_separation",1)
	_scroll.add_child(_grid)
	_note=Label.new();_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(_note)
	hide()

func present(rows: Array[Dictionary],ui: RefCounted,mobile: bool,title: String,note: String="") -> void:
	_mobile=mobile;_rows=rows.duplicate(true)
	if ui!=null:
		theme=Theme.new();theme.default_font=ui.font
		add_theme_stylebox_override("panel",ui.styles[mobile].panel)
	_title.text=title
	_title.add_theme_font_size_override("font_size",18 if mobile else 14)
	_title.add_theme_color_override("font_color",Color(0.9,0.96,1.0))
	_note.text=note;_note.visible=not note.is_empty()
	_note.add_theme_font_size_override("font_size",15 if mobile else 12)
	_note.add_theme_color_override("font_color",Color(0.62,0.69,0.75))
	for child in _grid.get_children():_grid.remove_child(child);child.queue_free()
	for row in _rows:
		var caption:=Label.new();caption.text=str(row.label)
		caption.add_theme_font_size_override("font_size",16 if mobile else 13)
		caption.add_theme_color_override("font_color",Color(0.67,0.74,0.81))
		caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_grid.add_child(caption)
		var key:=Label.new();key.text=str(row.key);key.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		key.add_theme_font_size_override("font_size",16 if mobile else 13)
		key.add_theme_color_override("font_color",Color(0.95,0.98,1.0))
		_grid.add_child(key)
	_scroll.set_deferred("scroll_vertical",0)
	show()

func layout_in_viewport(viewport_size: Vector2,menu_left: float) -> void:
	if viewport_size.x<64 or viewport_size.y<64:return
	var width:=minf(265 if _mobile else 240,maxf(180,menu_left-52))
	var x:=minf(maxf(16,viewport_size.x*0.14),menu_left-width-28)
	var height:=minf(500,viewport_size.y-40) if _mobile else minf(510,viewport_size.y*0.64)
	var y:=20.0 if _mobile else minf(viewport_size.y*0.235,viewport_size.y-height-20)
	size=Vector2(width,height);position=Vector2(maxf(12,x),y)

static func reference_rows(strings: Array,mouse_steering: bool) -> Array[Dictionary]:
	# Read the maintained input map at presentation time so key changes cannot
	# leave a plausible but wrong shortcut printed on the pause screen.
	var rows: Array[Dictionary]=[]
	# The App Store bundle adds fourteen strings before this source control block.
	# Both known Mac layouts keep it 57 entries from the end of each language.
	var base:=strings.size()-57 if strings.size() in [3371,3385] else -1
	for direction in [[KEY_UP,0,"Up","UP"],[KEY_DOWN,1,"Down","DOWN"],
		[KEY_LEFT,2,"Left","LEFT"],[KEY_RIGHT,3,"Right","RIGHT"]]:
		if int(direction[0]) in Controls.TURN_KEYS:rows.append({"label":_source_text(strings,base+int(direction[1]),direction[2]),"key":direction[3]})
	if mouse_steering:rows.append({"label":"Mouse steering","key":"MOUSE"})
	_append_binding(rows,KEY_SPACE,"fire",strings,base+4,"Primary fire","SPACE")
	_append_binding(rows,KEY_R,"missiles",strings,base+5,"Secondary fire","R")
	_append_binding(rows,KEY_F,"dock",strings,base+6,"Dock / mine","F")
	_append_binding(rows,KEY_TAB,"time",strings,base+8,"Fast forward","TAB")
	if KEY_A in Controls.STRAFE_KEYS:rows.append({"label":_source_text(strings,base+11,"Strafe left"),"key":"A"})
	if KEY_D in Controls.STRAFE_KEYS:rows.append({"label":_source_text(strings,base+12,"Strafe right"),"key":"D"})
	if Controls.KEY_ACTIONS.get(KEY_P)=="pause" or Controls.KEY_ACTIONS.get(KEY_ESCAPE)=="pause":
		rows.append({"label":_source_text(strings,base+13,"Pause menu"),"key":"P / ESC" if Controls.KEY_ACTIONS.get(KEY_P)=="pause" else "ESC"})
	_append_binding(rows,KEY_E,"action_menu",strings,base+14,"Action menu","E")
	_append_binding(rows,KEY_Q,"autopilot",strings,560,"Autopilot","Q")
	_append_binding(rows,KEY_G,"secondary_menu",strings,base+15,"Rocket menu","G")
	_append_binding(rows,KEY_M,"mouse_mode",strings,base+18,"Mouse Ship/Menu","M")
	_append_binding(rows,KEY_BRACKETRIGHT,"throttle_up",strings,base+20,"Throttle up","]")
	_append_binding(rows,KEY_SLASH,"throttle_down",strings,base+21,"Throttle down","/")
	_append_binding(rows,KEY_S,"brake",strings,base+22,"Brake","S")
	return rows

static func _append_binding(rows: Array[Dictionary],key_code: int,action: String,strings: Array,text_id: int,fallback: String,key_name: String) -> void:
	if Controls.KEY_ACTIONS.get(key_code)==action:rows.append({"label":_source_text(strings,text_id,fallback),"key":key_name})

static func _source_text(strings: Array,index: int,fallback: String) -> String:
	return str(strings[index]) if index>=0 and index<strings.size() and not str(strings[index]).is_empty() else fallback

func snapshot() -> Dictionary:
	return {"rows":_rows.duplicate(true),"rect":Rect2(position,size),"visible":visible,
		"scroll_max":_scroll.get_v_scroll_bar().max_value,"scroll_page":_scroll.get_v_scroll_bar().page}
