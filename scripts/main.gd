extends Control

const DataStore := preload("res://scripts/data_store.gd")
const SyncService := preload("res://scripts/sync_service.gd")
const AnalysisChart := preload("res://scripts/analysis_chart.gd")

const KIND_LABELS := {
	"feeding": "喂养",
	"diaper": "尿布",
	"exercise": "锻炼",
	"hygiene": "卫生",
	"supplement": "补充剂",
	"growth": "身高体重数据"
}

const EXERCISE_ITEMS := {
	"按摩": ["抚触", "触觉球", "被动操", "排气操"],
	"大动作": ["翻身侧俯抬头", "拉起独自撑坐", "内耳前庭训练"],
	"精细动作认知": ["追视（黑白卡）", "触碰", "脚踏琴"],
	"语言": ["语言眼神交流", "读书", "听音乐摇铃"],
	"游戏": ["手绢躲猫猫", "照镜子", "顶牛牛"]
}

const HYGIENE_ITEMS := ["洗脸", "洗澡", "游泳"]
const SUPPLEMENT_ITEMS := ["AD", "D3", "DHA", "益生菌", "水", "铁剂", "乳糖酶", "其他"]
const TEXT_COLOR := Color("#493f45")
const MUTED_TEXT_COLOR := Color("#6f6b73")
const DANGER_TEXT_COLOR := Color("#a45f49")
const HOME_PHOTO := "res://assets/home_photo.jpg"

var store: BlueberryDataStore
var sync_service: BlueberrySyncService
var fields: Dictionary = {}
var current_kind := ""
var editing_id := ""
var message_label: Label
var diaper_detail_box: VBoxContainer
var exercise_item_option: OptionButton
var supplement_other_row: VBoxContainer
var active_choice_popup: PopupPanel
var sync_status_label: Label


func _ready() -> void:
	randomize()
	_install_readable_theme()
	store = DataStore.new()
	add_child(store)
	sync_service = SyncService.new()
	add_child(sync_service)
	show_home()


func show_home() -> void:
	var body := _screen("小蓝莓的日常", false)
	body.add_child(_home_photo_panel())

	var name := Label.new()
	name.text = "小蓝莓今天也在认真长大"
	name.add_theme_font_size_override("font_size", 26)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(name)

	var date := Label.new()
	date.text = "今天：%s" % store.today()
	date.add_theme_color_override("font_color", MUTED_TEXT_COLOR)
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(date)

	var today_summary := store.summarize(store.records_for_date(store.today()))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	body.add_child(chips)
	for text in ["记录 %s" % today_summary["total"], "奶量 %sml" % today_summary["milk_ml"], "尿布 %s" % today_summary["diaper"], "成长 %s" % today_summary["growth"]]:
		chips.add_child(_chip(text))

	body.add_child(_big_button("添加新的记录", "", Callable(self, "show_record_entry"), true))
	body.add_child(_big_button("数据总览", "", Callable(self, "show_visualization"), true))
	body.add_child(_big_button("数据分析", "", Callable(self, "show_data_analysis"), true))
	body.add_child(_big_button("记录查询与修正", "", Callable(self, "show_search"), true))
	body.add_child(_big_button("同步数据", "", Callable(self, "_sync_and_refresh_home"), true))
	sync_status_label = _empty_text("同步状态：未同步")
	sync_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(sync_status_label)


func show_record_entry() -> void:
	var body := _screen("添加新的记录", true)
	message_label = _message_label()
	body.add_child(_section_title("今天记什么？"))
	for kind in ["feeding", "diaper", "exercise", "hygiene", "supplement", "growth"]:
		body.add_child(_big_button(KIND_LABELS[kind], _record_hint(kind), func(): show_record_form(kind)))
	body.add_child(message_label)


func show_record_form(kind: String, record: Dictionary = {}) -> void:
	current_kind = kind
	editing_id = str(record.get("id", ""))
	fields = {}
	var data: Dictionary = record.get("data", {})
	var body := _screen(("%s%s" % ["修改", KIND_LABELS[kind]]) if editing_id != "" else ("记录" + KIND_LABELS[kind]), true, Callable(self, "show_search") if editing_id != "" else Callable(self, "show_record_entry"))
	message_label = _message_label()

	_add_date_picker(body, "date", "日期", str(record.get("date", store.today())))

	match kind:
		"feeding":
			_add_option(body, "feeding_type", "喂养方式", ["母乳", "配方奶粉"], data.get("feeding_type", "母乳"))
			_add_time_picker(body, "start_time", "开始时间", data.get("start_time", _now_time()))
			_add_time_picker(body, "end_time", "结束时间", data.get("end_time", _now_time()))
			_add_milk_picker(body, "milk_ml", "奶量（ml）", data.get("milk_ml", 0))
			_add_text(body, "note", "备注（150字内）", data.get("note", ""))
		"diaper":
			var diaper_type := _add_option(body, "diaper_type", "类型", ["小便", "大便"], data.get("diaper_type", "小便"))
			diaper_type.item_selected.connect(func(_idx): _refresh_diaper_fields())
			_add_time_picker(body, "time", "时间", data.get("time", _now_time()))
			diaper_detail_box = VBoxContainer.new()
			diaper_detail_box.add_theme_constant_override("separation", 10)
			body.add_child(diaper_detail_box)
			_refresh_diaper_fields(data)
		"exercise":
			var category := _add_option(body, "category", "大类", EXERCISE_ITEMS.keys(), data.get("category", "按摩"))
			category.item_selected.connect(func(_idx): _refresh_exercise_items())
			_add_time_picker(body, "time", "时间", data.get("time", _now_time()))
			exercise_item_option = _add_option(body, "item", "细分", [], data.get("item", ""))
			_refresh_exercise_items(data.get("item", ""))
		"hygiene":
			_add_time_picker(body, "time", "时间", data.get("time", _now_time()))
			_add_option(body, "item", "项目", HYGIENE_ITEMS, data.get("item", "洗脸"))
		"supplement":
			_add_time_picker(body, "time", "时间", data.get("time", _now_time()))
			var item := _add_option(body, "item", "项目", SUPPLEMENT_ITEMS, data.get("item", "AD"))
			item.item_selected.connect(func(_idx): _refresh_supplement_other())
			_add_line(body, "other", "其他（15字内）", data.get("other", ""), "例如 钙")
			supplement_other_row = fields["other"].get_parent()
			_refresh_supplement_other()
		"growth":
			_add_line(body, "height_cm", "身高（cm）", data.get("height_cm", ""), "例如 62.5")
			_add_line(body, "weight_kg", "体重（kg）", data.get("weight_kg", ""), "例如 6.35")

	var save := _button("保存", Callable(self, "_save_record"))
	save.custom_minimum_size = Vector2(0, 54)
	body.add_child(save)
	body.add_child(message_label)


