class_name Localization
extends Node

signal localization_started
signal localization_ready
signal localization_paused
signal localization_resumed
signal localization_stopping
signal localization_stopped
signal localization_failed(reason: String)

signal locale_changing(
	from_locale: String,
	to_locale: String
)

signal locale_changed(
	locale: String
)

signal translation_registered(
	locale: String
)

signal translation_unregistered(
	locale: String
)

enum State {
	IDLE,
	STARTING,
	READY,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

const EXPECTED_NODE_NAME: StringName = &"Localization"

@export_group("Localization")
@export var auto_start: bool = true
@export var auto_detect_locale: bool = true
@export var auto_use_fallback: bool = true
@export var clear_on_stop: bool = false
@export var console_output: bool = true

@export_group("Locale")
@export var default_locale: String = "en"
@export var fallback_locale: String = "en"
@export var startup_locale: String = ""

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var localization_error: String = ""

var _translations: Dictionary = {}
var _locale_order: Array[String] = []
var _current_locale: String = ""


func _enter_tree() -> void:
	state = State.STARTING


func _ready() -> void:
	if auto_start:
		start()


func _exit_tree() -> void:
	_shutdown()


func start() -> bool:
	if state == State.READY:
		return true

	if state == State.PAUSED:
		return resume()

	if state == State.STOPPING:
		return false

	if state == State.FAILED or state == State.STOPPED:
		state = State.IDLE
		localization_error = ""

	if validate_root and not _validate_root():
		return _fail(localization_error)

	if not _validate_locales():
		return _fail(localization_error)

	state = State.STARTING

	localization_started.emit()

	var initial_locale: String = startup_locale

	if initial_locale.is_empty():
		if auto_detect_locale:
			initial_locale = OS.get_locale()
		else:
			initial_locale = default_locale

	if not set_locale(
		initial_locale,
		auto_use_fallback
	):
		if not set_locale(
			default_locale,
			auto_use_fallback
		):
			return _fail(
				"Không thể thiết lập Locale khởi động"
			)

	state = State.READY

	localization_ready.emit()

	_log(
		"Localization Ready: "
		+ _current_locale
	)

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED

	localization_paused.emit()

