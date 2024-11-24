package hrt.prefab.fx.gpuemitter;

class TurbulenceSimulationShader extends ComputeUtils {

	static var SRC = {
		@param var intensity : Float;
		@const var octaves : Int;
		@param var noiseTex : Sampler2D;
		@param var noiseScale : Float;
		@param var scrollSpeed : Vec3;
		@param var innerTurmoil : Float;
		@param var lacunarity : Float;
		@param var persistence : Float;

		var speed : Vec3;
		var prevModelView : Mat4;
		var modelView : Mat4;
		var dt : Float;

		function noise( pos : Vec3 ) : Float {
			var i = floor(pos);
    		var f = fract(pos);
			f = f*f*(3.0-2.0*f);
			var uv = (i.xy+vec2(37.0,239.0)*i.z) + f.xy;
			var rg = noiseTex.getLod( (uv+0.5) / 256.0, 0 ).yx;
			return 2.0 * mix( rg.x, rg.y, f.z ) - 1.0;
		}

		function noiseAt( pos : Vec3 ) : Float {
			var amount = 0.;
			var tot = 0.;
			var pos = pos * 0.1 * noiseScale;
			var k = 1.;
			var t = global.time * scrollSpeed;
			@unroll for( i in 0...octaves ) {
				var staticOffset = vec3(0, 0, 1);
				var f = 1.0;
				if (i == 0) {
					f = 0.5;
					amount += noise(pos - t - staticOffset * global.time * innerTurmoil) * k * f;
				}
				staticOffset = vec3(0, 0, -1);
				if (i == 1) staticOffset = vec3(0, 0, -0.6);
				if (i == 2) staticOffset = vec3(-0.9, 0, 1.1);
				if (i == 3) staticOffset = vec3(0.8, 0.95,-1.2);
				if (i == 4) staticOffset = vec3(0,-0.84,-1.3);
				if (i == 5) staticOffset = vec3(0.3, -0.05, -0.9);
				amount += noise(pos - t - staticOffset * global.time * innerTurmoil) * k * f;
				tot += k;
				pos *= lacunarity;
				k *= persistence;
			}
			return amount / tot;
		}

		function main() {
			var idx = computeVar.globalInvocation.x;
			var prevPos = vec3(0.0) * prevModelView.mat3x4();

			var n = noiseAt(prevPos);

			speed += normalize(scrollSpeed) * n * intensity;
		}
	}
}

class TurbulenceSimulation extends SimulationShader {
	static var noiseTex : h3d.mat.Texture;
	
	@:s var intensity : Float = 1.0;
	@:s var octaves : Int = 2;
	@:s var noiseScale : Float = 1.0;
	@:s var scrollSpeedX : Float = 1.0;
	@:s var scrollSpeedY : Float = 0.0;
	@:s var scrollSpeedZ : Float = 0.0;
	@:s var innerTurmoil : Float = 0.0;
	@:s var lacunarity : Float = 2.0;
	@:s var persistence : Float = 0.5;

	override function makeShader() {
		return new TurbulenceSimulationShader();
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);

		if ( noiseTex == null || noiseTex.isDisposed() ) {
			if ( noiseTex == null )
				noiseTex = new h3d.mat.Texture(256, 256);
			var rands : Array<Int> = [];
			var rand = new hxd.Rand(0);
			for(_ in 0...256 * 256)
				rands.push(rand.random(256));
			var pix = hxd.Pixels.alloc(256, 256, RGBA);
			for(x in 0...256) {
				for(y in 0...256) {
					var r = rands[x + y * 256];
					var g = rands[((x - 37) & 255) + ((y - 239) & 255) * 256];
					var off = (x + y*256) * 4;
					pix.bytes.set(off, r);
					pix.bytes.set(off+1, g);
					pix.bytes.set(off+3, 255);
				}
			}
			noiseTex.uploadPixels(pix);
			noiseTex.wrap = Repeat;
		}

		var sh = cast(shader, TurbulenceSimulationShader);
		sh.noiseTex = noiseTex;
		sh.intensity = intensity;
		sh.octaves = octaves;
		sh.noiseScale = noiseScale;
		sh.scrollSpeed.set(scrollSpeedX, scrollSpeedY, scrollSpeedZ);
		sh.innerTurmoil = innerTurmoil;
		sh.lacunarity = lacunarity;
		sh.persistence = persistence;
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Simulation">
				<dl>
					<dt>Intensity</dt><dd><input type="range" min="0" max="5" field="intensity"/></dd>
					<dt>Octaves</dt><dd><input type="range" min="1" max="4" step="1" field="octaves"/></dd>
					<dt>Noise scale</dt><dd><input type="range" min="0" max="1" field="noiseScale"/></dd>
					<dt>Noise speed X</dt><dd><input type="range" min="-1" max="1" field="scrollSpeedX"/></dd>
					<dt>Noise speed Y</dt><dd><input type="range" min="-1" max="1" field="scrollSpeedY"/></dd>
					<dt>Noise speed Z</dt><dd><input type="range" min="-1" max="1" field="scrollSpeedZ"/></dd>
					<dt>Turmoil</dt><dd><input type="range" min="0" max="1" field="innerTurmoil"/></dd>
					<dt>Lacunarity</dt><dd><input type="range" min="0" max="2" field="lacunarity"/></dd>
					<dt>Persistence</dt><dd><input type="range" min="0" max="1" field="persistence"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("turbulenceSimulation", TurbulenceSimulation);
}