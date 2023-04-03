package hrt.prefab2.fx;
import hrt.prefab2.fx.BaseFX.AdditionalProperies;
import hrt.prefab2.Curve;
import hrt.prefab2.Prefab as PrefabElement;
import hrt.prefab2.fx.BaseFX.ObjectAnimation;
import hrt.prefab2.fx.BaseFX.ShaderAnimation;


@:allow(hrt.prefab2.fx.FX)
class FXAnimation extends h3d.scene.Object {
	public static var defaultCullingDistance = 0.0;

	public var onEnd : Void -> Void;
	public var playSpeed : Float = 0;
	public var localTime : Float = 0.0;
	public var startDelay : Float = 0.0;
	public var duration : Float;

	/** Enable automatic culling based on `cullingRadius` and `cullingDistance`. Will override `culled` on every sync. **/
	public var autoCull(default, set) = true;
	public var cullingRadius : Float;
	public var cullingDistance = defaultCullingDistance;

	public var objAnims: Array<ObjectAnimation>;
	public var events: Array<hrt.prefab2.fx.Event.EventInstance>;
	public var emitters : Array<hrt.prefab2.fx.Emitter.EmitterObject>;
	public var trails : Array<hrt.prefab2.l3d.Trails.TrailObj>;
	public var shaderAnims : Array<ShaderAnimation> = [];
	public var constraints : Array<hrt.prefab2.l3d.Constraint>;

	var evaluator : Evaluator;
	var parentFX : FXAnimation;
	var random : hxd.Rand;
	var prevTime = -1.0;
	var randSeed : Int;
	var firstSync = true;

	public function new(?parent) {
		super(parent);
		randSeed = #if editor 0 #else Std.random(0xFFFFFF) #end;
		random = new hxd.Rand(randSeed);
		evaluator = new Evaluator();
		name = "FXAnimation";
		inheritCulled = true;
	}

	function init(def: FX, ?root: PrefabElement) {
		if(root == null)
			root = def;
		initObjAnimations(root);
		initEmitters(root);
		BaseFX.getShaderAnims(root, shaderAnims);
		if(shaderAnims.length == 0) shaderAnims = null;
		events = initEvents(root);
		var root = def.getFXRoot(def);
		initConstraints(root != null ? root : def);

		trails = findAll((p) -> Std.downcast(p, hrt.prefab2.l3d.Trails.TrailObj));
	}

	public function reset() {
		firstSync = true;
		prevTime = -1.0;
		localTime = 0;
		if(parentFX == null) {
			for(c in findAll(o -> Std.downcast(o, FXAnimation))) {
				if(c != this)
					c.reset();
			}
		}
	}

	public function setRandSeed(seed: Int) {
		randSeed = seed;
		random.init(seed);
		if(emitters != null)
			for(em in emitters)
				em.setRandSeed(randSeed);
	}

	function set_autoCull(b : Bool) {
		if(autoCull && !b)
			culled = false; // Make sure we un-cull FX when auto-cull is disabled
		return autoCull = b;
	}

	public function updateCulling(camera : h3d.Camera) {
		culled = false;
		var scale = getAbsPos().getScale();
		var uniScale = hxd.Math.abs(hxd.Math.max(hxd.Math.max(scale.x, scale.y), scale.z));
		var pos = getAbsPos().getPosition();
		tmpSphere.load(pos.x, pos.y, pos.z, cullingRadius * uniScale);
		if(!camera.frustum.hasSphere(tmpSphere))
			culled = true;

		if(!culled && cullingDistance > 0) {
			var distSq = camera.pos.distanceSq(pos);
			if(distSq > cullingDistance * cullingDistance)
				culled = true;
		}
	}

	static var tmpSphere = new h3d.col.Sphere();
	override function syncRec(ctx:h3d.scene.RenderContext) {
		var changed = posChanged;
		if( changed ) calcAbsPos();

		if( autoCull )
			updateCulling(ctx.camera);

		var old = ctx.visibleFlag;
		if( !visible || (culled && inheritCulled) )
			ctx.visibleFlag = false;

		var fullSync = ctx.visibleFlag || alwaysSyncAnimation || firstSync;
		var finishedPlaying = false;
		// TODO(ces) restore playspeed
		if(playSpeed > 0 || firstSync) {
			// This is done in syncRec() to make sure time and events are updated regarless of culling state,
			// so we restore FX in correct state when unculled
			if(parentFX != null) {
				var t = hxd.Math.max(0, parentFX.localTime - startDelay);
				setTime(t, fullSync);
			}
			else {
				var curTime = localTime;
				setTime(curTime, fullSync);
				localTime += ctx.elapsedTime * playSpeed;
				if( duration > 0 && curTime < duration && localTime >= duration) {
					localTime = duration;
					finishedPlaying = true;
				}
			}
		}

		for (t in trails) {
			t.timeScale = 0.0;
		}

		if(fullSync)
			super.syncRec(ctx);

		if( finishedPlaying && onEnd != null )
			onEnd();  // Delay until after syncRec, to avoid calling syncRec on children

		firstSync = false;
		ctx.visibleFlag = old;
	}

