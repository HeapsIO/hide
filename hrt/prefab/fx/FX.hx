package hrt.prefab.fx;
import hrt.prefab.Curve;
import hrt.prefab.Prefab as PrefabElement;
import hrt.prefab.fx.BaseFX.ObjectAnimation;
import hrt.prefab.fx.BaseFX.ShaderAnimation;

class FXAnimation extends h3d.scene.Object {

	public var onEnd : Void -> Void;
	public var playSpeed : Float;
	public var localTime : Float = 0.0;
	public var duration : Float;
	public var cullingRadius : Float;

	public var objects: Array<ObjectAnimation> = [];
	public var shaderAnims : Array<ShaderAnimation> = [];
	public var emitters : Array<hrt.prefab.fx.Emitter.EmitterObject> = [];
	public var constraints : Array<hrt.prefab.Constraint> = [];
	public var script : hrt.prefab.fx.FXScript;

	var evaluator : Evaluator;
	var random : hxd.Rand;

	public function new(?parent) {
		super(parent);
		random = new hxd.Rand(Std.random(0xFFFFFF));
		evaluator = new Evaluator(random);
		name = "FXAnimation";
		setTime(0);
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

	override function syncRec( ctx : h3d.scene.RenderContext ) {
		for(emitter in emitters)
			emitter.setParticleVibility(visible && !culled);

		#if !editor
		if(playSpeed > 0) {
			var curTime = localTime;
			setTime(curTime);

			localTime += ctx.elapsedTime * playSpeed;
			if(duration > 0 && curTime < duration && localTime >= duration) {
				setTime(duration);
				if(onEnd != null )
					onEnd();
			}
		}
		#end

		super.syncRec(ctx);
	}

	static var tempMat = new h3d.Matrix();
	public function setTime( time : Float ) {
		this.localTime = time;
		if(culled || !visible)
			return;
		for(anim in objects) {
			var m = tempMat;
			if(anim.scale != null) {
				var scale = evaluator.getVector(anim.scale, time);
				m.initScale(scale.x, scale.y, scale.z);
			}
			else
				m.identity();

			if(anim.rotation != null) {
				var rotation = evaluator.getVector(anim.rotation, time);
				rotation.scale3(Math.PI / 180.0);
				m.rotate(rotation.x, rotation.y, rotation.z);
			}

			var baseMat = anim.elt.getTransform();
			var offset = baseMat.getPosition();
			baseMat.tx = baseMat.ty = baseMat.tz = 0.0;  // Ignore
			m.multiply(baseMat, m);
			m.translate(offset.x, offset.y, offset.z);

			if(anim.position != null) {
				var pos = evaluator.getVector(anim.position, time);
				m.translate(pos.x, pos.y, pos.z);
			}

			anim.obj.setTransform(m);

			if(anim.visibility != null)
				anim.obj.visible = anim.elt.visible && evaluator.getFloat(anim.visibility, time) > 0.5;

			if(anim.color != null) {
				switch(anim.color) {
					case VCurve(a):
						for(mat in anim.obj.getMaterials())
							mat.color.a = evaluator.getFloat(anim.color, time);
					default:
						for(mat in anim.obj.getMaterials())
							mat.color = evaluator.getVector(anim.color, time);
				}
			}

			if(anim.events != null) {
				for(evt in anim.events) {
					evt.setTime(time - evt.evt.time);
				}
			}
		}

		for(anim in shaderAnims) {
			anim.setTime(time);
		}

		for(em in emitters) {
			if(em.visible)
				em.setTime(time);
		}

		if(script != null)
			script.update();
	}

	public function resolveConstraints( caster : h3d.scene.Object ) {
		for( co in constraints ) {
			if( !co.enabled )
		 		continue;

			var objectName = co.object.split(".").pop();
			var targetName = co.target.split(".").pop();

			var isInFX = co.object.split(".")[1] == "FXRoot";
			var srcObj = objectName == "FXRoot" ? this : isInFX ? this.getObjectByName(objectName) : caster.getObjectByName(objectName);
			var targetObj = caster.getObjectByName(targetName);
			if(targetObj == null)
				targetObj = caster;
			if( srcObj != null && targetObj != null ){
				srcObj.follow = targetObj;
				srcObj.followPositionOnly = co.positionOnly;
			}
			else
				trace ("Failed te resolve constraint for FX : " + name);
		}
	}
}

class FX extends BaseFX {

	public function new() {
		super();
		type = "fx";
		cullingRadius = 3.0;
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.cullingRadius = cullingRadius;
		if( scriptCode != "" ) obj.scriptCode = scriptCode;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		if(obj.cullingRadius != null)
			cullingRadius = obj.cullingRadius;
		scriptCode = obj.scriptCode;
	}

