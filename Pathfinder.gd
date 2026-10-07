extends Node2D

var cell_size := 16
var jumpHeight := 2
var jumpDistance := 2

var tileMap
var graph

var showLines := true

const TEST = preload("res://face.tscn")

# --- Caches ---
var _used_cells := {}          # Dictionary for O(1) membership
var _points := []             # graph points ids list
var _pos_by_id := {}          # id -> Vector2 position
var _celltype_cache := {}    # key -> Vector2 or null

func _ready():
	graph = AStar2D.new()
	tileMap = find_parent("Master").find_node("Map")

	# Cache used cells once
	var cells = tileMap.get_used_cells()
	_used_cells.clear()
	for c in cells:
		_used_cells[c] = true

	createMap()
	createConections()
	# Cache point lists after connections
	_cache_graph_points()

func _cache_graph_points():
	_points = graph.get_points()
	_pos_by_id.clear()
	for id in _points:
		_pos_by_id[id] = graph.get_point_position(id)

func _celltype_key(pos: Vector2, global: bool, isAbove: bool) -> String:
	# pos is expected in map coordinates unless global=true.
	# If global=true, it will be converted before keying.
	return "%s|%s|%s" % [str(pos), str(global), str(isAbove)]

func cellType(pos, global := false, isAbove := false):
	# Convert global to map coordinates
	if global:
		pos = tileMap.world_to_map(pos)

	if isAbove:
		pos += Vector2.DOWN

	var key := _celltype_key(pos, false, false) # after conversion, global/isAbove already applied
	if _celltype_cache.has(key):
		return _celltype_cache[key]

	# Early: if block exists above, invalid
	if _used_cells.has(pos + Vector2.UP):
		_celltype_cache[key] = null
		return null

	var results := Vector2.ZERO

	# Left check
	if _used_cells.has(pos + Vector2.UP + Vector2.LEFT):
		results[0] = 1
	elif !_used_cells.has(pos + Vector2.LEFT):
		results[0] = -1

	# Right check
	if _used_cells.has(pos + Vector2.UP + Vector2.RIGHT):
		results[1] = 1
	elif !_used_cells.has(pos + Vector2.RIGHT):
		results[1] = -1

	_celltype_cache[key] = results
	return results

func createPoint(cell):
	var above := Vector2(cell[0], cell[1] - 1)
	var pos := tileMap.map_to_world(above) + Vector2(cell_size / 2, cell_size / 2)

	# Your duplicate check is expensive-ish because it calls get_closest_point(pos)
	# but it's okay. We'll keep it to preserve behavior.
	if graph.get_points().size() > 0:
		var closest_id = graph.get_closest_point(pos)
		if graph.get_point_position(closest_id) == pos:
			return

	if showLines:
		var test = TEST.instance()
		test.set_position(pos)
		call_deferred("add_child", test)

	graph.add_point(graph.get_available_point_id(), pos)

func createMap():
	var space_state = get_world_2d().direct_space_state
	var cells_array = tileMap.get_used_cells()

	for cell in cells_array:
		var stat = cellType(cell)
		if stat and stat != Vector2(0, 0):
			createPoint(cell)

			# Raycast “landing” points when there's a drop
			if stat[1] == -1:
				var pos := tileMap.map_to_world(Vector2(cell[0] + 1, cell[1]))
				var pto := Vector2(pos[0], pos[1] + 1000)
				var result = space_state.intersect_ray(pos, pto)
				if result:
					createPoint(tileMap.world_to_map(result.position))

			if stat[0] == -1:
				var pos := tileMap.map_to_world(Vector2(cell[0] - 1, cell[1]))
				var pto := Vector2(pos[0], pos[1] + 1000)
				var result = space_state.intersect_ray(pos, pto)
				if result:
					createPoint(tileMap.world_to_map(result.position))

