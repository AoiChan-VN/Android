extends Node

const SAVE_DIR := "user://save/"
const SETTINGS_FILE := "user://save/settings.cfg"

func _ready():
	if !DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR) 
