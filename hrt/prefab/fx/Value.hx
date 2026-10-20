package hrt.prefab.fx;

/** One value per param mode, `u` a random in [0, 1] of the particle, one per slot `rid` **/
enum Value {
	VZero;
	VConst(v: Float);
	// lerp(min, max, u)
	VRandom(rid: Int, min: Float, max: Float);
	// lerp(from, to, c(t)), c with plain keys
	VCurve(c: Curve, from: Float, to: Float);
	// lerp(from, to, c(t)), c a blend or a remap by an FX parameter (`Evaluator.getParamCurve`)
	VParamCurve(c: Curve, from: Float, to: Float);
	// lerp(lerp(fromMin, fromMax, u), lerp(toMin, toMax, u), c(t)), c plain or by a parameter
	VRandomCurve(rid: Int, c: Curve, fromMin: Float, fromMax: Float, toMin: Float, toMax: Float);
	// lerp(lerp(aFrom, aTo, a(t)), lerp(bFrom, bTo, b(t)), u), a and b plain
	VCurveRange(rid: Int, a: Curve, aFrom: Float, aTo: Float, b: Curve, bFrom: Float, bTo: Float);

	VVector(x: Value, y: Value, z: Value, ?w: Value);
	VHsl(h: Value, s: Value, l: Value, a: Value);
}

/** A Spawn param component, read when a particle spawns: `min` alone when `rid` < 0, else lerp(min, max, u), both over the FX time **/
@:structInit class SpawnValue {
	public var rid : Int;
	public var min : Value;
	public var max : Value;
}
