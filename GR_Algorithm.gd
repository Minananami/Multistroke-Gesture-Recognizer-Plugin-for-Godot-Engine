@tool
extends Node
class_name GestureRecognizer

# Connection to class that handles the structure of saved gestures as resources (name + LUT)
const GestureResource = preload("res://addons/Gesture_recognizer/resources/gestures/GestureResource.gd")

# Constants defining the gesture processing resolution and scaling parameters
const NumPoints: int = 32                         # The number of points each gesture is resampled to, for uniformity
const point_radius: int = 1                       # Radius for marking a thicker region around each point in LUT
const LUTSize: int = 32 + point_radius * 2        # Size of the binary Look-Up Table (LUT) grid
const MinIntCoord: int = point_radius             # Min and Max integer coordinates for scaling points into a square
const MaxIntCoord: int = LUTSize - point_radius

# List containing all gesture templates [{"name": name, "LUT": LUT}]
var _gestures_templates: Array = []

# Class representing a single point in a gesture
class Point:
	var x: float
	var y: float
	var id: int   # Stroke ID, used to distinguish separate strokes in a gesture
	
	func _init(x: float, y: float, id: int):
		self.x = x
		self.y = y
		self.id = id

#-----------------------------------------------------------------------
#-------------------- Gesture Class Functions --------------------------
#-----------------------------------------------------------------------

# Class to represent a single gesture (template or input)
class Gesture:
	var name: String    # Name of the gesture
	var points: Array   # Processed list of points after normalization
	var LUT: Array      # The gesture's binary LUT, used for recognition comparisons
	
	# When initializing new Gesture, automatically normalize points and generate its LUT
	func _init(name: String, points: Array):
		self.name = name
		self.points = self._normalize_points(points)
		self.LUT = self._compute_LUT(self.points)
	
	# Normalize the points of the gesture through multiple steps
	static func _normalize_points(points: Array) -> Array:
		points = Gesture._resample_points(points) # Resample gesture to uniform number of points
		Gesture._translate_to_origin(points) # Move gesture to origin (centered at 0,0)
		Gesture._scale_and_int_points(points) # Scale gesture to fit within a grid of LUT size, make int coords
		return points
	
	static func _resample_points(points: Array) -> Array:
		var I = Gesture._path_length(points) / (NumPoints) # Distance between resampled points
		var D = 0.0 # Cumulative distance along the gesture path
		var new_points = [Point.new(points[0].x, points[0].y, points[0].id)] # Start with the first point
		
		var i = 1
		while new_points.size() < NumPoints and i < points.size():
			# Ensure resampling respects strokes, there may be >=1 strokes in one gesture
			if points[i].id == points[i - 1].id:
				var d = Gesture._euclidean_distance(points[i - 1], points[i]) # Distance between consecutive points
				if (D + d) >= I: # When the resampled distance is reached, calculate new point
					var qx = points[i - 1].x + ((I - D) / d) * (points[i].x - points[i - 1].x)
					var qy = points[i - 1].y + ((I - D) / d) * (points[i].y - points[i - 1].y)
					new_points.append(Point.new(qx, qy, points[i].id))
					points.insert(i, new_points[-1])
					D = 0.0
				else:
					D += d
			i += 1
		
		# Ensure exactly `NumPoints` points in the gesture (sometimes it's NumPoints-1)
		if new_points.size() == NumPoints-1:
			new_points.append(points[points.size() - 1])
		return new_points
	
	static func _translate_to_origin(points: Array) -> void:
		# Translate gesture points so their centroid (center of mass) aligns with the origin (0,0)
		var centroid = Vector2(0, 0)
		for p in points:
			centroid += Vector2(p.x, p.y)
		centroid /= NumPoints
		
		for p in points:
			p.x -= centroid.x
			p.y -= centroid.y
	
	# Scale points into the range [0, MaxIntCoord - 1], ensuring the gesture fits a uniform square
	static func _scale_and_int_points(points: Array) -> void:
		var min_x = INF
		var max_x = -INF
		var min_y = INF
		var max_y = -INF
		
		for p in points:
			min_x = min(min_x, p.x)
			max_x = max(max_x, p.x)
			min_y = min(min_y, p.y)
			max_y = max(max_y, p.y)
		
		# Scale by a larger coordinate to fit in a square
		var scale = max(max_x - min_x, max_y - min_y)
		if scale == 0: # Avoid division by zero
			scale = 1
		
		# Scaling to MaxIntCoord sized square, convert points to integers
		for p in points:
			p.x = int(round(((p.x - min_x) / scale) * (MaxIntCoord - MinIntCoord - 1))) + MinIntCoord
			p.y = int(round(((p.y - min_y) / scale) * (MaxIntCoord - MinIntCoord - 1))) + MinIntCoord
	
	# Generate a binary Look-Up Table (LUT) to represent the gesture as a grid
	static func _compute_LUT(points: Array) -> Array:
		var LUT = []
		for i in range(0, LUTSize):
			LUT.append([])
			for y in range(LUTSize):
				LUT[i].append(0)
		
		# Create offsets for marking a thicker region around each point
		var point_offsets = []
		
		# Making 'brush radius' offsets matrix (1 == matrix 3*3, 2 == m 5*5)
		for dx in range(-point_radius, point_radius + 1):
			for dy in range(-point_radius, point_radius + 1):
				point_offsets.append(Vector2(dx, dy))
		
		# Mark presence of a point and offcet neightbors, cycle only for required cells of LUT
		for p in points:
			for offset in point_offsets:
				var x = p.x + int(offset.x)
				var y = p.y + int(offset.y)
				LUT[x][y] = 1
		
		return LUT
	
	static func _path_length(points: Array) -> float:
		var d = 0.0
		for i in range(1, points.size()):
			if points[i].id == points[i - 1].id:
				d += Gesture._euclidean_distance(points[i - 1], points[i])
		return d
	
	static func _squared_euclidean_distance(p1: Point, p2: Point) -> float:
		return pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2)
	
	static func _euclidean_distance(p1: Point, p2: Point) -> float:
		return sqrt(Gesture._squared_euclidean_distance(p1, p2))

