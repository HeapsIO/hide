package hrt.animgraph.anim;
import hrt.tools.MapUtils;

typedef BlendSpaceInstancePoint = {
	x: Float,
	y: Float,
	speed: Float,
	?animInfo: AnimInfo, // can be null if no animation could be loaded
}

typedef AnimInfo = {
	anim: h3d.anim.Animation,
	proxy: hrt.animgraph.nodes.Input.AnimProxy,
	keepSync: Bool,
	selfSpeed: Float,
	selfTime: Float,
	objects: Array<BlendSpaceObject>,
}

class BlendSpaceObject extends h3d.anim.Animation.AnimatedObject {
	public var matrices : Array<h3d.Matrix> = [];
	public var outMatrix = new h3d.Matrix();
	public var defaultMatrix = new h3d.Matrix();
	public var touchedThisFrame = false;
}

@:access(hrt.animgraph.BlendSpace2D)
class BlendSpace2D2 extends h3d.anim.Animation {
	public var x(default, set): Float = 0.5;
	var realX : Float = 0.5;
	var vX : Float = 0.0;

	public var y(default, set): Float = 0.5;
	var realY : Float = 0.5;
	var vY : Float = 0.0;

	var blendSpace : hrt.animgraph.BlendSpace2D;
	var animSet : Map<String, String>;

	var dirtyPos: Bool = true;

	var syncAnimTime: Float;

	var prevAnimEventBind : h3d.anim.Animation;
	static var tmpMatrix = new h3d.Matrix();

	function set_x(v: Float) : Float {
		if (v != x)
			currentTriangle = -1;
		return x = v;
	}

	function set_y(v: Float) : Float {
		if (v != y)
			currentTriangle = -1;
		return y = v;
	}

	function getBSObjects() : Array<BlendSpaceObject> {
		return cast objects;
	}

	var currentTriangle : Int = -1;
	var weights : Array<Float> = [1.0,0.0,0.0];
	var currentAnimLenght = 1.0;

	var animInfos: Array<AnimInfo> = [];
	var points : Array<BlendSpaceInstancePoint> = [];
	var triangles : Array<Array<BlendSpaceInstancePoint>> = [];

	var workQuat = new h3d.Quat();
	var workQuats : Array<h3d.Quat> = [new h3d.Quat(), new h3d.Quat(), new h3d.Quat()];
	var refQuat = new h3d.Quat();
	var modelCache : h3d.prim.ModelCache;

	public function new(blendSpace: hrt.animgraph.BlendSpace2D, animSet: Map<String, String>, modelCache: h3d.prim.ModelCache) {
		this.blendSpace = blendSpace;
		this.animSet = animSet;
		this.modelCache = modelCache;
		super(blendSpace.name, 100, 1/60.0);
	}

	public function resetSmooth() {
		realX = x;
		realY = y;
		vX = 0.0;
		vY = 0.0;
	}

	override function bind(object: h3d.scene.Object) {
		animInfos = [];
		points = [];
		triangles = [];
		currentTriangle = -1;
		objects = [];

		resetSmooth();

		var curOurBoneId = 0;

		if (blendSpace == null)
			throw "Can't bind with a null blendSpace";

		// only one animation is created per anim path, so if multiple points use the same anim, only one instance is created
		var animMap : Map<String, Int> = [];
		var allObjects : Map<String, BlendSpaceObject> = [];

		for (blendSpacePoint in blendSpace.points) {
			var point : BlendSpaceInstancePoint = {x: blendSpacePoint.x, y: blendSpacePoint.y, speed: blendSpacePoint.speed};
			if (blendSpacePoint.animPath != null && blendSpacePoint.animPath.length > 0) {
				try
				{
					var path = animSet.get(blendSpacePoint.animPath);
					if (path == null) {
						if (StringTools.endsWith(blendSpacePoint.animPath, ".fbx")) {
							path = blendSpacePoint.animPath;
						}
					}
					if (path != null) {

						function makeAnim() : Int {
							// Create a new animation
							var index = animInfos.length;
							var animModel = hxd.res.Loader.currentInstance.load(path).toModel();
							var animBase = modelCache.loadAnimation(animModel);
							var proxy = new hrt.animgraph.nodes.Input.AnimProxy(null);
							var animInstance = animBase.createInstance(proxy);

							animInstance.bind(object);

							var animObjects = [];
							for (obj in animInstance.getObjects()) {
								var o = MapUtils.getOrPut(allObjects, obj.objectName, {
									var o = new BlendSpaceObject(obj.objectName);
									o.targetJoint = obj.targetJoint;
									o.targetSkin = obj.targetSkin;
									o.targetObject = obj.targetObject;

									@:privateAccess
									if (o.targetSkin != null) {
										Tools.decomposeMatrix(o.targetSkin.skinData.allJoints[o.targetJoint].defMat, o.defaultMatrix);
									} else {
										o.defaultMatrix = h3d.anim.SmoothTransition.MZERO;
									}
									objects.push(o);
									o;
								});

								animObjects.push(o);
							}

							animInfos.push({anim: animInstance, proxy: proxy, selfSpeed: 1.0, keepSync: blendSpacePoint.keepSync, selfTime: 0, objects: animObjects});
							return index;
						}

						var animIndex = if (blendSpacePoint.keepSync) {
							MapUtils.getOrPut(animMap, path, makeAnim());
						} else {
							// All anims not kept in sync are unique, so we bypass the animMap
							var i = makeAnim();
							animInfos[i].selfSpeed = blendSpacePoint.speed;
							i;
						}

						point.animInfo = animInfos[animIndex];
					}

					points.push(point);
				} catch (e) {
					trace('Couldn\'t load anim ${blendSpacePoint.animPath} : ${e.toString()}');
				}
			}
		}

		trace(allObjects);

		triangulate();
	}

