package hrt.animgraph.nodes;
using hrt.tools.MapUtils;

typedef BlendSpaceInstancePoint = {
	x: Float,
	y: Float,
	?animInfo: AnimInfo,
}

typedef AnimInfo = {
	anim: h3d.anim.Animation,
	proxy: hrt.animgraph.nodes.Input.AnimProxy,
	indexRemap: Array<Int>,
}

@:access(hrt.animgraph.BlendSpace2D)
class BlendSpace2D extends AnimNode {
	@:input var bsX(default, set): Float = 0.5;
	@:input var bsY(default, set): Float = 0.5;

	@:s var path : String = "AnimGraph/blendSpaceOgreLocomotion.blendspace2d";

	var dirtyPos: Bool = true;

	function set_bsX(v: Float) : Float {
		if (v != bsX)
			currentTriangle = -1;
		return bsX = v;
	}

	function set_bsY(v: Float) : Float {
		if (v != bsY)
			currentTriangle = -1;
		return bsY = v;
	}

	var currentTriangle : Int = -1;
	var weights : Array<Float> = [1.0,0.0,0.0];

	var animInfos: Array<AnimInfo> = [];
	var points : Array<BlendSpaceInstancePoint> = [];
	var triangles : Array<Array<BlendSpaceInstancePoint>> = [];
	var blendSpace : hrt.animgraph.BlendSpace2D;

	var workQuat = new h3d.Quat();
	var workQuats : Array<h3d.Quat> = [new h3d.Quat(), new h3d.Quat(), new h3d.Quat()];
	var refQuat = new h3d.Quat();

	override function getBones(ctx: hrt.animgraph.nodes.AnimNode.GetBoneContext):Map<String, Int> {
		var boneMap : Map<String, Int> = [];
		animInfos = [];
		points = [];
		triangles = [];
		currentTriangle = -1;

		var curOurBoneId = 0;

		if (blendSpace == null) {
			blendSpace = cast hxd.res.Loader.currentInstance.load(path).toPrefab().load();
		}

		// only one animation is created per anim path, so if multiple points use the same anim, only one instance is created
		var animMap : Map<String, Int> = [];

		for (blendSpacePoint in blendSpace.points) {
			var point : BlendSpaceInstancePoint = {x: blendSpacePoint.x, y: blendSpacePoint.y};
			try
			{
				var animIndex = animMap.getOrPut(blendSpacePoint.animPath, {
					// Create a new animation
					var index = animInfos.length;
					var animBase = hxd.res.Loader.currentInstance.load(blendSpacePoint.animPath).toModel().toHmd().loadAnimation();

					var proxy = new hrt.animgraph.nodes.Input.AnimProxy(null);
					var animInstance = animBase.createInstance(proxy);

					var indexRemap = [];

					for (boneId => obj in animInstance.getObjects()) {
						var ourId = boneMap.getOrPut(obj.objectName, curOurBoneId++);
						indexRemap[ourId] = boneId;
					}

					animInfos.push({anim: animInstance, proxy: proxy, indexRemap: indexRemap});
					index;
				});

				point.animInfo = animInfos[animIndex];
			} catch (e) {
				trace('Couldn\'t load anim ${blendSpacePoint.animPath} : ${e.toString()}');
			}
			points.push(point);
		}

		for (blendSpaceTriangle in blendSpace.triangles) {
			var triangle : Array<BlendSpaceInstancePoint> = [];
			for (i => index in blendSpaceTriangle) {
				triangle[i] = points[index];
			}
			triangles.push(triangle);
		}

		for (info in animInfos) {
			for (i in 0...curOurBoneId) {
				if(info.indexRemap[i] == null) {
					info.indexRemap[i] = -1;
				}
			}
		}

		return boneMap;
	}

	override function tick(dt:Float) {
		super.tick(dt);

		trace(bsX, bsY);
		for (animInfo in animInfos) {
			animInfo.anim.update(dt);
			@:privateAccess animInfo.anim.isSync = false;
		}
	}

