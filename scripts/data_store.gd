extends Node
class_name BlueberryDataStore

const SAVE_PATH := "user://blueberry_daily_records.json"
const META_PATH := "user://blueberry_daily_meta.json"

var records: Array = []
var last_sync_at := 0

func _init() -> void:
	load_records()
	load_meta()


func load_records() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		records = []
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		records = []
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	records = parsed if typeof(parsed) == TYPE_ARRAY else []


func save_records() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(records, "\t", false))


func load_meta() -> void:
	if not FileAccess.file_exists(META_PATH):
		last_sync_at = 0
		return
	var file := FileAccess.open(META_PATH, FileAccess.READ)
	if file == null:
		last_sync_at = 0
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		last_sync_at = int(parsed.get("last_sync_at", 0))


func save_meta() -> void:
	var file := FileAccess.open(META_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"last_sync_at": last_sync_at}, "\t", false))


func add_record(record: Dictionary) -> Dictionary:
	record["id"] = _new_id()
	record["created_at"] = Time.get_datetime_string_from_system()
	record["updated_at"] = record["created_at"]
	record["created_at_ms"] = _now_ms()
	record["updated_at_ms"] = record["created_at_ms"]
	record["deleted"] = false
	records.append(record)
	save_records()
	return record


func update_record(id: String, record: Dictionary) -> bool:
	for i in range(records.size()):
		if str(records[i].get("id", "")) == id:
			record["id"] = id
			record["created_at"] = records[i].get("created_at", Time.get_datetime_string_from_system())
			record["created_at_ms"] = int(records[i].get("created_at_ms", _now_ms()))
			record["updated_at"] = Time.get_datetime_string_from_system()
			record["updated_at_ms"] = _now_ms()
			record["deleted"] = false
			records[i] = record
			save_records()
			return true
	return false


func delete_record(id: String) -> bool:
	for i in range(records.size()):
		if str(records[i].get("id", "")) == id:
			records[i]["deleted"] = true
			records[i]["updated_at"] = Time.get_datetime_string_from_system()
			records[i]["updated_at_ms"] = _now_ms()
			records[i]["local_only_delete"] = true
			save_records()
			return true
	return false


func merge_remote_records(remote_records: Array) -> int:
	var changed := 0
	for remote in remote_records:
		if not (remote is Dictionary):
			continue
		var local_record := _record_from_remote(remote)
		if local_record.is_empty():
			continue
		if _add_if_missing(local_record):
			changed += 1
	if changed > 0:
		save_records()
	return changed


func sync_payload(since: int = 0) -> Array:
	var payload: Array = []
	for record in records:
		if not bool(record.get("deleted", false)) and not bool(record.get("synced", false)):
			payload.append(_record_to_remote(record))
	return payload


func mark_uploaded(record_ids: Array) -> void:
	var changed := false
	for record in records:
		if record_ids.has(str(record.get("id", ""))):
			record["synced"] = true
			changed = true
	if changed:
		save_records()


func set_last_sync_at(value: int) -> void:
	last_sync_at = max(last_sync_at, value)
	save_meta()


func records_for_date(date: String) -> Array:
	var result: Array = []
	for record in records:
		if not bool(record.get("deleted", false)) and str(record.get("date", "")) == date:
			result.append(record)
	result.sort_custom(func(a, b): return _record_time(a) < _record_time(b))
	return result


func records_between(start_date: String, end_date: String) -> Array:
	var result: Array = []
	for record in records:
		var date := str(record.get("date", ""))
		if not bool(record.get("deleted", false)) and date >= start_date and date <= end_date:
			result.append(record)
	result.sort_custom(func(a, b):
		if str(a.get("date", "")) == str(b.get("date", "")):
			return _record_time(a) < _record_time(b)
		return str(a.get("date", "")) < str(b.get("date", ""))
	)
	return result


