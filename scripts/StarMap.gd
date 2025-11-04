extends Node2D

# Star generation settings
const NUM_STARS = 300  # Double for 2x width
const STAR_COLORS = [
	Color.WHITE,
	Color(0.8, 0.9, 1.0),  # Light blue
	Color(1.0, 0.9, 0.7),  # Yellow
	Color(1.0, 0.8, 0.6),  # Orange
	Color(0.9, 0.9, 1.0),  # Pale blue
]

# Map settings
const MAP_WIDTH_MULTIPLIER = 2.0
const EDGE_SCROLL_MARGIN = 50.0
const EDGE_SCROLL_SPEED = 300.0

# Network settings (adjustable)
var num_columns: int = 8
var min_nodes_per_column: int = 3
var max_nodes_per_column: int = 5
var min_node_distance: float = 100.0
var max_node_distance: float = 500.0
var prevent_parallel_paths: bool = false  # Disabled by default for stability
const ANGLE_TOLERANCE: float = 5.0  # Degrees

# Node encounter type spawn rates (0-100, will be normalized)
var combat_spawn_rate: int = 33
var treasure_spawn_rate: int = 33
var mystery_spawn_rate: int = 34

# Stars and network
var stars: Array[Star] = []
var network_nodes: Array[Dictionary] = []  # {position: Vector2, connections: Array[int], type: String, revealed: bool}
var home_node_idx: int = -1
var end_node_idx: int = -1
var map_width: float = 0.0

# Player
var player_current_node: int = -1
var player_sprite: Sprite2D
var is_player_moving: bool = false

@onready var star_container: Node2D = $StarContainer
@onready var network_layer: Node2D = $NetworkLayer
@onready var icon_layer: Node2D = $IconLayer
@onready var camera: Camera2D = $Camera2D
@onready var to_combat_button: Button = $UI/ToCombatButton
@onready var refresh_button: Button = $UI/RefreshButton
@onready var deck_builder_button: Button = $UI/DeckBuilderButton
@onready var parallel_path_button: Button = $UI/ParallelPathButton

# Control buttons
@onready var columns_label: Label = $UI/ColumnsLabel
@onready var columns_decrease_btn: Button = $UI/ColumnsDecreaseBtn
@onready var columns_increase_btn: Button = $UI/ColumnsIncreaseBtn
@onready var min_rows_label: Label = $UI/MinRowsLabel
@onready var min_rows_decrease_btn: Button = $UI/MinRowsDecreaseBtn
@onready var min_rows_increase_btn: Button = $UI/MinRowsIncreaseBtn
@onready var max_rows_label: Label = $UI/MaxRowsLabel
@onready var max_rows_decrease_btn: Button = $UI/MaxRowsDecreaseBtn
@onready var max_rows_increase_btn: Button = $UI/MaxRowsIncreaseBtn
@onready var min_dist_label: Label = $UI/MinDistLabel
@onready var min_dist_decrease_btn: Button = $UI/MinDistDecreaseBtn
@onready var min_dist_increase_btn: Button = $UI/MinDistIncreaseBtn
@onready var max_dist_label: Label = $UI/MaxDistLabel
@onready var max_dist_decrease_btn: Button = $UI/MaxDistDecreaseBtn
@onready var max_dist_increase_btn: Button = $UI/MaxDistIncreaseBtn

func _ready():
	var viewport_size = get_viewport_rect().size
	map_width = viewport_size.x * MAP_WIDTH_MULTIPLIER

	# Setup camera
	camera.position = Vector2(viewport_size.x / 2, viewport_size.y / 2)
	camera.limit_left = 0
	camera.limit_right = int(map_width)
	camera.limit_top = 0
	camera.limit_bottom = int(viewport_size.y)

	# Check if we have saved starmap data
	if GameData.has_starmap_data:
		load_starfield()
	else:
		generate_starfield()

	to_combat_button.pressed.connect(_on_to_combat)
	refresh_button.pressed.connect(_on_refresh_starmap)
	deck_builder_button.pressed.connect(_on_deck_builder)
	parallel_path_button.pressed.connect(_on_toggle_parallel_paths)

	update_parallel_path_button()

	# Connect control buttons
	columns_decrease_btn.pressed.connect(_on_columns_decrease)
	columns_increase_btn.pressed.connect(_on_columns_increase)
	min_rows_decrease_btn.pressed.connect(_on_min_rows_decrease)
	min_rows_increase_btn.pressed.connect(_on_min_rows_increase)
	max_rows_decrease_btn.pressed.connect(_on_max_rows_decrease)
	max_rows_increase_btn.pressed.connect(_on_max_rows_increase)
	min_dist_decrease_btn.pressed.connect(_on_min_dist_decrease)
	min_dist_increase_btn.pressed.connect(_on_min_dist_increase)
	max_dist_decrease_btn.pressed.connect(_on_max_dist_decrease)
	max_dist_increase_btn.pressed.connect(_on_max_dist_increase)

	update_control_labels()

