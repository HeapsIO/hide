package hrt.prefab.fx;

/** A curve shape over time **/
enum CurveShape {
	ShCurve(c: Curve);
	ShEasing(e: Easing);
	// lerp(a, b, parameter)
	ShBlend(a: Curve, b: Curve, param: String);
	// the shape at the value of a parameter
	ShParamRemap(s: CurveShape, param: String);
	// the shape at the time `remap` gives
	ShValueRemap(s: CurveShape, remap: Value);
}

/** One value per param mode, `u` a random in [0, 1] of the particle, one per slot `rid` **/
enum Value {
	VZero;
	VConst(v: Float);
	// lerp(min, max, u)
	VRandom(rid: Int, min: Float, max: Float);
	// lerp(from, to, s(t))
	VCurve(s: CurveShape, from: Float, to: Float);
	// lerp(lerp(fromMin, fromMax, u), lerp(toMin, toMax, u), s(t))
	VRandomCurve(rid: Int, s: CurveShape, fromMin: Float, fromMax: Float, toMin: Float, toMax: Float);
	// lerp(a, b, u)
	VCurveRange(rid: Int, a: Value, b: Value);

	VVector(x: Value, y: Value, z: Value, ?w: Value);
	VHsl(h: Value, s: Value, l: Value, a: Value);
}