	override public function refreshObjectAnims(ctx: Context) {
		var fxanim = Std.downcast(ctx.local3d, FXAnimation);
		fxanim.objects = [];
		getObjAnimations(ctx, this, fxanim.objects);
	}

	static function getObjAnimations(ctx:Context, elt: PrefabElement, anims: Array<ObjectAnimation>) {
		if(Std.downcast(elt, hrt.prefab.fx.Emitter) == null) {
			// Don't extract animations for children of Emitters
			for(c in elt.children) {
				getObjAnimations(ctx, c, anims);
			}
		}

		var obj3d = elt.to(hrt.prefab.Object3D);
		if(obj3d == null)
			return;

		// TODO: Support references?
		var objCtx = ctx.shared.contexts.get(elt);
		if(objCtx == null || objCtx.local3d == null)
			return;

		var anyFound = false;

		function makeVal(name, def) : Value {
			var c = Curve.getCurve(elt, name);
			if(c != null)
				anyFound = true;
			return c != null ? VCurve(c) : def;
		}

		function makeVector(name: String, defVal: Float, uniform: Bool=true, scale: Float=1.0) : Value {
			var curves = Curve.getCurves(elt, name);
			if(curves == null || curves.length == 0)
				return null;

			anyFound = true;

			if(uniform && curves.length == 1 && curves[0].name == name)
				return scale != 1.0 ? VCurveScale(curves[0], scale) : VCurve(curves[0]);

			return Curve.getVectorValue(curves, defVal, scale);
		}

		function makeColor(name: String) {
			var curves = Curve.getCurves(elt, name);
			if(curves == null || curves.length == 0)
				return null;

			anyFound = true;
			return Curve.getColorValue(curves);
		}

		var anim : ObjectAnimation = {
			elt: obj3d,
			obj: objCtx.local3d,
			events: null,
			position: makeVector("position", 0.0),
			scale: makeVector("scale", 1.0, true),
			rotation: makeVector("rotation", 0.0, 360.0),
			color: makeColor("color"),
			visibility: makeVal("visibility", null),
		};

		for(evt in elt.getAll(Event)) {
			var eventObj = evt.prepare(objCtx);
			if(eventObj == null) continue;
			if(anim.events == null) anim.events = [];
			anim.events.push(eventObj);
			anyFound = true;
		}

		if(anyFound)
			anims.push(anim);
	}

	function getEmitters(ctx: Context, elt: PrefabElement, emitters: Array<hrt.prefab.fx.Emitter.EmitterObject>) {
		var em = Std.downcast(elt, hrt.prefab.fx.Emitter);
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

	override function make( ctx : Context ) : Context {
		ctx = ctx.clone(this);
		var fxanim = createInstance(ctx.local3d);
		fxanim.duration = duration;
		fxanim.cullingRadius = cullingRadius;
		ctx.local3d = fxanim;
		fxanim.playSpeed = 1.0;

		#if editor
		super.make(ctx);
		#else
		var root = getFXRoot(ctx, this);
		if(root != null){
			for( c in root.children ){
				var co = Std.downcast(c , Constraint);
				if(co == null) c.make(ctx);
			}
			getConstraints(ctx, root, fxanim.constraints);
		}
		else
			super.make(ctx);
		#end

		getObjAnimations(ctx, this, fxanim.objects);
		BaseFX.getShaderAnims(ctx, this, fxanim.shaderAnims);
		getEmitters(ctx, this, fxanim.emitters);

		if(scriptCode != null && scriptCode != ""){
			var parser = new FXScriptParser();
			fxanim.script = parser.createFXScript(scriptCode, fxanim);
			fxanim.script.init();
		}

		return ctx;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, null);
		var fxanim = Std.downcast(ctx.local3d, FXAnimation);
		fxanim.duration = duration;
		fxanim.cullingRadius = cullingRadius;
	}

	function createInstance(parent: h3d.scene.Object) : FXAnimation {
		return new FXAnimation(parent);
	}

	#if editor
	override function edit( ctx : EditContext ) {
		var props = new hide.Element('
			<div class="group" name="FX Scene">
				<dl>
					<dt>Duration</dt><dd><input type="number" value="0" field="duration"/></dd>
					<dt>Culling radius</dt><dd><input type="number" field="cullingRadius"/></dd>
				</dl>
			</div>');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : HideProps {
		return { icon : "cube", name : "FX", allowParent: _ -> false};
	}
	#end

	static var _ = Library.register("fx", FX, "fx");
}