func createConections():
	# Use cached points list
	var points = graph.get_points()
	# Optional: clear cache for cellType between phases if needed
	# _celltype_cache.clear()

	for point in points:
		var closestRight := -1
		var closestLeftDrop := -1
		var closestRightDrop := -1

		var pos := graph.get_point_position(point)
		var stat = cellType(pos, true, true)
		if stat == null:
			continue

		var pointsToJoin := []
		var noBiJoin := []

		for newPoint in points:
			if newPoint == point:
				continue

			var newPos := graph.get_point_position(newPoint)

			# If current supports standing on surface edge (your stat[1]==0 case)
			if stat[1] == 0:
				if newPos[1] == pos[1] and newPos[0] > pos[0]:
					if closestRight < 0 or newPos[0] < graph.get_point_position(closestRight)[0]:
						closestRight = newPoint

			# Left drop/jump rules
			if stat[0] == -1:
				if newPos[0] == pos[0] - cell_size and newPos[1] > pos[1]:
					if closestLeftDrop < 0 or newPos[1] < graph.get_point_position(closestLeftDrop)[1]:
						closestLeftDrop = newPoint

				if newPos[1] >= pos[1] - (cell_size * jumpHeight) and newPos[1] <= pos[1] and \
					newPos[0] > pos[0] - (cell_size * (jumpDistance + 2)) and newPos[0] < pos[0] and \
					cellType(newPos, true, true)[1] == -1:
					pointsToJoin.append(newPoint)

			# Right drop/jump rules
			if stat[1] == -1:
				if newPos[0] == pos[0] + cell_size and newPos[1] > pos[1]:
					if closestRightDrop < 0 or newPos[1] < graph.get_point_position(closestRightDrop)[1]:
						closestRightDrop = newPoint

				if newPos[1] >= pos[1] - (cell_size * jumpHeight) and newPos[1] <= pos[1] and \
					newPos[0] < pos[0] + (cell_size * (jumpDistance + 2)) and newPos[0] > pos[0] and \
					cellType(newPos, true, true)[0] == -1:
					pointsToJoin.append(newPoint)

		if closestRight > 0:
			pointsToJoin.append(closestRight)

		if closestLeftDrop > 0:
			if graph.get_point_position(closestLeftDrop)[1] <= pos[1] + (cell_size * jumpHeight):
				pointsToJoin.append(closestLeftDrop)
			else:
				noBiJoin.append(closestLeftDrop)

		if closestRightDrop > 0:
			if graph.get_point_position(closestRightDrop)[1] <= pos[1] + (cell_size * jumpHeight):
				pointsToJoin.append(closestRightDrop)
			else:
				noBiJoin.append(closestRightDrop)

		for joinPoint in pointsToJoin:
			graph.connect_points(point, joinPoint)

		for joinPoint in noBiJoin:
			graph.connect_points(point, joinPoint, false)

	_cache_graph_points()
	update()

func _draw():
	if !showLines:
		return

	# Instead of recomputing pair rules (O(N²)), just draw existing edges.
	# AStar2D doesn't expose “all edge list” directly in a super clean way,
	# but we can iterate points and their connected ids.
	var points = _points

	for point in points:
		var pos = _pos_by_id[point]
		var connections = graph.get_point_connections(point) # Godot 4 has get_point_connections in AStar2D
		if connections == null:
			continue

		for joinPoint in connections:
			# Color heuristic:
			# You previously used red for bi-directional default connect_points(...)
			# and green for connect_points(..., false).
			# Godot AStar2D stores bidirectional? If your Godot version supports:
			# we’d need edge direction info. If not available, pick one color.
			# For simplicity, draw all edges in red here.
			# (If you want, tell me your Godot version and I’ll adapt coloring.)
			draw_line(pos, _pos_by_id[joinPoint], Color(255, 0, 0), 1)

func findPath(start, end):
	var first_point = graph.get_closest_point(start)
	var finish = graph.get_closest_point(end)
	var path = graph.get_id_path(first_point, finish)

	if path.size() == 0:
		return path

	var actions = []
	var lastPos

	for point in path:
		var pos = graph.get_point_position(point)
		var stat = cellType(pos, true, true)

		if lastPos and lastPos[1] >= pos[1] - (cell_size * jumpHeight) and \
			((lastPos[0] < pos[0] and stat[0] < 0) or (lastPos[0] > pos[0] and stat[1] < 0)):
			actions.append(null)

		lastPos = pos

		if point == path[0] and path.size() > 1:
			var nextPos = graph.get_point_position(path[1])
			if start.distance_to(nextPos) > pos.distance_to(nextPos):
				actions.append(pos)

		elif point == path[-1] and path.size() > 1:
			if graph.get_point_position(path[-2]).distance_to(end) < pos.distance_to(end):
				actions.append(pos)

		else:
			actions.append(pos)

	actions.append(end)
	return actions
