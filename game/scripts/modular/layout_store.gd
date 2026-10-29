extends RefCounted
const Layout = preload("res://scripts/modular/modular_layout.gd")
static func load_layout(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {"ok":false,"error":"布局存档不存在","manifest":{}}
	var parser := JSON.new()
	var parse_error := parser.parse(FileAccess.get_file_as_string(path))
	var parsed: Variant = parser.data if parse_error==OK else null
	if not parsed is Dictionary:return {"ok":false,"error":"布局存档损坏，已保留原文件","manifest":{}}
	var reason := Layout.validate(parsed)
	return {"ok":reason.is_empty(),"error":reason,"manifest":parsed if reason.is_empty() else {}}
static func save_layout(path: String, manifest: Dictionary) -> String:
	var reason := Layout.validate(manifest)
	if not reason.is_empty():return reason
	var pending := path+".tmp"
	var file := FileAccess.open(pending,FileAccess.WRITE)
	if file==null:return "无法写入布局临时文件"
	file.store_string(JSON.stringify(manifest,"\t"));file.flush()
	var error := file.get_error();file.close()
	if error!=OK:return "布局写入失败"
	var reloaded := load_layout(pending)
	if not reloaded.ok or reloaded.manifest!=JSON.parse_string(JSON.stringify(manifest)):return "布局回读校验失败"
	error=DirAccess.rename_absolute(ProjectSettings.globalize_path(pending),ProjectSettings.globalize_path(path))
	return "" if error==OK else "布局原子替换失败"
