extends Node
class_name BlueberrySyncService

const SYNC_URL := "https://crescents720-d2gwxjftkfbd3035d-1433723768.ap-shanghai.app.tcloudbase.com/blueberrySync"
const APP_SECRET := "xiaolanmei-family-2026"

var _request: HTTPRequest


func _ready() -> void:
	_request = HTTPRequest.new()
	add_child(_request)
	_request.timeout = 15.0


func ping() -> Dictionary:
	var result: Dictionary = await _post({"action": "ping"})
	return result


func sync_records(records: Array, since: int, cursor: String = "") -> Dictionary:
	var result: Dictionary = await _post({
		"action": "sync",
		"records": records,
		"since": since,
		"cursor": cursor
	})
	return result


func _post(payload: Dictionary) -> Dictionary:
	payload["secret"] = APP_SECRET
	var body := JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := _request.request(SYNC_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		return {"ok": false, "error": "无法发起同步请求：%s" % err}

	var result: Array = await _request.request_completed
	var request_result: int = int(result[0])
	var response_code: int = int(result[1])
	var response_body: PackedByteArray = result[3]
	var text := response_body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if request_result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "网络请求失败：%s（%s）" % [_request_result_name(request_result), request_result]}
	if response_code < 200 or response_code >= 300:
		var detail := text if text.strip_edges() != "" else "空响应，可能是云函数超时或网关中断"
		return {"ok": false, "error": "云端返回 %s：%s" % [response_code, detail]}
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "云端响应不是有效 JSON：%s" % text}
	return parsed


func _request_result_name(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "响应数据不完整"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "无法连接服务器"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "无法解析域名"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "连接中断"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS/证书握手失败"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "服务器无响应"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "响应过大"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "响应解压失败"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "请求失败"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "无法打开下载文件"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "无法写入下载文件"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "重定向过多"
		HTTPRequest.RESULT_TIMEOUT:
			return "请求超时"
		_:
			return "未知错误"
