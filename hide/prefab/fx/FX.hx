package hide.prefab.fx;
import hide.prefab.Curve;
import hide.prefab.Prefab as PrefabElement;

typedef ShaderParam = {
	def: hxsl.Ast.TVar,
	value: Value
};

typedef ShaderParams = Array<ShaderParam>;

class ShaderAnimation extends Evaluator {
	public var params : ShaderParams;
	public var shader : hxsl.DynamicShader;

	public function setTime(time: Float) {
		for(param in params) {
			var v = param.def;
			switch(v.type) {
				case TFloat:
					var val = getFloat(param.value, time);
					shader.setParamValue(v, val);
				case TInt:
					var val = hxd.Math.round(getFloat(param.value, time));
					shader.setParamValue(v, val);
				case TBool:
					var val = getFloat(param.value, time) >= 0.5;
					shader.setParamValue(v, val);
				case TVec(_, VFloat):
					var val = getVector(param.value, time);
					shader.setParamValue(v, val);
				default:
			}
		}
	}
}

typedef ObjectAnimation = {
	elt: hide.prefab.Object3D,
	obj: h3d.scene.Object,
	?position: Value,
	?scale: Value,
	?rotation: Value,
	?color: Value,
	?visibility: Value
};

class FXAnimation extends h3d.scene.Object {

	public var onEnd : Void -> Void;

	public var playSpeed : Float;
	public var localTime(default, null) : Float = 0.0;
	public var worldTime(default, null) : Float = 0.0;
	public var duration : Float;

	public var loopAnims : Bool;
	public var objects: Array<ObjectAnimation> = [];
	public var shaderAnims : Array<ShaderAnimation> = [];
	public var emitters : Array<hide.prefab.fx.Emitter.EmitterObject> = [];
	public var contraints : Array<hide.prefab.Constraint> = [];
	public var script : hide.prefab.fx.FXScript;

	var evaluator : Evaluator;
	var random : hxd.Rand;

	public function new(?parent) {
		super(parent);
		random = new hxd.Rand(Std.random(0xFFFFFF));
		evaluator = new Evaluator(random);
		name = "FXAnimation";
		setTime(0,0);
	}

	override function onRemove() {
		super.onRemove();
		for(obj in objects)
			obj.obj.remove();
		for(emitter in emitters)
			emitter.reset();
	}

	public function setRandSeed(seed: Int) {
		random.init(seed);
		for(em in emitters) {
			em.setRandSeed(seed);
		}
	}

	override function sync( ctx : h3d.scene.RenderContext ) {
		super.sync(ctx);
		#if !editor
		worldTime += ctx.elapsedTime;
		localTime += ctx.elapsedTime * playSpeed;
		setTime(localTime, worldTime);

		if(localTime >duration && duration != 0 /*Infinite*/) {
			if(onEnd != null )
				onEnd();
		}
		#end
	}

	static var tempMat = new h3d.Matrix();
	public function setTime( localTime : Float, ?worldTime : Float ) {
		if(worldTime == null) worldTime = localTime;
		for(anim in objects) {
			var m = tempMat;
			if(anim.scale != null) {
				var scale = evaluator.getVector(anim.scale, localTime);
				m.initScale(scale.x, scale.y, scale.z);
			}
			else
				m.identity();

			if(anim.rotation != null) {
				var rotation = evaluator.getVector(anim.rotation, localTime);
				rotation.scale3(Math.PI / 180.0);
				m.rotate(rotation.x, rotation.y, rotation.z);
			}

			var baseMat = anim.elt.getTransform();
			var offset = baseMat.getPosition();
			baseMat.tx = baseMat.ty = baseMat.tz = 0.0;  // Ignore
			m.multiply(baseMat, m);
			m.translate(offset.x, offset.y, offset.z);

			if(anim.position != null) {
				var pos = evaluator.getVector(anim.position, localTime);
				m.translate(pos.x, pos.y, pos.z);
			}

			anim.obj.setTransform(m);

			if(anim.visibility != null)
				anim.obj.visible = anim.elt.visible && evaluator.getFloat(anim.visibility, localTime) > 0.5;

			if(anim.color != null) {
				var mesh = Std.instance(anim.obj, h3d.scene.Mesh);
				if(mesh != null) {
					var mat = mesh.material;
					switch(anim.color) {
						case VCurve(a):
							mat.color.a = evaluator.getFloat(anim.color, localTime);
						default:
							mat.color = evaluator.getVector(anim.color, localTime);
					}
				}
			}
		}

		for(anim in shaderAnims) {
			anim.setTime(localTime);
		}

		function setAnimFrame(object : h3d.scene.Object, time : Float){
			var anim = object.currentAnimation;
			if(object.currentAnimation != null){
				anim.loop = false;
				anim.pause = true;
				if(loopAnims){
					var frameTime = time * anim.sampling * anim.speed;
					var frameIndex = frameTime - hxd.Math.floor(frameTime / anim.frameCount) * anim.frameCount;
					anim.setFrame( frameIndex );
				}else
					anim.setFrame( hxd.Math.clamp(time * anim.sampling * anim.speed, 0, anim.frameCount));
			}
			for(i in 0...object.numChildren)
				setAnimFrame(object.getChildAt(i), time);
		}
		setAnimFrame(this, localTime);

		for(em in emitters) {
			if(em.visible)
				em.setTime(worldTime);
		}

		if(script != null)
			script.eval();
	}

