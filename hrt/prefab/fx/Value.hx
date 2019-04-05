package hide.prefab.fx;

enum Value {
	VZero;
	VConst(v: Float);
	VCurve(c: Curve);
	VCurveScale(c: Curve, scale: Float);
	VRandom(idx: Int, scale: Value);
	VAdd(a: Value, b: Value);
	VMult(a: Value, b: Value);
	VVector(x: Value, y: Value, z: Value, ?w: Value);
	VHsl(h: Value, s: Value, l: Value, a: Value);
	VBool(v: Value);
	VInt(v: Value);
}
