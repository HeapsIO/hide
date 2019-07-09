package hrt.prefab.fx;
import hrt.prefab.Curve;
import hrt.prefab.Prefab as PrefabElement;
import hrt.prefab.fx.BaseFX.ObjectAnimation;
import hrt.prefab.fx.BaseFX.ShaderAnimation;

class FX2DAnimation extends h2d.Object {

	public var prefab : hrt.prefab.Prefab;
	public var onEnd : Void -> Void;
	public var followVisibility : h3d.scene.Object;

	public var playSpeed : Float;
	public var localTime : Float = 0.0;
	public var startLoop : Float = 0.0;
	public var duration : Float;

	public var loop : Bool;
	public var objects: Array<ObjectAnimation> = [];
	public var shaderAnims : Array<ShaderAnimation> = [];
	public var constraints : Array<hrt.prefab.Constraint> = [];

	var evaluator : Evaluator;
	var random : hxd.Rand;

	public function new(?parent) {
		super(parent);
		random = new hxd.Rand(Std.random(0xFFFFFF));
		evaluator = new Evaluator(random);
		name = "FX2DAnimation";
		setTime(0);
	}

	public function setRandSeed(seed: Int) {
		random.init(seed);
	}

	public dynamic function customVisibility(self: FX2DAnimation) : Bool {
		return true;
	}

	override function sync( ctx : h2d.RenderContext ) {
		var visiblity : Bool = true;
		if(followVisibility != null)
			visiblity = visiblity && followVisibility.visible;
		if(customVisibility != null)
			visiblity = visiblity && customVisibility(this);

		this.visible = visiblity;

		super.sync(ctx);
	}

	public function setTime( time : Float ) {
		
		this.localTime = time;

		for(anim in objects) {
			if(anim.scale != null) {
				var scale = evaluator.getVector(anim.scale, time);
				anim.obj2d.scaleX = scale.x;
				anim.obj2d.scaleY = scale.y;
			}

			if(anim.rotation != null) {
				var rotation = evaluator.getVector(anim.rotation, time);
				anim.obj2d.rotation = rotation.x;
			}

			if(anim.position != null) {
				var pos = evaluator.getVector(anim.position, time);
				anim.obj2d.x = pos.x;
				anim.obj2d.y = pos.y;
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
							drawable.color = evaluator.getVector(anim.color, time);
				}
			}
			
			var atlas : Dynamic = Std.downcast(anim.elt2d, hrt.prefab.fx2d.Atlas);
			if (atlas == null) {
				atlas = Std.downcast(anim.elt2d, hrt.prefab.fx2d.Anim2D);
			}
			if (atlas != null) {
				@:privateAccess if (!atlas.loop) {
					var t = time - atlas.delayStart;
					if (t < 0) {
						atlas.h2dAnim.curFrame = 0;
					} else {
						var nbFrames = Math.floor(t*atlas.fpsAnimation);
						atlas.h2dAnim.curFrame = Math.min(nbFrames, atlas.h2dAnim.frames.length-1);
					}
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
	}
}

class FX2D extends BaseFX {
	
	var loop : Bool = false;
	var startLoop : Float = 0.0;

	public function new() {
		super();
		type = "fx2d";
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.type = type;
		obj.loop = loop;
		obj.startLoop = startLoop;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		loop = obj.loop;
		startLoop = obj.startLoop;
	}

	override public function refreshObjectAnims(ctx: Context) {
		var fxanim = Std.downcast(ctx.local2d, FX2DAnimation);
		fxanim.objects = [];
		getObjAnimations(ctx, this, fxanim.objects);
	}

	static function getObjAnimations(ctx:Context, elt: PrefabElement, anims: Array<ObjectAnimation>) {
		for(c in elt.children) {
			getObjAnimations(ctx, c, anims);
		}
		
		var obj2d = elt.to(hrt.prefab.Object2D);
		if(obj2d == null)
			return;

		// TODO: Support references?
		var objCtx = ctx.shared.contexts.get(elt);
		if(objCtx == null || objCtx.local2d == null)
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
			elt2d: obj2d,
			obj2d: objCtx.local2d,
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

		if (Std.is(elt, hrt.prefab.fx2d.Anim2D) || Std.is(elt, hrt.prefab.fx2d.Atlas))
			anyFound = true;

		if(anyFound)
			anims.push(anim);
	}

	override function make( ctx : Context ) : Context {
		ctx = ctx.clone(this);
		var fxanim = createInstance(ctx.local2d);
		fxanim.duration = duration;
		fxanim.loop = loop;
		fxanim.startLoop = startLoop;
		ctx.local2d = fxanim;
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

		return ctx;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, null);
		var fxanim = Std.downcast(ctx.local2d, FX2DAnimation);
		fxanim.duration = duration;
		fxanim.loop = loop;
	}

	function createInstance(parent: h2d.Object) : FX2DAnimation {
		return new FX2DAnimation(parent);
	}

	#if editor
	override function edit( ctx : EditContext ) {
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

	override function getHideProps() : HideProps {
		return { icon : "cube", name : "FX2D", allowParent: _ -> false};
	}
	#end

	static var _ = Library.register("fx2d", FX2D, "fx2d");
}