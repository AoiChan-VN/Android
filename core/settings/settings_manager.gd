extends Node

var settings := GameSettings.new()

func _ready():
	load_settings()

func load_settings():
	var config := ConfigFile.new()

	if config.load(SaveManager.SETTINGS_FILE) != OK:
		save_settings()
		return

	settings.graphics_quality = config.get_value("graphics", "quality", 2)
	settings.fps_limit = config.get_value("graphics", "fps", 60)

	settings.master_volume = config.get_value("audio", "master", 1.0)
	settings.music_volume = config.get_value("audio", "music", 1.0)
	settings.sfx_volume = config.get_value("audio", "sfx", 1.0)
	settings.voice_volume = config.get_value("audio", "voice", 1.0)

	settings.gyro_enabled = config.get_value("controls", "gyro", false)
	settings.invert_y = config.get_value("controls", "invert_y", false)
	settings.aim_assist = config.get_value("controls", "aim_assist", true)
	settings.auto_pickup = config.get_value("controls", "auto_pickup", true)
	settings.auto_open_door = config.get_value("controls", "auto_open_door", true)

func save_settings():
	var config := ConfigFile.new()

	config.set_value("graphics", "quality", settings.graphics_quality)
	config.set_value("graphics", "fps", settings.fps_limit)

	config.set_value("audio", "master", settings.master_volume)
	config.set_value("audio", "music", settings.music_volume)
	config.set_value("audio", "sfx", settings.sfx_volume)
	config.set_value("audio", "voice", settings.voice_volume)

	config.set_value("controls", "gyro", settings.gyro_enabled)
	config.set_value("controls", "invert_y", settings.invert_y)
	config.set_value("controls", "aim_assist", settings.aim_assist)
	config.set_value("controls", "auto_pickup", settings.auto_pickup)
	config.set_value("controls", "auto_open_door", settings.auto_open_door)

	config.save(SaveManager.SETTINGS_FILE)

	EventBus.settings_changed.emit() 
