extends RefCounted
class_name CardinalXRHandInput

# Joint data comes from OpenXR's optical tracker; inferred controller hands
# keep using action-map inputs instead of synthesizing pinch gestures.
const CLOSE_DISTANCE := 0.025
const OPEN_DISTANCE := 0.040
const REQUIRED := [XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_THUMB_TIP, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL]
var pinched := false
var armed := false

func reset() -> void:
	pinched = false
	armed = false

func sample(tracker: XRHandTracker) -> Dictionary:
	if tracker == null or not tracker.has_tracking_data or tracker.hand_tracking_source in [XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER, XRHandTracker.HAND_TRACKING_SOURCE_NOT_TRACKED]:
		reset()
		return {}
	var points := {}
	for joint in range(XRHandTracker.HAND_JOINT_MAX):
		var flags := tracker.get_hand_joint_flags(joint)
		if flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID and flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED:
			var point := tracker.get_hand_joint_transform(joint).origin
			if point.is_finite(): points[joint] = point
	for joint in REQUIRED:
		if not points.has(joint):
			reset()
			return {}
	var thumb: Vector3 = points[XRHandTracker.HAND_JOINT_THUMB_TIP]
	var index: Vector3 = points[XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP]
	var knuckle: Vector3 = points[XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL]
	var wrist: Vector3 = points[XRHandTracker.HAND_JOINT_WRIST]
	var direction := knuckle - wrist
	if direction.length_squared() < 0.00001:
		reset()
		return {}
	var separation := thumb.distance_to(index)
	# Tracking recovered with fingers touching must not press a fresh control.
	if not armed:
		if separation > OPEN_DISTANCE: armed = true
		pinched = false
	elif pinched:
		pinched = separation < OPEN_DISTANCE
	else:
		pinched = separation < CLOSE_DISTANCE
	return {"origin": knuckle, "direction": direction.normalized(), "position": wrist, "pressed": pinched, "points": points}