	function triangulate() : Void {
		triangles = [];

		var h2dPoints : Array<h2d.col.Point> = [];
		for (point in points) {
			// normalize x / y in range 0/1 so the triangulation is done in a square
			// this avoid the triangulation failing to create triangles when one axis is far larger than the other

			var x = (point.x - blendSpace.minX) / (blendSpace.maxX - blendSpace.minX);
			var y = (point.y - blendSpace.minY) / (blendSpace.maxY - blendSpace.minY);


			h2dPoints.push(new h2d.col.Point(x, y));
		}

		var triangulation = h2d.col.Delaunay.triangulate(h2dPoints);
		if (triangulation == null) {
			// todo : put blend space into "1d mode" if triangulation failed
			throw "triangulation failed";
			return;
		}

		for (triTriangle in triangulation) {
			var triangle : Array<BlendSpaceInstancePoint> = [];
			triangle[0] = points[h2dPoints.indexOf(triTriangle.p1)];
			triangle[1] = points[h2dPoints.indexOf(triTriangle.p2)];
			triangle[2] = points[h2dPoints.indexOf(triTriangle.p3)];
			triangles.push(triangle);
		}
	}

	override function clone(?a:h3d.anim.Animation):h3d.anim.Animation {
		var a : BlendSpace2D2 = cast a;
		if (a == null)
			a = new BlendSpace2D2(blendSpace, animSet, modelCache);
		a.blendSpace = blendSpace;
		a.animSet = animSet;
		a.modelCache = a.modelCache;
		return super.clone(a);
	}

	override function update(dt:Float):Float {
		var dt2 = super.update(dt);

		if (blendSpace.smoothX > 0) {
			var r = criticalSpringDamper(realX, vX, x, 0, blendSpace.smoothX, dt);
			realX = r.x;
			vX = r.v;

			currentTriangle = -1;
		} else {
			realX = x;
		}

		if (blendSpace.smoothX > 0) {
			var r = criticalSpringDamper(realY, vY, y, 0, blendSpace.smoothY, dt);
			realY = r.x;
			vY = r.v;

			currentTriangle = -1;
		} else {
			realY = y;
		}

		syncAnimTime = (syncAnimTime + dt / currentAnimLenght) % 1.0;

		updateCurrentTriangle();

		if (currentTriangle < 0)
			return dt2;

		var triangle = triangles[currentTriangle];

		// update our anim infos
		for (animInfo in animInfos) {
			var skip = false;

			var newTime = if (animInfo.keepSync) {
				animInfo.anim.getDuration() * syncAnimTime;
			} else {
				animInfo.anim.frame / (animInfo.anim.speed * animInfo.anim.sampling) + dt * animInfo.selfSpeed;
			}

			// Check if the anim info is in one of our triangle points, and if so
			// tick it normaly,

			for (p in triangle) {

				if (p.animInfo == animInfo) {
					skip = true;
					//var scale = animInfo.selfSpeed;
					var delta = newTime - animInfo.anim.frame / (animInfo.anim.speed * animInfo.anim.sampling);
					animInfo.anim.update(delta);
					break;
				}
			}

			if (skip)
				continue;

			animInfo.anim.setFrame(newTime * (animInfo.anim.speed * animInfo.anim.sampling));
		}
		return dt2;
	}

