package hrt.prefab.fx;

enum Value {
	VZero;
	VConst(v: Float);
	VCurve(c: Curve);
	// random(rid) * scale + add
	VRandom(rid: Int, scale: Float, add: Float);
	// a + (b - a) * t
	VLerp(a: Value, b: Value, t: Value);
	VEasing(e: Easing);
	// lerp(a.getVal(t), b.getVal(t), blendVar)
	VBlendCurves(a: Curve, b: Curve, blendVar: String);
	VParamRemap(a: Value, param: String);
	VValueRemap(v: Value, remap: Value);

	VVector(x: Value, y: Value, z: Value, ?w: Value);
	VHsl(h: Value, s: Value, l: Value, a: Value);
}