func _process(delta):
	handle_edge_scrolling(delta)

func generate_starfield():
	var viewport_size = get_viewport_rect().size

	for i in range(NUM_STARS):
		# Random position across 2x width
		var pos = Vector2(
			randf() * map_width,
			randf() * viewport_size.y
		)

		# Random size (biased toward smaller stars, with some large bright ones)
		var size_roll = randf()
		var size = 2.0 if size_roll < 0.7 else (4.0 if size_roll < 0.9 else 6.0)

		# Random color
		var color = STAR_COLORS[randi() % STAR_COLORS.size()]

		# Brightness correlates with size
		var brightness = size / 6.0

		# Create star instance
		create_star(pos, size, color, brightness)

	# Generate network
	generate_network()
	draw_network()
	create_node_icons()
	setup_player()

func create_star(pos: Vector2, size: float, color: Color, brightness: float):
	var star = Star.new()
	star_container.add_child(star)
	star.position = pos
	star.setup(size, color, brightness)

	# Add collision shape programmatically
	var collision_shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = size * 4
	collision_shape.shape = circle
	star.add_child(collision_shape)

	stars.append(star)

func load_starfield():
	var viewport_size = get_viewport_rect().size

	for i in range(NUM_STARS):
		var pos = Vector2(
			randf() * map_width,
			randf() * viewport_size.y
		)
		var size_roll = randf()
		var size = 2.0 if size_roll < 0.7 else (4.0 if size_roll < 0.9 else 6.0)
		var color = STAR_COLORS[randi() % STAR_COLORS.size()]
		var brightness = size / 6.0
		create_star(pos, size, color, brightness)

	generate_network()
	draw_network()
	create_node_icons()
	setup_player()

func handle_edge_scrolling(delta: float):
	var viewport_size = get_viewport_rect().size
	var mouse_pos = get_viewport().get_mouse_position()

	var scroll_velocity = Vector2.ZERO

	# Check left edge
	if mouse_pos.x < EDGE_SCROLL_MARGIN:
		scroll_velocity.x = -EDGE_SCROLL_SPEED
	# Check right edge
	elif mouse_pos.x > viewport_size.x - EDGE_SCROLL_MARGIN:
		scroll_velocity.x = EDGE_SCROLL_SPEED

	# Apply smooth scrolling
	camera.position += scroll_velocity * delta
	camera.position.x = clamp(camera.position.x, viewport_size.x / 2, map_width - viewport_size.x / 2)