func _save_record() -> void:
	var record := _collect_record()
	if record.is_empty():
		return
	if editing_id == "":
		store.add_record(record)
		_show_message("已经记好了。")
	else:
		store.update_record(editing_id, record)
		_show_message("已经更新。")
	await _sync_silently()
	await get_tree().create_timer(0.35).timeout
	if editing_id == "":
		show_record_entry()
	else:
		show_search(str(record.get("date", store.today())))


func _collect_record() -> Dictionary:
	var data: Dictionary = {}
	match current_kind:
		"feeding":
			data = {
				"feeding_type": _option_value("feeding_type"),
				"start_time": _control_value("start_time"),
				"end_time": _control_value("end_time"),
				"milk_ml": max(0, int(_control_value("milk_ml"))),
				"note": _field_text("note")
			}
			if str(data["note"]).length() > 150:
				return _invalid("备注不能超过150字。")
		"diaper":
			data = {"diaper_type": _option_value("diaper_type"), "time": _control_value("time")}
			if data["diaper_type"] == "小便":
				data["pee_amount"] = _option_value("pee_amount")
			else:
				data["poop_texture"] = _option_value("poop_texture")
				data["poop_color"] = _field_text("poop_color")
				data["poop_amount"] = _option_value("poop_amount")
				data["note"] = _field_text("note")
				if str(data["note"]).length() > 150:
					return _invalid("备注不能超过150字。")
		"exercise":
			data = {"time": _control_value("time"), "category": _option_value("category"), "item": _option_value("item")}
		"hygiene":
			data = {"time": _control_value("time"), "item": _option_value("item")}
		"supplement":
			data = {"time": _control_value("time"), "item": _option_value("item")}
			if data["item"] == "其他":
				data["other"] = _field_text("other")
				if str(data["other"]).strip_edges() == "":
					return _invalid("请填写“其他”的名称。")
				if str(data["other"]).length() > 15:
					return _invalid("其他名称不能超过15字。")
				data["item"] = data["other"]
		"growth":
			var height_text := _field_text("height_cm")
			var weight_text := _field_text("weight_kg")
			if height_text == "" and weight_text == "":
				return _invalid("身高和体重至少填写一项。")
			if height_text != "" and not _is_valid_positive_number(height_text):
				return _invalid("身高请填写有效数字。")
			if weight_text != "" and not _is_valid_positive_number(weight_text):
				return _invalid("体重请填写有效数字。")
			data = {}
			if height_text != "":
				data["height_cm"] = float(height_text)
			if weight_text != "":
				data["weight_kg"] = float(weight_text)

	var date := _control_value("date")
	if not _looks_like_date(date):
		return _invalid("日期格式请写成 YYYY-MM-DD。")
	return {"kind": current_kind, "date": date, "data": data}


func show_visualization(date_value: String = "") -> void:
	var body := _screen("数据总览", true)
	message_label = _message_label()
	var date := date_value if date_value != "" else store.today()
	_add_date_picker(body, "viz_date", "日期", date)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	body.add_child(controls)
	controls.add_child(_button("按天", func(): _render_visual(body, _control_value("viz_date"), false)))
	controls.add_child(_button("按周", func(): _render_visual(body, _control_value("viz_date"), true)))
	body.add_child(message_label)
	_render_visual(body, date, false)


func show_data_analysis(date_value: String = "") -> void:
	var body := _screen("数据分析", true)
	message_label = _message_label()
	var date := date_value if date_value != "" else store.today()
	_add_date_picker(body, "analysis_date", "结束日期", date)
	_add_option(body, "analysis_window", "时间窗", ["近三天", "近一周", "近一月"], "近一周")
	_add_option(body, "analysis_kind", "分析类型", ["喂养", "尿布"], "喂养")
	body.add_child(_button("展示", func(): _render_analysis(body)))
	body.add_child(message_label)
	_render_analysis(body)


