package hide.prefab.fx;
import hide.prefab.Curve;
import hide.prefab.Prefab as PrefabElement;

typedef ShaderAnimation = hide.prefab.Shader.ShaderAnimation;

enum Value {
	VConst(v: Float);
	VCurve(c: Curve);
	VCurveValue(c: Curve, scale: Float);
	VNoise(idx: Int, scale: Value);
	VAdd(a: Value, b: Value);
	VMult(a: Value, b: Value);
	VVector(x: Value, y: Value, z: Value, ?w: Value);
	VHsl(h: Value, s: Value, l: Value, a: Value);
	VBool(v: Value);
	VInt(v: Value);
}

class Evaluator {
	var randValues : Array<Float> = [];
	var random: hxd.Rand;

	public function new(random: hxd.Rand) {
		this.random = random;
	}

	public function getVal(val: Value, time: Float) : Dynamic {
		return null; // TODO?
	}

	public function getFloat(val: Value, time: Float) : Float {
		switch(val) {
			case VConst(v): return v;
			case VCurve(c): return c.getVal(time);
			case VCurveValue(c, scale): return c.getVal(time) * scale;
			case VNoise(idx, scale):
				if(!(randValues[idx] > 0))
					randValues[idx] = random.rand();
				return randValues[idx] * getFloat(scale, time);
			case VMult(a, b):
				return getFloat(a, time) * getFloat(b, time);
			case VAdd(a, b):
				return getFloat(a, time) + getFloat(b, time);
			default: 0.0;
		}
		return 0.0;
	}

	public function getSum(val: Value, time: Float) : Float {
		switch(val) {
			case VConst(v): return v * time;
			case VCurveValue(c, scale): return c.getSum(time) * scale;
			case VAdd(a, b):
				return getSum(a, time) + getSum(b, time);
			default: 0.0;
		}
		return 0.0;
	}

	public function getVector(v: Value, time: Float) : h3d.Vector {
		switch(v) {
			case VMult(a, b):
				var av = getVector(a, time);
				var bv = getVector(b, time);
				return new h3d.Vector(av.x * bv.x, av.y * bv.y, av.z * bv.z, av.w * bv.w);
			case VVector(x, y, z, null):
				return new h3d.Vector(getFloat(x, time), getFloat(y, time), getFloat(z, time), 1.0);
			case VVector(x, y, z, w):
				return new h3d.Vector(getFloat(x, time), getFloat(y, time), getFloat(z, time), getFloat(w, time));
			case VHsl(h, s, l, a):
				var hval = getFloat(h, time);
				var sval = getFloat(s, time);
				var lval = getFloat(l, time);
				var aval = getFloat(a, time);
				var col = new h3d.Vector(0,0,0,1);
				col.makeColor(hval, sval, lval);
				return col;
			default:
				var f = getFloat(v, time);
				return new h3d.Vector(f, f, f, 1.0);
		}
	}
}

typedef ObjectCurves = {
	?x: Curve,
	?y: Curve,
	?z: Curve,
	?rotationX: Curve,
	?rotationY: Curve,
	?rotationZ: Curve,
	?scaleX: Curve,
	?scaleY: Curve,
	?scaleZ: Curve,
	?visibility: Curve,
	?custom: Array<Curve>
}

typedef ObjectAnimation = {
	elt: hide.prefab.Object3D,
	obj: h3d.scene.Object,
	curves: ObjectCurves
};

class FXAnimation {
	
	public var objects: Array<ObjectAnimation> = [];
	public var shaderAnims : Array<ShaderAnimation> = [];

	public function new() { }

	public function setTime(time: Float) {
		for(anim in objects) {
			var mat = getTransform(anim.curves, time);
			mat.multiply(anim.elt.getTransform(), mat);
			anim.obj.setTransform(mat);
			if(anim.curves.visibility != null) {
				var visible = anim.curves.visibility.getVal(time) > 0.5;
				anim.obj.visible = anim.elt.visible && visible;
			}
		}

		for(anim in shaderAnims) {
			anim.setTime(time);
		}
	}

	public function getTransform(curves: ObjectCurves, time: Float, ?m: h3d.Matrix) {
		if(m == null)
			m = new h3d.Matrix();

		var x = curves.x == null ? 0. : curves.x.getVal(time);
		var y = curves.y == null ? 0. : curves.y.getVal(time);
		var z = curves.z == null ? 0. : curves.z.getVal(time);

		var rotationX = curves.rotationX == null ? 0. : curves.rotationX.getVal(time);
		var rotationY = curves.rotationY == null ? 0. : curves.rotationY.getVal(time);
		var rotationZ = curves.rotationZ == null ? 0. : curves.rotationZ.getVal(time);

		var scaleX = curves.scaleX == null ? 1. : curves.scaleX.getVal(time);
		var scaleY = curves.scaleY == null ? 1. : curves.scaleY.getVal(time);
		var scaleZ = curves.scaleZ == null ? 1. : curves.scaleZ.getVal(time);

		m.initScale(scaleX, scaleY, scaleZ);
		m.rotate(rotationX, rotationY, rotationZ);
		m.translate(x, y, z);

		return m;
	}
}

