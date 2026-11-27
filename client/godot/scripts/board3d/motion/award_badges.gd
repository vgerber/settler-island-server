class_name AwardBadges
extends MotionLayer
## The longest road and largest army badges: when an award changes hands the badge flies from the stand of the
## old holder (the deck when nobody held it) to the stand of the new one (the deck when nobody holds it any more).

const FLIGHT_SECONDS := 0.6
const APEX := 0.8
const SPIN_TURNS := 1.0
const LIFT := 0.12

var _road := _badge(AwardArt.road())
var _army := _badge(AwardArt.army())
var _flying: Array[MeshInstance3D] = []


func _init() -> void:
	name = "AwardBadges"
	add_child(_road)
	add_child(_army)


## Badges in the air now, for tests.
func badges_in_air() -> int:
	return _flying.size()


func finish_all() -> void:
	super.finish_all()
	for badge in _flying:
		badge.visible = false
	_flying.clear()


func road(event: SiEventLongestRoadChanged) -> void:
	_fly(_road, player.shown_view.longest_road, event.holder)


func army(event: SiEventLargestArmyChanged) -> void:
	_fly(_army, player.shown_view.largest_army, event.holder)


func _fly(badge: MeshInstance3D, previous: Variant, holder: Variant) -> void:
	if previous == holder or _flying.has(badge):
		return
	var from := _end(previous)
	var to := _end(holder)
	badge.visible = true
	_flying.append(badge)
	var tween := _tween()
	tween.tween_method(_move.bind(badge, from, to), 0.0, 1.0, FLIGHT_SECONDS)
	tween.tween_callback(_land.bind(badge))


func _end(seat: Variant) -> Vector3:
	var point := layout.deck_point() if seat == null else layout.seat_point(int(seat))
	return point + Vector3(0.0, LIFT, 0.0)


func _move(progress: float, badge: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var flat := from.lerp(to, smoothstep(0.0, 1.0, progress))
	badge.position = Vector3(flat.x, flat.y + APEX * sin(progress * PI), flat.z)
	badge.rotation.y = TAU * SPIN_TURNS * progress


func _land(badge: MeshInstance3D) -> void:
	badge.visible = false
	_flying.erase(badge)


static func _badge(mesh: Mesh) -> MeshInstance3D:
	var badge := MeshInstance3D.new()
	badge.mesh = mesh
	badge.material_override = ClayMaterials.terrain()
	badge.visible = false
	return badge
