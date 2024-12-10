@tool
extends Panel

@onready var gestures_path: String = "res://addons/Gesture_recognizer/resources/gestures/"
@onready var test_path: String = "res://addons/Gesture_recognizer/resources/testers/"
@onready var drawing_area = $DrawingArea
@onready var button_add_existing_type = $Button_AddExistingType
@onready var list_type_name = $List_TypeName
@onready var button_add_new_type = $Button_AddNewType
@onready var text_new_name = $Text_NewName
@onready var button_view_all = $Button_ViewAll
@onready var result_label = $ResultLabel
@onready var button_test = $Button_Test
@onready var button_score = $Button_Score

var drawing_points = []
var is_drawing = false
var recognizer = GestureRecognizer.new()
var min_score_limitation = 0.7
var current_gesture_id = 0 
var stroke_timer = Timer.new()
var recognize_timer = Timer.new()

var max_points = 500
var min_points = 10
var invalid_characters = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]

var _recognition_thread: Thread = null
var _recognition_result: Dictionary = {}
var _is_recognizing: bool = false

func _ready():
	print("Interface is ready.")
	
	add_child(stroke_timer)
	stroke_timer.wait_time = 1.0  # seconds for multi-stroke
	stroke_timer.one_shot = true
	stroke_timer.connect("timeout", Callable(self, "_on_stroke_timeout"))
	
	drawing_area.connect("gui_input", Callable(self, "_on_drawing_area_input"))
	button_add_existing_type.connect("pressed", Callable(self, "_on_add_existing_type_pressed"))
	button_add_new_type.connect("pressed", Callable(self, "_on_add_new_type_pressed"))
	button_view_all.connect("pressed", Callable(self, "_on_view_all_pressed"))
	button_test.connect("pressed", Callable(self, "_test"))
	button_score.connect("pressed", Callable(self, "_score"))
	recognizer.LoadGesturesFromResources(gestures_path)
	_update_gesture_list()
	

func _on_drawing_area_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if stroke_timer.is_stopped() and drawing_points.size() > 0:
				drawing_points.clear()
				current_gesture_id = 0
				queue_redraw()
			#print("Started drawing.")
			is_drawing = true
			stroke_timer.stop()
			drawing_points.append([])
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			#print("Stopped drawing.")
			is_drawing = false
			current_gesture_id += 1
			stroke_timer.start()
			#_recognize_gesture()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			#print("Canvas cleared.")
			_is_recognizing = false
			stroke_timer.stop()
			drawing_points.clear()
			result_label.text = ""
			current_gesture_id = 0
			if _recognition_thread and _recognition_thread.is_active():
				_recognition_thread.wait_to_finish() 
				_recognition_thread = null
			queue_redraw()
	elif event is InputEventMouseMotion and is_drawing:
		if drawing_area.get_rect().has_point(drawing_area.get_local_mouse_position()):
			if _get_flattened_points().size() >= max_points:
				result_label.text = "Error: Maximum number of points reached."
				is_drawing = false
				return
			
			var local_position = drawing_area.get_local_mouse_position()
			var new_point = recognizer.Point.new(local_position.x, local_position.y, current_gesture_id)
			drawing_points[-1].append(new_point)
			queue_redraw()
	
func _draw():
	#print("Drawing function called.")
	for stroke in drawing_points:
		for i in range(stroke.size() - 1):
			var start_point = Vector2(stroke[i].x, stroke[i].y)
			var end_point = Vector2(stroke[i + 1].x, stroke[i + 1].y)
			draw_line(start_point, end_point, Color(0.95, 0.95, 1, 0.9), 2)

func _on_stroke_timeout():
	#print("Gesture timer expired. Starting recognition.")
	_recognize_gesture()
	if _is_recognizing == false:
		drawing_points.clear()
		queue_redraw()
		current_gesture_id = 0

func _recognize_gesture():
	if _is_recognizing:
		return
		
	var total_points = 0
	for stroke in drawing_points:
		total_points += stroke.size()
		
	if total_points < min_points:
		result_label.text = "Error: Not enough points, draw a longer line."
	else:
		result_label.text = "Recognizing..."
		_is_recognizing = true
		_recognition_result = {}
		await get_tree().process_frame
		_recognition_thread = Thread.new()
		_recognition_thread.start(Callable(self, "_run_recognition"))