func generate_network():
	var viewport_size = get_viewport_rect().size
	network_nodes.clear()

	var column_width = map_width / float(num_columns + 1)  # +1 for spacing
	var vertical_margin = 100.0
	var usable_height = viewport_size.y - (vertical_margin * 2)

	# Track which stars have been used globally
	var used_stars: Array[Star] = []

	# Generate nodes in columns
	for col in range(num_columns):
		var nodes_in_column = 1  # Default

		# First column: only home node
		if col == 0:
			nodes_in_column = 1
		# Column 1: always 2 nodes
		elif col == 1:
			nodes_in_column = 2
		# Column 2: always 3 nodes
		elif col == 2:
			nodes_in_column = 3
		# Last column: only end node
		elif col == num_columns - 1:
			nodes_in_column = 1
		# Penultimate column (second to last): always 3 nodes
		elif col == num_columns - 2:
			nodes_in_column = 3
		# Middle columns (3 to num_columns-3): random number between min and max
		else:
			nodes_in_column = randi() % (max_nodes_per_column - min_nodes_per_column + 1) + min_nodes_per_column

		# Calculate x position range for this column
		var x_min = column_width * col + column_width * 0.3
		var x_max = column_width * (col + 1) + column_width * 0.7

		# Get stars in this column's X range (excluding already used stars)
		var column_stars = []
		for star in stars:
			if star in used_stars:
				continue  # Skip stars that have been assigned
			if star.position.x >= x_min and star.position.x <= x_max:
				if star.position.y >= vertical_margin and star.position.y <= viewport_size.y - vertical_margin:
					column_stars.append(star)

		# Create nodes for this column
		for row in range(nodes_in_column):
			var node_pos: Vector2
			var found_valid_star = false

			if nodes_in_column == 1:
				# Center single node vertically - find closest star to center
				var target_y = viewport_size.y / 2.0

				# Try to find a star that doesn't create parallel paths
				var sorted_stars = column_stars.duplicate()
				sorted_stars.sort_custom(func(a, b): return abs(a.position.y - target_y) < abs(b.position.y - target_y))

				for star in sorted_stars:
					# Check if this star is far enough from existing nodes
					if is_too_close_to_nodes(star.position):
						continue

					# Get existing nodes in previous column that might connect
					var prev_column_nodes: Array[int] = []
					for i in range(network_nodes.size()):
						if network_nodes[i]["column"] == col - 1:
							prev_column_nodes.append(i)

					if not would_create_parallel_path(star.position, prev_column_nodes):
						node_pos = star.position
						used_stars.append(star)  # Mark star as used
						found_valid_star = true
						break

				if not found_valid_star:
					node_pos = Vector2(column_width * (col + 1), target_y)
			else:
				# Distribute nodes evenly - find stars near target positions
				var target_y = vertical_margin + (usable_height / float(nodes_in_column + 1)) * (row + 1)

				# Sort available stars by distance to target
				var sorted_stars = column_stars.duplicate()
				sorted_stars.sort_custom(func(a, b): return abs(a.position.y - target_y) < abs(b.position.y - target_y))

				for star in sorted_stars:
					# Check if this star is far enough from existing nodes
					if is_too_close_to_nodes(star.position):
						continue

					# Get nodes in this column that already exist (might connect vertically)
					# and nodes in previous column (might connect forward)
					var potential_connections: Array[int] = []
					for i in range(network_nodes.size()):
						if network_nodes[i]["column"] == col or network_nodes[i]["column"] == col - 1:
							potential_connections.append(i)

					if not would_create_parallel_path(star.position, potential_connections):
						node_pos = star.position
						column_stars.erase(star)
						used_stars.append(star)  # Mark star as used globally
						found_valid_star = true
						break

				if not found_valid_star:
					node_pos = Vector2(column_width * (col + 1), target_y)

			var node_type = "normal"
			if col == 0:
				node_type = "home"
				home_node_idx = network_nodes.size()
			elif col == num_columns - 1:
				node_type = "end"
				end_node_idx = network_nodes.size()

			network_nodes.append({
				"position": node_pos,
				"connections": [],
				"type": node_type,
				"column": col,
				"is_exit": false,
				"revealed": true,  # All nodes visible by default
				"visited": false
			})

	# Connect nodes forward only
	connect_network_forward()

	# Ensure path exists from home to end
	ensure_path_exists()

	print("Generated ", network_nodes.size(), " nodes")

func find_node_near_position(target: Vector2) -> int:
	var closest_idx = -1
	var closest_dist = INF

	for i in range(network_nodes.size()):
		var dist = network_nodes[i]["position"].distance_to(target)
		if dist < closest_dist:
			closest_dist = dist
			closest_idx = i

	return closest_idx

func find_closest_star_to_y(star_list: Array, target_y: float) -> Star:
	var closest_star: Star = null
	var closest_dist = INF

	for star in star_list:
		var dist = abs(star.position.y - target_y)
		if dist < closest_dist:
			closest_dist = dist
			closest_star = star

	return closest_star

func calculate_line_angle(p1: Vector2, p2: Vector2) -> float:
	# Calculate angle in degrees (0-360)
	var angle = rad_to_deg(atan2(p2.y - p1.y, p2.x - p1.x))
	# Normalize to 0-360
	if angle < 0:
		angle += 360.0
	return angle

func angles_too_similar(angle1: float, angle2: float) -> bool:
	# Check if two angles are within ANGLE_TOLERANCE degrees
	var diff = abs(angle1 - angle2)
	# Handle wraparound (e.g., 359 and 1 degrees)
	if diff > 180:
		diff = 360 - diff
	return diff <= ANGLE_TOLERANCE

