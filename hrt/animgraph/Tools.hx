package hrt.animgraph;

class Tools {
	@:haxe.warning("-WInlineOptimizedField")

	// from https://theorangeduck.com/page/quaternion-weighted-average
	static public function weightedBlend(inRotations: Array<h3d.Quat>, inReference: h3d.Quat, inWeights: Array<Float>, outRotation: h3d.Quat) {
		outRotation.set(0,0,0,0);

		var mulRes = inline new h3d.Quat();

		var invRef = inline inReference.clone();
		invRef.conjugate();

		for (index => rotation in inRotations) {
			var weight = inWeights[index];

			inline mulRes.multiply(invRef, rotation);
			if (mulRes.w < 0) inline mulRes.negate();
			mulRes.w *= weight;
			mulRes.x *= weight;
			mulRes.y *= weight;
			mulRes.z *= weight;

			outRotation.w += mulRes.w;
			outRotation.x += mulRes.x;
			outRotation.y += mulRes.y;
			outRotation.z += mulRes.z;
		}

		outRotation.normalize();
		inline outRotation.multiply(inReference, outRotation);
		if (outRotation.w < 0) inline mulRes.negate();
	}


	static var workMatrix = new h3d.Matrix();
	static public function splitMatrix(inMatrix: h3d.Matrix, outMatrix: h3d.Matrix) {
		workMatrix.load(inMatrix);
		var scale = inline workMatrix.getScale();
		workMatrix.prependScale(1.0/scale.x, 1.0/scale.y, 1.0/scale.z);
		var quat = inline new h3d.Quat();
		inline quat.initRotateMatrix(workMatrix);

		outMatrix.zero();

		outMatrix._11 = scale.x;
		outMatrix._22 = scale.y;
		outMatrix._33 = scale.z;
		outMatrix._12 = quat.x;
		outMatrix._13 = quat.y;
		outMatrix._21 = quat.z;
		outMatrix._23 = quat.w;
		outMatrix.tx = inMatrix.tx;
		outMatrix.ty = inMatrix.ty;
		outMatrix.tz = inMatrix.tz;
	}
}