	static var tempMat = new h3d.Matrix();
	static var tempTransform = new h3d.Matrix();
	static var tempVec = new h3d.Vector();
	public function setTime( time : Float, fullSync=true ) {
		var dt = time - this.localTime;
		this.localTime = time;
		if(fullSync) {
			if(objAnims != null) {
				for(anim in objAnims) {
					if(anim.scale != null || anim.rotation != null || anim.position != null) {
						var m = tempMat;
						if(anim.scale != null) {
							var scale = evaluator.getVector(anim.scale, time, tempVec);
							m.initScale(scale.x, scale.y, scale.z);
						}
						else
							m.identity();

						if(anim.rotation != null) {
							var rotation = evaluator.getVector(anim.rotation, time, tempVec);
							rotation.scale3(Math.PI / 180.0);
							m.rotate(rotation.x, rotation.y, rotation.z);
						}

						var baseMat = anim.elt.getTransform(tempTransform);
						var offset = baseMat.getPosition();
						baseMat.tx = baseMat.ty = baseMat.tz = 0.0;  // Ignore
						m.multiply(baseMat, m);
						m.translate(offset.x, offset.y, offset.z);

						if(anim.position != null) {
							var pos = evaluator.getVector(anim.position, time, tempVec);
							m.translate(pos.x, pos.y, pos.z);
						}

						anim.obj.setTransform(m);
					}

					if(anim.visibility != null)
						anim.obj.visible = anim.elt.visible && evaluator.getFloat(anim.visibility, time) > 0.5;

					if(anim.color != null) {
						switch(anim.color) {
							case VCurve(a):
								for(mat in anim.obj.getMaterials())
									mat.color.a = evaluator.getFloat(anim.color, time);
							default:
								for(mat in anim.obj.getMaterials())
									mat.color.load(evaluator.getVector(anim.color, time, tempVec));
						}
					}
					Event.updateEvents(anim.events, time, prevTime);

					if( anim.additionalProperies != null ) {
						switch(anim.additionalProperies) {
							case None :
							case PointLight( color, power, size, range ) :
								var l = Std.downcast(anim.obj, h3d.scene.pbr.PointLight);
								if( l != null ) {
									if( color != null ) l.color = evaluator.getVector(color, time, tempVec);
									if( power != null ) l.power = evaluator.getFloat(power, time);
									if( size != null ) l.size = evaluator.getFloat(size, time);
									if( range != null ) l.range = evaluator.getFloat(range, time);
								}
							case DirLight(color, power):
								var l = Std.downcast(anim.obj, h3d.scene.pbr.DirLight);
								if( l != null ) {
									if( color != null ) l.color = evaluator.getVector(color, time, tempVec);
									if( power != null ) l.power = evaluator.getFloat(power, time);
								}
							case SpotLight(color, power, range, angle, fallOff):
								var l = Std.downcast(anim.obj, h3d.scene.pbr.SpotLight);
								if( l != null ) {
									if( color != null ) l.color = evaluator.getVector(color, time, tempVec);
									if( power != null ) l.power = evaluator.getFloat(power, time);
									if( range != null ) l.range = evaluator.getFloat(range, time);
									if( angle != null ) l.angle = evaluator.getFloat(angle, time);
									if( fallOff != null ) l.fallOff = evaluator.getFloat(fallOff, time);
								}
						}
					}
				}
			}

			if(shaderAnims != null)
				for(anim in shaderAnims)
					anim.setTime(time);

			if(emitters != null) {
				for(em in emitters) {
					if(em.visible)
						em.setTime(time);
				}
			}

			for (t in trails) {
				t.update(hxd.Math.max(dt, 0.0));
			}
		}

		Event.updateEvents(events, time, prevTime);

		this.prevTime = localTime;
	}

	function initEvents(elt: PrefabElement) {
		var childEvents = [for(c in elt.children) if(c.enabled && c.to(Event) != null) c.to(Event)];
		var ret = null;
		for(evt in childEvents) {
			var eventObj = evt.prepare();
			if(eventObj == null) continue;
			if(ret == null) ret = [];
			ret.push(eventObj);
		}
		return ret;
	}