func is_too_close_to_nodes(new_pos: Vector2) -> bool:
	# Check if the new position is too close to any existing node
	for node in network_nodes:
		var dist = new_pos.distance_to(node["position"])
		if dist < min_node_distance:
			return true
	return false

func would_create_parallel_path(new_node_pos: Vector2, existing_nodes: Array[int]) -> bool:
	if not prevent_parallel_paths or existing_nodes.size() == 0:
		return false

	# Calculate angles of all existing connections
	var existing_angles = []
	for i in range(network_nodes.size()):
		if not network_nodes[i].has("connections"):
			continue
		for j in network_nodes[i]["connections"]:
			if i < j:  # Check each connection once
				var angle = calculate_line_angle(network_nodes[i]["position"], network_nodes[j]["position"])
				existing_angles.append(angle)

	# If no existing connections yet, allow placement
	if existing_angles.size() == 0:
		return false

	# Check if any potential connection from existing_nodes to new_node_pos
	# would create a parallel path
	for node_idx in existing_nodes:
		if node_idx < 0 or node_idx >= network_nodes.size():
			continue
		var new_angle = calculate_line_angle(network_nodes[node_idx]["position"], new_node_pos)
		for existing_angle in existing_angles:
			if angles_too_similar(new_angle, existing_angle):
				return true

	return false

func connect_network_forward():
	# For each column, connect adjacent nodes vertically and select one exit node
	for col in range(num_columns):
		# Get all nodes in this column
		var column_nodes = []
		for i in range(network_nodes.size()):
			if network_nodes[i]["column"] == col:
				column_nodes.append(i)

		# Skip if no nodes in column
		if column_nodes.size() == 0:
			continue

		# Sort nodes by Y position
		column_nodes.sort_custom(func(a, b): return network_nodes[a]["position"].y < network_nodes[b]["position"].y)

		# Connect adjacent nodes within the column (bidirectional for exploration)
		for i in range(column_nodes.size() - 1):
			var node_idx = column_nodes[i]
			var next_node_idx = column_nodes[i + 1]

			# Add bidirectional connection
			if not network_nodes[node_idx]["connections"].has(next_node_idx):
				network_nodes[node_idx]["connections"].append(next_node_idx)
			if not network_nodes[next_node_idx]["connections"].has(node_idx):
				network_nodes[next_node_idx]["connections"].append(node_idx)

		# Add skip connections for larger columns
		var num_skip_connections = 0
		if column_nodes.size() >= 7:
			num_skip_connections = 2
		elif column_nodes.size() >= 5:
			num_skip_connections = 1

		for skip_idx in range(num_skip_connections):
			# Find two non-adjacent nodes to connect
			var attempts = 0
			var skip_added = false
			while attempts < 20 and not skip_added:
				var from_idx = randi() % column_nodes.size()
				var to_idx = randi() % column_nodes.size()

				# Ensure they're not adjacent and not the same
				if abs(from_idx - to_idx) > 1:
					var node_a = column_nodes[from_idx]
					var node_b = column_nodes[to_idx]

					# Add bidirectional skip connection
					if not network_nodes[node_a]["connections"].has(node_b):
						network_nodes[node_a]["connections"].append(node_b)
						network_nodes[node_b]["connections"].append(node_a)
						skip_added = true

				attempts += 1

		# Handle connections to next column
		if col < num_columns - 1:
			# Find all nodes in next column
			var next_column_nodes = []
			for i in range(network_nodes.size()):
				if network_nodes[i]["column"] == col + 1:
					next_column_nodes.append(i)

			# If this is the home column (column 0), connect home to ALL nodes in column 1
			if col == 0:
				var home_idx = column_nodes[0]  # Home is the only node in column 0
				network_nodes[home_idx]["is_exit"] = true
				for target_idx in next_column_nodes:
					network_nodes[home_idx]["connections"].append(target_idx)
			else:
				# For other columns, select one random exit node that connects to ALL nodes in next column
				var exit_node_idx = column_nodes[randi() % column_nodes.size()]
				network_nodes[exit_node_idx]["is_exit"] = true

				# Connect exit node to ALL nodes in next column
				for target_idx in next_column_nodes:
					network_nodes[exit_node_idx]["connections"].append(target_idx)

