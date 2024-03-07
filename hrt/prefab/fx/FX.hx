package hrt.prefab.fx;
import hrt.prefab.fx.BaseFX.AdditionalProperies;
import hrt.prefab.Curve;
import hrt.prefab.Prefab as PrefabElement;
import hrt.prefab.fx.BaseFX.ObjectAnimation;
import hrt.prefab.fx.BaseFX.ShaderAnimation;
import hrt.prefab.fx.Event;


@:allow(hrt.prefab.fx.FX)
class FXAnimation extends h3d.scene.Object {
	public static var defaultCullingDistance = 0.0;

	public var onEnd : Void -> Void;
	public var playSpeed : Float = 0;
	public var localTime : Float = 0.0;
	public var startDelay : Float = 0.0;
	public var loop : Bool = false;
	public var duration : Float;

	/** Enable automatic culling based on `cullingRadius` and `cullingDistance`. Will override `culled` on every sync. **/
	public var autoCull(default, set) = true;
	public var cullingRadius : Float;
	public var cullingDistance = defaultCullingDistance;

	public var blendFactor: Float;

	public var objAnims: Array<ObjectAnimation>;
	public var events: Array<hrt.prefab.fx.Event.EventInstance>;
	public var emitters : Array<hrt.prefab.fx.Emitter.EmitterObject>;
	public var trails : Array<hrt.prefab.l3d.Trails.TrailObj>;
	public var shaderAnims : Array<ShaderAnimation> = [];
	public var constraints : Array<hrt.prefab.l3d.Constraint>;

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
		hrt.prefab.fx.BaseFX.BaseFXTools.getShaderAnims(root, shaderAnims);
		if(shaderAnims.length == 0) shaderAnims = null;
		events = initEvents(root, events);
		var root = hrt.prefab.fx.BaseFX.BaseFXTools.getFXRoot(def);
		initConstraints(root != null ? root : def);

