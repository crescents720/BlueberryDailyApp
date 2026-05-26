extends Control
class_name BlueberryAnalysisChart

const TEXT_COLOR := Color("#493f45")
const MUTED_TEXT_COLOR := Color("#6f6b73")
const GRID_COLOR := Color("#eadfd5")
const MILK_COLOR := Color("#8aa7e6")
const FEED_POINT_COLOR := Color("#d986a8")
const PEE_COLOR := Color("#74b9c9")
const POOP_COLOR := Color("#d58a55")

var mode := "feeding"
var dates: Array = []
var feeding_totals: Array = []
var feeding_times: Array = []
var diaper_points: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(0, 420)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_feeding_data(date_values: Array, totals: Array, times: Array) -> void:
	mode = "feeding"
	dates = date_values
	feeding_totals = totals
	feeding_times = times
	diaper_points = []
	queue_redraw()


func set_diaper_data(date_values: Array, points: Array) -> void:
	mode = "diaper"
	dates = date_values
	feeding_totals = []
	feeding_times = []
	diaper_points = points
	queue_redraw()


func _draw() -> void:
	if dates.is_empty():
		_draw_empty()
		return
	var rect := Rect2(Vector2(48, 24), size - Vector2(86, 84))
	if rect.size.x <= 10 or rect.size.y <= 10:
		return
	_draw_grid(rect)
	if mode == "feeding":
		_draw_feeding(rect)
	else:
		_draw_diaper(rect)
	_draw_dates(rect)


func _draw_empty() -> void:
	var font := get_theme_default_font()
	draw_string(font, Vector2(24, 80), "这段时间还没有可展示的数据", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MUTED_TEXT_COLOR)


func _draw_grid(rect: Rect2) -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(rect.position, rect.size), Color("#fffaf6"), true)
	draw_rect(Rect2(rect.position, rect.size), GRID_COLOR, false, 1.0)
	for i in range(5):
		var ratio := float(i) / 4.0
		var y := rect.position.y + rect.size.y * ratio
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), GRID_COLOR, 1.0)
		var hour := int(round((1.0 - ratio) * 24.0))
		draw_string(font, Vector2(rect.end.x + 6, y + 5), "%02d:00" % hour, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED_TEXT_COLOR)
	draw_string(font, Vector2(rect.end.x - 34, rect.position.y - 7), "时间", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED_TEXT_COLOR)


func _draw_feeding(rect: Rect2) -> void:
	var font := get_theme_default_font()
	var max_milk := 100
	for value in feeding_totals:
		max_milk = max(max_milk, int(value))
	max_milk = int(ceil(float(max_milk) / 100.0) * 100.0)

	for i in range(5):
		var ratio := float(i) / 4.0
		var y := rect.position.y + rect.size.y * ratio
		var label_value := int(round((1.0 - ratio) * max_milk))
		draw_string(font, Vector2(4, y + 5), "%s" % label_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED_TEXT_COLOR)
	draw_string(font, Vector2(4, rect.position.y - 7), "ml", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED_TEXT_COLOR)

	var step := rect.size.x / max(1, dates.size())
	var bar_width := clamp(step * 0.48, 8.0, 28.0)
	for i in range(dates.size()):
		var center_x := rect.position.x + step * (i + 0.5)
		var total := float(feeding_totals[i])
		var bar_h := rect.size.y * total / float(max_milk)
		var bar_rect := Rect2(Vector2(center_x - bar_width / 2.0, rect.end.y - bar_h), Vector2(bar_width, bar_h))
		draw_rect(bar_rect, MILK_COLOR, true)
		for minute in feeding_times[i]:
			var y := _time_to_y(rect, int(minute))
			draw_circle(Vector2(center_x, y), 4.0, FEED_POINT_COLOR)

	_draw_legend([
		{"label": "每日累计奶量", "color": MILK_COLOR},
		{"label": "喂奶时间点", "color": FEED_POINT_COLOR}
	])


func _draw_diaper(rect: Rect2) -> void:
	var step := rect.size.x / max(1, dates.size())
	for point in diaper_points:
		var day_index := int(point.get("day_index", 0))
		var minute := int(point.get("minute", 0))
		var amount := str(point.get("amount", "中"))
		var diaper_type := str(point.get("type", "小便"))
		var radius := 5.0
		if amount == "大":
			radius = 8.0
		elif amount == "小":
			radius = 4.0
		var x := rect.position.x + step * (day_index + 0.5)
		var y := _time_to_y(rect, minute)
		draw_circle(Vector2(x, y), radius, POOP_COLOR if diaper_type == "大便" else PEE_COLOR)

	_draw_legend([
		{"label": "小便", "color": PEE_COLOR},
		{"label": "大便", "color": POOP_COLOR},
		{"label": "圆点大小=量", "color": MUTED_TEXT_COLOR}
	])


func _draw_dates(rect: Rect2) -> void:
	var font := get_theme_default_font()
	var step := rect.size.x / max(1, dates.size())
	var skip := max(1, int(ceil(float(dates.size()) / 7.0)))
	for i in range(dates.size()):
		if i % skip != 0 and i != dates.size() - 1:
			continue
		var x := rect.position.x + step * (i + 0.5)
		var label := _short_date(str(dates[i]))
		draw_string(font, Vector2(x - 20, rect.end.y + 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED_TEXT_COLOR)


func _draw_legend(items: Array) -> void:
	var font := get_theme_default_font()
	var x := 48.0
	var y := size.y - 22.0
	for item in items:
		var color: Color = item["color"]
		draw_circle(Vector2(x, y - 4), 5.0, color)
		draw_string(font, Vector2(x + 9, y), str(item["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MUTED_TEXT_COLOR)
		x += 108.0


func _time_to_y(rect: Rect2, minute: int) -> float:
	return rect.end.y - rect.size.y * clamp(float(minute) / 1440.0, 0.0, 1.0)


func _short_date(value: String) -> String:
	var parts := value.split("-")
	if parts.size() == 3:
		return "%s/%s" % [parts[1], parts[2]]
	return value