func ensure_path_exists():
	# Use BFS to check if path exists
	if home_node_idx < 0 or end_node_idx < 0:
		return

	var visited = []
	for i in range(network_nodes.size()):
		visited.append(false)

	var queue = [home_node_idx]
	visited[home_node_idx] = true
	var path_exists = false

	while queue.size() > 0:
		var current = queue.pop_front()

		if current == end_node_idx:
			path_exists = true
			break

		for neighbor_idx in network_nodes[current]["connections"]:
			if not visited[neighbor_idx]:
				visited[neighbor_idx] = true
				queue.append(neighbor_idx)

	# If no path, create one by connecting nodes along the way
	if not path_exists:
		connect_path_to_end()

func connect_path_to_end():
	# Create a guaranteed path by connecting one node from each column to the next
	var current = home_node_idx
	var current_col = network_nodes[current]["column"]

	while current_col < num_columns - 1:
		# Find a node in the next column that we can connect to
		var next_col = current_col + 1
		var next_node = -1

		# Find all nodes in next column
		var candidates = []
		for i in range(network_nodes.size()):
			if network_nodes[i]["column"] == next_col:
				candidates.append(i)

		# Try to connect to a random candidate without crossing
		candidates.shuffle()
		for candidate in candidates:
			var pos_current = network_nodes[current]["position"]
			var pos_candidate = network_nodes[candidate]["position"]

			var would_cross = false
			for k in range(network_nodes.size()):
				for l in network_nodes[k]["connections"]:
					if k < l:
						var pos_k = network_nodes[k]["position"]
						var pos_l = network_nodes[l]["position"]

						if lines_intersect(pos_current, pos_candidate, pos_k, pos_l):
							would_cross = true
							break
				if would_cross:
					break

			if not would_cross:
				next_node = candidate
				break

		# If all candidates would cross, just connect to the first one anyway (guarantee path)
		if next_node < 0 and candidates.size() > 0:
			next_node = candidates[0]

		if next_node >= 0:
			if not network_nodes[current]["connections"].has(next_node):
				network_nodes[current]["connections"].append(next_node)

			current = next_node
			current_col = network_nodes[current]["column"]
		else:
			break

func lines_intersect(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	# Check if line segments (p1,p2) and (p3,p4) intersect
	# Don't count as intersection if they share an endpoint
	if p1 == p3 or p1 == p4 or p2 == p3 or p2 == p4:
		return false

	var d1 = direction(p3, p4, p1)
	var d2 = direction(p3, p4, p2)
	var d3 = direction(p1, p2, p3)
	var d4 = direction(p1, p2, p4)

	if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and \
	   ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)):
		return true

	return false

func direction(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p3.x - p1.x) * (p2.y - p1.y) - (p2.x - p1.x) * (p3.y - p1.y)

func draw_network():
	# Clear previous lines
	for child in network_layer.get_children():
		child.queue_free()

	# Draw connection lines
	var line_node = Node2D.new()
	network_layer.add_child(line_node)

	line_node.draw.connect(func():
		for i in range(network_nodes.size()):
			# Only draw connections for revealed nodes
			if not network_nodes[i]["revealed"]:
				continue

			for j in network_nodes[i]["connections"]:
				if i < j and network_nodes[j]["revealed"]:  # Draw each line only once and both nodes revealed
					# Check if this is an exit connection (goes to next column)
					var is_exit_connection = network_nodes[j]["column"] > network_nodes[i]["column"]

					# Only draw exit connections if the source node has been visited
					if is_exit_connection and not network_nodes[i]["visited"]:
						continue

					# Check if this path is a legal move from current player position
					var is_legal_move = false
					var is_legal_exit_move = false
					if player_current_node >= 0:
						if i == player_current_node and is_node_reachable(j):
							is_legal_move = true
							# Check if this is an exit connection
							if is_exit_connection:
								is_legal_exit_move = true
						elif j == player_current_node and is_node_reachable(i):
							is_legal_move = true
							# Check if this is an exit connection (reversed)
							if is_exit_connection:
								is_legal_exit_move = true

					# Draw with different color/width based on connection type
					var line_color = Color(0.3, 0.6, 0.9, 0.5)
					var line_width = 3.0
					if is_legal_exit_move:
						line_color = Color(0.2, 1.0, 0.3, 0.9)  # Bright green for exit paths
						line_width = 5.0
					elif is_legal_move:
						line_color = Color(1.0, 1.0, 0.3, 0.9)  # Bright yellow for within-column
						line_width = 5.0

					line_node.draw_line(
						network_nodes[i]["position"],
						network_nodes[j]["position"],
						line_color,
						line_width
					)
	)
	line_node.queue_redraw()