func _render_analysis(body: VBoxContainer) -> void:
	for child in body.get_children():
		if child.has_meta("analysis"):
			body.remove_child(child)
			child.queue_free()

	var end_date := _control_value("analysis_date")
	if not _looks_like_date(end_date):
		_show_message("日期格式请写成 YYYY-MM-DD。")
		return
	var days := _analysis_window_days(_option_value("analysis_window"))
	var dates := _date_range_ending(end_date, days)
	var start_date := str(dates[0])
	var records := store.records_between(start_date, end_date)
	var kind := _option_value("analysis_kind")

	var panel := _panel()
	panel.set_meta("analysis", true)
	body.add_child(panel)
	body.move_child(panel, body.get_child_count() - 2)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)

	var title := _section_title("%s · %s 至 %s" % [kind, start_date, end_date])
	box.add_child(title)
	var chart: BlueberryAnalysisChart = AnalysisChart.new()
	box.add_child(chart)
	if kind == "喂养":
		var feeding_data := _feeding_analysis_data(records, dates)
		chart.set_feeding_data(dates, feeding_data["totals"], feeding_data["times"])
	else:
		chart.set_diaper_data(dates, _diaper_analysis_points(records, dates))
	call_deferred("_make_scroll_friendly", panel)


func _analysis_window_days(label: String) -> int:
	match label:
		"近三天":
			return 3
		"近一月":
			return 30
		_:
			return 7


func _date_range_ending(end_date: String, days: int) -> Array:
	var end_day := _date_to_day_number(end_date)
	var result: Array = []
	for i in range(days - 1, -1, -1):
		result.append(_date_from_day_number(end_day - i))
	return result


func _feeding_analysis_data(records: Array, dates: Array) -> Dictionary:
	var index := _date_index_map(dates)
	var totals: Array = []
	var times: Array = []
	for _date in dates:
		totals.append(0)
		times.append([])

	for record in records:
		if str(record.get("kind", "")) != "feeding":
			continue
		var date := str(record.get("date", ""))
		if not index.has(date):
			continue
		var day_index := int(index[date])
		var data: Dictionary = record.get("data", {})
		totals[day_index] = int(totals[day_index]) + int(data.get("milk_ml", 0))
		var minute := _time_to_minutes(str(data.get("start_time", data.get("time", "00:00"))))
		times[day_index].append(minute)
	return {"totals": totals, "times": times}


func _diaper_analysis_points(records: Array, dates: Array) -> Array:
	var index := _date_index_map(dates)
	var points: Array = []
	for record in records:
		if str(record.get("kind", "")) != "diaper":
			continue
		var date := str(record.get("date", ""))
		if not index.has(date):
			continue
		var data: Dictionary = record.get("data", {})
		var diaper_type := str(data.get("diaper_type", "小便"))
		var amount := str(data.get("pee_amount", data.get("poop_amount", "中")))
		points.append({
			"day_index": int(index[date]),
			"minute": _time_to_minutes(str(data.get("time", "00:00"))),
			"type": diaper_type,
			"amount": amount
		})
	return points


func _date_index_map(dates: Array) -> Dictionary:
	var result := {}
	for i in range(dates.size()):
		result[str(dates[i])] = i
	return result


func _time_to_minutes(value: String) -> int:
	var parts := value.split(":")
	if parts.size() != 2:
		return 0
	return clampi(int(parts[0]) * 60 + int(parts[1]), 0, 1439)


func _render_visual(body: VBoxContainer, date: String, weekly: bool) -> void:
	for child in body.get_children():
		if child.has_meta("viz"):
			body.remove_child(child)
			child.queue_free()
	if not _looks_like_date(date):
		_show_message("日期格式请写成 YYYY-MM-DD。")
		return

	var records: Array
	var title := ""
	if weekly:
		var bounds := store.week_bounds(date)
		records = store.records_between(bounds[0], bounds[1])
		title = "%s 至 %s" % [bounds[0], bounds[1]]
	else:
		records = store.records_for_date(date)
		title = date
	var summary := store.summarize(records)
	var box := VBoxContainer.new()
	box.set_meta("viz", true)
	box.add_theme_constant_override("separation", 12)
	body.add_child(box)
	body.move_child(box, body.get_child_count() - 2)

	var panel := _panel()
	box.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	panel.add_child(inner)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	inner.add_child(_section_title(title))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	inner.add_child(chips)
	for text in ["总记录 %s" % summary["total"], "喂养 %s" % summary["feeding"], "奶量 %sml" % summary["milk_ml"], "尿布 %s" % summary["diaper"], "成长 %s" % summary["growth"]]:
		chips.add_child(_chip(text))

	if records.is_empty():
		box.add_child(_empty_text("这段时间还没有记录。"))
	else:
		_add_grouped_overview(box, records, weekly)


func show_search(date_value: String = "") -> void:
	var body := _screen("记录查询与修正", true)
	message_label = _message_label()
	_add_date_picker(body, "search_date", "查询日期", date_value if date_value != "" else store.today())
	body.add_child(_button("查询", func(): _render_search(body, _control_value("search_date"))))
	body.add_child(message_label)
	_render_search(body, _control_value("search_date"))


func _render_search(body: VBoxContainer, date: String) -> void:
	for child in body.get_children():
		if child.has_meta("search_result"):
			body.remove_child(child)
			child.queue_free()
	if not _looks_like_date(date):
		_show_message("日期格式请写成 YYYY-MM-DD。")
		return
	var box := VBoxContainer.new()
	box.set_meta("search_result", true)
	box.add_theme_constant_override("separation", 12)
	body.add_child(box)
	var records := store.records_for_date(date)
	if records.is_empty():
		box.add_child(_empty_text("这一天还没有记录。"))
		return
	for record in records:
		box.add_child(_record_card(record, true))


