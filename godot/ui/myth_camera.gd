class_name MythCamera extends RefCounted
## MDL: the pan/zoom camera every map-like surface shares (living map,
## destiny constellation, future minimap). Wheel zooms toward the cursor,
## drag pans, edges stay clamped. Feed events through handle(); use
## to_map() for hit-testing and drag_moved to tell a pan from a click.

var zoom := 1.0
var cam := Vector2.ZERO
var min_zoom := 1.0
var max_zoom := 2.6
var drag_moved := false
var _dragging := false


func to_map(p: Vector2) -> Vector2:
	return (p - cam) / zoom


func to_screen(p: Vector2) -> Vector2:
	return p * zoom + cam


func clamp_cam(size: Vector2) -> void:
	cam.x = clampf(cam.x, size.x * (1.0 - zoom), 0.0)
	cam.y = clampf(cam.y, size.y * (1.0 - zoom), 0.0)


func zoom_at(at: Vector2, factor: float, size: Vector2) -> void:
	var before := to_map(at)
	zoom = clampf(zoom * factor, min_zoom, max_zoom)
	cam = at - before * zoom
	clamp_cam(size)


## Feed every gui_input event. → true when consumed (the surface should
## just queue_redraw and stop); false means hover/click handling may run.
func handle(event: InputEvent, ctrl: Control) -> bool:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_at(event.position, 1.15, ctrl.size)
			ctrl.queue_redraw()
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_at(event.position, 1.0 / 1.15, ctrl.size)
			ctrl.queue_redraw()
			return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				drag_moved = false
			return false
	elif event is InputEventMouseMotion and _dragging and zoom > 1.001:
		cam += event.relative
		drag_moved = drag_moved or event.relative.length() > 2.0
		clamp_cam(ctrl.size)
		ctrl.queue_redraw()
		return true
	return false