	function updateCurrentTriangle() {
		if (triangles.length < 1)
			return;

		if (currentTriangle == -1) {
			var curPos = inline new h2d.col.Point(realX, realY);

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

			var max = 0;
			for (i in 1...3) {
				if (weights[i] > weights[max]) {
					max = i;
				}
			}

			var strongestAnim = triangles[currentTriangle][max].animInfo?.anim;
			if (prevAnimEventBind != strongestAnim) {
				if (prevAnimEventBind != null)
					prevAnimEventBind.onEvent = null;
				if (strongestAnim != null)
					strongestAnim.onEvent = animEventHander;
				prevAnimEventBind = strongestAnim;
			}

			currentAnimLenght = 0.0;

			// Compensate for null animations that don't have length
			var nulls = 0;
			var nullWeights: Float = 0;
			for (i => pt in triangles[currentTriangle]) {
				if (pt.animInfo == null || !pt.animInfo.keepSync) {
					nulls ++;
					nullWeights += weights[i];
				}
			}

			if (nulls < 3) {
				nullWeights /= (3 - nulls);
			}

			for (i => pt in triangles[currentTriangle]) {
				if(pt.animInfo != null && pt.animInfo.keepSync) {
					var blendLength = pt.animInfo.anim.getDuration()/pt.speed * (weights[i] + nullWeights);
					currentAnimLenght += blendLength;
				}
			}
		}
	}

	@:haxe.warning("-WInlineOptimizedField")
	override function sync(decompose:Bool = false) {
		updateCurrentTriangle();

		if (currentTriangle < 0)
			return;

		var triangle = triangles[currentTriangle];

		// Reset tmpMatrices to the default matrix
		for (object in getBSObjects()) {
			for (i => _ in triangle) {
				object.matrices[i] = object.defaultMatrix;
			}
			object.touchedThisFrame = false;
		}

		for (ptIndex => point in triangle) {
			point.animInfo.anim.isSync = false;
			point.animInfo.anim.sync(true);

			// copy modified matrices references
			@:privateAccess
			for (object in point.animInfo.objects) {
				object.matrices[ptIndex] = (if( object.targetSkin != null ) object.targetSkin.currentRelPose[object.targetJoint] else object.targetObject.defaultTransform) ?? object.matrices[ptIndex];
			}
		}


		for (object in getBSObjects()) {
			var outMatrix = object.outMatrix;

			var blendedPos = inline new h3d.Vector();
			var blendedRot = inline new h3d.Quat();
			var blendedScale = inline new h3d.Vector();

			var triangle = triangles[currentTriangle];
			var def = object.defaultMatrix;
			refQuat.set(def._12, def._13, def._21, def._23);

			for (ptIndex => point in triangle) {
				var w =  weights[ptIndex];
				if (w == 0) {
					continue;
				}

				var matrix = object.matrices[ptIndex];

				if (matrix == null)
					continue;

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

			if (!decompose) {
				Tools.recomposeMatrix(outMatrix, tmpMatrix);
				outMatrix.load(tmpMatrix);
			}

			@:privateAccess if( object.targetSkin != null ) object.targetSkin.currentRelPose[object.targetJoint] = outMatrix else object.targetObject.defaultTransform = outMatrix;
		}

	}

	function animEventHander(name: String) {
		onEvent(name);
	}

	function setupAnimEvents() {
		// handled by the triangle setup
	}

	static function halfLifeToDamping(halfLife: Float) {
    	return (4.0 * 0.69314718056) / (halfLife + 1e-5);
	}

	static function fastNegexp(x: Float) : Float
	{
		return 1.0 / (1.0 + x + 0.48*x*x + 0.235*x*x*x);
	}


	inline static function criticalSpringDamper(x: Float, v: Float, xGloal: Float, vGoal: Float, halfLife: Float, dt: Float) : {x: Float, v: Float} {
		final damping = halfLifeToDamping(halfLife);
		final c = xGloal + (damping * vGoal) / (damping * damping ) / 4.0;
		final half_damping = damping / 2.0;
		final j0 = x - c;
		final j1 = v + j0 * half_damping;
		final eydt = fastNegexp(half_damping * dt);

		return {x: eydt * (j0 + j1 * dt) + c, v: eydt *(v - j1*half_damping*dt)};
	}
}