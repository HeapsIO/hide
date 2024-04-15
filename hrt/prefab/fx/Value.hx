package hrt.prefab.fx;

enum Value {
	VZero;
	VOne;
	VConst(v: Float);
	VCurve(c: Curve);
	VBlend(a: Value, b: Value, blendVar: String);
	VRandomBetweenCurves(idx: Int, c: Curve);
	VCurveScale(c: Curve, scale: Float);
	VRandom(idx: Int, scale: Value);
	VRandomScale(idx: Int, scale: Float);
	VAddRandCurve(cst: Float, ridx: Int, rscale: Float, c: Curve);
	VAdd(a: Value, b: Value);
	VMult(a: Value, b: Value);
	VVector(x: Value, y: Value, z: Value, ?w: Value);
	VHsl(h: Value, s: Value, l: Value, a: Value);
	VBool(v: Value);
	VInt(v: Value);
}
