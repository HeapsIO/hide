package hide.prefab.fx;


enum EmitShape {
	Sphere;
	Circle;
}

private class EmitterParam {
	var baseValue : Float;
	var curve : hide.prefab.Curve;
	var random : Float = 0.0;

	public function new(val: Float=0.0) {
		this.baseValue = val;
	}
	
	public function get(t: Float) {
		return baseValue;
	}

	public function getSum(t: Float) {
		return baseValue * t;
	}
}

private class EmitterVector {
	// var baseValue : h3d.Vector;
	// var random : h3d.Vector;
	// var curveX : hide.prefab.Curve;
	// var curveY : hide.prefab.Curve;
	// var curveZ : hide.prefab.Curve;
	// var curveX : hide.prefab.Curve;
	// var curveY : hide.prefab.Curve;
	// var curveZ : hide.prefab.Curve;
	public var x : EmitterParam;
	public var y : EmitterParam;
	public var z : EmitterParam;

	public function new() {

	}

	public function get(t: Float) : h3d.Vector {
		return new h3d.Vector();
	}
}



@:allow(hide.prefab.fx.EmitterObject)
private class ParticleInstance {
	var parent : EmitterObject;
	public var life = 0.0;
	public var obj : h3d.scene.Object;

	public var curVelocity = new h3d.Vector();
	public var curPos = new h3d.Vector();
	public var orientation = new h3d.Quat();
	//public var orientation = new h3d.Matrix();

	// public var speed : EmitterVector;
	public var localSpeed : EmitterVector;
	public var globalSpeed : EmitterVector;
	public var localOffset : EmitterVector;

	public function new(parent: EmitterObject) {
		this.parent = parent;
		parent.instances.push(this);
	}

	public function update(dt : Float) {
		
		// if(localSpeed != null) 
		{
			var locSpeedVec = new h3d.Vector(4, 0, 0);
			locSpeedVec.transform3x3(orientation.toMatrix());			
			curVelocity = locSpeedVec;
		}
		{
			var globSpeedVec = new h3d.Vector(0, 0, -2);
			curVelocity = curVelocity.add(globSpeedVec);
		}

		curPos.x += curVelocity.x * dt;
		curPos.y += curVelocity.y * dt;
		curPos.z += curVelocity.z * dt;
		obj.setPos(curPos.x, curPos.y, curPos.z);
		if(localOffset != null) {
			var off = localOffset.get(life);
			obj.x += off.x;
			obj.y += off.y;
			obj.z += off.x;
		}

		life += dt;
	}

	public function remove() {
		obj.remove();
		parent.instances.remove(this);
	}
}

@:allow(hide.prefab.fx.ParticleInstance)
@:allow(hide.prefab.fx.Emitter)
class EmitterObject extends h3d.scene.Object {

	public var particleTemplate : hide.prefab.Prefab;
	public var maxCount = 20;
	public var lifeTime = 2.0;
	public var emitRate = new EmitterParam(10.0);
	public var emitShape : EmitShape = Circle;
	public var emitShapeSize = new EmitterParam(6.0);


	//public var emitSpeed = new EmitterParam(1.0);
	public var localSpeed = new EmitterVector(); 
	public var partSpeed = new EmitterVector();


	var context : hide.prefab.Context;
	var emitCount = 0;
	var lastTime = -1.0;
	var curTime = 0.0;

	var instances : Array<ParticleInstance> = [];
	

	function reset() {
		curTime = 0.0;
		lastTime = 0.0;
		emitCount = 0;
		for(inst in instances.copy()) {
			inst.remove();
		}
	}

	function doEmit(count: Int) {
		calcAbsPos();

		var shapeSize = emitShapeSize.get(curTime);
		context.local3d = this.parent;
		if(particleTemplate == null)
			return;
		// var localTrans = new h3d.Matrix();
		for(i in 0...count) {
			var ctx = particleTemplate.makeInstance(context);
			var obj3d = ctx.local3d;

			var localPos = new h3d.Vector();
			var localDir = new h3d.Vector();
			switch(emitShape) {
				case Circle:
					var dx = 0.0, dy = 0.0;
					do {
						dx = hxd.Math.srand(1.0);
						dy = hxd.Math.srand(1.0);
					}
					while(dx * dx + dy * dy > 1.0);
					dx *= shapeSize / 2.0;
					dy *= shapeSize / 2.0;
					localPos.set(0, dx, dy);
					// localTrans.initTranslate(0, dx, dy);
				default:
			}

			localPos.transform(absPos);
			// localTrans.multiply(localTrans, absPos);
			var part = new ParticleInstance(this);
			part.obj = obj3d;
			part.curPos = localPos;
			//part.transform = localTrans;
			part.orientation.initRotateMatrix(absPos);
			// part.curVelocity
		}
		context.local3d = this;		
		emitCount += count;
	}

	override function sync(ctx) {
		super.sync(ctx);
		if(ctx.elapsedTime == 0)
			return;
		
		if(ctx.time < lastTime || lastTime < 0) {
			reset();
		}
		var deltaTime = ctx.time - lastTime;
		curTime += deltaTime;
		lastTime = curTime;

		if(deltaTime <= 0.01)
			return;

		var emitTarget = emitRate.getSum(curTime);
		var delta = hxd.Math.floor(emitTarget - emitCount);
		doEmit(delta);


		var i = instances.length;
		while (i-- > 0) {
			if(instances[i].life > lifeTime) {
				instances[i].remove();
			}
			else {
				instances[i].update(deltaTime);
			}
		}

		// for(inst in instances) {
		// 	inst.update(deltaTime);
		// }
	}
}

class Emitter extends Object3D {


	override function save() {
		var obj : Dynamic = super.save();
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var emitterObj = new EmitterObject();
		emitterObj.context = ctx;
		emitterObj.particleTemplate = children[0];
		ctx.local3d.addChild(emitterObj);
		ctx.local3d = emitterObj;
		ctx.local3d.name = name;		
		applyPos(ctx.local3d);
		return ctx;
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		#if editor
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Layer">
				<dl>
					<dt>Locked</dt><dd><input type="checkbox" field="locked"/></dd>
					<dt>Color</dt><dd><input name="colorVal"/></dd>
				</dl>
			</div>
		'),this, function(pname) {
			ctx.onChange(this, pname);
		});
		#end
	}


	override function getHideProps() {
		return { icon : "asterisk", name : "Emitter", fileSource : null };
	}

	static var _ = Library.register("emitter", Emitter);

}