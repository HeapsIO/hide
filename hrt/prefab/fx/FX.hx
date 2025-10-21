package hrt.prefab.fx;
import hrt.prefab.fx.BaseFX.AdditionalProperies;
import hrt.prefab.Curve;
import hrt.prefab.Prefab as PrefabElement;
import hrt.prefab.fx.BaseFX.ObjectAnimation;
import hrt.prefab.fx.BaseFX.ShaderAnimation;
import hrt.prefab.fx.Event;

/**
	What part of the FXAnimation loop is currently playing
**/
enum FXPlayState {
	Start;
	Loop;
	End;

	/**localTime reached duration **/
	Finished;
}
@:allow(hrt.prefab.fx.FX)
class FXAnimation extends h3d.scene.Object {
	public static var defaultCullingDistance = 0.0;

	public var onEnd : Void -> Void;
	public var playSpeed : Float = 0;
	public var localTime : Float = 0.0;
	public var startDelay : Float = 0.0;
	public var loop(default, set) : Bool = false;
	public var loopStart: Float = -1;
	public var loopEnd: Float = -1;
	public var hasLoopPoints(default, null): Bool = false;
	public var duration : Float;

	function set_loop(v: Bool) {
		loop = v;
		return loop;
	}

	function set_playState(newPlayState: FXPlayState) : FXPlayState {
		playState = newPlayState;
		onPlayStateChange(playState);
		return playState;
	}

		/** Enable automatic culling based on `cullingRadius` and `cullingDistance`. Will override `culled` on every sync. **/
	public var autoCull(default, set) = true;
	public var cullingRadius : Float;
	public var cullingDistance = defaultCullingDistance;

	public var objAnims: Array<ObjectAnimation>;
	public var events: Array<hrt.prefab.fx.Event.EventInstance>;
	public var emitters : Array<hrt.prefab.fx.Emitter.EmitterObject>;
	public var trails : Array<hrt.prefab.l3d.Trails.TrailObj>;
	public var customAnims : Array<BaseFX.CustomAnimation> = [];
	public var constraints : Array<hrt.prefab.l3d.Constraint>;
	public var effects : Array<hrt.prefab.rfx.RendererFX>;
	public var shaderTargets : Array<hrt.prefab.fx.ShaderTarget.ShaderTargetObj>;

	public var subFXs : Array<FXAnimation> = [];

	public dynamic function onPlayStateChange(newPlayState: FXPlayState) : Void {

	}

	var evaluator : Evaluator;
	var parentFX : FXAnimation;
	var random : hxd.Rand;
	var randSeed : Int;
	var firstSync = true;
	public var playState(default, set) : FXPlayState = End;
	var stopTime : Float = -1;

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

		for (shaderTarget in def.flatten(hrt.prefab.fx.ShaderTarget)) {
			if (!shaderTarget.enabled)
				continue;
			shaderTarget.applyShaderTarget(def, shaderTarget.target);
		}

		initSubFXs(root);
		initObjAnimations(root);
		initEmitters(root);
		updateCustomAnims(root);

		events = initEvents(root, events);
		var root = hrt.prefab.fx.BaseFX.BaseFXTools.getFXRoot(def);
		initConstraints(root != null ? root : def);

		trails = findAll((p) -> Std.downcast(p, hrt.prefab.l3d.Trails.TrailObj));
		setParameters(def.parameters);

		initLoop();

		for (p in def.flatten(hrt.prefab.rfx.RendererFX)) {
			var rfx : hrt.prefab.rfx.RendererFX = cast p;
			if (@:privateAccess rfx.instance == null)
				continue;

			if (this.effects == null)
				this.effects = [];
			this.effects.push(rfx);
		}