func _run_recognition():
	var flattened_points = _get_flattened_points()
	recognize_timer = Time.get_ticks_msec()
	_recognition_result = recognizer.Recognize(flattened_points, min_score_limitation)
	call_deferred("_on_recognition_complete")

func _get_flattened_points() -> Array:
	var flattened_points = []
	for stroke in drawing_points:
		flattened_points += stroke 
	return flattened_points

func _on_recognition_complete():
	if _recognition_result.size() > 0:
		var rounded_score = String("%.3f" % _recognition_result["score"])
		
		var end_time = Time.get_ticks_msec()
		var recognized_time = end_time - recognize_timer
		var string_time = String("%.0f" % recognized_time)
		result_label.text = "Recognized as: " + _recognition_result["name"] + " (Score: " + rounded_score + ", Time: " + string_time + " ms)"
	
	_recognition_thread.wait_to_finish()
	_recognition_thread = null
	_is_recognizing = false
	current_gesture_id = 0

func _on_add_existing_type_pressed():
	#print("Add to existing type button pressed.")
	var selected_type = list_type_name.get_selected_id()
	var selected_name = list_type_name.get_item_text(selected_type)
	if selected_type != -1:
		var flattened_points = _get_flattened_points()
		
		if flattened_points.size() <= min_points:
			result_label.text = "Error: Not enough points, draw a longer line."
			return
		
		if flattened_points.size() > max_points:
			result_label.text = "Error: Maximum number of points reached."
			return
		
		var num = recognizer.AddGesture(gestures_path, selected_name, flattened_points)
		drawing_points.clear()
		result_label.text = "Added to type: " + list_type_name.get_item_text(selected_type) + " (total variations: " + str(num) + ")"
		_update_gesture_list()
		queue_redraw()
		current_gesture_id = 0
	else:
		result_label.text = "Error: Please select an existing gesture type."
		return

func _on_add_new_type_pressed():
	#print("Add to new type button pressed.")
	var new_type_name = text_new_name.text.strip_edges()
	if new_type_name != "":
		if not _is_valid_filename(new_type_name):
			result_label.text = "Error: Gesture name contains invalid characters."
			return
		#print("Adding new gesture type: " + new_type_name)
		var flattened_points = _get_flattened_points()
		
		if flattened_points.size() <= min_points:
			result_label.text = "Error: Not enough points detected. Please draw a gesture."
			return
		
		if flattened_points.size() > max_points:
			result_label.text = "Error: Maximum number of points exceeded. Simplify your gesture."
			return
		
		var num = recognizer.AddGesture(gestures_path, new_type_name, flattened_points)
		drawing_points.clear()
		result_label.text = "Added to new type: " + new_type_name + " (total variations: " + str(num) + ")"
		text_new_name.text = ""
		_update_gesture_list()
		queue_redraw()
		current_gesture_id = 0
	else:
		result_label.text = "Error: Please enter a gesture name."
		return

func _on_view_all_pressed():
	#print("View all gestures button pressed.")
	var dir = DirAccess.open(gestures_path)
	if dir:
		OS.shell_open(ProjectSettings.globalize_path(gestures_path))
	else:
		result_label.text = "No gestures folder found."

func _update_gesture_list():
	list_type_name.clear()
	var gesture_names = recognizer.GetGestureNames()
	for name in gesture_names:
		list_type_name.add_item(name)

func _is_valid_filename(name: String) -> bool:
	for char in invalid_characters:
		if name.find(char) != -1:
			return false
	return true

func _test():
	recognizer.LoadTest(test_path, "res://addons/Gesture_recognizer/resources/testers_NP32_LS32/")
	var new_type_name = text_new_name.text.strip_edges()
	if new_type_name != "":
		var flattened_points = _get_flattened_points()
		recognizer.Test(test_path, new_type_name, flattened_points)
		drawing_points.clear()
		text_new_name.text = ""
		_update_gesture_list()
		queue_redraw()
		current_gesture_id = 0

func _score():
	
	recognizer.RunRecognitionBatch("res://addons/Gesture_recognizer/resources/test_NP32_LS32/", "res://addons/Gesture_recognizer/resources/testers_NP32_LS32/", "res://addons/Gesture_recognizer/resources/recognition_results3232.csv")