#-----------------------------------------------------------------------
#-------------------- QDollarRecognizer functions ----------------------
#-----------------------------------------------------------------------

# Identify the closest gesture match using Accuracy score
func Recognize(original_points: Array, min_score_lim: float) -> Dictionary:
	if _gestures_templates.size() <= 0:
		print("No gesture templates available for recognition.")
		return {"name": "No Templates", "score": INF}
		
	var gesture_LUT = Gesture.new("", original_points).LUT
	var best_score = -INF
	var best_match = null
	
	# Compare the input gesture LUT against all templates LUTs
	for template in _gestures_templates:
		var score = AccuracyScore(gesture_LUT, template["LUT"], template["name"])
		if score > best_score:
			best_score = score
			best_match = template["name"]
	
	# Return the name of best match if the score is higher then min_dscore_limit, else "No Match"
	return {"name": best_match, "score": best_score} if best_match and best_score >= min_score_lim else {"name": "No Match", "score": INF}

# Calculate the Accuracy score between two LUTs (difference in matching cells)
func AccuracyScore(LUT1: Array, LUT2: Array, template_name: String) -> float:
	var tp = 0  # True Positive
	var tn = 0  # True Negative
	#var fp = 0  # False Positive
	#var fn = 0  # False Negative
	var total = LUTSize ** 2
	
	for x in range(LUTSize):
		for y in range(LUTSize):
			var A = LUT1[x][y]
			var B = LUT2[x][y]
			
			tp += A & B  # True Positive: both A and B are 1
			tn += (1 - A) & (1 - B)  # True Negative: both A and B are 0
			#fp += (1 - A) & B  # False Positive: A is 0, but B is 1
			#fn += A & (1 - B)  # False Negative: A is 1, but B is 0 
	
	var accuracy = float(tp + tn) / total
	print("------------------------------\nTemplate:", template_name)
	print("  Accuracy: ", accuracy)
	
	return accuracy

#-----------------------------------------------------------------------
#-------------------- Loading and Saving gestures ----------------------
#-----------------------------------------------------------------------

# Add a new gesture template by normalizing points and saving as a resource
func AddGesture(gestures_path:String, name: String, original_points: Array) -> int:
	var points = Gesture._normalize_points(original_points.duplicate(true))
	var LUT = Gesture._compute_LUT(points)
	
	var gesture_resource = GestureResource.new()
	gesture_resource.gesture_name = name
	gesture_resource.LUT = LUT
	
	# Save the gesture as a Godot resource '.tres'
	var index = 1
	var resource_path = gestures_path + name + ".tres"
	while FileAccess.file_exists(resource_path):
		resource_path = gestures_path + name + "_" + str(index) + ".tres"
		index += 1
	var result = ResourceSaver.save(gesture_resource, resource_path)
	
	if result == OK:
		print("Gesture saved as resource at: " + resource_path)
	else:
		print("Failed to save gesture resource.")
	
	# Add the gesture to the internal list of templates
	_gestures_templates.append({"name": name, "LUT": LUT})
	
	# Return the total number of gestures with the same name
	var num = 0
	for gest in _gestures_templates:
		if gest.name == name:
			num += 1
	
	return num

# Load templates from resources to _gestures_templates list on addon startup
func LoadGesturesFromResources(gestures_path: String) -> void:
	var dir = DirAccess.open(gestures_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				var gesture_resource = load(gestures_path + file_name)
				if gesture_resource is GestureResource:
					_gestures_templates.append({
						"name": gesture_resource.gesture_name, 
						"LUT": gesture_resource.LUT})
					print("Loaded gesture: " + gesture_resource.gesture_name)
					
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		print("Failed to open gestures directory.")

# Function to retrieve the unique names of all loaded gesture templates
func GetGestureNames() -> Array:
	var gesture_names = []
	for gest in _gestures_templates:
		if gest["name"] not in gesture_names:
			gesture_names.append(gest["name"])
	return gesture_names