		resetSelf();
	}

	public function initSubFXs(root: PrefabElement) {
		subFXs = [];
		for (fx in root.findAll(SubFX)) {
			var anim = Std.downcast(fx.refInstance?.findFirstLocal3d(), FXAnimation);
			if (anim != null) {
				subFXs.push(anim);
			}
		}
	}

	public function initLoop() {
		loopStart = 0;
		loopEnd = duration;
		hasLoopPoints = false;

		if (events == null)
			return;

		for (event in events) {
			var nameLower = event.evt.name.toLowerCase();
			if (nameLower == "loop") {
				loopStart = event.evt.time;
				var duration = event.evt.getDuration();
				if (duration > 0) {
					loopEnd = loopStart + duration;
				}
				hasLoopPoints = true;
			}
			if (nameLower == "end") {
				loopEnd = event.evt.time;
				hasLoopPoints = true;
			}
		}
	}

	public function hasEnd() {
		return loopEnd < duration && loopEnd >= 0;
	}

	public function reset() {
		resetSelf();

		if(parentFX == null) {
			for(c in findAll(o -> Std.downcast(o, FXAnimation))) {
				if(c != this)
					c.reset();
			}
		}

		if (customAnims != null) {
			for (anim in customAnims) {
				anim.startedPlaying = false;
			}
		}

	}

	function resetSelf() {
		firstSync = true;
		localTime = 0;
		playState = Start;
	}

	public function updateCustomAnims(root : Prefab) {
		if (customAnims == null)
			customAnims = [];
		hrt.prefab.fx.BaseFX.BaseFXTools.getCustomAnimations(root, customAnims, null);
		if(customAnims.length == 0)
			customAnims = null;
		else {
			for (a in customAnims) {
				a.parameters = evaluator.parameters;
			}
		}
	}

	public function setParameter(name: String, value: Dynamic) {
		evaluator.parameters[name] = value;
	}

	public function getParameter(name: String) {
		return evaluator.parameters[name];
	}

	public function getParameters() {
		return evaluator.parameters.keys();
	}

	public function setParameters(params: Array<Parameter>) {
		evaluator.parameters.clear();
		if (params == null)
			return;
		for (p in params) {
			evaluator.parameters[p.name] = p.def;
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

		if (firstSync) {
			if (ctx.scene != null && effects != null) {
				var renderer = ctx.scene.renderer;
				for (rfx in effects) {
					if (@:privateAccess rfx.instance == null)
						continue;

					renderer.effects.push(@:privateAccess rfx.instance);
				}
			}
		}

		var needIncrement = false;
		var curTime = localTime;

		if(playSpeed > 0 || firstSync) {
			if (parentFX == null) {
				var dt = firstSync ? 0 : ctx.elapsedTime * playSpeed;

				setTimeInternal(curTime + dt, dt, false, fullSync);
			}
		}

		for (t in trails) {
			t.timeScale = 0.0;
		}

		if(fullSync)
			super.syncRec(ctx);

		if(playState == Start && localTime >= duration && duration > 0) {
			stop(onEnd);
		}

		if(playState == End && localTime >= duration) {
			playState = Finished;
			finishedPlaying = true;
		}

		if(finishedPlaying) {
			Event.stopAllEvents(events);
			if (onEnd != null ) {
				onEnd();  // Delay until after syncRec, to avoid calling syncRec on children
			}
		}

		firstSync = false;
		ctx.visibleFlag = old;
	}

	static var closest : Map<h3d.scene.Object, {instance: EventInstance, distance: Float, jumpTo: Float}> = [];


	/**
		Jump or rewind in time instantly in the current fx
	**/
	public function seek(newTime: Float, fullsync: Bool = true) {
		setTimeInternal(newTime, 0, true, fullsync);
	}

	/**
		Increase the current playtime of the animation by a small ammount
	**/
	public function update(dt: Float, fullsync: Bool = true) {
		setTimeInternal(localTime + dt, dt, false, fullsync);
	}

	/**
		Prefer using seek or update depending on the context
	**/
	@:deprecated
	public function setTime(newTime: Float, fullsync: Bool = true) {
		seek(newTime, fullsync);
	}

	/**
		newTime is the new time to set, relative to the "parent" timeline
		dt is the relative delta of time since the last "parent" update
		Depending on how the parent loops, `newTime != lastTime + dt`, that's why the two arguments exists
	**/
	public function setTimeInternal(newTimeParent:Float, dt: Float, isSeek: Bool, fullSync: Bool = true) {

		var oldLocalTime = localTime;
		localTime = newTimeParent - startDelay;

		if (isSeek && loop) {
			if (loopEnd > 0 && localTime >= loopEnd) {
				playState = End;
			} else if (localTime < loopStart) {
				playState = Start;
			} else {
				playState = Loop;
			}
		}
		else if (loop) {
			if (playState == Start) {
				if (localTime >= loopStart) {
					playState = Loop;
				}
			}

			if (playState == Loop && isSeek) {
				if (loopEnd > 0 && localTime >= loopEnd) {
					playState = End;
				} else if (localTime < loopStart) {
					playState = Start;
				}
			}

			if (playState == Loop) {
				localTime = oldLocalTime + dt;
				if (loopEnd > 0 && loopEnd - loopStart > 0) {
					localTime = ((localTime - loopStart) % (loopEnd - loopStart)) + loopStart;
				}
			}

			if (playState == End) {
				// Fast forward to end of loop if we are still in the loop
				if (loopEnd > 0 && stopTime >= 0) {
					var loopCatchTime = loopEnd - stopTime;
					var passedTime = localTime - stopTime;
					if(loopCatchTime > 0.1) { // Catch up lerp from loop
						if(passedTime < 0.1)
							localTime = hxd.Math.lerp(stopTime, loopEnd, passedTime / 0.1);
						else if(localTime < loopEnd)
							localTime = loopEnd;
					}
				}
			}
		}

		for (subFX in subFXs) {
			subFX.setTimeInternal(localTime, dt, isSeek, fullSync);
		}

		if (fullSync) {
			syncAnims(localTime, dt);
		}


		if(customAnims != null) {
			for(anim in customAnims) {
				if (fullSync || (anim.startedPlaying && anim.finishSync)) {
					anim.setTime(localTime);
					anim.startedPlaying = true;
				}
			}
		}

		if (fullSync) {
			syncParticles(localTime, dt, isSeek);

			for (t in trails) {
				t.update(hxd.Math.max(dt, 0.0));
			}

			#if editor
			if (isSeek || hxd.Math.abs(dt) > hxd.Timer.dt * 1.5) {
				fixEventSeek();
			}
			#end
		}

		Event.updateEvents(events, localTime, oldLocalTime, duration);
	}

	function fixEventSeek() {
		var time = localTime;

		if (events == null)
			return;

		var closest : Map<h3d.scene.Object, {instance: EventInstance, distance: Float, jumpTo: Float}> = [];

		for (instance in events) {
			var event = Std.downcast(instance.evt, hrt.prefab.fx.AnimEvent);
			if (event == null)
				continue;

			var previous = hrt.tools.MapUtils.getOrPut(closest, event.findFirstLocal3d(), {instance: instance, distance: hxd.Math.POSITIVE_INFINITY, jumpTo: 0.0});
			if (previous.distance == 0)
				continue;

			var firstFrame = event.time;
			var toFirstFrame = firstFrame - time;
			if (toFirstFrame >= 0 && toFirstFrame < previous.distance) {
				previous.instance = instance;
				previous.distance = toFirstFrame;
				previous.jumpTo = 0.0001;
			}

			var anim = event.animation != null ? event.shared.loadAnimation(event.animation) : null;
			var duration = event.duration > 0 ? event.duration : (anim?.getDuration() ?? 0.0);
			var lastFrame = event.time + duration;
			var toLastFrame = time - lastFrame;
			if (toLastFrame >= 0 && toLastFrame < previous.distance) {
				previous.instance = instance;
				previous.distance = toLastFrame;
				previous.jumpTo = duration-0.0001;
			}

			// We are currently playing this animation
			if (toFirstFrame < 0 && toLastFrame < 0) {
				previous.instance = null;
				previous.distance = 0;
				continue;
			}
		}

		for (obj in closest) {
			if (obj.instance == null) // can be null if we are in the middle of the animation
				continue;
			obj.instance.setTime(obj.jumpTo);
		}
	}

	function syncParticles(newTime: Float, dt: Float, seek: Bool) {
		if(emitters != null) {
			for(em in emitters) {
				if(em.visible)
				{
					em.setTime(newTime, dt, seek);
				}
			}
		}
	}

	static var tempMat = new h3d.Matrix();
	static var tempTransform = new h3d.Matrix();
	static var tempVec = new h3d.Vector4();

	function syncAnims(newTime: Float, dt: Float) {
		if(objAnims != null) {
			for(anim in objAnims) {
				if(anim.scale != null || anim.rotation != null || anim.position != null) {
					var m = tempMat;
					if(anim.scale != null) {
						var scale = evaluator.getVector(anim.scale, newTime, tempVec);
						m.initScale(scale.x, scale.y, scale.z);
					}
					else
						m.identity();

					if(anim.rotation != null) {
						var rotation = evaluator.getVector(anim.rotation, newTime, tempVec);
						rotation.scale3(Math.PI / 180.0);
						m.rotate(rotation.x, rotation.y, rotation.z);
					}

					var baseMat = anim.elt.getTransform(tempTransform);
					var offset = baseMat.getPosition();
					baseMat.tx = baseMat.ty = baseMat.tz = 0.0;  // Ignore
					m.multiply(baseMat, m);
					m.translate(offset.x, offset.y, offset.z);

					if(anim.position != null) {
						var pos = evaluator.getVector(anim.position, newTime, tempVec);
						m.translate(pos.x, pos.y, pos.z);
					}

					anim.obj.setTransform(m);
				}

				// Animations that are only applied on local transforms of leafs objects
				if (anim.localRotation != null || anim.localPosition != null) {
					var leafObjects = anim.elt.findAll(Object3D, o -> o.children == null || o.children.length == 0);

					for (o in leafObjects) {
						if (o.local3d == null)
							continue;
						var baseMat = o.getTransform();

						tempMat.identity();
						var m = tempMat;

						if(anim.localRotation != null) {
							var localRotation = evaluator.getVector(anim.localRotation, newTime, tempVec);
							localRotation.scale3(Math.PI / 180.0);
							m.rotate(localRotation.x, localRotation.y, localRotation.z);
						}

						if(anim.localPosition != null) {
							var localPosition = evaluator.getVector(anim.localPosition, newTime, tempVec);
							m.translate(localPosition.x, localPosition.y, localPosition.z);
						}

						m.multiply(m, baseMat);
						o.local3d.setTransform(m);
					}
				}

				if(anim.visibility != null) {
					var visible = anim.elt.visible;
					#if editor
					var editor = anim.elt.shared.editor;
					visible = visible && (editor?.isVisible(anim.elt) ?? true);
					#end
					anim.obj.visible = visible && evaluator.getFloat(anim.visibility, newTime) > 0.5;
				}

				if(anim.color != null) {
					switch(anim.color) {
						case VCurve(a):
							for(mat in anim.obj.getMaterials())
								mat.color.a = evaluator.getFloat(anim.color, newTime);
						default:
							for(mat in anim.obj.getMaterials())
								mat.color.load(evaluator.getVector(anim.color, newTime, tempVec));
					}
				}

				if( anim.additionalProperies != null ) {
					switch(anim.additionalProperies) {
						case None :
						case PointLight( color, power, size, range ) :
							var l = Std.downcast(anim.obj, h3d.scene.pbr.PointLight);
							if( l != null ) {
								if( color != null ) {
									var v = evaluator.getVector(color, newTime, tempVec);
									l.color.set(v.x, v.y, v.z);
								}
								if( power != null ) l.power = evaluator.getFloat(power, newTime);
								if( size != null ) l.size = evaluator.getFloat(size, newTime);
								if( range != null ) l.range = evaluator.getFloat(range, newTime);
							}
						case DirLight(color, power):
							var l = Std.downcast(anim.obj, h3d.scene.pbr.DirLight);
							if( l != null ) {
								if( color != null ) {
									var v = evaluator.getVector(color, newTime, tempVec);
									l.color.set(v.x, v.y, v.z);
								}
								if( power != null ) l.power = evaluator.getFloat(power, newTime);
							}
						case SpotLight(color, power, range, angle, fallOff):
							var l = Std.downcast(anim.obj, h3d.scene.pbr.SpotLight);
							if( l != null ) {
								if( color != null ) {
									var v = evaluator.getVector(color, newTime, tempVec);
									l.color.set(v.x, v.y, v.z);
								}
								if( power != null ) l.power = evaluator.getFloat(power, newTime);
								if( range != null ) l.range = evaluator.getFloat(range, newTime);
								if( angle != null ) l.angle = evaluator.getFloat(angle, newTime);
								if( fallOff != null ) l.fallOff = evaluator.getFloat(fallOff, newTime);
							}
					}
				}
			}
		}

		if (effects != null) {
			for (e in effects)
				@:privateAccess e.updateInstance();
		}
	}


	public function stop(instant: Bool = false, onEnd: () -> Void = null) {
		this.onEnd = onEnd;
		playState = End;
		if (loopEnd < 0 || loopEnd == duration)
			instant = true;
		if (instant == true) {
			if (localTime < duration)
				setTimeInternal(startDelay + duration, 0, true, true);
		} else {
			stopTime = localTime;
		}
	}

	function initEvents(elt: PrefabElement, ?out : Array<Event.EventInstance> ) : Array<Event.EventInstance> {
		if (elt == null || @:privateAccess !elt.shouldBeInstanciated() || elt.findFirstLocal3d() == null)
			return out;

		if( Std.isOfType(elt, IEvent) ) {
			var asEvent = cast(elt, IEvent);
			var eventObj = asEvent.prepare();
			if(eventObj != null) {
				if(out == null) out = [];
				out.push(eventObj);
			}
		}

		for(child in elt.children) {
			out = initEvents(child, out);
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
			return c.makeVal();
		}

		function makeVector(name: String, defVal: Float, uniform: Bool=true, scale: Float=1.0) : Value {
			var curves = Curve.getCurves(elt, name);
			if(curves == null || curves.length == 0)
				return null;

			anyFound = true;

			if(uniform && curves.length == 1 && curves[0].name == name) {
				return scale != 1.0 ? VMult(curves[0].makeVal(), VConst(scale)) : curves[0].makeVal();
			}

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
			position: makeVector("position", 0.0),
			localPosition: makeVector("localPosition", 0.0),
			scale: makeVector("scale", 1.0, true),
			rotation: makeVector("rotation", 0.0, 360.0),
			localRotation: makeVector("localRotation", 0.0, 360.0),
			color: makeColor("color"),
			visibility: makeVal("visibility", null),
			additionalProperies: ap,
		};

		if(anyFound) {
			if(objAnims == null) objAnims = [];
			objAnims.push(anim);
		}
	}

	function initEmitters(elt: PrefabElement) {
		if (emitters != null)
			emitters.resize(0);

		function rec(elt: PrefabElement) {
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
					rec(c);
				}
			}
		}
		rec(elt);
	}

	function initConstraints(elt : PrefabElement ){
		if(elt == null || @:privateAccess !elt.shouldBeInstanciated()) return;
		var co = Std.downcast(elt, hrt.prefab.l3d.Constraint);
		if(co != null) {
			if(constraints == null) constraints = [];
			constraints.push(co);
		}

		var sub = Std.downcast(elt, SubFX);
		if (sub != null) {
			initConstraints(sub.refInstance);
		}
		for(c in elt.children) {
			initConstraints(c);
		}
	}

	public function resolveConstraints( caster : h3d.scene.Object ) {
		if( constraints == null ) return;
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

	override function onRemove() {
		if ( effects != null ) {
			var scene = getScene();
			if ( scene != null ) {
				for (rfx in effects) {
					if (@:privateAccess rfx.instance == null)
						continue;
					scene.renderer.effects.remove(@:privateAccess rfx.instance);
				}
			}
		}

		if (shaderTargets != null)
			for (st in shaderTargets)
				st.remove();

		super.onRemove();
	}
}

