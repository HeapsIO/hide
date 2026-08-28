package hrt.prefab.fx;

enum Value {
	// fast flat values
	VZero;
	VConst(v: Float);
	VCurve(c: Curve);
	// c * scale + add
	VCurveT(c: Curve, scale: Float, add: Float);
	// random(rid) * scale + add
	VRandom(rid: Int, scale: Float, add: Float);
	// (random(rid) * scale + add) * c
	VRandMultCurve(rid: Int, scale: Float, add: Float, c: Curve);  
	// random(rid) * scale + add + c
	VRandAddCurve(rid: Int, scale: Float, add: Float, c: Curve);  
	// lerp(a.getVal(t), b.getVal(t), blendVar) * scale + add
	VBlendCurves(scale: Float, add: Float, a: Curve, b: Curve, blendVar: String);
	// (random(rid) * scale + add) * lerp(a.getVal(t), b.getVal(t), blendVar)
	VRandomBlendCurves(rid: Int, scale: Float, add: Float, a: Curve, b: Curve, blendVar: String);
	// lerp(a.getVal(t), b.getVal(t), (random(rid)+1)/2)
	VRandomBetweenCurves(rid: Int, a: Curve, b: Curve);  

	// rare complex values that we cannot currently optimize
	VParamRemap(a: Value, param: String);
	VValueRemap(v: Value, remap: Value);
	VAdd(a: Value, b: Value);
	VMult(a: Value, b: Value);

	VVector(x: Value, y: Value, z: Value, ?w: Value);
	VHsl(h: Value, s: Value, l: Value, a: Value);
}