	public function resolveContraints( caster : h3d.scene.Object ) {
		for(co in contraints){
			var objectName = co.object.split(".").pop();
			var targetName = co.target.split(".").pop();
			var isInFX = co.object.split(".")[1] == "FXRoot";
			var srcObj = objectName == "FXRoot" ? this : isInFX ? this.getObjectByName(objectName) : caster.getObjectByName(objectName);
			var targetObj = caster.getObjectByName(targetName);
			if( srcObj != null && targetObj != null )
				srcObj.follow = targetObj;
		}
	}
}

class FX extends hxd.prefab.Library {

	public var duration : Float;
	public var loopAnims : Bool;
	public var script : String;

	public function new() {
		super();
		type = "fx";
		duration = 5.0;
		loopAnims = true;
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.duration = duration;
		obj.loopAnims = loopAnims;
		if( script != "" ) obj.script = script;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		duration = obj.duration == null ? 5.0 : obj.duration;
		loopAnims = obj.loopAnims == null ? true : obj.loopAnims;
		script = obj.script;
	}

	static function getObjAnimations(ctx:Context, elt: PrefabElement, anims: Array<ObjectAnimation>) {
		if(Std.instance(elt, hide.prefab.fx.Emitter) == null) {
			// Don't extract animations for children of Emitters
			for(c in elt.children) {
				getObjAnimations(ctx, c, anims);
			}
		}

		var obj3d = elt.to(hide.prefab.Object3D);
		if(obj3d == null)
			return;

		// TODO: Support references?
		var objCtx = ctx.shared.contexts.get(elt);
		if(objCtx == null || objCtx.local3d == null)
			return;

		var anyFound = false;

		function makeVal(name, def) : Value {
			var c = hide.prefab.Curve.getCurve(elt, name);
			if(c != null)
				anyFound = true;
			return c != null ? VCurve(c) : def;
		}

		function makeVector(name: String, defVal: Float, uniform: Bool=true, scale: Float=1.0) : Value {
			var curves = hide.prefab.Curve.getCurves(elt, name);
			if(curves == null || curves.length == 0)
				return null;

			anyFound = true;

			if(uniform && curves.length == 1 && curves[0].name == name)
				return scale != 1.0 ? VCurveScale(curves[0], scale) : VCurve(curves[0]);

			return hide.prefab.Curve.getVectorValue(curves, defVal, scale);
		}

		function makeColor(name: String) {
			var curves = hide.prefab.Curve.getCurves(elt, name);
			if(curves == null || curves.length == 0)
				return null;

			anyFound = true;
			return hide.prefab.Curve.getColorValue(curves);
		}

		var anim : ObjectAnimation = {
			elt: obj3d,
			obj: objCtx.local3d,
			position: makeVector("position", 0.0),
			scale: makeVector("scale", 1.0, true),
			rotation: makeVector("rotation", 0.0, 360.0),
			color: makeColor("color"),
			visibility: makeVal("visibility", null),
		};

		if(anyFound)
			anims.push(anim);
	}

	public static function makeShaderParams(ctx: Context, shaderElt: hide.prefab.Shader) {
		shaderElt.loadShaderDef(ctx);
		var shaderDef = shaderElt.shaderDef;
		if(shaderDef == null)
			return null;

		var ret : ShaderParams = [];

		for(v in shaderDef.shader.data.vars) {
			if(v.kind != Param)
				continue;

			var prop = Reflect.field(shaderElt.props, v.name);
			if(prop == null)
				prop = hide.prefab.Shader.getDefault(v.type);

			var curves = hide.prefab.Curve.getCurves(shaderElt, v.name);
			if(curves == null || curves.length == 0)
				continue;

			switch(v.type) {
				case TVec(_, VFloat) :
					var isColor = v.name.toLowerCase().indexOf("color") >= 0;
					var val = isColor ? hide.prefab.Curve.getColorValue(curves) : hide.prefab.Curve.getVectorValue(curves);
					ret.push({
						def: v,
						value: val
					});

				default:
					var base = 1.0;
					if(Std.is(prop, Float) || Std.is(prop, Int))
						base = cast prop;
					var curve = hide.prefab.Curve.getCurve(shaderElt, v.name);
					var val = Value.VConst(base);
					if(curve != null)
						val = Value.VCurveScale(curve, base);
					ret.push({
						def: v,
						value: val
					});
			}
		}

		return ret;
	}

