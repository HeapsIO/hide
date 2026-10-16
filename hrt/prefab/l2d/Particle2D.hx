package hrt.prefab.l2d;

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

	public var isBurstEmit : Bool;
	public var burstDelay : Float;
	public var initialBurstDelay : Float;
	public var burstParticleCount : Int;

	public function new( ?parent ) {
		super(parent);
		randomSeed = Std.random(0xFFFFFF);
		random = new hxd.Rand(randomSeed);
		evaluator = new Evaluator();
		onEnd = function() {
			for( g in groups ) {
				if( g.emitLoop )
					@:privateAccess g.needRebuild = true;
			}
		}
	}

	function tick( dt : Float, full=true) {
		var group = this.groups[0];
		var enableValue = evaluator.getFloat(enable, curTime) >= 0.5;
		if (group.enable != enableValue) // prevent batch.clear() when false
			group.enable = enableValue;

		// Burst emit mode
		if (isBurstEmit) {
			group.emitSync = 1; // If not 1, there is some delay between particle spawns.
			group.emitDelay = 0;

			var shouldBurst = (curTime >= initialBurstDelay && (lastTime < initialBurstDelay || lastTime > curTime)) ||
			(curTime - initialBurstDelay >= 0 && ((lastTime - initialBurstDelay) % burstDelay >= (curTime - initialBurstDelay) % burstDelay && lastTime <= curTime));
			if (shouldBurst) {
				group.nparts = burstParticleCount;
				group.rebuild();
				group.nparts = 0;
				@:privateAccess group.needRebuild = false;
			}
		}

		group.speed = evaluator.getFloat(speed, curTime);
		group.speedIncr = evaluator.getFloat(speedIncr, curTime);
		group.gravity = evaluator.getFloat(gravity, curTime);

		lastTime = curTime;
		curTime += dt;
	}

	public function reset() {
		for( g in groups ) {
			@:privateAccess g.needRebuild = true;
		}
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

@:deprecated("Use Emitter2D instead")
@:prefabHideInAddMenu
class Particle2D extends Object2D {

	@:s var paramsParticleGroup : Dynamic;
	@:s var isBurstEmit : Bool;
	@:s var burstParticleCount : Int;
	@:s var initialBurstDelay : Float;
	@:s var burstDelay : Float;

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);

		var particles2d = (cast local2d : Particles);

		particles2d.visible = visible;
		particles2d.isBurstEmit = this.isBurstEmit;
		particles2d.burstParticleCount = this.burstParticleCount;
		particles2d.initialBurstDelay = this.initialBurstDelay;
		particles2d.burstDelay = this.burstDelay;

		if (this.isBurstEmit) {
			for (g in particles2d.getGroups()) {
				g.nparts = 0;
			}
		}

		function makeVal(name, def ) : Value {
			var c = Curve.getCurve(this, name);
			return c != null ? VCurve(c, 0, 1) : def;
		}

		if (paramsParticleGroup != null) {
			particles2d.enable = makeVal("enable", VConst((paramsParticleGroup.enable) ? 1 : 0));
			particles2d.speed = makeVal("speed", VConst(paramsParticleGroup.speed));
			particles2d.speedIncr = makeVal("speedIncr", VConst(paramsParticleGroup.speedIncr));
			particles2d.gravity = makeVal("gravity", VConst(paramsParticleGroup.gravity));
		}
	}

	override function makeObject(parent2d:h2d.Object):h2d.Object {
		var particle2d = new Particles(parent2d);

		var group = new ParticleGroup(particle2d);
		particle2d.addGroup(group);
		if (paramsParticleGroup != null)
			group.load(1, paramsParticleGroup);
		else
			paramsParticleGroup = group.save();
		group.rebuildOnChange = false;

		return particle2d;
	}

	override function makeInteractive():h2d.Interactive {
		if(local2d == null)
			return null;
		var particles2d = cast(local2d, h2d.Particles);
		var int = new h2d.Interactive(50, 50);
		particles2d.addChildAt(int, 0);
		int.propagateEvents = true;
		int.x = int.y = -25;
		return int;
	}

	#if editor

	public static var emitter2dParams : Array<hrt.prefab.fx.EmitterHelper.ParamDef> = [
		// EMIT PARAMS
		{ name: "enable", t: PBool, disp: "Enable", def : 1.0, animate: true, groupName : "Emit Params" },
		{ name: "speed", t: PFloat(), disp: "Initial Speed", def : 1.0, animate: true, groupName : "Emit Params" },
		{ name: "speedIncr", t: PFloat(), disp: "Acceleration", def : 1.0, animate: true, groupName : "Emit Params" },
		{ name: "gravity", t: PFloat(), disp: "Gravity", def : 1.0, animate: true, groupName : "Emit Params" }
	];

	static function getParamsHTMLform() {
		return
			'<div class="content">
				<div class="group" name="Display">
					<dl>
						<dt>Name</dt><dd><input field="name" onchange="$(this).closest(\'.section\').find(\'>h1 span\').text($(this).val())"/></dd>
						<dt>Blend Mode</dt><dd><select field="blendMode"/></dd></dd>
						<dt>Texture</dt><dd><input type="texture" field="texture"/></dd>
						<dt>Color Gradient</dt><dd><input type="texture" field="colorGradient"/></dd>
						<dt>Sort Mode</dt><dd><select field="sortMode"/></dd></dd>
						<dt>Relative</dt><dd><input type="checkbox" field="isRelative"/></dd>
					</dl>
				</div>

				<div class="group" name="Emit">
					<dl>
						<dt>Mode</dt><dd><select field="emitMode"/></dd>
						<dt></dt><dd>
							X <input type="number" style="width:59px" field="dx"/>
							Y <input type="number" style="width:59px" field="dy"/>
						</dd>
						<dt>Count</dt><dd><input type="range" field="nparts" min="0" max="300" step="1"/></dd>
						<dt>Distance</dt><dd><input type="range" field="emitDist" min="0" max="1000" step="1"/></dd>
						<dt>Distance Y</dt><dd><input type="range" field="emitDistY" min="0" max="1000" step="1"/></dd>
						<dt>Angle</dt><dd><input type="range" field="emitAngle" min="-1.571" max="1.571" step="0.0524"/></dd>
						<dt>Sync</dt><dd><input type="range" field="emitSync" min="0" max="1"/></dd>
						<dt>Delay</dt><dd><input type="range" field="emitDelay" min="0" max="10"/></dd>
						<dt>Loop</dt><dd><input type="checkbox" field="emitLoop"/></dd>
					</dl>
				</div>

				<div class="group" name="Life">
					<dl>
						<dt>Initial</dt><dd><input type="range" field="life" min="0" max="10"/></dd>
						<dt>Randomness</dt><dd><input type="range" field="lifeRand" min="0" max="1"/></dd>
						<dt>Fade In</dt><dd><input type="range" field="fadeIn" min="0" max="1"/></dd>
						<dt>Fade Out</dt><dd><input type="range" field="fadeOut" min="0" max="1"/></dd>
						<dt>Fade Power</dt><dd><input type="range" field="fadePower" min="0" max="3"/></dd>
					</dl>
				</div>

				<div class="group" name="Speed">
					<dl>
						<dt>Initial</dt><dd><input type="range" field="speed" min="0" max="1000"/></dd>
						<dt>Randomness</dt><dd><input type="range" field="speedRand" min="0" max="1"/></dd>
						<dt>Acceleration</dt><dd><input type="range" field="speedIncr" min="-1" max="1"/></dd>
						<dt>Gravity</dt><dd><input type="range" field="gravity" min="-500" max="500" step="1"/></dd>
						<dt>Gravity Angle</dt><dd><input type="range" field="gravityAngle" min="0" max="1" step="0.1"/></dd>
					</dl>
				</div>

				<div class="group" name="Size">
					<dl>
						<dt>Initial</dt><dd><input type="range" field="size" min="0.01" max="2"/></dd>
						<dt>Randomness</dt><dd><input type="range" field="sizeRand" min="0" max="1"/></dd>
						<dt>Growth</dt><dd><input type="range" field="sizeIncr" min="-1" max="1"/></dd>
						<dt></dt><dd>
							Grow u <input type="checkbox" field="incrX"/>
							Grow v <input type="checkbox" field="incrY"/>
						</dd>
					</dl>
				</div>

				<div class="group" name="Rotation">
					<dl>
						<dt>Initial</dt><dd><input type="range" field="rotInit" min="0" max="1"/></dd>
						<dt>Speed</dt><dd><input type="range" field="rotSpeed" min="0" max="20"/></dd>
						<dt>Randomness</dt><dd><input type="range" field="rotSpeedRand" min="0" max="1"/></dd>
						<dt>Auto orient</dt><dd><input type="checkbox" field="rotAuto"/></dd>
					</dl>
				</div>

				<div class="group" name="Animation">
					<dl>
						<dt>Animation Repeat</dt><dd><input type="range" field="animationRepeat" min="0" max="10"/></dd>
						<dt>Frame Division</dt><dd>
							X <input type="number" style="width:30px" field="frameDivisionX" min="1" max="16"/>
							Y <input type="number" style="width:30px" field="frameDivisionY" min="1" max="16"/>
							# <input type="number" style="width:30px" field="frameCount" min="0" max="32"/>
						</dd>
					</dl>
				</div>

			</div>';
	}

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);

		if (this.local2d == null)
			this.make();

		var params = new hide.Element(getParamsHTMLform());

		var particles2d = (cast local2d : Particles);
		var group = @:privateAccess particles2d.groups[0];
		ctx.properties.add(new hide.Element('
		<div class="content">
			<div class="group" name="Emit">
				<dt>Is burst emit</dt><dd><input type="checkbox" field="isBurstEmit"/></dd>
				<dt>Burst particle count</dt><dd><input type="range" field="burstParticleCount" min="0" max="100" step="1"/></dd>
				<dt>Initial burst delay</dt><dd><input type="range" field="initialBurstDelay" min="0" max="10" step="0.1"/></dd>
				<dt>Delay between burst</dt><dd><input type="range" field="burstDelay" min="0" max="10" step="0.1"/></dd>
			</div>
		</div>
		'), this, function (pname) { ctx.onChange(this, pname); });

		ctx.properties.add(params, group, function (pname) {
			// if fx2d is running, tick() changes group params and modifies group.save()
			// if a param has a curve and we changed this param on the right panel,
			// the saved value will be the value of the curve at this point.
			Reflect.setField(paramsParticleGroup, pname, Reflect.field(group.save(), pname));


			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "square", name : "Particle2D", allowParent: (_) -> false };
	}

	#end

	static var _ = Prefab.register("particle2D", Particle2D);

}