package hrt.prefab.fx.gpuemitter;

class RelativeTransformSimulationShader extends ComputeUtils {

	override function onRemove(emitter : GPUEmitterObject) {
		super.onRemove(emitter);

		if ( curveTexture != null )
			curveTexture.dispose();
		curveTexture = null;
	}

	static var SRC = {

		@const(511) var CURVE_MASK : Int;

		@param var x : Float;
		@param var y : Float;
		@param var z : Float;

		@param var scaleX : Float;
		@param var scaleY : Float;
		@param var scaleZ : Float;

		@param var rotX : Float;
		@param var rotY : Float;
		@param var rotZ : Float;

		@param var speedX : Float;
		@param var speedY : Float;
		@param var speedZ : Float;

		@param var curveTexture : Sampler2D;

		var life : Float;
		var lifeTime : Float;
		var relativeTransform : Mat4;
		var dt : Float;

		function hasBit(n : Int) : Bool {
			return (CURVE_MASK & (1 << n) ) != 0;
		}

		function getCurve(n : Int, l : Float) : Float {
			var c = 0.0;
			if ( CURVE_MASK != 0 )
				c = curveTexture.getLod(vec2(l / lifeTime, (n + 0.5) / 9.0), 0.0).r;
			return c;
		}

		function getDiff(n : Int) : Float {
			return getCurve(n, life + dt) - getCurve(n, life);
		}

		function main() {
			var justAlive = life <= 0.0;
			var translation = justAlive ? vec3(x,y,z) : vec3(0.0);
			var scale = vec3(scaleX, scaleY, scaleZ);
			var rotation = vec3(rotX, rotY, rotZ);

			var speed = vec3(speedX,speedY,speedZ);

			if ( hasBit(0) )
				translation.x = justAlive ? getCurve(0, life) : getDiff(0);
			if ( hasBit(1) )
				translation.y = justAlive ? getCurve(1, life) : getDiff(1);
			if ( hasBit(2) )
				translation.z = justAlive ? getCurve(2, life) : getDiff(2);

			if ( hasBit(3) )
				scale.x = getCurve(3, life);
			if ( hasBit(4) )
				scale.y = getCurve(4, life);
			if ( hasBit(5) )
				scale.z = getCurve(5, life);

			if ( hasBit(6) )
				rotation.x = getCurve(6, life);
			if ( hasBit(7) )
				rotation.y = getCurve(7, life);
			if ( hasBit(8) )
				rotation.z = getCurve(8, life);

			// rotation not supported
			var shaderTRS = scaleMatrix(scale) * translationMatrix(translation) * translationMatrix(speed);
			relativeTransform = relativeTransform * shaderTRS;
		}
	}
}

class RelativeTransformSimulation extends SimulationShader {

	@:s var x : Float = 0.0;
	@:s var y : Float = 0.0;
	@:s var z : Float = 0.0;

	@:s var scaleX : Float = 1.0;
	@:s var scaleY : Float = 1.0;
	@:s var scaleZ : Float = 1.0;

	@:s var rotX : Float = 0.0;
	@:s var rotY : Float = 0.0;
	@:s var rotZ : Float = 0.0;

	@:s var speedX : Float = 0.0;
	@:s var speedY : Float = 0.0;
	@:s var speedZ : Float = 0.0;

	override function makeShader() {
		return new RelativeTransformSimulationShader();
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);

		#if !editor
		var s = Std.downcast(shader, RelativeTransformSimulationShader);
		if ( s.curveTexture != null )
			s.curveTexture.dispose();

		s.x = x;
		s.y = y;
		s.z = z;

		s.scaleX = scaleX;
		s.scaleY = scaleY;
		s.scaleZ = scaleZ;

		s.rotX = rotX;
		s.rotY = rotY;
		s.rotZ = rotZ;

		s.speedX = speedX;
		s.speedY = speedY;
		s.speedZ = speedZ;

		s.CURVE_MASK = 0;

		var width = 256;
		var height = 9;

		s.curveTexture = new h3d.mat.Texture(width, height, null, R32F);

		var curves = findAll(hrt.prefab.Curve, p -> p.shouldBeInstanciated());
		if ( curves.length == 0 )
			return;

		var curveNames = ["x", "y", "z", "scaleX", "scaleY", "scaleZ", "rotX", "rotY", "rotZ"];

		var evaluator = new Evaluator();

		var pixels = hxd.Pixels.alloc(width, height, s.curveTexture.format);
		for ( c in curves ) {
			for ( index => name in curveNames ) {
				if ( c.name != name )
					continue;
				var c = c.makeVal();
				s.CURVE_MASK = s.CURVE_MASK | (1 << index);
				for ( i in 0...width )
					pixels.setPixelF(i, index, new h3d.Vector4(evaluator.getFloat(c, (i / width))));
			}
		}

		s.curveTexture.uploadPixels(pixels);
		#end
	}

	override function postMakeInstance() {
		super.postMakeInstance();

		updateInstance();
	}

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		ctx.build(
			<category("Simulation")>
				<line label="Position">
					<slider field={x}/>
					<slider field={y}/>
					<slider field={z}/>
				</line>
				<slider-group label="Scale">
					<slider label="X" field={scaleX}/>
					<slider label="Y" field={scaleY}/>
					<slider label="Z" field={scaleZ}/>
				</slider-group>
				<line label="Rotation">
					<slider label="X" field={rotX}/>
					<slider label="Y" field={rotY}/>
					<slider label="Z" field={rotZ}/>
				</line>
				<line label="Speed">
					<slider label="X" field={speedX}/>
					<slider label="Y" field={speedY}/>
					<slider label="Z" field={speedZ}/>
				</line>
			</category>
		);
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Simulation">
				<dl>
					<dt>X</dt><dd><input type="range" field="x"/></dd>
					<dt>Y</dt><dd><input type="range" field="y"/></dd>
					<dt>Z</dt><dd><input type="range" field="z"/></dd>
					<dt>Scale X</dt><dd><input type="range" field="scaleX"/></dd>
					<dt>Scale Y</dt><dd><input type="range" field="scaleY"/></dd>
					<dt>Scale Z</dt><dd><input type="range" field="scaleZ"/></dd>
					<dt>Rotation X</dt><dd><input type="range" field="rotX"/></dd>
					<dt>Rotation Y</dt><dd><input type="range" field="rotY"/></dd>
					<dt>Rotation Z</dt><dd><input type="range" field="rotZ"/></dd>
					<dt>Speed X</dt><dd><input type="range" field="speedX"/></dd>
					<dt>Speed Y</dt><dd><input type="range" field="speedY"/></dd>
					<dt>Speed Z</dt><dd><input type="range" field="speedZ"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : hide.prefab.HideProps {
		var p = super.getHideProps();
		p.onChildUpdate = function(p : hrt.prefab.Prefab) updateInstance(p != null ? p.name : null);
		return p;
	}
	#end

	static var _ = Prefab.register("relativeTransformSimulation", RelativeTransformSimulation);
}