func _record_card(record: Dictionary, editable: bool) -> PanelContainer:
	var panel := _panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var title := Label.new()
	title.text = "%s  %s" % [store.display_time(record), store.display_title(record)]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(title)

	var details := Label.new()
	details.text = _detail_text(record)
	details.add_theme_color_override("font_color", MUTED_TEXT_COLOR)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(details)

	if editable:
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		box.add_child(actions)
		actions.add_child(_button("编辑", func(): show_record_form(str(record.get("kind", "")), record)))
		actions.add_child(_button("删除", func(): _delete_and_refresh(record)))
	return panel


func _add_grouped_overview(parent: VBoxContainer, records: Array, show_date: bool) -> void:
	for kind in ["feeding", "diaper", "exercise", "hygiene", "supplement", "growth"]:
		var grouped: Array = []
		for record in records:
			if str(record.get("kind", "")) == kind:
				grouped.append(record)
		parent.add_child(_record_table(kind, grouped, show_date))


func _record_table(kind: String, records: Array, show_date: bool) -> PanelContainer:
	var panel := _panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)

	var title := Label.new()
	title.text = "%s（%s）" % [KIND_LABELS[kind], records.size()]
	title.add_theme_font_size_override("font_size", 21)
	box.add_child(title)

	if records.is_empty():
		box.add_child(_empty_text("暂无记录"))
		return panel

	box.add_child(_table_header(show_date))
	for record in records:
		box.add_child(_table_row(record, show_date))
	return panel


func _table_header(show_date: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_table_cell("时间" if not show_date else "日期/时间", 0.9, true))
	row.add_child(_table_cell("内容", 1.0, true))
	row.add_child(_table_cell("详情", 1.35, true))
	return row


func _table_row(record: Dictionary, show_date: bool) -> HBoxContainer:
	var data: Dictionary = record.get("data", {})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_table_cell(_table_time(record, show_date), 0.9, false))
	row.add_child(_table_cell(_table_content(record, data), 1.0, false))
	row.add_child(_table_cell(_table_detail(record, data), 1.35, false))
	return row


func _table_cell(text: String, ratio: float, bold: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_stretch_ratio = ratio
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16 if bold else 15)
	label.add_theme_color_override("font_color", TEXT_COLOR if bold else MUTED_TEXT_COLOR)
	return label


func _table_time(record: Dictionary, show_date: bool) -> String:
	var prefix := "%s\n" % record.get("date", "") if show_date else ""
	var data: Dictionary = record.get("data", {})
	if str(record.get("kind", "")) == "feeding":
		return "%s%s-%s" % [prefix, data.get("start_time", ""), data.get("end_time", "")]
	if str(record.get("kind", "")) == "growth":
		return "%s测量" % prefix
	return "%s%s" % [prefix, data.get("time", "")]


func _table_content(record: Dictionary, data: Dictionary) -> String:
	match str(record.get("kind", "")):
		"feeding":
			return "%s\n%s ml" % [data.get("feeding_type", ""), data.get("milk_ml", 0)]
		"diaper":
			return str(data.get("diaper_type", ""))
		"exercise":
			return "%s\n%s" % [data.get("category", ""), data.get("item", "")]
		"hygiene":
			return str(data.get("item", ""))
		"supplement":
			return str(data.get("item", ""))
		"growth":
			return _growth_measure_text(data)
		_:
			return ""


func _table_detail(record: Dictionary, data: Dictionary) -> String:
	match str(record.get("kind", "")):
		"feeding":
			return str(data.get("note", ""))
		"diaper":
			if data.get("diaper_type", "") == "小便":
				return "量：%s" % data.get("pee_amount", "")
			return "性状：%s\n颜色：%s\n量：%s\n%s" % [data.get("poop_texture", ""), data.get("poop_color", ""), data.get("poop_amount", ""), data.get("note", "")]
		"exercise":
			return "锻炼记录"
		"hygiene":
			return "卫生护理"
		"supplement":
			return "补充/饮水"
		"growth":
			return "成长数据"
		_:
			return ""


func _delete_and_refresh(record: Dictionary) -> void:
	var date := str(record.get("date", store.today()))
	store.delete_record(str(record.get("id", "")))
	await _sync_silently()
	show_search(date)


func _sync_and_refresh_home() -> void:
	if sync_status_label != null:
		sync_status_label.text = "同步中..."
	var result: Dictionary = await _sync_now()
	if sync_status_label != null:
		if bool(result.get("ok", false)):
			sync_status_label.text = "同步完成：下载 %s 条，上传 %s 条" % [int(result.get("merged", 0)), int(result.get("uploaded", 0))]
			await get_tree().create_timer(0.5).timeout
			show_home()
		else:
			sync_status_label.text = "同步失败：%s" % result.get("error", "未知错误")


func _sync_silently() -> void:
	await _sync_now()


func _sync_now() -> Dictionary:
	if sync_service == null:
		return {"ok": false, "error": "同步服务未初始化"}
	var upload_payload := store.sync_payload()
	var cursor := ""
	var merged := 0
	var uploaded_ids: Array = []
	var latest := store.last_sync_at
	var result: Dictionary = {}
	var first_request := true
	for page in range(20):
		result = await sync_service.sync_records(upload_payload if first_request else [], store.last_sync_at, cursor)
		first_request = false
		if not bool(result.get("ok", false)):
			return result
		for saved in result.get("saved", []):
			if saved is Dictionary:
				uploaded_ids.append(str(saved.get("record_id", saved.get("id", ""))))
		var remote_records: Array = result.get("records", [])
		merged += store.merge_remote_records(remote_records)
		for record in remote_records:
			if record is Dictionary:
				latest = max(latest, int(record.get("updated_at", 0)))
		cursor = str(result.get("next_cursor", ""))
		if not bool(result.get("has_more", false)) or cursor == "":
			break
	store.mark_uploaded(uploaded_ids)
	store.set_last_sync_at(latest)
	result["merged"] = merged
	result["uploaded"] = uploaded_ids.size()
	return result