func summarize(record_list: Array) -> Dictionary:
	var summary := {
		"total": record_list.size(),
		"feeding": 0,
		"diaper": 0,
		"exercise": 0,
		"hygiene": 0,
		"supplement": 0,
		"growth": 0,
		"milk_ml": 0,
		"pee": 0,
		"poop": 0
	}
	for record in record_list:
		var kind := str(record.get("kind", ""))
		if summary.has(kind):
			summary[kind] += 1
		var data: Dictionary = record.get("data", {})
		if kind == "feeding":
			summary["milk_ml"] += int(data.get("milk_ml", 0))
		if kind == "diaper":
			if str(data.get("diaper_type", "")) == "小便":
				summary["pee"] += 1
			if str(data.get("diaper_type", "")) == "大便":
				summary["poop"] += 1
	return summary


func week_bounds(date: String) -> PackedStringArray:
	var day_number := _date_to_day_number(date)
	if day_number < 0:
		return PackedStringArray([date, date])
	var weekday: int = int((day_number + 3) % 7)
	var days_from_monday: int = weekday
	var start_day := day_number - days_from_monday
	return PackedStringArray([_date_from_day_number(start_day), _date_from_day_number(start_day + 6)])


func today() -> String:
	var d: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


func display_title(record: Dictionary) -> String:
	var data: Dictionary = record.get("data", {})
	match str(record.get("kind", "")):
		"feeding":
			return "喂养 · %s · %sml" % [data.get("feeding_type", ""), data.get("milk_ml", "0")]
		"diaper":
			return "尿布 · %s" % data.get("diaper_type", "")
		"exercise":
			return "锻炼 · %s · %s" % [data.get("category", ""), data.get("item", "")]
		"hygiene":
			return "卫生 · %s" % data.get("item", "")
		"supplement":
			return "补充剂 · %s" % data.get("item", "")
		"growth":
			return "身高体重 · %s" % _growth_display(data)
		_:
			return "记录"


func display_time(record: Dictionary) -> String:
	var data: Dictionary = record.get("data", {})
	if str(record.get("kind", "")) == "growth":
		return "测量"
	if data.has("start_time"):
		return str(data.get("start_time", ""))
	return str(data.get("time", ""))


func _record_time(record: Dictionary) -> String:
	var data: Dictionary = record.get("data", {})
	return str(data.get("start_time", data.get("time", "00:00")))


func _growth_display(data: Dictionary) -> String:
	var parts: Array = []
	if data.has("height_cm"):
		parts.append("%scm" % data.get("height_cm", ""))
	if data.has("weight_kg"):
		parts.append("%skg" % data.get("weight_kg", ""))
	return " · ".join(parts)


func _new_id() -> String:
	return "%s-%s" % [Time.get_unix_time_from_system(), randi()]


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _add_if_missing(incoming: Dictionary) -> bool:
	var incoming_id := str(incoming.get("id", ""))
	if incoming_id == "":
		return false
	for i in range(records.size()):
		if str(records[i].get("id", "")) == incoming_id:
			return false
	incoming["synced"] = true
	records.append(incoming)
	return true


func _record_to_remote(record: Dictionary) -> Dictionary:
	return {
		"record_id": str(record.get("id", "")),
		"kind": str(record.get("kind", "")),
		"date": str(record.get("date", "")),
		"data": record.get("data", {}),
		"deleted": false,
		"created_at": int(record.get("created_at_ms", _now_ms())),
		"updated_at": int(record.get("updated_at_ms", _now_ms())),
		"updated_by": "godot_app"
	}


func _record_from_remote(remote: Dictionary) -> Dictionary:
	var record_id := str(remote.get("record_id", remote.get("id", "")))
	if record_id == "":
		return {}
	var record := {
		"id": record_id,
		"kind": str(remote.get("kind", "")),
		"date": str(remote.get("date", "")),
		"data": remote.get("data", {}),
		"deleted": bool(remote.get("deleted", false)),
		"created_at": Time.get_datetime_string_from_unix_time(float(remote.get("created_at", _now_ms())) / 1000.0),
		"updated_at": Time.get_datetime_string_from_unix_time(float(remote.get("updated_at", _now_ms())) / 1000.0),
		"created_at_ms": int(remote.get("created_at", _now_ms())),
		"updated_at_ms": int(remote.get("updated_at", _now_ms()))
	}
	record["synced"] = true
	return record


func _date_to_day_number(date: String) -> int:
	var parts := date.split("-")
	if parts.size() != 3:
		return -1
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
