package hrt.prefab.fx;


class SwarmElement {
	public function new() {};

	public var x: Float = 0.0;
	public var y: Float = 0.0;
	public var z: Float = 0.0;

	public var vx: Float = 0.0;
	public var vy: Float = 0.0;
	public var vz: Float = 0.0;

	// Interpolation
	public var prev_x: Float = 0.0;
	public var prev_y: Float = 0.0;
	public var prev_z: Float = 0.0;

	public var prev_vx: Float = 0.0;
	public var prev_vy: Float = 0.0;
	public var prev_vz: Float = 0.0;
}

class SwarmObject extends h3d.scene.Object {
	public var prefab : Swarm = null;
	public var elements: Array<SwarmElement> = [];
	public var lastPos :h3d.Vector = null;
	public var facingAngle: Float = 0.0;
	public var targetAngle: Float = 0.0;


	var time = 0.0;
	var stepTime = 0.0;

	#if editor
	public var debugViz : h3d.scene.Graphics = null;
	public var debugVizElem : h3d.scene.Graphics = null;

	#end

	public function new( ?parent : h3d.scene.Object, prefab : Swarm) {
		super(parent);
		this.prefab = prefab;
		this.followPositionOnly = true;

		#if editor
		debugViz = new h3d.scene.Graphics(this);
		debugVizElem = new h3d.scene.Graphics(this);
		debugVizElem.follow = this.getScene();
		#end
	}

	static var tmpVector = new h3d.Vector();
	static var tmpVector2 = new h3d.Vector();
	static var tmpVector3 = new h3d.Vector();

	var stepSize = 1.0/15.0;
	var maxIter = 3;

	// Performs a fixed step in the simulation
	// Avoid degenerating parameters at low framerates
	function step() {
		var absPos = getAbsPos();

		if (lastPos == null) {
			lastPos = absPos.getPosition();
		}

		var curPos = absPos.getPosition();
		var delta = curPos.sub(lastPos);
		delta.z = 0.0;

		if (delta.lengthSq() > 0.00001) {
			delta.normalize();
			var forward = tmpVector;
			forward.set(1.0,0.0,0.0);
			var up = tmpVector2;
			up.set(0.0,0.0,1.0);

			targetAngle = -hxd.Math.atan2(delta.cross(forward).dot(up), delta.dot(forward));
		}

		if (stepSize > 0.0001) {
			var diff = (targetAngle - facingAngle);
			trace(diff / (hxd.Math.PI * 2.0));
			while (diff > hxd.Math.PI) {
				diff -= hxd.Math.PI * 2.0;
			}
			while (diff < -hxd.Math.PI) {
				diff += hxd.Math.PI * 2.0;
			}
			facingAngle += diff * (1-hxd.Math.pow(0.5, stepSize));
			facingAngle = (facingAngle % (hxd.Math.PI * 2.0));
		}

		lastPos.load(curPos);


		var prevLen = elements.length;
		elements.resize(prefab.numObjects);
		for (i in prevLen...prefab.numObjects) {
			var pos = getPointPos(i, tmpVector);
			var e = new SwarmElement();
			e.x = pos.x;
			e.y = pos.y;
			e.z = pos.z;

			e.vx = 0.0;
			e.vy = 0.0;
			e.vz = 0.0;

			elements[i] = e;
		}


		for (i in 0...elements.length) {
			var e = elements[i];

			var maxAccDist = 10.0;

			var target = getPointPos(i, tmpVector);
			target.transform(absPos);
			var dir = tmpVector2;
			dir.set(target.x - e.x, target.y - e.y, target.z - e.z);
			var len = dir.length();

			e.prev_vx = e.vx;
			e.prev_vy = e.vy;
			e.prev_vz = e.vz;

			e.prev_x = e.x;
			e.prev_y = e.y;
			e.prev_z = e.z;

			if (len > 0.001) {
				var curVec = tmpVector3;
				curVec.set(e.vx, e.vy, e.vz);
				dir.normalize();
				dir.scale(len * prefab.acceleration);
				curVec.scale(prefab.braking);
				dir = dir.sub(curVec);

				e.vx += dir.x * stepSize;
				e.vy += dir.y * stepSize;
				e.vz += dir.z * stepSize;

				curVec.set(e.vx, e.vy, e.vz);
				var spd = curVec.length();
				spd = hxd.Math.clamp(spd, 0.0, prefab.maxSpeed * hxd.Math.lerp(0.75, 1.25, hashf(i, 744102359)));
				curVec.normalize();

				var spdNorm = tmpVector2;
				spdNorm.load(curVec);
				spdNorm.set(spdNorm.y, -spdNorm.x, spdNorm.z);

				spdNorm.scale(hxd.Math.sin(time + hashf(i, 17) * hxd.Math.PI * 2.0) * prefab.objectSelfSin * hxd.Math.max(0.10, spd/prefab.maxSpeed));

				curVec.scale(spd);

				e.vx = curVec.x;
				e.vy = curVec.y;
				e.vz = curVec.z;

				e.x += e.vx * stepSize + spdNorm.x * stepSize;
				e.y += e.vy * stepSize + spdNorm.y * stepSize;
				e.z += e.vz * stepSize + spdNorm.z * stepSize;
			}
		}
	}

