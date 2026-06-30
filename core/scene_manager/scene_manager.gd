extends Node

var current_scene: Node

func load_scene(path: String):
	call_deferred("_load_scene", path)

func _load_scene(path: String):
	if current_scene:
		current_scene.queue_free()

	var scene := load(path).instantiate()

	get_tree().root.add_child(scene)
	current_scene = scene

	EventBus.scene_loaded.emit(path) 
