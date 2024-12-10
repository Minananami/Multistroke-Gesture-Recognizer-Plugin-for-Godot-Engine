# Multistroke Gesture Recognizer Plugin for Godot Engine

## Overview
This plugin provides a gesture-cloud recognition system for 2D hand-drawn symbols, optimized for integration into the Godot Engine. It enables developers to create symbol-based mechanics for games and applications, such as drawing symbols to trigger actions.

## Features
- Multi-stroke gesture recognition.
- Recognition does NOT depend on the number of points in the gesture, its position on the screen or its scale.
- Supports adding, saving, and recognizing gestures.
- Has an interface for an example of using the algorithm.

## Requirements
- Godot Engine 3.5 or higher.

## Installation
1. Download or clone the repository.
2. Place the plugin folder into your Godot project's 'addons' directory.
3. Enable the plugin in **Project Settings > Plugins**.
4. If everything is done correctly, the plugin interface will appear on the left dock.

## Usage
1. **Drawing Gestures**:
   - Use left mouse button on the drawing area to create a gesture.
   - Strokes within 1 second will be counted as one gesture.
   - After 1 second of inactivity the recognition will start.

2. **Managing Templates**:
   - Add new gesture types with custom names.
   - Append variations to existing types with auto indexing of file names.

3. **Implementing in games**:
   If you want to integrate the recognizer into your custom code - look how it is done in the `GR_interface.gd`:
   - Create an instance of the `GestureRecognizer` class. You can then load gestures from a specified directory containing saved gesture resources (.tres files).
   ```
   var recognizer = GestureRecognizer.new()
   recognizer.LoadGesturesFromResources("res://addons/gesture_recognizer/resources/gestures/")
   ```
   - The algorithm requires a set of points representing the user-drawn gesture. Each point should be an instance of the Point class, containing x, y, and id (stroke ID). You can collect these points manually from user input, similar to how it's done in the plugin interface's _on_drawing_area_input function.
   ```
   var new_point = recognizer.Point.new(local_position.x, local_position.y, current_gesture_id)
   drawing_points[].append(new_point)
   ```
   - You should flatten the points array before using the Recognize method. Adjust the minimum score threshold by your needs. The Recognize method returns a dictionary {"name": best_match, "score": best_score}.
   ```
   var flattened_points = []
   for stroke in drawing_points:
	flattened_points += stroke
   recognition_result = recognizer.Recognize(flattened_points, min_score_threshold)
   ```
