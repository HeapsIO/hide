package hrt.prefab2.fx;
import hrt.prefab2.Curve;
import hrt.prefab2.Prefab as PrefabElement;
import hrt.prefab2.fx.BaseFX.ObjectAnimation;
import hrt.prefab2.fx.BaseFX.ShaderAnimation;

@:allow(hrt.prefab2.fx.FX2D)
class FX2DAnimation extends h2d.Object {

	public var prefab : hrt.prefab2.Prefab;
	public var onEnd : Void -> Void;

	public var playSpeed : Float;
	public var localTime : Float = 0.0;
	var prevTime = -1.0;
	public var startLoop : Float = 0.0;
	public var duration : Float;

	public var loop : Bool;
	public var objects: Array<ObjectAnimation> = [];
	public var shaderAnims : Array<ShaderAnimation> = [];
	public var emitters : Array<hrt.prefab2.l2d.Particle2D.Particles>;
	public var events: Array<hrt.prefab2.fx.Event.EventInstance>;

	var evaluator : Evaluator;
	var random : hxd.Rand;

	public function new(?parent) {
		super(parent);
		random = new hxd.Rand(Std.random(0xFFFFFF));
		evaluator = new Evaluator();
		name = "FX2DAnimation";
		setTime(0);
	}

	public function setRandSeed(seed: Int) {
		random.init(seed);
	}

	function init(def: FX2D) {
		initEmitters(def);
		if (def.children.length == 1 && def.children[0].name == "FXRoot")
			events = initEvents(def.children[0]);
		else
			events = initEvents(def);
	}

	function initEmitters(elt: PrefabElement) {
		var em = Std.downcast(elt, hrt.prefab2.l2d.Particle2D);
		if(em != null)  {
			if(em.local2d == null) return;
			if(emitters == null) emitters = [];
			var emobj : hrt.prefab2.l2d.Particle2D.Particles = cast em.local2d;
			emitters.push(emobj);
		}
		else {
			for(c in elt.children) {
				initEmitters(c);
			}
		}
	}

	function initEvents(elt: PrefabElement) {
		var childEvents = [for(c in elt.children) if(c.to(Event) != null) c.to(Event)];
		var ret = null;
		for(evt in childEvents) {
			var eventObj = evt.prepare();
			if(eventObj == null) continue;
			if(ret == null) ret = [];
			ret.push(eventObj);
		}
		return ret;
	}


	static var tmpPt = new h3d.Vector();
	public function setTime( time : Float ) {

		this.localTime = time;

		for(anim in objects) {
			if(anim.scale != null) {
				evaluator.getVector(anim.scale, time, tmpPt);
				anim.obj2d.scaleX = tmpPt.x;
				anim.obj2d.scaleY = tmpPt.y;
			}

			if(anim.rotation != null) {
				var rotation = evaluator.getFloat(anim.rotation, time);
				anim.obj2d.rotation = rotation * (Math.PI / 180.0);
			}

			if(anim.position != null) {
				evaluator.getVector(anim.position, time, tmpPt);
				anim.obj2d.x = anim.elt2d.x + tmpPt.x;
				anim.obj2d.y = anim.elt2d.y + tmpPt.y;
			}

			if(anim.visibility != null)
				anim.obj2d.visible = anim.elt2d.visible && evaluator.getFloat(anim.visibility, time) > 0.5;

			if(anim.color != null) {
				switch(anim.color) {
					case VCurve(a):
						anim.obj2d.alpha = evaluator.getFloat(anim.color, time);
					default:
						var drawable = Std.downcast(anim.obj2d, h2d.Drawable);
						if (drawable != null)
							evaluator.getVector(anim.color, time, drawable.color);
				}
			}

			var atlas : Dynamic = Std.downcast(anim.elt2d, hrt.prefab2.l2d.Atlas);
			if (atlas == null) {
				atlas = Std.downcast(anim.elt2d, hrt.prefab2.l2d.Anim2D);
			}
			if (atlas != null) {
				@:privateAccess if (!atlas.loop) {
					var t = time - atlas.delayStart;
					if (t < 0) {
						(cast anim.obj2d : h2d.Anim).curFrame = 0;
					} else {
						var nbFrames = Math.floor(t*atlas.fpsAnimation);
						(cast anim.obj2d : h2d.Anim).curFrame = Math.min(nbFrames, (cast anim.obj2d : h2d.Anim).frames.length-1);
					}
				}
			}
		}

		for(anim in shaderAnims) {
			anim.setTime(time);
		}
		if (emitters != null) {
			for(em in emitters) {
				if(em.visible)
					em.setTime(time);
			}
		}

		Event.updateEvents(events, time, prevTime);

		this.prevTime = localTime;
	}

