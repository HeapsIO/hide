package hrt.prefab.fx;
import hrt.prefab.Curve;
import hrt.prefab.Prefab as PrefabElement;
import hrt.prefab.fx.BaseFX.ObjectAnimation;
import hrt.prefab.fx.BaseFX.ShaderAnimation;
import hrt.prefab.fx.Event;

@:allow(hrt.prefab.fx.FX2D)
class FX2DAnimation extends h2d.Object {

	public var prefab : hrt.prefab.Prefab;
	public var onEnd : Void -> Void;

	public var playSpeed : Float;
	public var localTime : Float = 0.0;
	var prevTime = -1.0;
	public var startLoop : Float = 0.0;
	public var duration : Float;

	public var loop : Bool;
	public var objects: Array<ObjectAnimation> = [];
	public var customAnims : Array<BaseFX.CustomAnimation> = [];
	public var emitters : Array<hrt.prefab.l2d.Particle2D.Particles>;
	public var events: Array<hrt.prefab.fx.Event.EventInstance>;

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
		var em = Std.downcast(elt, hrt.prefab.l2d.Particle2D);
		if(em != null)  {
			if(em.local2d == null) return;
				if(emitters == null) emitters = [];
			var emobj : hrt.prefab.l2d.Particle2D.Particles = cast em.local2d;
				emitters.push(emobj);
			}
		else {
			for(c in elt.children) {
				initEmitters(c);
			}
		}
	}

	function initEvents(elt: PrefabElement, ?out : Array<Event.EventInstance> ) : Array<Event.EventInstance> {
		if (elt == null || @:privateAccess !elt.shouldBeInstanciated())
			return out;

		if( Std.isOfType(elt, IEvent) ) {
			var asEvent = cast(elt, IEvent);
			var eventObj = asEvent.prepare();
			if(eventObj != null) {
				if(out == null) out = [];
				out.push(eventObj);
			}
		}

		var sub = Std.downcast(elt, SubFX);
		if (sub != null) {
			var eventLen = out?.length ?? 0;
			out = initEvents(sub.refInstance, out);
			Std.downcast(sub.refInstance.findFirstLocal2d(), FX2DAnimation).events = null;
			if (out != null) {
				// Offset the start time of the events that were added to our array in
				// init events
				for (i in eventLen...out.length) {
					out[i].evt.time += sub.time;
				}
			}
		}

		for(child in elt.children) {
			out = initEvents(child, out);
		}
		return out;
	}


	static var tmpPt = new h3d.Vector4();
	public function setTime( time : Float ) {

		this.localTime = time;

		for(anim in objects) {
			if(anim.scale != null) {
				evaluator.getVector(anim.scale, time, tmpPt);
				anim.obj2d.scaleX = anim.elt2d.scaleX * tmpPt.x;
				anim.obj2d.scaleY = anim.elt2d.scaleY * tmpPt.y;
			}

			if(anim.rotation != null) {
				var rotation = evaluator.getFloat(anim.rotation, time);
				anim.obj2d.rotation = anim.elt2d.rotation + rotation * (Math.PI / 180.0);
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

			var atlas : Dynamic = Std.downcast(anim.elt2d, hrt.prefab.l2d.Atlas);
			if (atlas == null) {
				atlas = Std.downcast(anim.elt2d, hrt.prefab.l2d.Anim2D);
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

		if(customAnims != null)
			for(anim in customAnims)
				anim.setTime(time);

		if (emitters != null) {
			for(em in emitters) {
				if(em.visible)
					em.setTime(time);
			}
		}

		Event.updateEvents(events, time, prevTime, duration);

		this.prevTime = localTime;
	}

	override function sync( ctx : h2d.RenderContext ) {
		var changed = posChanged;
		if( changed ) calcAbsPos();

		if( visible && playSpeed > 0 ) {
			var curTime = localTime;
			setTime(curTime);
			super.sync(ctx);
			localTime += ctx.elapsedTime * playSpeed;

			if (loop && localTime > duration) {
				localTime = (localTime % duration);
			}

			if( duration > 0 && curTime < duration && localTime >= duration) {
				localTime = duration;
				if( onEnd != null )
					onEnd();
			}
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


	function getObjAnimations(elt: PrefabElement, anims: Array<ObjectAnimation>) {
		for(c in elt.children) {
			getObjAnimations(c, anims);
		}

		var obj2d = elt.to(hrt.prefab.Object2D);
		if(obj2d == null || obj2d.local2d == null)
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
				return scale != 1.0 ? VMult(curves[0].makeVal(), VConst(scale)) : curves[0].makeVal();

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
			obj2d: obj2d.local2d,
			position: makeVector("position", 0.0),
			scale: makeVector("scale", 1.0, true),
			rotation: makeVector("rotation", 0.0, 360.0),
			color: makeColor("color"),
			visibility: makeVal("visibility", null),
		};

		if (Std.isOfType(elt, hrt.prefab.l2d.Anim2D) || Std.isOfType(elt, hrt.prefab.l2d.Atlas))
			anyFound = true;

		if(anyFound)
			anims.push(anim);
	}

	override function make( ?sh:hrt.prefab.Prefab.ContextMake) : Prefab {
		#if editor
		return super.__makeInternal(sh);
		#else
		var fromRef = shared.parentPrefab != null;
		var useFXRoot = #if editor fromRef #else true #end;
		var root = hrt.prefab.fx.BaseFX.BaseFXTools.getFXRoot(this);
		if( useFXRoot && root != null ) {
			var childrenBackup = children;
			children = [root];
			var r = super.__makeInternal(sh);
			children = childrenBackup;
			return r;
		} else
			return super.__makeInternal(sh);
		#end
	}


	override function postMakeInstance() {
		var fxanim : FX2DAnimation = cast local2d;
		fxanim.init(this);
		getObjAnimations(this, fxanim.objects);
		hrt.prefab.fx.BaseFX.BaseFXTools.getCustomAnimations(this, fxanim.customAnims);
	}

	override function makeObject(parent2d: h2d.Object) : h2d.Object {
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

	override function onEditorTreeChanged(child: Prefab) : hrt.prefab.Prefab.TreeChangedResult {
		return Rebuild;
	}

	public function refreshObjectAnims() {
		var fxanim = Std.downcast(local2d, FX2DAnimation);
		fxanim.objects = [];
		getObjAnimations(this, fxanim.objects);
	}

	override function edit( ctx : hide.prefab.EditContext ) {
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

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "cube", name : "FX2D", allowParent: _ -> false};
	}
	#end

	static var _ = Prefab.register("fx2d", FX2D, "fx2d");
}