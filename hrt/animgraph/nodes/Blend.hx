package hrt.animgraph.nodes;

class Blend extends AnimNode {
	@:input var a : AnimNode;
	@:input var b : AnimNode;
	@:input var alpha : Float = 0.5;

	var tempMatrix: h3d.Matrix = new h3d.Matrix();
	override function getBoneTransform(boneId:Int, outMatrix:h3d.Matrix) {
		if (a != null) {
			var sourceBoneId = boneIdToAnimInputBone[getInputBoneId(boneId, 0)];
			if (sourceBoneId != -1) {
				a.getBoneTransform(sourceBoneId, tempMatrix);
			} else {
				tempMatrix = @:privateAccess h3d.anim.SmoothTransition.MZERO;
			}
		}
		if (b != null) {
			var sourceBoneId = boneIdToAnimInputBone[getInputBoneId(boneId, 1)];
			if (sourceBoneId != -1) {
				b.getBoneTransform(sourceBoneId, outMatrix);
			} else {
				outMatrix.load(@:privateAccess h3d.anim.SmoothTransition.MZERO);
			}
		}

		var m1 = tempMatrix;
		var m2 = outMatrix;

		var q1 = inline new h3d.Quat(m1._12, m1._13, m1._21, m1._23);
		var q2 = inline new h3d.Quat(m2._12, m2._13, m2._21, m2._23);


		inline q1.lerp(q1, q2, alpha, true);
		inline q1.normalize();
		outMatrix._12 = q1.x;
		outMatrix._13 = q1.y;
		outMatrix._21 = q1.z;
		outMatrix._23 = q1.w;

		var x = m1._41 * alpha + m2._41 * (1-alpha);
		var y = m1._42 * alpha + m2._42 * (1-alpha);
		var z = m1._43 * alpha + m2._43 * (1-alpha);

		m1._41 = x;
		m1._42 = y;
		m1._43 = z;
	}

	override function getSize():Int {
		return Node.SIZE_SMALL;
	}
}