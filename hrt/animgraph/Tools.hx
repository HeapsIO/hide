package hrt.animgraph;

class Tools {

	@:haxe.warning("-WInlineOptimizedField")
	static public function weightedBlend(inRotations: Array<h3d.Quat>, inReference: h3d.Quat, inWeights: Array<Float>, outRotation: h3d.Quat) {
		outRotation.set(0,0,0,0);

		var mulRes = inline new h3d.Quat();

		for (index => rotation in inRotations) {
			var weight = inWeights[index];

			var invRef = inline inReference.clone();
			invRef.conjugate();
			inline mulRes.multiply(invRef, rotation);
			if (mulRes.w < 0) inline mulRes.negate();
			mulRes.w *= weight;
			mulRes.x *= weight;
			mulRes.y *= weight;
			mulRes.z *= weight;

			outRotation.w += mulRes.w * weight;
			outRotation.x += mulRes.x * weight;
			outRotation.y += mulRes.y * weight;
			outRotation.z += mulRes.z * weight;
		}

		outRotation.normalize();
		inline outRotation.multiply(inReference, outRotation);
		if (outRotation.w < 0) outRotation.conjugate();
	}
}