func _refresh_diaper_fields(data: Dictionary = {}) -> void:
	for child in diaper_detail_box.get_children():
		diaper_detail_box.remove_child(child)
		child.queue_free()
	var diaper_type := _option_value("diaper_type")
	if diaper_type == "小便":
		_add_option(diaper_detail_box, "pee_amount", "尿量", ["大", "中", "小"], data.get("pee_amount", "中"))
	else:
		_add_option(diaper_detail_box, "poop_texture", "性状", ["偏稀", "正常", "便干"], data.get("poop_texture", "正常"))
		_add_line(diaper_detail_box, "poop_color", "颜色", data.get("poop_color", ""), "例如 金黄")
		_add_option(diaper_detail_box, "poop_amount", "便量", ["大", "中", "小"], data.get("poop_amount", "中"))
		_add_text(diaper_detail_box, "note", "备注（150字内）", data.get("note", ""))


func _refresh_exercise_items(selected_item: String = "") -> void:
	if exercise_item_option == null:
		return
	exercise_item_option.clear()
	var items: Array = EXERCISE_ITEMS.get(_option_value("category"), [])
	for item in items:
		exercise_item_option.add_item(item)
	var idx := items.find(selected_item)
	if exercise_item_option.item_count > 0:
		exercise_item_option.select(max(0, idx))


func _refresh_supplement_other() -> void:
	if supplement_other_row != null:
		supplement_other_row.visible = _option_value("item") == "其他"


func _screen(title: String, back: bool, back_to: Callable = Callable(self, "show_home")) -> VBoxContainer:
	var old_pages: Array = []
	for child in get_children():
		if child != store and child != sync_service:
			old_pages.append(child)
	
	var page := Control.new()
	page.set_meta("page", true)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.clip_contents = true
	page.child_entered_tree.connect(func(node): call_deferred("_make_scroll_friendly", node))
	add_child(page)
	_animate_page_in(page, old_pages)
	
	var bg := ColorRect.new()
	bg.color = Color("#fff8f1")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	page.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	body.add_child(header)
	if back:
		header.add_child(_button("‹", back_to, Vector2(48, 44)))
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 30)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(label)
	call_deferred("_make_scroll_friendly", page)
	return body


func _animate_page_in(page: Control, old_pages: Array) -> void:
	var width: float = maxf(get_viewport_rect().size.x, 390.0)
	page.position.x = width
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(page, "position:x", 0.0, 0.24).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	for old_page in old_pages:
		if old_page is Control:
			tween.tween_property(old_page, "position:x", -width * 0.32, 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
			tween.tween_property(old_page, "modulate:a", 0.0, 0.18)
		else:
			old_page.queue_free()
	tween.finished.connect(func():
		for old_page in old_pages:
			if is_instance_valid(old_page):
				old_page.queue_free()
	)


func _make_scroll_friendly(node: Node) -> void:
	if node is ScrollContainer:
		node.mouse_filter = Control.MOUSE_FILTER_STOP
	elif node is Label or node is TextureRect or node is ColorRect:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif node is Button or node is OptionButton or node is PanelContainer:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	elif node is LineEdit or node is TextEdit:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	elif node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_PASS

	for child in node.get_children():
		_make_scroll_friendly(child)


func _big_button(title: String, subtitle: String, action: Callable, centered := false) -> PanelContainer:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(0, 72 if centered else 0)
	panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			action.call()
	)
	if centered:
		var center := CenterContainer.new()
		panel.add_child(center)
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
		var label := Label.new()
		label.text = title
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 24)
		center.add_child(label)
		return panel

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 24)
	box.add_child(t)
	if subtitle != "":
		var s := Label.new()
		s.text = subtitle
		s.add_theme_color_override("font_color", MUTED_TEXT_COLOR)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(s)
	return panel


