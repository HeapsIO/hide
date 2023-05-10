package hrt.prefab.fx;


class SwarmElement {
	public function new() {};

	public var x: Float = 0.0;
	public var y: Float = 0.0;
	public var z: Float = 0.0;

	public var vx: Float = 0.0;
	public var vy: Float = 0.0;
	public var vz: Float = 0.0;
}

class SwarmObject extends h3d.scene.Object {
	public var prefab : Swarm = null;
	public var elements: Array<SwarmElement> = [];

	var time = 0.0;

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

	override function syncRec(ctx:h3d.scene.RenderContext) {
		super.syncRec(ctx);

		time = ctx.time;

		var prevLen = elements.length;
		elements.resize(prefab.numObjects);
		for (i in prevLen...prefab.numObjects) {
			var pos = getPointPos(i, tmpVector);
			var e = new SwarmElement();
			e.x = pos.x;
			e.y = pos.y;
			e.z = pos.z;

			e.vx = 1.0;
			e.vy = 0.0;
			e.vz = 0.0;

			elements[i] = e;
		}


		var absPos = getAbsPos();
		for (i in 0...elements.length) {
			var e = elements[i];

			var maxAccDist = 10.0;

			var target = getPointPos(i, tmpVector);
			target.transform(absPos);
			var dir = tmpVector2;
			dir.set(target.x - e.x, target.y - e.y, target.z - e.z);
			var len = dir.length();
			if (len > 0.001) {
				var curVec = tmpVector3;
				curVec.set(e.vx, e.vy, e.vz);
				dir.normalize();
				dir.scale(len * prefab.acceleration);
				curVec.scale(prefab.braking);
				dir = dir.sub(curVec);

				e.vx += dir.x * ctx.elapsedTime;
				e.vy += dir.y * ctx.elapsedTime;
				e.vz += dir.z * ctx.elapsedTime;

				curVec.set(e.vx, e.vy, e.vz);
				var spd = curVec.length();
				spd = hxd.Math.clamp(spd, 0.0, prefab.maxSpeed * hxd.Math.lerp(0.75, 1.25, hashf(i, 744102359)));
				curVec.normalize();
				curVec.scale(spd);

				e.vx = curVec.x;
				e.vy = curVec.y;
				e.vz = curVec.z;

				e.x += e.vx * ctx.elapsedTime;
				e.y += e.vy * ctx.elapsedTime;
				e.z += e.vz * ctx.elapsedTime;
			}

		}

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
			tmpVector.set(e.vx, e.vy, e.vz);
			tmpVector.normalize();
			tmpVector.scale(0.25);
			debugVizElem.moveTo(e.x, e.y, e.z);
			debugVizElem.lineTo(e.x + tmpVector.x, e.y + tmpVector.y, e.z + tmpVector.z);
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
		var sigma = (hashf(id, 4449) % 1.0 + time * hxd.Math.lerp(0.5, 1.5, hashf(id, 99741+s)) * 0.05) * hxd.Math.PI * 2.0;

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

	@:s public var debugTargets : Bool = false;


	override function createObject(ctx:Context) {
		return new SwarmObject(ctx.local3d, this);
	}

	#if editor
	override function getHideProps() : HideProps {
		return { icon : "random", name : "Swarm", allowParent : function(p) return p.to(FX) != null || p.getParent(FX) != null };
	}
	#end

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
				<dt>Debug Targets</dt><dd><input type="checkbox" field="debugTargets"/></dd>

			</dl>
		</div>'), this);
	}

	static var _ = hrt.prefab.Library.register("Swarm", Swarm);
}