	override function sync( ctx : h2d.RenderContext ) {
		var changed = posChanged;
		if( changed ) calcAbsPos();

		if( visible && playSpeed > 0 ) {
			var curTime = localTime;
			setTime(curTime);
			localTime += ctx.elapsedTime * playSpeed;
			if( duration > 0 && curTime < duration && localTime >= duration) {
				localTime = duration;
				if( onEnd != null )
					onEnd();
			}
			super.sync(ctx);
		}
	}
}

class FX2D extends Object2D implements BaseFX {

	@:s public var duration : Float;
	@:s public var startDelay : Float;
	@:c public var scriptCode : String;
	@:c public var cullingRadius : Float;
	@:c public var markers : Array<{t: Float}> = [];

	@:s var loop : Bool = false;
	@:s var startLoop : Float = 0.0;

	public function new() {
		super();
	}

	function getObjAnimations(elt: PrefabElement, anims: Array<ObjectAnimation>) {
		for(c in elt.children) {
			getObjAnimations(c, anims);
		}

		var obj2d = elt.to(hrt.prefab2.Object2D);
		if(obj2d == null)
			return;

		// TODO: Support references?
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
			elt2d: obj2d,
			obj2d: local2d,
			events: null,
			position: makeVector("position", 0.0),
			scale: makeVector("scale", 1.0, true),
			rotation: makeVector("rotation", 0.0, 360.0),
			color: makeColor("color"),
			visibility: makeVal("visibility", null),
		};

		for(evt in elt.getAll(Event)) {
			var eventObj = evt.prepare();
			if(eventObj == null) continue;
			if(anim.events == null) anim.events = [];
			anim.events.push(eventObj);
			anyFound = true;
		}

		if (Std.isOfType(elt, hrt.prefab2.l2d.Anim2D) || Std.isOfType(elt, hrt.prefab2.l2d.Atlas))
			anyFound = true;

		if(anyFound)
			anims.push(anim);
	}

	override function makeInstanceRec(params: hrt.prefab2.Prefab.InstanciateContext) : Void {
		#if editor
		super.makeInstanceRec(params);
		#else
		var fromRef = shared.parent != null;
		var useFXRoot = #if editor fromRef #else true #end;
		var root = hrt.prefab2.fx.BaseFX.BaseFXTools.getFXRoot(this);
		if( useFXRoot && root != null ) {
			var childrenBackup = children;
			children = [root];
			super.makeInstanceRec(params);
			children = childrenBackup;
		} else
			super.makeInstanceRec(params);
		#end
	}


	override function postMakeInstance(ctx: hrt.prefab2.Prefab.InstanciateContext) {
		var fxanim : FX2DAnimation = cast local2d;
		fxanim.init(this);
		getObjAnimations(this, fxanim.objects);
		hrt.prefab2.fx.BaseFX.BaseFXTools.getShaderAnims(this, fxanim.shaderAnims);
	}

	override function makeObject2d(parent2d: h2d.Object) : h2d.Object {
		var fxanim = createInstance(parent2d);
		fxanim.duration = duration;
		fxanim.loop = loop;
		fxanim.startLoop = startLoop;
		fxanim.playSpeed = 1.0;

		return fxanim;
	}

	public function getTargetShader2D(name : String ) {
		return local2d;
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);
		var fxanim = Std.downcast(local2d, FX2DAnimation);
		fxanim.duration = duration;
		fxanim.loop = loop;
	}

	function createInstance(parent: h2d.Object) : FX2DAnimation {
		var inst = new FX2DAnimation(parent);
		inst.prefab = this;
		return inst;
	}

	#if editor
	public function refreshObjectAnims() {
		var fxanim = Std.downcast(local2d, FX2DAnimation);
		fxanim.objects = [];
		getObjAnimations(this, fxanim.objects);
	}

	override function edit( ctx : hide.prefab2.EditContext ) {
		var props = new hide.Element('
			<div class="group" name="FX2D Scene">
				<dl>
					<dt>Duration</dt><dd><input type="number" value="0" field="duration"/></dd>
					<dt>Loop</dt><dd><input type="checkbox" field="loop"/></dd>
					<dt>Start loop</dt><dd><input type="range" min="0" max="5" field="startLoop"/></dd>
				</dl>
			</div>');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : hide.prefab2.HideProps {
		return { icon : "cube", name : "FX2D", allowParent: _ -> false};
	}
	#end

	static var _ = Prefab.register("fx2d", FX2D, "fx2d");
}