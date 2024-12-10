@tool
extends EditorPlugin

var interface_scene

func _enter_tree() -> void:
	print("Plugin loaded.")
	interface_scene = preload("res://addons/Gesture_recognizer/GR_interface.tscn").instantiate()
	
	add_control_to_dock(DOCK_SLOT_LEFT_UL, interface_scene)
	add_custom_type("GestureRecognizer", "Node", preload("res://addons/Gesture_recognizer/GR_Algorithm.gd"), null)

func _exit_tree() -> void:
	remove_control_from_docks(interface_scene)
	interface_scene.queue_free()
	remove_custom_type("GestureRecognizer")