func create_node_icons():
	# Clear previous icons
	for child in icon_layer.get_children():
		child.queue_free()

	# Create icons for each node
	var icons_created = 0
	for i in range(network_nodes.size()):
		if network_nodes[i]["revealed"]:
			var is_reachable = is_node_reachable(i)
			var icon = create_node_icon(network_nodes[i], i, is_reachable)
			icon_layer.add_child(icon)
			icon.position = network_nodes[i]["position"]
			icons_created += 1

	print("Created ", icons_created, " node icons")

func is_node_reachable(node_idx: int) -> bool:
	if player_current_node < 0:
		return false
	return node_idx in network_nodes[player_current_node]["connections"]

func create_node_icon(node_data: Dictionary, node_idx: int, is_reachable: bool) -> Node2D:
	var icon_area = Area2D.new()
	var icon = Node2D.new()
	var type = node_data["type"]
	var is_exit = node_data.get("is_exit", false)

	icon_area.add_child(icon)

	# Add collision for clicking
	var collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 20.0
	collision.shape = circle
	icon_area.add_child(collision)

	# Connect click event
	icon_area.input_event.connect(func(_viewport, event, _shape_idx):
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_on_node_clicked(node_idx)
	)

	# Check if this node has been visited (for exit icon display)
	var is_visited = node_data.get("visited", false)

	icon.draw.connect(func():
		# Draw highlight glow if reachable
		if is_reachable:
			icon.draw_circle(Vector2(0, 0), 28, Color(1.0, 1.0, 0.4, 0.3))
			icon.draw_arc(Vector2(0, 0), 26, 0, TAU, 32, Color(1.0, 1.0, 0.2), 4.0)

		match type:
			"home":
				# Draw house
				icon.draw_rect(Rect2(-15, -10, 30, 20), Color(0.8, 0.6, 0.3))
				icon.draw_polygon([Vector2(-20, -10), Vector2(0, -25), Vector2(20, -10)], [Color(0.6, 0.3, 0.1)])
			"end":
				# Draw red skull
				icon.draw_circle(Vector2(0, -5), 12, Color(0.9, 0.1, 0.1))
				icon.draw_rect(Rect2(-8, 5, 16, 10), Color(0.9, 0.1, 0.1))
				icon.draw_circle(Vector2(-5, -8), 3, Color(0.1, 0.1, 0.1))
				icon.draw_circle(Vector2(5, -8), 3, Color(0.1, 0.1, 0.1))
			_:
				# Only show exit portal if this node is an exit AND has been visited
				if is_exit and is_visited:
					# Draw green portal/exit
					icon.draw_circle(Vector2(0, 0), 14, Color(0.2, 0.8, 0.3, 0.3))
					icon.draw_arc(Vector2(0, 0), 14, 0, TAU, 32, Color(0.2, 0.9, 0.3), 3.0)
					icon.draw_rect(Rect2(-8, -12, 16, 24), Color(0.1, 0.6, 0.2))
					icon.draw_circle(Vector2(0, 0), 6, Color(0.3, 1.0, 0.4))
				else:
					# Draw treasure chest (for regular nodes or unvisited exits)
					icon.draw_rect(Rect2(-10, -8, 20, 16), Color(0.7, 0.5, 0.2))
					icon.draw_line(Vector2(-10, 0), Vector2(10, 0), Color(0.9, 0.8, 0.3), 2.0)
					icon.draw_rect(Rect2(-3, -3, 6, 6), Color(0.9, 0.8, 0.3))
	)
	icon.queue_redraw()

	return icon_area

func setup_player():
	print("Setting up player at home node: ", home_node_idx)

	# Create player sprite
	player_sprite = Sprite2D.new()
	var texture = load("res://assets/sprites/corvette.svg")
	player_sprite.texture = texture
	player_sprite.scale = Vector2(0.5, 0.5)  # Scale down if needed
	add_child(player_sprite)

	# Start at home node
	player_current_node = home_node_idx
	if home_node_idx >= 0:
		player_sprite.position = network_nodes[home_node_idx]["position"]
		network_nodes[home_node_idx]["visited"] = true
		print("Player position: ", player_sprite.position)
		print("Player has ", network_nodes[home_node_idx]["connections"].size(), " connections")
		# Redraw to show updated state
		draw_network()
		create_node_icons()
	else:
		print("ERROR: home_node_idx is invalid!")