class FXScene extends Library {

	public function new() {
		super();
		type = "fx";
	}

	override function save() {
		var obj : Dynamic = super.save();
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
	}

	function getObjAnimations(ctx:Context, elt: PrefabElement, anims: Array<ObjectAnimation>) {
		if(Std.instance(elt, hide.prefab.fx.Emitter) == null) {
			// Don't extract animations for children of Emitters
			for(c in elt.children) {
				getObjAnimations(ctx, c, anims);
			}
		}

		var obj3d = elt.to(hide.prefab.Object3D);
		if(obj3d == null)
			return;

		var objCtx = ctx.shared.contexts.get(elt);
		if(objCtx == null || objCtx.local3d == null)
			return;

		var curves = getCurves(elt);
		if(curves == null)
			return;

		var anim : ObjectAnimation = {
			elt: obj3d,
			obj: objCtx.local3d,
			curves: curves
		};
		anims.push(anim);
	}

	function getShaderAnims(ctx: Context, elt: PrefabElement, anims: Array<ShaderAnimation>) {
		if(Std.instance(elt, hide.prefab.fx.Emitter) == null) {
			for(c in elt.children) {
				getShaderAnims(ctx, c, anims);
			}
		}

		var shader = elt.to(hide.prefab.Shader);
		if(shader == null)
			return;

		var shCtx = ctx.shared.contexts.get(elt);
		if(shCtx == null || shCtx.custom == null)
			return;

		anims.push(cast shCtx.custom);
	}

	override function makeInstance(ctx:Context):Context {
		if( inRec )
			return ctx;
		ctx = ctx.clone(this);
		super.makeInstance(ctx);
		var anim = new FXAnimation();
		getObjAnimations(ctx, this, anim.objects);
		getShaderAnims(ctx, this, anim.shaderAnims);
		ctx.custom = anim;
		return ctx; 
	}

	override function edit( ctx : EditContext ) {
		#if editor
		var props = new hide.Element('
			<div class="group" name="Level">
			</div>
		');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
		#end
	}

	override function getHideProps() {
		return { icon : "cube", name : "FX", fileSource : ["fx"] };
	}

	public function getCurves(element : hide.prefab.Prefab) : ObjectCurves {
		var ret : ObjectCurves = null;
		for(c in element.children) {
			var curve = c.to(Curve);
			if(curve == null)
				continue;
			if(ret == null)
				ret = {};
			switch(c.name) {
				case "position.x": ret.x = curve;
				case "position.y": ret.y = curve;
				case "position.z": ret.z = curve;
				case "rotation.x": ret.rotationX = curve;
				case "rotation.y": ret.rotationY = curve;
				case "rotation.z": ret.rotationZ = curve;
				case "scale.x": ret.scaleX = curve;
				case "scale.y": ret.scaleY = curve;
				case "scale.z": ret.scaleZ = curve;
				case "visibility": ret.visibility = curve;
				default: 
					if(ret.custom == null)
						ret.custom = [];
					ret.custom.push(curve);
			}
		}
		return ret;
	}

	// public function getTransform(curves: ObjectCurves, time: Float, ?m: h3d.Matrix) {
	// 	if(m == null)
	// 		m = new h3d.Matrix();

	// 	var x = curves.x == null ? 0. : curves.x.getVal(time);
	// 	var y = curves.y == null ? 0. : curves.y.getVal(time);
	// 	var z = curves.z == null ? 0. : curves.z.getVal(time);

	// 	var rotationX = curves.rotationX == null ? 0. : curves.rotationX.getVal(time);
	// 	var rotationY = curves.rotationY == null ? 0. : curves.rotationY.getVal(time);
	// 	var rotationZ = curves.rotationZ == null ? 0. : curves.rotationZ.getVal(time);

	// 	var scaleX = curves.scaleX == null ? 1. : curves.scaleX.getVal(time);
	// 	var scaleY = curves.scaleY == null ? 1. : curves.scaleY.getVal(time);
	// 	var scaleZ = curves.scaleZ == null ? 1. : curves.scaleZ.getVal(time);

	// 	m.initScale(scaleX, scaleY, scaleZ);
	// 	m.rotate(rotationX, rotationY, rotationZ);
	// 	m.translate(x, y, z);

	// 	return m;
	// }

	static var _ = Library.register("fx", FXScene);
}