	_log("Localization Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY

	localization_resumed.emit()

	_log("Localization Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func register_translation(
	translation: Translation,
	replace_existing: bool = false
) -> bool:
	if not _is_operational():
		return false

	if translation == null:
		_set_error(
			"Translation không hợp lệ"
		)
		return false

	var locale: String = (
		TranslationServer.standardize_locale(
			translation.get_locale(),
			true
		)
	)

	if locale.is_empty():
		_set_error(
			"Translation Locale không hợp lệ"
		)
		return false

	if _translations.has(locale):
		if not replace_existing:
			_set_error(
				"Translation Locale đã tồn tại: "
				+ locale
			)
			return false

		var previous: Translation = (
			_translations[locale]
		)

		if previous != null:
			TranslationServer.remove_translation(
				previous
			)

		_translations.erase(locale)
		_locale_order.erase(locale)

	translation.set_locale(locale)

	TranslationServer.add_translation(
		translation
	)

	_translations[locale] = translation
	_locale_order.append(locale)

	translation_registered.emit(
		locale
	)

	_log(
		"Translation Registered: "
		+ locale
	)

	return true


func unregister_translation(
	locale: String
) -> bool:
	var normalized_locale: String = (
		_standardize_locale(locale)
	)

	if normalized_locale.is_empty():
		return false

	if not _translations.has(
		normalized_locale
	):
		return false

	var translation: Translation = (
		_translations[normalized_locale]
	)

	if translation != null:
		TranslationServer.remove_translation(
			translation
		)

	_translations.erase(
		normalized_locale
	)

	_locale_order.erase(
		normalized_locale
	)

	translation_unregistered.emit(
		normalized_locale
	)

	_log(
		"Translation Unregistered: "
		+ normalized_locale
	)

	return true


func register_messages(
	locale: String,
	messages: Dictionary,
	replace_existing: bool = false
) -> bool:
	if not _is_operational():
		return false

	var normalized_locale: String = (
		_standardize_locale(locale)
	)

	if normalized_locale.is_empty():
		return false

	if messages.is_empty():
		_set_error(
			"Translation Messages không được rỗng"
		)
		return false

	var translation := Translation.new()

	translation.set_locale(
		normalized_locale
	)

	for message_id in messages.keys():
		var source_message: StringName = (
			StringName(
				str(message_id)
			)
		)

		var translated_message: StringName = (
			StringName(
				str(messages[message_id])
			)
		)

		if source_message.is_empty():
			continue

		translation.add_message(
			source_message,
			translated_message
		)

	return register_translation(
		translation,
		replace_existing
	)


func register_plural_messages(
	locale: String,
	messages: Dictionary,
	replace_existing: bool = false
) -> bool:
	if not _is_operational():
		return false

	var normalized_locale: String = (
		_standardize_locale(locale)
	)

	if normalized_locale.is_empty():
		return false

	if messages.is_empty():
		_set_error(
			"Plural Messages không được rỗng"
		)
		return false

	var translation := Translation.new()

	translation.set_locale(
		normalized_locale
	)

	for message_id in messages.keys():
		var source_message: StringName = (
			StringName(
				str(message_id)
			)
		)

		var plural_data: Variant = (
			messages[message_id]
		)

		if source_message.is_empty():
			continue

		if not plural_data is Array:
			continue

		var plural_messages: PackedStringArray = []

		for item in plural_data:
			plural_messages.append(
				str(item)
			)

		if plural_messages.is_empty():
			continue

		translation.add_plural_message(
			source_message,
			plural_messages
		)

	return register_translation(
		translation,
		replace_existing
	)


func translate(
	message: StringName,
	context: StringName = &""
) -> String:
	if not _is_operational():
		return String(message)

	return String(
		TranslationServer.translate(
			message,
			context
		)
	)


func translate_text(
	message: String,
	context: String = ""
) -> String:
	return translate(
		StringName(message),
		StringName(context)
	)


func translate_plural(
	message: StringName,
	plural_message: StringName,
	count: int,
	context: StringName = &""
) -> String:
	if not _is_operational():
		if count == 1:
			return String(message)

		return String(plural_message)

	return String(
		TranslationServer.translate_plural(
			message,
			plural_message,
			count,
			context
		)
	)


func translate_plural_text(
	message: String,
	plural_message: String,
	count: int,
	context: String = ""
) -> String:
	return translate_plural(
		StringName(message),
		StringName(plural_message),
		count,
		StringName(context)
	)


func set_locale(
	locale: String,
	use_fallback: bool = true
) -> bool:
	if not _is_operational() and state != State.STARTING:
		return false

	var requested_locale: String = (
		_standardize_locale(locale)
	)

	if requested_locale.is_empty():
		_set_error(
			"Locale không được để trống"
		)
		return false

	var target_locale: String = (
		_find_available_locale(
			requested_locale,
			use_fallback
		)
	)

	if target_locale.is_empty():
		_set_error(
			"Không tìm thấy Translation cho Locale: "
			+ requested_locale
		)
		return false

	var previous_locale: String = _current_locale

	if previous_locale == target_locale:
		TranslationServer.set_locale(
			target_locale
		)
		return true

	locale_changing.emit(
		previous_locale,
		target_locale
	)

	TranslationServer.set_locale(
		target_locale
	)

	_current_locale = (
		TranslationServer.get_locale()
	)

	locale_changed.emit(
		_current_locale
	)

	_log(
		"Locale Changed: "
		+ _current_locale
	)

	return true


func get_locale() -> String:
	if not _current_locale.is_empty():
		return _current_locale

	return TranslationServer.get_locale()


func get_available_locales() -> Array[String]:
	var result: Array[String] = []

	for locale in _locale_order:
		if _translations.has(locale):
			result.append(locale)

	return result


func has_locale(
	locale: String,
	exact: bool = false
) -> bool:
	var normalized_locale: String = (
		_standardize_locale(locale)
	)

	if normalized_locale.is_empty():
		return false

	if exact:
		return _translations.has(
			normalized_locale
		)

	for available_locale in _locale_order:
		if TranslationServer.compare_locales(
			available_locale,
			normalized_locale
		) > 0:
			return true

	return false


func get_translation(
	locale: String
) -> Translation:
	var normalized_locale: String = (
		_standardize_locale(locale)
	)

	if normalized_locale.is_empty():
		return null

	if not _translations.has(
		normalized_locale
	):
		return null

	return _translations[
		normalized_locale
	]


func get_loaded_locale_count() -> int:
	return _translations.size()


func get_system_locale() -> String:
	return _standardize_locale(
		OS.get_locale()
	)


func get_locale_name(
	locale: String
) -> String:
	var normalized_locale: String = (
		_standardize_locale(locale)
	)

	if normalized_locale.is_empty():
		return ""

	return TranslationServer.get_locale_name(
		normalized_locale
	)


func get_language_name(
	language: String
) -> String:
	if language.is_empty():
		return ""

	return TranslationServer.get_language_name(
		language
	)


func get_country_name(
	country: String
) -> String:
	if country.is_empty():
		return ""

	return TranslationServer.get_country_name(
		country
	)


func get_loaded_locales() -> PackedStringArray:
	return TranslationServer.get_loaded_locales()


func get_all_languages() -> PackedStringArray:
	return TranslationServer.get_all_languages()


func get_all_countries() -> PackedStringArray:
	return TranslationServer.get_all_countries()


func get_all_scripts() -> PackedStringArray:
	return TranslationServer.get_all_scripts()


func compare_locales(
	locale_a: String,
	locale_b: String
) -> int:
	return TranslationServer.compare_locales(
		_standardize_locale(locale_a),
		_standardize_locale(locale_b)
	)


func format_number(
	number: String,
	locale: String = ""
) -> String:
	var target_locale: String = locale

	if target_locale.is_empty():
		target_locale = get_locale()

	return TranslationServer.format_number(
		number,
		_standardize_locale(target_locale)
	)


func parse_number(
	number: String,
	locale: String = ""
) -> String:
	var target_locale: String = locale

	if target_locale.is_empty():
		target_locale = get_locale()

	return TranslationServer.parse_number(
		number,
		_standardize_locale(target_locale)
	)


func get_percent_sign(
	locale: String = ""
) -> String:
	var target_locale: String = locale

	if target_locale.is_empty():
		target_locale = get_locale()

	return TranslationServer.get_percent_sign(
		_standardize_locale(target_locale)
	)


func get_plural_rules(
	locale: String = ""
) -> String:
	var target_locale: String = locale

	if target_locale.is_empty():
		target_locale = get_locale()

	return TranslationServer.get_plural_rules(
		_standardize_locale(target_locale)
	)


func pseudolocalize(
	message: StringName
) -> String:
	if not _is_operational():
		return String(message)

	return String(
		TranslationServer.pseudolocalize(
			message
		)
	)


func set_pseudolocalization(
	enabled: bool
) -> void:
	TranslationServer.pseudolocalization_enabled = (
		enabled
	)


func is_pseudolocalization_enabled() -> bool:
	return TranslationServer.pseudolocalization_enabled


func clear_translations() -> void:
	var locales: Array[String] = (
		_locale_order.duplicate()
	)

	for locale in locales:
		unregister_translation(
			locale
		)


func is_ready() -> bool:
	return state == State.READY


func is_paused() -> bool:
	return state == State.PAUSED


func is_stopped() -> bool:
	return state == State.STOPPED


func is_failed() -> bool:
	return state == State.FAILED


func get_state() -> State:
	return state


func get_error() -> String:
	return localization_error


func _standardize_locale(
	locale: String
) -> String:
	if locale.is_empty():
		return ""

	return TranslationServer.standardize_locale(
		locale,
		true
	)


func _find_available_locale(
	requested_locale: String,
	use_fallback: bool
) -> String:
	if has_locale(
		requested_locale,
		true
	):
		return requested_locale

	var matches: Array[String] = []

	for available_locale in _locale_order:
		if TranslationServer.compare_locales(
			available_locale,
			requested_locale
		) > 0:
			matches.append(
				available_locale
			)

	if not matches.is_empty():
		return matches[0]

	if not use_fallback:
		return ""

	var normalized_fallback: String = (
		_standardize_locale(
			fallback_locale
		)
	)

	if normalized_fallback.is_empty():
		return ""

	if has_locale(
		normalized_fallback,
		true
	):
		return normalized_fallback

	for available_locale in _locale_order:
		if TranslationServer.compare_locales(
			available_locale,
			normalized_fallback
		) > 0:
			return available_locale

	return ""


func _validate_locales() -> bool:
	localization_error = ""

	default_locale = (
		_standardize_locale(
			default_locale
		)
	)

	fallback_locale = (
		_standardize_locale(
			fallback_locale
		)
	)

	if default_locale.is_empty():
		localization_error = (
			"Default Locale không hợp lệ"
		)
		return false

	if fallback_locale.is_empty():
		localization_error = (
			"Fallback Locale không hợp lệ"
		)
		return false

	if not startup_locale.is_empty():
		startup_locale = (
			_standardize_locale(
				startup_locale
			)
		)

		if startup_locale.is_empty():
			localization_error = (
				"Startup Locale không hợp lệ"
			)
			return false

	return true


func _validate_root() -> bool:
	localization_error = ""

	if not is_inside_tree():
		localization_error = (
			"Localization không nằm trong SceneTree"
		)
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Localization: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [
				EXPECTED_NODE_NAME,
				name
			]
		)

	return true


func _is_operational() -> bool:
	return (
		state == State.READY
		or state == State.PAUSED
	)


func _set_error(
	message: String
) -> void:
	localization_error = message

	_log_error(
		message
	)


func _fail(
	reason: String
) -> bool:
	state = State.FAILED
	localization_error = reason

	localization_failed.emit(
		reason
	)

	_log_error(
		reason
	)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	localization_stopping.emit()

	if clear_on_stop:
		clear_translations()

	state = State.STOPPED

	localization_stopped.emit()

	_log(
		"Localization Stopped"
	)


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[Localization] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[Localization] "
		+ message
) 
