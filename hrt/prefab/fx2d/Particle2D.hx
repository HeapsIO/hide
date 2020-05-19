package hrt.prefab.fx2d;

import hrt.prefab.fx.Evaluator;
import hrt.prefab.fx.Value;
import h2d.Particles.ParticleGroup;

class Particles extends h2d.Particles {
	
	var evaluator : Evaluator;
	
	var lastTime = -1.0;
	var curTime = 0.0;
	
	var random: hxd.Rand;
	var randomSeed = 0;

	public var catchupSpeed = 4; // Use larger ticks when catching-up to save calculations
	public var maxCatchupWindow = 0.5; // How many seconds max to simulate when catching up

	// param FX
	public var enable : Value;
	public var speed : Value;
	public var speedIncr : Value;
	public var gravity : Value;
	
	public function new( ?parent ) {
		super(parent);
		randomSeed = Std.random(0xFFFFFF);
		random = new hxd.Rand(randomSeed);
		evaluator = new Evaluator(random);
	}
	
	function tick( dt : Float, full=true) {
		var group = this.groups[0];

		var enableValue = evaluator.getFloat(enable, curTime) >= 0.5;
		if (group.enable != enableValue) // prevent batch.clear() when false
			group.enable = enableValue;

		group.speed = evaluator.getFloat(speed, curTime);
		group.speedIncr = evaluator.getFloat(speedIncr, curTime);
		group.gravity = evaluator.getFloat(gravity, curTime);

		lastTime = curTime;
		curTime += dt;
	}

	public function reset() {
		random.init(randomSeed);
		curTime = 0.0;
		lastTime = 0.0;
	}
	
	public function setTime(time: Float) {
		if(time < lastTime || lastTime < 0) {
			reset();
		}

		var catchupTime = time - curTime;
		#if !editor
		if(catchupTime > maxCatchupWindow) {
			curTime = time - maxCatchupWindow;
			catchupTime = maxCatchupWindow;
		}
		#end
		var catchupTickRate = hxd.Timer.wantedFPS / catchupSpeed;
		var numTicks = hxd.Math.ceil(catchupTickRate * catchupTime);
		for(i in 0...numTicks) {
			tick(catchupTime / numTicks, i == (numTicks - 1));
		}
	}

	override function getBounds( ?relativeTo : h2d.Object, ?out : h2d.col.Bounds ) : h2d.col.Bounds {
		if( out == null ) out = new h2d.col.Bounds() else out.empty();
		out = super.getBounds(relativeTo, out);
		out.xMin -= 25*scaleX;
		out.xMax += 25*scaleX;
		out.yMin -= 25*scaleY;
		out.yMax += 25*scaleY;
		return out;
	}

}

class Particle2D extends Object2D {

	var paramsParticleGroup : Dynamic;

	override public function load(v:Dynamic) {
		super.load(v);
		paramsParticleGroup = v.paramsParticleGroup;
	}

	override function save() {
		var o : Dynamic = super.save();
		o.paramsParticleGroup = paramsParticleGroup;
		return o;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, propName);

		var particles2d = (cast ctx.local2d : Particles);
		
		particles2d.visible = visible;

		function makeVal(name, def ) : Value {
			var c = Curve.getCurve(this, name);
			return c != null ? VCurve(c) : def;
		}
		
		if (paramsParticleGroup != null) {
			particles2d.enable = makeVal("enable", VConst((paramsParticleGroup.enable) ? 1 : 0));
			particles2d.speed = makeVal("speed", VConst(paramsParticleGroup.speed));
			particles2d.speedIncr = makeVal("speedIncr", VConst(paramsParticleGroup.speedIncr));
			particles2d.gravity = makeVal("gravity", VConst(paramsParticleGroup.gravity));
		}
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var particle2d = new Particles(ctx.local2d);
		ctx.local2d = particle2d;
		ctx.local2d.name = name;
	
		var group = new ParticleGroup(particle2d);
		particle2d.addGroup(group);
		if (paramsParticleGroup != null)
			group.load(1, paramsParticleGroup);
		else
			paramsParticleGroup = group.save();
		group.rebuildOnChange = false;

		updateInstance(ctx);
		return ctx;
	}

	#if editor

	public static var emitter2dParams : Array<hrt.prefab.fx.Emitter.ParamDef> = [
		// EMIT PARAMS
		{ name: "enable", t: PBool, disp: "Enable", def : 1.0, animate: true, groupName : "Emit Params" },
		{ name: "speed", t: PFloat(), disp: "Initial Speed", def : 1.0, animate: true, groupName : "Emit Params" },
		{ name: "speedIncr", t: PFloat(), disp: "Acceleration", def : 1.0, animate: true, groupName : "Emit Params" },
		{ name: "gravity", t: PFloat(), disp: "Gravity", def : 1.0, animate: true, groupName : "Emit Params" }
	];

	override function makeInteractive(ctx:Context):h2d.Interactive {
		var local2d = ctx.local2d;
		if(local2d == null)
			return null;
		var particles2d = cast(local2d, h2d.Particles);
		var int = new h2d.Interactive(50, 50);
		particles2d.addChildAt(int, 0);
		int.propagateEvents = true;
		int.x = int.y = -25;
		return int;
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var params = new hide.Element(hide.view.Particles2D.getParamsHTMLform());
		
		var particles2d = (cast ctx.getContext(this).local2d : Particles);
		var group = @:privateAccess particles2d.groups[0];
		ctx.properties.add(params, group, function (pname) {
			// if fx2d is running, tick() changes group params and modifies group.save()
			// if a param has a curve and we changed this param on the right panel, 
			// the saved value will be the value of the curve at this point.
			Reflect.setField(paramsParticleGroup, pname, Reflect.field(group.save(), pname));
		});
	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Particle2D" };
	}

	#end

	static var _ = Library.register("particle2D", Particle2D);

}