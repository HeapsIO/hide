package hrt.animgraph.nodes;

class Blend extends AnimNode {
	@:input var a : AnimNode;
	@:input var b : AnimNode;
	@:input var alpha : Float = 0.5;

	var tempMatrix: h3d.Matrix = new h3d.Matrix();

	@:haxe.warning("-WInlineOptimizedField")
	override function getBoneTransform(boneId:Int, outMatrix:h3d.Matrix, ctx: AnimNode.GetBoneTransformContext) {
		if (a != null) {
			var sourceBoneId = boneIdToAnimInputBone[getInputBoneId(boneId, 0)];
			if (sourceBoneId != -1) {
				a.getBoneTransform(sourceBoneId, tempMatrix, ctx);
			} else {
				tempMatrix.load(ctx.getDefPose());
			}
		} else {
			tempMatrix.load(ctx.getDefPose());
		}

		if (b != null) {
			var sourceBoneId = boneIdToAnimInputBone[getInputBoneId(boneId, 1)];
			if (sourceBoneId != -1) {
				b.getBoneTransform(sourceBoneId, outMatrix, ctx);
			} else {
				outMatrix.load(ctx.getDefPose());
			}
		}

		var m1 = tempMatrix;
		var m2 = outMatrix;

		var q1 = inline new h3d.Quat(m1._12, m1._13, m1._21, m1._23);
		var q2 = inline new h3d.Quat(m2._12, m2._13, m2._21, m2._23);

		var alphaClamped = hxd.Math.clamp(alpha);
		inline q1.lerp(q1, q2, alphaClamped, true);
		inline q1.normalize();
		outMatrix._12 = q1.x;
		outMatrix._13 = q1.y;
		outMatrix._21 = q1.z;
		outMatrix._23 = q1.w;

		var a = (1.0-alphaClamped);
		var b = (alphaClamped);

		var x = m1._41 * a + m2._41 * b;
		var y = m1._42 * a + m2._42 * b;
		var z = m1._43 * a + m2._43 * b;

		outMatrix._41 = x;
		outMatrix._42 = y;
		outMatrix._43 = z;

		outMatrix._11 = m1._11 * a + m2._11 * b;
		outMatrix._22 = m1._22 * a + m2._22 * b;
		outMatrix._33 = m1._33 * a + m2._33 * b;
	}

	override function setupAnimEvents() {
		a.onEvent = (name:String) -> {
			if (alpha < 0.5) onEvent(name);
		}
		b.onEvent = (name:String) -> {
			if (alpha > 0.5) onEvent(name);
		}
	}

	#if editor
	override function getSize():Int {
		return Node.SIZE_SMALL;
	}
	#end
}