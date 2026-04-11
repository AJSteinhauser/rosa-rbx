local function vector3ToPosition(vec: Vector3)
	return {
		x = vec.X,
		y = vec.Y,
		z = vec.Z,
	}
end

return {
	vector3ToPosition = vector3ToPosition,
}