	public static function getShaderAnims(ctx: Context, elt: PrefabElement, anims: Array<ShaderAnimation>) {
		if(Std.instance(elt, hide.prefab.fx.Emitter) == null) {
			for(c in elt.children) {
				getShaderAnims(ctx, c, anims);
			}
		}

		var shader = elt.to(hide.prefab.Shader);
		if(shader == null)
			return;

		for(shCtx in ctx.shared.getContexts(elt)) {
			if(shCtx.custom == null) continue;
			var anim: ShaderAnimation = new ShaderAnimation(new hxd.Rand(0));
			anim.shader = shCtx.custom;
			anim.params = makeShaderParams(ctx, shader);
			anims.push(anim);
		}
	}

	function getEmitters(ctx: Context, elt: PrefabElement, emitters: Array<hide.prefab.fx.Emitter.EmitterObject>) {
		var em = Std.instance(elt, hide.prefab.fx.Emitter);
		if(em != null)  {
			for(emCtx in ctx.shared.getContexts(elt)) {
				if(emCtx.local3d == null) continue;
				emitters.push(cast emCtx.local3d);
			}
		}
		else {
			for(c in elt.children) {
				getEmitters(ctx, c, emitters);
			}
		}
	}

	function getFXRoot( ctx : Context, elt : PrefabElement ) : PrefabElement {
		if( elt.name == "FXRoot" )
			return elt;
		else {
			for(c in elt.children) {
				var elt = getFXRoot(ctx, c);
				if(elt != null) return elt;
			}
		}
		return null;
	}

	function setupRenderer( ctx : Context, elt : PrefabElement )  {
		var renderProps = Std.instance(elt, hide.prefab.RenderProps);
		if(renderProps != null)
			renderProps.applyProps(ctx.local3d.getScene().renderer);
		else
			for(c in elt.children)
				setupRenderer(ctx, c);
	}

	function getContraints( ctx : Context, elt : PrefabElement, contraints : Array<hide.prefab.Constraint>){
		var co = Std.instance(elt, hide.prefab.Constraint);
		if(co != null)
			contraints.push(co);
		else
			for(c in elt.children)
				getContraints(ctx, c, contraints);
	}

	override function makeInstance( ctx : Context ) : Context {
		if( inRec ) return ctx;

		ctx = ctx.clone(this);
		var fxanim = new FXAnimation(ctx.local3d);
		fxanim.duration = duration;
		fxanim.loopAnims = loopAnims;
		ctx.local3d = fxanim;

		#if editor
		super.makeInstance(ctx);
		setupRenderer(ctx, this);
		#else
		var root = getFXRoot(ctx, this);
		if(root != null){
			for( c in root.children ){
				var co = Std.instance(c , Constraint);
				if(co == null) c.makeInstanceRec(ctx);
			}
			getContraints(ctx, root, fxanim.contraints);
			getObjAnimations(ctx, this, fxanim.objects);
		}
		else
			super.makeInstance(ctx);
		#end

		getObjAnimations(ctx, this, fxanim.objects);
		getShaderAnims(ctx, this, fxanim.shaderAnims);
		getEmitters(ctx, this, fxanim.emitters);

		if(script != ""){
			var parser = new FXScriptParser();
			var fxScript = parser.createFXScript(script, fxanim);
			fxanim.script = fxScript;
		}

		fxanim.playSpeed = 1.0;

		return ctx;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, null);
		var fxanim = Std.instance(ctx.local3d, FXAnimation);
		fxanim.duration = duration;
		fxanim.loopAnims = loopAnims;
	}

	#if editor
	override function edit( ctx : EditContext ) {
		var props = new hide.Element('
			<div class="group" name="FX Scene">
				<dl>
					<dt>Duration</dt><dd><input type="number" value="0" field="duration"/></dd>
					<dt>Loop Anims</dt><dd><input type="checkbox" field="loopAnims"/></dd>
				</dl>
			</div>');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : HideProps {
		return { icon : "cube", name : "FX" };
	}
	#end

	static var _ = hxd.prefab.Library.register("fx", FX, "fx");
}