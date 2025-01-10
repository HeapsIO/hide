package hrt.animgraph;

class Tools {

	// from https://theorangeduck.com/page/quaternion-weighted-average
	@:haxe.warning("-WInlineOptimizedField")
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

	/**
		Decompose a 3d matrix so the rotation quaternion is stored in [m12,m13,m21,m23] instead of mixed with the scale
	**/
	@:haxe.warning("-WInlineOptimizedField")
	static public function decomposeMatrix(inMatrix: h3d.Matrix, outMatrix: h3d.Matrix) {
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

	/**
		Transform a decomposed matrix into a normal one
	**/
	@:haxe.warning("-WInlineOptimizedField")
	static public function recomposeMatrix(inMatrix: h3d.Matrix, outMatrix: h3d.Matrix) {
		var quat = inline new h3d.Quat(inMatrix._12, inMatrix._13, inMatrix._21, inMatrix._23);
		inline quat.toMatrix(outMatrix);

		outMatrix._11 *= inMatrix._11;
		outMatrix._12 *= inMatrix._11;
		outMatrix._13 *= inMatrix._11;
		outMatrix._21 *= inMatrix._22;
		outMatrix._22 *= inMatrix._22;
		outMatrix._23 *= inMatrix._22;
		outMatrix._31 *= inMatrix._33;
		outMatrix._32 *= inMatrix._33;
		outMatrix._33 *= inMatrix._33;

		outMatrix._41 = inMatrix._41;
		outMatrix._42 = inMatrix._42;
		outMatrix._43 = inMatrix._43;
	}
}