extends Node

var current_scene: Node = null

func _ready() -> void:
	var root = get_tree().root
	current_scene = root.get_child(root.get_child_count() - 1)

func switch_scene(scene_path: String) -> void:
	call_deferred("_deferred_switch_scene", scene_path)

func _deferred_switch_scene(scene_path: String) -> void:
	if current_scene:
		current_scene.free()
	var new_scene_resource = load(scene_path)
	if new_scene_resource:
		current_scene = new_scene_resource.instantiate()
		get_tree().root.add_child(current_scene)
		get_tree().current_scene = current_scene
		_bind_scene_signals()

func _bind_scene_signals() -> void:
	if current_scene.has_signal("play_pressed"):
		current_scene.connect("play_pressed", _on_play_requested)
	if current_scene.has_signal("shop_pressed"):
		current_scene.connect("shop_pressed", _on_shop_requested)
	if current_scene.has_signal("inventory_pressed"):
		current_scene.connect("inventory_pressed", _on_inventory_requested)
	if current_scene.has_signal("back_pressed"):
		current_scene.connect("back_pressed", _on_back_requested)

func _on_play_requested() -> void:
	switch_scene("res://scenes/gameplay/gameplay.tscn")

func _on_shop_requested() -> void:
	switch_scene("res://scenes/shop/shop.tscn")

func _on_inventory_requested() -> void:
	switch_scene("res://scenes/inventory/inventory.tscn")

func _on_back_requested() -> void:
	switch_scene("res://scenes/main_menu/main_menu.tscn")
 