func _home_photo_panel() -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(0, 380)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fff1e8")
	style.border_color = Color("#f0d9c7")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	frame.add_theme_stylebox_override("panel", style)

	var photo := TextureRect.new()
	photo.texture = load(HOME_PHOTO)
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float blur_amount = 1.2;
void fragment() {
	vec2 p = TEXTURE_PIXEL_SIZE * blur_amount;
	vec4 c = texture(TEXTURE, UV) * 0.24;
	c += texture(TEXTURE, UV + vec2(p.x, 0.0)) * 0.12;
	c += texture(TEXTURE, UV - vec2(p.x, 0.0)) * 0.12;
	c += texture(TEXTURE, UV + vec2(0.0, p.y)) * 0.12;
	c += texture(TEXTURE, UV - vec2(0.0, p.y)) * 0.12;
	c += texture(TEXTURE, UV + vec2(p.x, p.y)) * 0.10;
	c += texture(TEXTURE, UV + vec2(-p.x, p.y)) * 0.10;
	c += texture(TEXTURE, UV + vec2(p.x, -p.y)) * 0.10;
	c += texture(TEXTURE, UV + vec2(-p.x, -p.y)) * 0.10;
	COLOR = c;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	photo.material = material
	frame.add_child(photo)

	var veil := ColorRect.new()
	veil.color = Color(1.0, 0.94, 0.88, 0.18)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(veil)
	return frame


func _button(text: String, action: Callable, min_size := Vector2(0, 46)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	return button


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#ffffff")
	style.border_color = Color("#f0d9c7")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0.72, 0.55, 0.44, 0.12)
	style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _chip(text: String) -> Label:
	var chip := Label.new()
	chip.text = "  %s  " % text
	chip.add_theme_color_override("font_color", TEXT_COLOR)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fff1d9")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	chip.add_theme_stylebox_override("normal", style)
	return chip


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 21)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _message_label() -> Label:
	var label := Label.new()
	label.text = ""
	label.add_theme_color_override("font_color", DANGER_TEXT_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _empty_text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MUTED_TEXT_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _line(label: String, value: String, placeholder: String) -> LineEdit:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var l := Label.new()
	l.text = label
	row.add_child(l)
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 46)
	row.add_child(edit)
	return edit


func _add_line(parent: VBoxContainer, key: String, label: String, value, placeholder: String) -> LineEdit:
	var edit := _line(label, str(value), placeholder)
	fields[key] = edit
	parent.add_child(edit.get_parent())
	return edit


func _value_button(label: String, value: String) -> Button:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var l := Label.new()
	l.text = label
	row.add_child(l)
	var button := _picker_button(value)
	row.add_child(button)
	return button


func _picker_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 46)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", TEXT_COLOR)
	return button


func _add_date_picker(parent: VBoxContainer, key: String, label: String, selected_date: String) -> Button:
	var picker := _value_button(label, selected_date)
	fields[key] = {"type": "date", "value": selected_date, "button": picker}
	picker.pressed.connect(func():
		_show_choice_popup(label, _date_options(_control_value(key)), _control_value(key), func(value): _set_value_control(key, str(value)))
	)
	parent.add_child(picker.get_parent())
	return picker


func _add_time_picker(parent: VBoxContainer, key: String, label: String, selected_time) -> HBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var title := Label.new()
	title.text = label
	row.add_child(title)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	row.add_child(controls)

	var time_parts := _parse_time(str(selected_time))
	var hour_button := _picker_button("%02d 时" % time_parts[0])
	var minute_button := _picker_button("%02d 分" % _snap_minute(time_parts[1]))
	controls.add_child(hour_button)
	controls.add_child(minute_button)

	fields[key] = {
		"type": "time",
		"hour": time_parts[0],
		"minute": _snap_minute(time_parts[1]),
		"hour_button": hour_button,
		"minute_button": minute_button
	}
	hour_button.pressed.connect(func():
		_show_choice_popup("选择小时", _hour_options(), "%02d" % int(fields[key]["hour"]), func(value):
			fields[key]["hour"] = int(value)
			_update_time_buttons(key)
		)
	)
	minute_button.pressed.connect(func():
		_show_choice_popup("选择分钟", _minute_options(), "%02d" % int(fields[key]["minute"]), func(value):
			fields[key]["minute"] = int(value)
			_update_time_buttons(key)
		)
	)
	parent.add_child(row)
	return controls


func _add_milk_picker(parent: VBoxContainer, key: String, label: String, selected_ml) -> Button:
	var values: Array = []
	for ml in range(0, 301, 10):
		values.append(ml)
	var rounded := clampi(int(round(float(selected_ml) / 10.0)) * 10, 0, 300)
	var picker := _value_button(label, "%d ml" % rounded)
	fields[key] = {"type": "choice", "value": str(rounded), "button": picker, "suffix": " ml"}
	var options: Array = []
	for ml in values:
		options.append({"label": "%d ml" % ml, "value": str(ml)})
	picker.pressed.connect(func():
		_show_choice_popup(label, options, _control_value(key), func(value): _set_value_control(key, str(value)))
	)
	parent.add_child(picker.get_parent())
	return picker


func _add_text(parent: VBoxContainer, key: String, label: String, value) -> TextEdit:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var l := Label.new()
	l.text = label
	row.add_child(l)
	var edit := TextEdit.new()
	edit.text = str(value)
	edit.custom_minimum_size = Vector2(0, 110)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	row.add_child(edit)
	fields[key] = edit
	parent.add_child(row)
	return edit


func _add_option(parent: VBoxContainer, key: String, label: String, options, selected_value = "") -> OptionButton:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var l := Label.new()
	l.text = label
	row.add_child(l)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(0, 46)
	for item in options:
		option.add_item(str(item))
	var idx := Array(options).find(str(selected_value))
	if option.item_count > 0:
		option.select(max(0, idx))
	row.add_child(option)
	fields[key] = option
	parent.add_child(row)
	return option


func _bar_row(label: String, value: int, max_value: int, color: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var text := Label.new()
	text.text = "%s  %s" % [label, value]
	box.add_child(text)
	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 16)
	progress.max_value = 100
	progress.value = 100.0 * float(value) / float(max_value)
	progress.show_percentage = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color("#f3ece6")
	bg_style.corner_radius_top_left = 8
	bg_style.corner_radius_top_right = 8
	bg_style.corner_radius_bottom_left = 8
	bg_style.corner_radius_bottom_right = 8
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.corner_radius_top_left = 8
	fill_style.corner_radius_top_right = 8
	fill_style.corner_radius_bottom_left = 8
	fill_style.corner_radius_bottom_right = 8
	progress.add_theme_stylebox_override("background", bg_style)
	progress.add_theme_stylebox_override("fill", fill_style)
	box.add_child(progress)
	return box