		trails = findAll((p) -> Std.downcast(p, hrt.prefab.l3d.Trails.TrailObj));
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
		if(playSpeed > 0 || firstSync) {
			// This is done in syncRec() to make sure time and events are updated regarless of culling state,
			// so we restore FX in correct state when unculled
			if(parentFX != null) {
				var t = hxd.Math.max(0, parentFX.localTime - startDelay);
				if (loop) {
					t = (t % duration);
				}
				setTime(t, fullSync);
			}
			else {
				var curTime = localTime;
				setTime(curTime, fullSync);
				localTime += ctx.elapsedTime * playSpeed;
				if( loop && duration > 0 ) {
					localTime = (localTime % duration);
				}
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
	static var tempVec = new h3d.Vector4();
	public function setTime( time : Float, fullSync=true ) {
		var dt = time - this.prevTime;
		this.localTime = time;
		if(fullSync) {
			if(objAnims != null) {
				for(anim in objAnims) {
					if(anim.scale != null || anim.rotation != null || anim.position != null
						|| anim.localRotation != null || anim.localPosition != null) {
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

						if(anim.localRotation != null) {
							var rotation = evaluator.getVector(anim.localRotation, time, tempVec);
							rotation.scale3(Math.PI / 180.0);

							var children = anim.obj.findAll(o -> Std.downcast(o, h3d.scene.Mesh));
							for (c in children) {
								var localTempMat = c.getTransform();
								localTempMat.initRotation(rotation.x, rotation.y, rotation.z);
								c.setTransform(localTempMat);
							}
						}

						if(anim.localPosition != null) {
							var localPosition = evaluator.getVector(anim.localPosition, time, tempVec);
							var children = anim.obj.findAll(o -> Std.downcast(o, h3d.scene.Mesh));
							for (c in children) {
								var localTempMat = c.getTransform();
								localTempMat.tx = localTempMat.ty = localTempMat.tz = 0;
								localTempMat.translate(localPosition.x, localPosition.y, localPosition.z);
								c.setTransform(localTempMat);
							}
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
									if( color != null ) {
										var v = evaluator.getVector(color, time, tempVec);
										l.color.set(v.x, v.y, v.z);
									}
									if( power != null ) l.power = evaluator.getFloat(power, time);
									if( size != null ) l.size = evaluator.getFloat(size, time);
									if( range != null ) l.range = evaluator.getFloat(range, time);
								}
							case DirLight(color, power):
								var l = Std.downcast(anim.obj, h3d.scene.pbr.DirLight);
								if( l != null ) {
									if( color != null ) {
										var v = evaluator.getVector(color, time, tempVec);
										l.color.set(v.x, v.y, v.z);
									}
									if( power != null ) l.power = evaluator.getFloat(power, time);
								}
							case SpotLight(color, power, range, angle, fallOff):
								var l = Std.downcast(anim.obj, h3d.scene.pbr.SpotLight);
								if( l != null ) {
									if( color != null ) {
										var v = evaluator.getVector(color, time, tempVec);
										l.color.set(v.x, v.y, v.z);
									}
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

	function initEvents(elt: PrefabElement, ?out : Array<Event.EventInstance> ) {
		var childEvents = [for(c in elt.children) if(c.enabled && c.to(Event) != null) c.to(Event)];
		for(evt in childEvents) {
			var eventObj = evt.prepare();
			if(eventObj == null) continue;
			if(out == null) out = [];
			out.push(eventObj);
		}
		return out;
	}

	function initObjAnimations(elt: PrefabElement) {
		if(@:privateAccess !elt.shouldBeInstanciated()) return;
		if(Std.downcast(elt, hrt.prefab.fx.Emitter) == null) {
			// Don't extract animations for children of Emitters
			for(c in elt.children) {
				initObjAnimations(c);
			}
		}

		var obj3d = elt.to(hrt.prefab.Object3D);
		if(obj3d == null)
			return;

		var anyFound = false;

		function makeVal(name, def) : Value {
			var c = Curve.getCurve(elt, name);
			if(c != null)
				anyFound = true;

			if (c == null)
				return def;

			return c.blendMode == CurveBlendMode.Blend ? VBlendCurve(c, blendFactor) : VCurve(c);
		}

		function makeVector(name: String, defVal: Float, uniform: Bool=true, scale: Float=1.0) : Value {
			var curves = Curve.getCurves(elt, name);
			if(curves == null || curves.length == 0)
				return null;

			anyFound = true;

			if(uniform && curves.length == 1 && curves[0].name == name) {
				if (curves[0].blendMode == CurveBlendMode.Blend)
					return VBlendCurve(curves[0], blendFactor);

				return scale != 1.0 ? VCurveScale(curves[0], scale) : VCurve(curves[0]);
			}

			return Curve.getVectorValue(curves, defVal, scale, blendFactor);
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
			localPosition: makeVector("localPosition", 0.0),
			scale: makeVector("scale", 1.0, true),
			rotation: makeVector("rotation", 0.0, 360.0),
			localRotation: makeVector("localRotation", 0.0, 360.0),
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
		var em = Std.downcast(elt, hrt.prefab.fx.Emitter);
		if(em != null)  {
			var local3d = Object3D.getLocal3d(em);
			if (local3d != null) {
				if(emitters == null) emitters = [];
				var emobj : hrt.prefab.fx.Emitter.EmitterObject = cast local3d;
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
		var co = Std.downcast(elt, hrt.prefab.l3d.Constraint);
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

class FX extends Object3D implements BaseFX {

	@:s public var duration : Float;
	@:s public var startDelay : Float = 0.0;
	@:c public var scriptCode : String;
	@:s public var cullingRadius : Float;
	@:s public var markers : Array<{t: Float}> = [];
	@:c public var blendFactor : Float;


	/*override function save(data : Dynamic) {
		super.save(data);
		data.cullingRadius = cullingRadius;
		if( scriptCode != "" ) data.scriptCode = scriptCode;
	}*/

	public function new(parent:Prefab, contextShared: ContextShared) {
		super(parent, contextShared);
		duration = 5.0;
		cullingRadius = 3.0;
		blendFactor = 1.0;
	}

	override function make( ?sh:hrt.prefab.Prefab.ContextMake) : Prefab  {
		var fromRef = shared.parentPrefab != null;
		var useFXRoot = #if editor fromRef #else true #end;
		var root = hrt.prefab.fx.BaseFX.BaseFXTools.getFXRoot(this);
		if(useFXRoot && root != null){
			var childrenBackup = children;
			children = [root];
			var r = super.__makeInternal(sh);
			children = childrenBackup;
			return r;
		}
		else
			return super.__makeInternal(sh);
	}

	override function makeObject(parent3d:h3d.scene.Object):h3d.scene.Object {
		var fxanim = createInstance(parent3d);
		fxanim.duration = duration;
		fxanim.cullingRadius = cullingRadius;
		fxanim.blendFactor = blendFactor;

		var p = fxanim.parent;
		while(p != null) {
			var fx = Std.downcast(p, FXAnimation);
			if(fx != null) {
				fxanim.parentFX = fx;
				break;
			}
			p = p.parent;
		}

		var fromRef = shared.parentPrefab != null;
		#if editor
		// only play if we are as a reference
		if( fromRef ) fxanim.playSpeed = 1.0;
		#else
		fxanim.playSpeed = 1.0;
		#end

		return fxanim;
	}

	override function postMakeInstance() {
		var root = hrt.prefab.fx.BaseFX.BaseFXTools.getFXRoot(this);
		var fxAnim : FXAnimation = cast local3d;
		fxAnim.init(this, root);
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(null);
		var fxanim = Std.downcast(local3d, FXAnimation);
		fxanim.duration = duration;
		fxanim.cullingRadius = cullingRadius;
		fxanim.blendFactor = blendFactor;

		// Populate the value among blend curves
		var curves = this.flatten(Curve);
		for (curve in curves) {
			if (curve.blendMode == CurveBlendMode.Blend)
				curve.blendFactor = blendFactor;
		}
	}

	function createInstance(parent: h3d.scene.Object) : FXAnimation {
		return new FXAnimation(parent);
	}

	#if editor

	public function refreshObjectAnims() : Void {
		var fxanim = Std.downcast(local3d, FXAnimation);
		fxanim.objAnims = null;
		fxanim.initObjAnimations(this);
	}

	override function edit( ctx : hide.prefab.EditContext ) {
		var props = new hide.Element('
			<div class="group" name="FX Scene">
				<dl>
					<dt>Duration</dt><dd><input type="number" value="0" field="duration"/></dd>
					<dt>Culling radius</dt><dd><input type="number" field="cullingRadius"/></dd>
					<dt>Blend factor</dt><dd><input type="range" field="blendFactor" min="0" max="1"/></dd>
				</dl>
			</div>');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "cube", name : "FX", allowParent: _ -> false};
	}
	#end

	// TOCO(ces) : restore extension support
	static var _ = Prefab.register("fx", FX, "fx");
}