	@:haxe.warning("-WInlineOptimizedField")
	override function getBoneTransform(boneId:Int, outMatrix:h3d.Matrix, ctx:hrt.animgraph.nodes.AnimNode.GetBoneTransformContext) {
		if (currentTriangle == -1) {
			var curPos = inline new h2d.col.Point(bsX, bsY);

			// find the triangle our curPos resides in
			var collided = false;
			for (triIndex => tri in triangles) {
				var colTri = inline new h2d.col.Triangle(inline new h2d.col.Point(tri[0].x, tri[0].y), inline new h2d.col.Point(tri[1].x, tri[1].y), inline new h2d.col.Point(tri[2].x, tri[2].y));
				if (inline colTri.contains(curPos)) {
					var bary = inline colTri.barycentric(curPos);
					currentTriangle = triIndex;
					weights[0] = bary.x;
					weights[1] = bary.y;
					weights[2] = bary.z;
					collided = true;
					break;
				}
			}

			var debugk = 0.0;
			// We are outside all triangles, find the closest edge
			if (currentTriangle == -1) {

				var closestDistanceSq : Float = hxd.Math.POSITIVE_INFINITY;

				for (triIndex => tri in triangles) {
					for (i in 0...3) {
						var i2 = (i+1) % 3;
						var p1 = tri[i];
						var p2 = tri[i2];

						var dx = p2.x - p1.x;
						var dy = p2.y - p1.y;
						var k = ((curPos.x - p1.x) * dx + (curPos.y - p1.y) * dy) / (dx * dx + dy * dy);
						k = hxd.Math.clamp(k, 0, 1);
						var mx = dx * k + p1.x - curPos.x;
						var my = dy * k + p1.y - curPos.y;
						var dist2SegmentSq = mx * mx + my * my;

						if (dist2SegmentSq < closestDistanceSq) {
							closestDistanceSq = dist2SegmentSq;
							currentTriangle = triIndex;

							debugk = k;

							weights[i] = 1.0 - k;
							weights[(i + 1) % 3] = k;
							weights[(i + 2) % 3] = 0.0;
						}
					}
				}
			}

			if (currentTriangle == -1)
				throw "assert";


			trace(bsX, bsY, weights, weights[0] + weights[1] + weights[2], currentTriangle, collided, debugk);
		}

		var blendedPos = inline new h3d.Vector();
		var blendedRot = inline new h3d.Quat();
		var blendedScale = inline new h3d.Vector();

		var triangle = triangles[currentTriangle];
		var def = ctx.getDefPose();
		refQuat.set(def._12, def._13, def._21, def._23);
		for (ptIndex => point in triangle) {
			@:privateAccess
			if (!point.animInfo.anim.isSync) {
				point.animInfo.anim.sync(true);
				point.animInfo.anim.isSync = true;
			}
			var boneIndex = point.animInfo.indexRemap[boneId];
			var matrix = if (boneIndex == -1 || point.animInfo.anim == null) {
				def;
			} else {
				point.animInfo.anim.getObjects()[boneIndex].targetObject.defaultTransform;
			}

			var w =  weights[ptIndex];
			if (w == 0) {
				continue;
			}
			blendedPos = inline blendedPos.add(inline new h3d.Vector(matrix.tx * w, matrix.ty * w, matrix.tz * w));
			blendedScale = inline blendedScale.add(inline new h3d.Vector(matrix._11 * w, matrix._22 * w, matrix._33 * w));
			workQuats[ptIndex].set(matrix._12, matrix._13, matrix._21, matrix._23);
		}

		Tools.weightedBlend(workQuats, refQuat, weights, workQuat);


		outMatrix.tx = blendedPos.x;
		outMatrix.ty = blendedPos.y;
		outMatrix.tz = blendedPos.z;

		outMatrix._11 = blendedScale.x;
		outMatrix._22 = blendedScale.y;
		outMatrix._33 = blendedScale.z;

		outMatrix._12 = workQuat.x;
		outMatrix._13 = workQuat.y;
		outMatrix._21 = workQuat.z;
		outMatrix._23 = workQuat.w;
	}
}