package hrt.prefab.fx;

@:structInit class SpawnValue {
	public var rid : Int;
	public var min : Value;
	public var max : Value;
}

@:structInit class ParamCurve {
	public var c1 : hrt.impl.Curve;
	public var c2 : hrt.impl.Curve;
	public var param : String; // FX parameter
}

enum Value {
	VZero;
	VConst(v: Float);
	// lerp(min, max, u)
	VRandom(rid: Int, min: Float, max: Float);
	// c(t), c with absolute values for keys
	VCurve(c: hrt.impl.Curve);
	// lerp(pc.c1(t), pc.c2(t), pc.param)
	VParamCurve(pc: ParamCurve);
	// lerp(lerp(fromMin, fromMax, u), lerp(toMin, toMax, u), c)
	VRandomCurve(rid: Int, pc: ParamCurve, fromMin: Float, fromMax: Float, toMin: Float, toMax: Float);
	// lerp(a(t), b(t), u), a and b with absolute values for keys
	VCurveRange(rid: Int, a: hrt.impl.Curve, b: hrt.impl.Curve);

	VVector(x: Value, y: Value, z: Value, ?w: Value);
	VHsl(h: Value, s: Value, l: Value, a: Value);
}
