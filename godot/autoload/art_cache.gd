extends Node
## Art — world key-art: generated once through the ComfyUI bridge, cached in
## user://art/<world_id>.png, painted onto menu cards and the game backdrop.

signal art_ready(world_id: String)

const WORLD_PROMPTS := {
	"embervale": "a candlelit fantasy valley village at dusk, timber inn glowing warm, misty hills, cinematic high fantasy establishing shot, no people, no text",
	"neonspire": "a rain-slick cyberpunk megacity street at night, neon cyan and magenta signs, towering spire, cinematic sci-fi establishing shot, no people, no text",
	"everyday": "a cozy corner cafe on a quiet city street at golden hour, warm window light, bicycles, slice of life illustration, no people, no text",
}

var _generating := {}


func path_for(world_id: String) -> String:
	return "user://art/%s.png" % world_id.validate_filename()


func has_art(world_id: String) -> bool:
	return world_id != "" and FileAccess.file_exists(path_for(world_id))


func texture_for(world_id: String) -> ImageTexture:
	if not has_art(world_id):
		return null
	var img := Image.load_from_file(path_for(world_id))
	return ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null


## Generate + cache key art if missing (one in flight per world). Emits
## art_ready(world_id) on success. `prompt` falls back to the built-in look.
func ensure(world_id: String, prompt := "") -> void:
	if world_id == "" or has_art(world_id) or _generating.get(world_id, false):
		return
	if prompt == "":
		prompt = WORLD_PROMPTS.get(world_id, "")
	if prompt == "":
		return
	_generating[world_id] = true
	var r := await Api.call_json(HTTPClient.METHOD_POST, "/api/characters/studio/generate",
		{"prompt": prompt + ", atmospheric establishing scene, no people, no text", "size": "1024x1024"})
	_generating[world_id] = false
	if r.get("_status", 0) != 200 or str(r.get("image_url", "")) == "":
		return
	var bytes := await Api.fetch_bytes(str(r["image_url"]).trim_prefix(Api.BASE))
	if bytes.is_empty():
		return
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK and img.load_jpg_from_buffer(bytes) != OK:
		return
	DirAccess.make_dir_recursive_absolute("user://art")
	img.save_png(path_for(world_id))
	art_ready.emit(world_id)