	override function syncRec(ctx:h3d.scene.RenderContext) {
		super.syncRec(ctx);

		stepTime += ctx.time - time;
		time = ctx.time;

		var numIter = 0;
		while(stepTime > stepSize && numIter < maxIter) {
			stepTime -= stepSize;
			numIter += 1;

			step();
		}

		stepTime = stepTime % stepSize;

		#if editor
		debugViz.clear();
		if (prefab.debugTargets) {
			for (i in 0...prefab.numObjects) {
				debugViz.setColorF(0.0,1.0,1.0,1.0);
				drawPoint(debugViz, getPointPos(i, tmpVector));
			}
		}


		debugVizElem.clear();
		for (e in elements) {
			debugVizElem.setColorF(0.5,0.0,0.0,1.0);
			var dd = stepTime/stepSize;

			var x = hxd.Math.lerp(e.prev_x, e.x, dd);
			var y = hxd.Math.lerp(e.prev_y, e.y, dd);
			var z = hxd.Math.lerp(e.prev_z, e.z, dd);

			var vx = hxd.Math.lerp(e.prev_vx, e.vx, dd);
			var vy = hxd.Math.lerp(e.prev_vy, e.vy, dd);
			var vz = hxd.Math.lerp(e.prev_vz, e.vz, dd);

			tmpVector.set(vx, vy, vz);
			tmpVector.normalize();
			tmpVector.scale(0.25);
			debugVizElem.moveTo(x, y, z);
			debugVizElem.lineTo(x + tmpVector.x, y + tmpVector.y, z + tmpVector.z);
		}
		#end
	}

	#if editor
	function drawPoint(viz: h3d.scene.Graphics, pos: h3d.Vector, size: Float = 0.5) {
		viz.moveTo(pos.x - size/2.0, pos.y, pos.z);
		viz.lineTo(pos.x + size/2.0, pos.y, pos.z);

		viz.moveTo(pos.x, pos.y - size/2.0, pos.z);
		viz.lineTo(pos.x, pos.y + size/2.0, pos.z);

		viz.moveTo(pos.x, pos.y, pos.z - size/2.0);
		viz.lineTo(pos.x, pos.y, pos.z + size/2.0);
	}
	#end

	inline function hashf(id: Int, seed:Int) : Float {
		var h = hxd.Rand.hash(id, seed);
		return (h % 10007) / 10007.0;
	}

	function getPointPos(id: Int, ?outPos: h3d.Vector) : h3d.Vector {
		if (outPos == null)
			outPos = new h3d.Vector();

		var s = prefab.seed;

		var r = hxd.Math.lerp(0.5, 1.5, hashf(id, 188947+s)) * 1.0;
		var theta = hxd.Math.lerp(0.2, hxd.Math.PI * 2.0 - 0.2, hashf(id, 7841+s) % 1.0);
		var sigma = (hashf(id, 4449) % 1.0 + 0.0 * hxd.Math.lerp(0.5, 1.5, hashf(id, 99741+s)) * 0.05) * hxd.Math.PI * 2.0 + facingAngle;

		var st = hxd.Math.sin(theta);
		outPos.x = r * st * hxd.Math.cos(sigma);
		outPos.y = r * st * hxd.Math.sin(sigma);
		outPos.z = r * hxd.Math.cos(theta);

		return outPos;
	}

}

class Swarm extends Object3D {
	@:s public var numObjects : Int = 3;
	@:s public var seed : Int = 0;
	@:s public var acceleration : Float = 1.0;
	@:s public var maxSpeed : Float = 10.0;

	@:s public var braking : Float = 1.0;

	@:s public var objectSelfSin : Float = 1.0;


	@:s public var debugTargets : Bool = false;


	override function createObject(ctx:Context) {
		return new SwarmObject(ctx.local3d, this);
	}

	#if editor
	override function getHideProps() : HideProps {
		return { icon : "random", name : "Swarm", allowParent : function(p) return p.to(FX) != null || p.getParent(FX) != null };
	}

	override public function edit(ctx:EditContext) {
		super.edit(ctx);
		var props = ctx.properties.add(new hide.Element('
		<div class="group" name="Trail Properties">
			<dl>
				<dt>Count</dt><dd><input field="numObjects"/></dd>
				<dt>Random Seed</dt><dd><input field="seed"/></dd>
				<dt>Acceleration</dt><dd><input type="range" field="acceleration" min = "0.01" max = "10.0"/></dd>
				<dt>MaxSpeed</dt><dd><input type="range" field="acceleration" min = "0.01" max = "100.0"/></dd>
				<dt>Braking</dt><dd><input type="range" field="braking" min = "0.01" max = "10.0"/></dd>

				<dt>ObjectSelfSin</dt><dd><input type="range" field="objectSelfSin" min = "0.01" max = "10.0"/></dd>


				<dt>Debug Targets</dt><dd><input type="checkbox" field="debugTargets"/></dd>

			</dl>
		</div>'), this);
	}
	#end

	static var _ = hrt.prefab.Library.register("Swarm", Swarm);
}