func _field_text(key: String) -> String:
	var node = fields.get(key)
	if node == null:
		return ""
	if node is TextEdit:
		return node.text.strip_edges()
	if node is LineEdit:
		return node.text.strip_edges()
	return ""


func _control_value(key: String) -> String:
	var node = fields.get(key)
	if node == null:
		return ""
	if node is Dictionary:
		if node.get("type", "") == "time":
			return "%02d:%02d" % [int(node.get("hour", 0)), int(node.get("minute", 0))]
		return str(node.get("value", ""))
	if node is OptionButton:
		var metadata: Variant = node.get_item_metadata(node.selected)
		if metadata != null:
			return str(metadata)
		return node.get_item_text(node.selected)
	return _field_text(key)


func _option_value(key: String) -> String:
	var option: OptionButton = fields.get(key)
	if option == null or option.item_count == 0:
		return ""
	return option.get_item_text(option.selected)


func _set_value_control(key: String, value: String) -> void:
	var node = fields.get(key)
	if not (node is Dictionary):
		return
	node["value"] = value
	var button: Button = node.get("button")
	if button != null:
		var suffix := str(node.get("suffix", ""))
		button.text = value + suffix


func _update_time_buttons(key: String) -> void:
	var node: Dictionary = fields.get(key, {})
	var hour_button: Button = node.get("hour_button")
	var minute_button: Button = node.get("minute_button")
	if hour_button != null:
		hour_button.text = "%02d 时" % int(node.get("hour", 0))
	if minute_button != null:
		minute_button.text = "%02d 分" % int(node.get("minute", 0))


func _show_choice_popup(title: String, options: Array, selected_value: String, on_select: Callable) -> void:
	if active_choice_popup != null and is_instance_valid(active_choice_popup):
		active_choice_popup.queue_free()

	var popup := PopupPanel.new()
	active_choice_popup = popup
	add_child(popup)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 16)
	outer.add_theme_constant_override("margin_right", 16)
	outer.add_theme_constant_override("margin_top", 16)
	outer.add_theme_constant_override("margin_bottom", 16)
	popup.add_child(outer)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	outer.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	header.add_child(_button("关闭", func(): popup.queue_free(), Vector2(72, 42)))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, minf(520.0, get_viewport_rect().size.y * 0.62))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for option in options:
		var value := str(option.get("value", option.get("label", "")))
		var label := str(option.get("label", value))
		var row_button := _choice_button(label, value, selected_value, on_select, popup)
		row_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(row_button)

	call_deferred("_make_scroll_friendly", popup)
	popup.popup_centered(Vector2i(int(minf(360.0, get_viewport_rect().size.x - 32.0)), int(minf(640.0, get_viewport_rect().size.y - 64.0))))


func _choice_button(label: String, value: String, selected_value: String, on_select: Callable, popup: PopupPanel) -> Button:
	var text := ("✓  " if value == selected_value else "") + label
	return _button(text, func():
		on_select.call(value)
		popup.queue_free()
	, Vector2(0, 44))


func _show_message(text: String) -> void:
	if message_label != null:
		message_label.text = text


func _invalid(text: String) -> Dictionary:
	_show_message(text)
	return {}


func _looks_like_date(value: String) -> bool:
	var parts := value.split("-")
	return parts.size() == 3 and parts[0].length() == 4 and parts[1].length() == 2 and parts[2].length() == 2


func _is_valid_positive_number(value: String) -> bool:
	var text := value.strip_edges()
	if text == "":
		return false
	var dot_count := 0
	var digit_count := 0
	for i in range(text.length()):
		var c := text.substr(i, 1)
		if c == ".":
			dot_count += 1
			if dot_count > 1:
				return false
		elif c < "0" or c > "9":
			return false
		else:
			digit_count += 1
	if digit_count == 0:
		return false
	return float(text) > 0.0


func _format_measure(value) -> String:
	var number := float(value)
	var text := "%.2f" % number
	while text.ends_with("0"):
		text = text.left(text.length() - 1)
	if text.ends_with("."):
		text = text.left(text.length() - 1)
	return text


func _growth_measure_text(data: Dictionary) -> String:
	var parts: Array = []
	if data.has("height_cm"):
		parts.append("身高 %s cm" % _format_measure(data.get("height_cm", "")))
	if data.has("weight_kg"):
		parts.append("体重 %s kg" % _format_measure(data.get("weight_kg", "")))
	return "\n".join(parts)


func _date_options(selected_date: String) -> Array:
	var options: Array = []
	var today_value := store.today() if store != null else _system_today()
	var today_day := _date_to_day_number(today_value)
	var selected_added: bool = false
	var offsets: Array = [0, -1, -2, -3, -4, -5, -6, -7]
	for offset in range(-8, -61, -1):
		offsets.append(offset)
	for offset in range(1, 8):
		offsets.append(offset)
	for raw_offset in offsets:
		var offset: int = int(raw_offset)
		var value: String = _date_from_day_number(today_day + offset)
		var label: String = value
		if offset == 0:
			label += "  今天"
		elif offset == -1:
			label += "  昨天"
		elif offset == 1:
			label += "  明天"
		if value == selected_date:
			selected_added = true
		options.append({"label": label, "value": value})
	if not selected_added and _looks_like_date(selected_date):
		options.push_front({"label": selected_date, "value": selected_date})
	return options


