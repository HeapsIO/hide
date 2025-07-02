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

		@param var curveTexture : Sampler2D;

		var life : Float;
		var relativeTransform : Mat4;

		function hasBit(n : Int) : Bool {
			return (CURVE_MASK & (1 << n) ) != 0;
		}

		function getCurve(n : Int) : Float {
			return curveTexture.getLod(vec2(life, (n + 0.5) / 9.0), 0.0).r;
		}

		function main() {
			var translation = vec3(x,y,z);
			var scale = vec3(scaleX, scaleY, scaleZ);
			var rotation = vec3(rotX, rotY, rotZ);

			if ( hasBit(0) )
				translation.x = getCurve(0);
			if ( hasBit(1) )
				translation.y = getCurve(1);
			if ( hasBit(2) )
				translation.z = getCurve(2);

			if ( hasBit(3) )
				scale.x = getCurve(3);
			if ( hasBit(4) )
				scale.y = getCurve(4);
			if ( hasBit(5) )
				scale.z = getCurve(5);

			if ( hasBit(6) )
				rotation.x = getCurve(6);
			if ( hasBit(7) )
				rotation.y = getCurve(7);
			if ( hasBit(8) )
				rotation.z = getCurve(8);

			// rotation not supported
			var shaderTRS = scaleMatrix(scale) * translationMatrix(translation);
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

	override function makeShader() {
		return new RelativeTransformSimulationShader();
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);

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

		s.CURVE_MASK = 0;

		var width = 256;
		var height = 9;

		s.curveTexture = new h3d.mat.Texture(width, height, null, R32F);

		var curves = findAll(hrt.prefab.Curve);
		if ( curves.length == 0 )
			return;

		var curveNames = ["x", "y", "z", "scaleX", "scaleY", "scaleZ", "rotX", "rotY", "rotZ"];


		var pixels = hxd.Pixels.alloc(width, height, s.curveTexture.format);
		for ( c in curves ) {
			if ( !c.shouldBeInstanciated() )
				continue;
			for ( index => name in curveNames ) {
				if ( c.name != name )
					continue;
				s.CURVE_MASK = s.CURVE_MASK | (1 << index);
				for ( i in 0...width )
					pixels.setPixelF(i, index, new h3d.Vector4(c.getVal(i / width)));
			}
		}

		s.curveTexture.uploadPixels(pixels);
	}

	override function postMakeInstance() {
		super.postMakeInstance();

		updateInstance();
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