func _on_node_clicked(node_idx: int):
	# Check if this node is connected to current node
	if player_current_node < 0 or is_player_moving:
		return

	if node_idx in network_nodes[player_current_node]["connections"]:
		# Move player to this node
		move_player_to_node(node_idx)

func move_player_to_node(node_idx: int):
	is_player_moving = true
	var target_position = network_nodes[node_idx]["position"]

	# Calculate distance to determine animation duration
	var distance = player_sprite.position.distance_to(target_position)
	var duration = min(distance / 400.0, 1.0)  # Speed of 400 pixels/sec, max 1 second

	# Create tween for smooth movement
	var tween = create_tween()
	tween.tween_property(player_sprite, "position", target_position, duration)
	tween.finished.connect(func():
		is_player_moving = false
		player_current_node = node_idx
		# Mark this node as visited
		network_nodes[node_idx]["visited"] = true
		# Redraw to show exit portal and updated paths
		draw_network()
		create_node_icons()
	)

func _on_refresh_starmap():
	# Clear existing stars
	for star in stars:
		star.queue_free()
	stars.clear()

	# Clear network
	network_nodes.clear()
	for child in network_layer.get_children():
		child.queue_free()
	for child in icon_layer.get_children():
		child.queue_free()

	# Clear player
	if player_sprite:
		player_sprite.queue_free()
		player_sprite = null
	player_current_node = -1

	# Generate new starfield
	generate_starfield()

func _on_to_combat():
	get_tree().change_scene_to_file("res://scenes/Combat.tscn")

func _on_deck_builder():
	get_tree().change_scene_to_file("res://scenes/DeckBuilder.tscn")

func _on_toggle_parallel_paths():
	prevent_parallel_paths = not prevent_parallel_paths
	update_parallel_path_button()
	_on_refresh_starmap()

func update_parallel_path_button():
	if prevent_parallel_paths:
		parallel_path_button.text = "Prevent Parallel: ON"
	else:
		parallel_path_button.text = "Prevent Parallel: OFF"

# Control button handlers
func _on_columns_decrease():
	# Need at least 4 columns to support: home(0), 2-nodes(1), 3-nodes(2), end(3)
	num_columns = max(4, num_columns - 1)
	update_control_labels()
	_on_refresh_starmap()

func _on_columns_increase():
	num_columns = min(15, num_columns + 1)
	update_control_labels()
	_on_refresh_starmap()

func _on_min_rows_decrease():
	min_nodes_per_column = max(1, min_nodes_per_column - 1)
	# Ensure min doesn't exceed max
	if min_nodes_per_column > max_nodes_per_column:
		max_nodes_per_column = min_nodes_per_column
	update_control_labels()
	_on_refresh_starmap()

func _on_min_rows_increase():
	min_nodes_per_column = min(8, min_nodes_per_column + 1)
	update_control_labels()
	_on_refresh_starmap()

func _on_max_rows_decrease():
	max_nodes_per_column = max(min_nodes_per_column, max_nodes_per_column - 1)
	update_control_labels()
	_on_refresh_starmap()

func _on_max_rows_increase():
	max_nodes_per_column = min(8, max_nodes_per_column + 1)
	update_control_labels()
	_on_refresh_starmap()

func _on_min_dist_decrease():
	min_node_distance = max(50.0, min_node_distance - 25.0)
	# Ensure min doesn't exceed max
	if min_node_distance >= max_node_distance:
		min_node_distance = max_node_distance - 50.0
	update_control_labels()
	_on_refresh_starmap()

func _on_min_dist_increase():
	min_node_distance = min(max_node_distance - 50.0, min_node_distance + 25.0)
	update_control_labels()
	_on_refresh_starmap()

func _on_max_dist_decrease():
	max_node_distance = max(min_node_distance + 50.0, max_node_distance - 25.0)
	update_control_labels()
	_on_refresh_starmap()

func _on_max_dist_increase():
	max_node_distance = min(800.0, max_node_distance + 25.0)
	update_control_labels()
	_on_refresh_starmap()

func update_control_labels():
	columns_label.text = "Columns: " + str(num_columns)
	min_rows_label.text = "Min Rows: " + str(min_nodes_per_column)
	max_rows_label.text = "Max Rows: " + str(max_nodes_per_column)
	min_dist_label.text = "Min Dist: " + str(int(min_node_distance))
	max_dist_label.text = "Max Dist: " + str(int(max_node_distance))