func _system_today() -> String:
	var d: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


func _date_to_day_number(date: String) -> int:
	var parts := date.split("-")
	if parts.size() != 3:
		return 0
	var y := int(parts[0])
	var m := int(parts[1])
	var d := int(parts[2])
	if m <= 2:
		y -= 1
		m += 12
	var era := int(floor(float(y) / 400.0))
	var yoe := y - era * 400
	var doy := int((153 * (m - 3) + 2) / 5) + d - 1
	var doe := yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
	return era * 146097 + doe - 719468


func _date_from_day_number(day_number: int) -> String:
	var z := day_number + 719468
	var era := int(floor(float(z) / 146097.0))
	var doe := z - era * 146097
	var yoe := int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
	var y := yoe + era * 400
	var doy := doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
	var mp := int((5 * doy + 2) / 153)
	var d := doy - int((153 * mp + 2) / 5) + 1
	var m := mp + 3 if mp < 10 else mp - 9
	y += 1 if m <= 2 else 0
	return "%04d-%02d-%02d" % [y, m, d]


func _parse_time(value: String) -> PackedInt32Array:
	var parts := value.split(":")
	if parts.size() != 2:
		var now := _now_time().split(":")
		return PackedInt32Array([int(now[0]), _snap_minute(int(now[1]))])
	return PackedInt32Array([clampi(int(parts[0]), 0, 23), _snap_minute(int(parts[1]))])


func _snap_minute(value: int) -> int:
	return clampi(int(round(float(value) / 5.0)) * 5, 0, 55)


func _hour_options() -> Array:
	var options: Array = []
	for hour in range(24):
		options.append({"label": "%02d 时" % hour, "value": "%02d" % hour})
	return options


func _minute_options() -> Array:
	var options: Array = []
	for minute in range(0, 60, 5):
		options.append({"label": "%02d 分" % minute, "value": "%02d" % minute})
	return options


func _now_time() -> String:
	var d: Dictionary = Time.get_datetime_dict_from_system()
	return "%02d:%02d" % [d["hour"], d["minute"]]


func _install_readable_theme() -> void:
	var readable_theme := Theme.new()
	readable_theme.default_font_size = 18
	for type_name in ["Label", "Button", "OptionButton", "LineEdit", "TextEdit", "ProgressBar"]:
		readable_theme.set_color("font_color", type_name, TEXT_COLOR)
	for type_name in ["Button", "OptionButton"]:
		readable_theme.set_color("font_hover_color", type_name, TEXT_COLOR)
		readable_theme.set_color("font_pressed_color", type_name, TEXT_COLOR)
		readable_theme.set_color("font_focus_color", type_name, TEXT_COLOR)
		readable_theme.set_color("font_disabled_color", type_name, MUTED_TEXT_COLOR)
	for type_name in ["LineEdit", "TextEdit"]:
		readable_theme.set_color("font_placeholder_color", type_name, MUTED_TEXT_COLOR)
		readable_theme.set_color("font_readonly_color", type_name, MUTED_TEXT_COLOR)
	for type_name in ["Button", "OptionButton", "LineEdit", "TextEdit"]:
		readable_theme.set_stylebox("normal", type_name, _control_style(Color("#ffffff")))
		readable_theme.set_stylebox("focus", type_name, _control_style(Color("#ffffff"), Color("#d8b8a1")))
		if type_name in ["Button", "OptionButton"]:
			readable_theme.set_stylebox("hover", type_name, _control_style(Color("#fffaf6"), Color("#e2c5ad")))
			readable_theme.set_stylebox("pressed", type_name, _control_style(Color("#fff1e8"), Color("#d8b8a1")))
		if type_name == "LineEdit":
			readable_theme.set_stylebox("read_only", type_name, _control_style(Color("#ffffff")))
	theme = readable_theme


func _control_style(bg_color: Color, border_color := Color("#ead2bf")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.set_content_margin(SIDE_LEFT, 12)
	style.set_content_margin(SIDE_RIGHT, 12)
	style.set_content_margin(SIDE_TOP, 8)
	style.set_content_margin(SIDE_BOTTOM, 8)
	return style


func _record_hint(kind: String) -> String:
	match kind:
		"feeding":
			return "母乳/配方奶、时间、奶量和备注"
		"diaper":
			return "小便或大便，记录量、性状和颜色"
		"exercise":
			return "按摩、大动作、认知、语言和游戏"
		"hygiene":
			return "洗脸、洗澡、游泳"
		"supplement":
			return "AD、D3、DHA、益生菌等"
		"growth":
			return "记录身高和体重"
		_:
			return ""


func _detail_text(record: Dictionary) -> String:
	var data: Dictionary = record.get("data", {})
	match str(record.get("kind", "")):
		"feeding":
			return "%s-%s，备注：%s" % [data.get("start_time", ""), data.get("end_time", ""), data.get("note", "无")]
		"diaper":
			if data.get("diaper_type", "") == "小便":
				return "尿量：%s" % data.get("pee_amount", "")
			return "性状：%s，颜色：%s，量：%s，备注：%s" % [data.get("poop_texture", ""), data.get("poop_color", ""), data.get("poop_amount", ""), data.get("note", "无")]
		"exercise":
			return data.get("category", "")
		"hygiene":
			return "卫生护理"
		"supplement":
			return "补充剂/饮水"
		"growth":
			return _growth_measure_text(data).replace("\n", "，")
		_:
			return ""