enum abstract ParameterType(String) {
	var TBlend;
}
typedef Parameter = {
	var type: ParameterType;
	var name: String;
	var color: Int;
	var def: Dynamic;
};

class FX extends Object3D implements BaseFX {

	@:s public var duration : Float;
	@:s public var startDelay : Float = 0.0;
	@:c public var scriptCode : String;
	@:s public var cullingRadius : Float;
	@:s public var markers : Array<{t: Float}> = [];

	@:s public var parameters : Array<Parameter> = [];

	#if editor
	static var identRegex = ~/^[A-Za-z_][A-Za-z0-9_]*$/;
	#end

	public function new(parent:Prefab, contextShared: ContextShared) {
		super(parent, contextShared);
		duration = 5.0;
		cullingRadius = 3.0;
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

	override function updateInstance(?propName : String ) {
		super.updateInstance(null);
		var fxanim = Std.downcast(local3d, FXAnimation);
		fxanim.duration = duration;
		fxanim.cullingRadius = cullingRadius;

		fxanim.setParameters(parameters);
	}

	public override function postMakeInstance() {
		var root = hrt.prefab.fx.BaseFX.BaseFXTools.getFXRoot(this);
		var fxAnim = Std.downcast(local3d, FXAnimation);
		if (fxAnim == null)
			return;

		fxAnim.init(this, root);
	}

	public function setTarget(target : h3d.scene.Object) {
		for (shaderTarget in this.findAll(hrt.prefab.fx.ShaderTarget))
			shaderTarget.target = target;
	}

	function createInstance(parent: h3d.scene.Object) : FXAnimation {
		return new FXAnimation(parent);
	}

	#if editor

	override function onEditorTreeChanged(child: Prefab) : hrt.prefab.Prefab.TreeChangedResult {
		return Rebuild;
	}

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
				</dl>
			</div>');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});

		var param = new hide.Element('
			<div class="group flex-props fx-params" name="Parameters">
				<dl id="params">
				</dl>
				<dl>
				<dt></dt><dd><input type="button" value="Add Parameter" id="addParamButton"/></dd>
				</dl>
			</div>
		'
		);

		function isParameterNameUnique(name: String) {
			for (p in parameters) {
				if (p.name == name) return false;
			}
			return true;
		}

		function rebuildParameters() {
			var params = param.find("#params");
			(params.get(0):Dynamic).replaceChildren();
			if (parameters != null) {
				for (i => p in parameters) {
					var line = new hide.Element('<div class="hover-parent"/>');
					line.appendTo(params);
					var elem = new hide.Element('<dt class="flex"><div id="color"></div><span id="name" contenteditable class="fill"></span></dt>').appendTo(line);
					var editable = new hide.comp.ContentEditable(null, elem.find("#name"));
					editable.value = p.name;
					editable.spellcheck = false;
					editable.onChange = function(v: String) {
						var error = false;
						if (!identRegex.match(v)) {
							hide.Ide.inst.quickMessage('Parameter name "$v" is not a valid identifier');
							error = true;
						}
						else if (!isParameterNameUnique(v)) {
							hide.Ide.inst.quickMessage('Parameter "$v" already exists');
							error = true;
						}
						if (error) {
							editable.value = p.name;
							return;
						}

						var old = p.name;
						var fn = function(isUndo: Bool) {
							var from = isUndo ? v : old;
							var to = isUndo ? old : v;
							p.name = to;

							// rename all curves that used this param as a blendParam
							var curves = flatten(Curve);
							for (c in curves) {
								if (c.blendMode == Blend && c.blendParam == from) {
									c.blendParam = to;
								}
							}

							editable.value = p.name;
							ctx.onChange(this, "parameters");
							ctx.rebuildPrefab(this);
						}
						ctx.properties.undo.change(Custom(fn));
						fn(false);
					};

					var colorPicker = new hide.comp.ColorPicker.ColorBox(null, elem.find("#color"), true, false);
					colorPicker.value = p.color;
					colorPicker.element.width(8);
					colorPicker.element.height(16);
					var lastColor = p.color;
					colorPicker.onChange = function(temp: Bool) {
						if (temp) {
							p.color = colorPicker.value;
							ctx.onChange(this, "parameters");
						}
						else {
							var old = lastColor;
							var current = colorPicker.value;
							var fn = function(isUndo : Bool) {
								p.color = isUndo ? old : current;
								colorPicker.value = p.color;
								ctx.rebuildPrefab(this, false);
							}
							ctx.properties.undo.change(Custom(fn));
							fn(false);
						}
					}

					var dd = new hide.Element('<dd class="flex">').appendTo(line);
					var range = new hide.comp.Range(dd, new hide.Element('<input min="0" max="1" type="range"/>'));
					var btn = new hide.Element('<div class="tb-group small hover-reveal"><div class="button2"><div class="icon ico ico-times"></div></div></div>').appendTo(dd);
					btn.find(".button2").get(0).onclick = function(e) {
						var fn = function(isUndo: Bool) {
							if (!isUndo) {
								parameters.splice(i, 1);
							}
							else {
								parameters.insert(i, p);
							}
							rebuildParameters();
							ctx.onChange(this, "parameters");
						}
						ctx.properties.undo.change(Custom(fn));
						fn(false);
					}

					range.value = p.def;
					var lastDef = p.def;
					range.onChange = function(temp: Bool) {
						if (temp) {
							p.def = range.value;
							ctx.onChange(this, "parameters");
						}
						else {
							var old = lastDef;
							var current = range.value;
							lastDef = current;
							var fn = function(isUndo: Bool) {
								p.def = isUndo ? old : current;
								range.value = p.def;
								ctx.onChange(this, "parameters");
							}
							ctx.properties.undo.change(Custom(fn));
							fn(false);
						}
					}
				}
			}
		}



		param.find("#addParamButton").get(0).onclick = (_) -> {

			var color = hrt.impl.ColorSpace.HSLtoiRGB(new h3d.Vector4((parameters.length * 0.618033988749895) % 1.0, 0.75, 0.5), null).toInt(false);
			var paramName = "newParam";
			var i = 0;
			while (!isParameterNameUnique(paramName)) {
				i ++;
				paramName = 'newParam$i';
			}
			var newElem = {type: TBlend, name: paramName, color: color, def: 0.0};
			var fn = function(isUndo: Bool) {
				if (!isUndo) {
					parameters.push(newElem);
				} else {
					parameters.pop();
				}
				ctx.onChange(this, "parameters");
				rebuildParameters();
			}
			ctx.properties.undo.change(Custom(fn));
			fn(false);
		};

		ctx.properties.add(param);

		rebuildParameters();

	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "cube", name : "FX", allowParent: _ -> false};
	}
	#end

	// TOCO(ces) : restore extension support
	static var _ = Prefab.register("fx", FX, "fx");
}