	function initObjAnimations(elt: PrefabElement) {
		if(!elt.enabled) return;
		if(Std.downcast(elt, hrt.prefab2.fx.Emitter) == null) {
			// Don't extract animations for children of Emitters
			for(c in elt.children) {
				initObjAnimations(c);
			}
		}

		var obj3d = elt.to(hrt.prefab2.Object3D);
		if(obj3d == null)
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

		var ap : AdditionalProperies = null;
		var local3d = Object3D.getLocal3d(elt);
		if( Std.isOfType(local3d, h3d.scene.pbr.PointLight)) {
			ap = PointLight(makeColor("color"), makeVal("power", null), makeVal("size", null), makeVal("range", null) );
		}
		else if( Std.isOfType(local3d, h3d.scene.pbr.SpotLight)) {
			ap = SpotLight(makeColor("color"), makeVal("power", null), makeVal("range", null), makeVal("angle", null), makeVal("fallOff", null) );
		}
		else if( Std.isOfType(local3d, h3d.scene.pbr.DirLight)) {
			ap = DirLight(makeColor("color"), makeVal("power", null));
		}

		var anim : ObjectAnimation = {
			elt: obj3d,
			obj: local3d,
			events: null,
			position: makeVector("position", 0.0),
			scale: makeVector("scale", 1.0, true),
			rotation: makeVector("rotation", 0.0, 360.0),
			color: makeColor("color"),
			visibility: makeVal("visibility", null),
			additionalProperies: ap,
		};

		anim.events = initEvents(elt);
		if(anim.events != null)
			anyFound = true;

		if(anyFound) {
			if(objAnims == null) objAnims = [];
			objAnims.push(anim);
		}
	}

	function initEmitters(elt: PrefabElement) {
		if(!elt.enabled) return;
		var em = Std.downcast(elt, hrt.prefab2.fx.Emitter);
		if(em != null)  {
			var local3d = Object3D.getLocal3d(em);
			if (local3d != null) {
				if(emitters == null) emitters = [];
				var emobj : hrt.prefab2.fx.Emitter.EmitterObject = cast local3d;
				emobj.setRandSeed(randSeed);
				emitters.push(emobj);
			}
		}
		else {
			for(c in elt.children) {
				initEmitters(c);
			}
		}
	}

	function initConstraints(elt : PrefabElement ){
		if(!elt.enabled) return;
		var co = Std.downcast(elt, hrt.prefab2.l3d.Constraint);
		if(co != null) {
			if(constraints == null) constraints = [];
			constraints.push(co);
		}
		else
			for(c in elt.children)
				initConstraints(c);
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
			if( srcObj != null && targetObj != null ) {
				srcObj.follow = targetObj;
				srcObj.followPositionOnly = co.positionOnly;
			}
		}
	}
}

class FX extends BaseFX {

	public function new() {
		super();
		cullingRadius = 3.0;
	}

	/*override function save(data : Dynamic) {
		super.save(data);
		data.cullingRadius = cullingRadius;
		if( scriptCode != "" ) data.scriptCode = scriptCode;
	}*/

	override function load( obj : Dynamic ) {
		super.load(obj);
		if(obj.cullingRadius != null)
			cullingRadius = obj.cullingRadius;
		scriptCode = obj.scriptCode;
	}

	override function makeInstanceRec(params: hrt.prefab2.Prefab.InstanciateContext) : Void  {
		var fromRef = shared.parent != null;
		var useFXRoot = #if editor fromRef #else true #end;
		var root = getFXRoot(this);
		if(useFXRoot && root != null){
			var childrenBackup = children;
			children = [root];
			super.makeInstanceRec(params);
			children = childrenBackup;
		}
		else
			super.makeInstanceRec(params);
	}

	override function makeObject3d(parent3d:h3d.scene.Object):h3d.scene.Object {
		var fxanim = createInstance(parent3d);
		fxanim.duration = duration;
		fxanim.cullingRadius = cullingRadius;

		var p = fxanim.parent;
		while(p != null) {
			var fx = Std.downcast(p, FXAnimation);
			if(fx != null) {
				fxanim.parentFX = fx;
				break;
			}
			p = p.parent;
		}

		var fromRef = shared.parent != null;
		#if editor
		// only play if we are as a reference
		if( fromRef ) fxanim.playSpeed = 1.0;
		#else
		fxanim.playSpeed = 1.0;
		#end

		return fxanim;
	}

	override function postChildrenMakeInstance(ctx:hrt.prefab2.Prefab.InstanciateContext) {
		var root = getFXRoot(this);
		var fxAnim : FXAnimation = cast local3d;
		fxAnim.init(this, root);
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(null);
		var fxanim = Std.downcast(local3d, FXAnimation);
		fxanim.duration = duration;
		fxanim.cullingRadius = cullingRadius;
	}

	function createInstance(parent: h3d.scene.Object) : FXAnimation {
		return new FXAnimation(parent);
	}

	#if editor

	override function refreshObjectAnims() {
		var fxanim = Std.downcast(local3d, FXAnimation);
		fxanim.objAnims = null;
		fxanim.initObjAnimations(this);
	}

	override function edit( ctx : hide.prefab2.EditContext ) {
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

	override function getHideProps() : hide.prefab2.HideProps {
		return { icon : "cube", name : "FX", allowParent: _ -> false};
	}
	#end

	// TOCO(ces) : restore extension support
	static var _ = Prefab.register("fx", FX, "fx");
}