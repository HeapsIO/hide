package hrt.prefab.l2d;

enum abstract NoiseMode(String) {
	var Perlin;
	var Ridged;
}

enum abstract RepeatMode(String) {
	var Both;
	var X;
	var Y;
	var None;
}

class NoiseGenerator extends Prefab {

	@:s public var seed : Int;

	@:s public var mode : NoiseMode = Perlin;

	@:s public var scale : Float = 1.;
	@:s public var channels : Int = 1;
	@:s public var normals : Bool = false;
	@:s public var contrast : Float = 0.;
	@:s public var brightness : Float = 0.;
	@:s public var repeat : RepeatMode = Both;

	@:s public var size : Int = 512;
	@:s public var octaves : Int = 1;
	@:s public var persist : Float = 0.5;
	@:s public var lacunarity : Float = 2.;
	@:s public var gain : Float = 2.0;
	@:s public var offset : Float = 0.5;
	@:s public var turbulence : Float = 0.;
	@:s public var turbulenceScale : Float = 1.;
	@:s public var inverse : Bool;

	var tex : h3d.mat.Texture;

	function new(?parent) {
		super(parent);
		seed = Std.random(100);
	}

	public function updateTexture( t : h3d.mat.Texture ) {
		var e = h3d.Engine.getCurrent();
		e.pushTarget(t);
		@:privateAccess e.flushTarget();
		var pass = new h3d.pass.ScreenFx(new NoiseShader());
		pass.shader.seed = seed;
		pass.shader.channels = normals ? 0 : channels;
		pass.shader.octaves = octaves;
		var scale = size * scale * scale / 16;
		pass.shader.scale = Math.round(scale*0.5) * 2;
		pass.shader.persist = persist;
		pass.shader.lacunarity = lacunarity;

		pass.shader.mode = switch( mode ) {
		case Perlin: 0;
		case Ridged :
			pass.shader.gain = gain;
			pass.shader.offset = offset;
			1;
		}

		pass.shader.contrast = contrast;
		pass.shader.brightness = brightness;
		pass.shader.normals = normals;
		pass.shader.inverse = inverse ? 1 : 0;
		pass.shader.repeat = switch repeat {
			case Both: 0;
			case X: 1;
			case Y: 2;
			case None: 3;
		}

		pass.shader.turbulence = turbulence * 16 / size;
		pass.shader.turbulenceScale = turbulenceScale;

		pass.render();
		pass.dispose();
		e.popTarget();
	}

	public function toTexture() {
		if( tex != null )
			return tex;
		tex = new h3d.mat.Texture(size, size, [Target]);
		if( !tex.flags.has(IsNPOT) ) tex.wrap = Repeat;
		updateTexture(tex);
		var e = h3d.Engine.getCurrent();
		tex.realloc = function() haxe.Timer.delay(function() {
			e.setCurrent();
			updateTexture(tex);
		}, 0);
		return tex;
	}

	override function reload(p:Dynamic) {
		if( tex != null ) {
			tex.dispose();
			tex = null;
		}
		super.reload(p);
	}

	function makeTile( tex : h3d.mat.Texture ) {
		var t = h2d.Tile.fromTexture(tex);
		if( tex.flags.has(IsNPOT) )
			return t;
		// make wrapping artefacts apparent, if any
		return t.sub(repeat == Both || repeat == X ? tex.width >> 1 : 0, repeat == Both || repeat == Y ? tex.height >> 1 : 0, tex.width, tex.height);
	}

	override function makeInstance( ctx : Context ) {
		var tex = new h3d.mat.Texture(size, size, [Target]);
		updateTexture(tex);
		ctx = ctx.clone(this);
		var bmp = new h2d.Bitmap(makeTile(tex), ctx.local2d);
		bmp.tileWrap = !tex.flags.has(IsNPOT);
		bmp.visible = false;
		bmp.x = -size >> 1;
		bmp.y = -size >> 1;
		ctx.local2d = bmp;
		ctx.cleanup = function() tex.dispose();
		return ctx;
	}

	#if editor

	override function getHideProps() : HideProps {
		return { icon : "cloud", name : "Noise Generator" };
	}

	override function edit( ctx : EditContext ) {
		var e = ctx.properties.add(new hide.Element('
			<dl>
				<dt>Mode</dt><dd><select field="mode">
					<option value="Perlin">Perlin</option>
					<option value="Ridged">Ridged</option>
				</select>
				</dd>
				<dt>Size</dt><dd><input type="range" min="16" max="2048" step="16" field="size"/></dd>
				<dt>Scale</dt><dd><input type="range" min="0" max="2" field="scale"/></dd>
				<dt>Channels</dt><dd><input type="range" min="1" max="4" step="1" field="channels"/></dd>
				<dt>NormalMap</dt><dd><input type="checkbox" field="normals"/></dd>
				<dt>Repeat</dt><dd>
					<select field="repeat">
						<option value="Both">Both</option>
						<option value="X">X</option>
						<option value="Y">Y</option>
						<option value="None">None</option>
					</select>
				</dd>
			</dl>
			<br/>
			<dl>
				<dt>Octaves</dt><dd><input type="range" min="1" max="8" step="1" field="octaves"/></dd>
				<dt>Persistence</dt><dd><input type="range" min="0.01" max="1" field="persist"/></dd>
				<dt>Lacunarity</dt><dd><input type="range" min="1" max="5" field="lacunarity"/></dd>
			</dl>
			<br/>
			${mode == Ridged ? '
				<dl>
					<dt>Offset</dt><dd><input type="range" min="-1" max="1" field="offset"/></dd>
					<dt>Gain</dt><dd><input type="range" min="0.01" max="5" field="gain"/></dd>
				</dl>
				<br/>
			' : ''}
			<dl>
				<dt>Turbulence</dt><dd><input type="range" min="0" max="1" field="turbulence"/></dd>
				<dt>Scale</dt><dd><input type="range" min="0" max="10" field="turbulenceScale"/></dd>
			</dl>
			<br/>
			<dl>
				<dt>Contrast</dt><dd><input type="range" min="-1" max="1" field="contrast"/></dd>
				<dt>Brightness</dt><dd><input type="range" min="-1" max="1" field="brightness"/></dd>
				<dt>Inverse</dt><dd><input type="checkbox" field="inverse"/></dd>
			</dl>
			<br/>
			<dl>
				<dt>Seed</dt><dd><input type="range" step="1" min="0" max="100" field="seed"/></dd>
				<dt>&nbsp;</dt><dd><input type="button" value="Download" name="dl"/></dd>
			</dl>
		'),this,function(pname)  {
			var bmp = cast(ctx.getContext(this).local2d, h2d.Bitmap);
			var tex = bmp.tile.getTexture();
			if( tex.width != size ) {
				tex.resize(size, size);
				bmp.tile = makeTile(tex);
				bmp.tileWrap = !tex.flags.has(IsNPOT);
				bmp.x = -size >> 1;
				bmp.y = -size >> 1;
			}
			updateTexture(tex);
			ctx.onChange(this, pname);
		});
		var bmp = cast(ctx.getContext(this).local2d, h2d.Bitmap);
		e.find("[name=dl]").click(function(_) {
			ctx.ide.chooseFileSave("noise.png", function(f) if( f != null ) {
				try {
					var data = cast(ctx.getContext(this).local2d, h2d.Bitmap).tile.getTexture().capturePixels().toPNG();
					sys.io.File.saveBytes(ctx.ide.getPath(f), data);
				} catch( e : Dynamic ) {
					ctx.ide.error(e);
				}
			});
		});
		bmp.visible = true;
		ctx.cleanups.push(function() bmp.visible = false);
	}

	#end

	static var _ = Library.register("noise", NoiseGenerator);

}

class NoiseShader extends h3d.shader.ScreenShader {

	static var SRC = {

		@:import h3d.shader.NoiseLib;

		@const(5) var channels : Int = 1;
		@const(64) var octaves : Int = 1;
		@const(4) var mode : Int;
		@const var normals : Bool;
		@const(4) var repeat : Int;

		@param var seed : Int;
		@param var scale : Float = 8;
		@param var persist : Float = 0.5;
		@param var lacunarity : Float = 2.0;

		@param var gain : Float;
		@param var offset : Float;
		@param var inverse : Float;

		@param var contrast : Float;
		@param var brightness : Float;
		@param var turbulence : Float;
		@param var turbulenceScale : Float;

		function makeRepeat( scale : Float ) : Vec2 {
			var s = int(scale * 0.5) * 2.;
			return if( repeat == 0 ) vec2(s) else if( repeat == 1 ) vec2(s,scale) else if( repeat == 2 ) vec2(scale,s) else vec2(scale);
		}

		function makePeriod( scale : Vec2 ) : Vec2 {
			// TODO : the period is unbound for no-repeat but psrnoise
			// still exhibits rounding behaviors with low scales
			if( repeat == 0 )
				return scale;
			if( repeat == 1 )
				return vec2(scale.x, 1e9);
			if( repeat == 2 )
				return vec2(1e9, scale.y);
			return vec2(1e9);
		}

		function perturb( uv : Vec2, scale : Float, seed : Int ) : Vec2 {
			if( turbulence > 0. ) {
				var turbScaleRepeat = makeRepeat(scale * turbulenceScale);
				noiseSeed = channels * octaves + 1 + seed;
				uv.x += psnoise(calculatedUV * turbScaleRepeat, makePeriod(turbScaleRepeat)) * turbulence;
				noiseSeed = channels * octaves + 1025 + seed;
				uv.y += psnoise(calculatedUV * turbScaleRepeat, makePeriod(turbScaleRepeat)) * turbulence;
			}
			return uv;
		}

		function noise( seed : Int, scale : Float ) : Float {
			var scaleRepeat = makeRepeat(scale);
			var uv = perturb(calculatedUV,scale,seed);
			noiseSeed = seed;
			return psnoise(uv * scaleRepeat, makePeriod(scaleRepeat));
		}

		function noiseNormal( seed : Int, scale : Float ) : Vec3 {
			var scaleRepeat = makeRepeat(scale);
			var uv = perturb(calculatedUV, scale,seed);
			noiseSeed = seed;
			return psrdnoise(uv * scaleRepeat, makePeriod(scaleRepeat), 0.).yzx;
		}

		function calc( channel : Int ) : Float {
			var v = 0.;
			var seed = seed + channel * octaves;
			var scale = scale;
			switch( mode ) {
			case 0: // perlin
				var k = 1.;
				for( i in 0...octaves ) {
					v += noise(seed + i, scale) * k;
					k *= persist;
					scale *= lacunarity;
				}
			case 1: // ridged
				var k = 1.;
				var s = lacunarity;
				var weight = 1.;
				var tot = 0.;
				for( i in 0...octaves ) {
					var g = noise(seed + i, scale) * k;
					g = offset - abs(g);
					g *= g;
					g *= weight;
					v += g * s;
					tot += k;
					weight = g * gain;
					if( weight < 0 ) weight = 0 else if( weight > 1 ) weight = 1;
					k *= persist;
					scale *= lacunarity;
				}
				v /= tot;
			}
			v = (v * (1 + contrast) + 1) * 0.5 + brightness;
			if( inverse > 0 ) v = 1 - v;
			return v;
		}

		function calcNormal() : Vec3 {
			var v = vec3(0.);
			var scale = scale;
			switch( mode ) {
			case 0:
				var k = 1.;
				for( i in 0...octaves ) {
					v += noiseNormal(seed + i, scale) * k;
					k *= persist;
					scale *= lacunarity;
				}
			default:
				// TODO
				v.z = 1.;
			}
			v.z = (v.z + 1) * 0.5 + 10;
			v = v.normalize();
			v.xy *= pow(2., 1. + contrast * 4.);
			return v.normalize();
		}

		function fragment() {
			var out = vec4(0, 0, 0, 1);

			if( normals ) {
				out = packNormal(calcNormal());
			} else {
				if( channels >= 1 ) {
					out.r = calc(0);
					if( channels == 1 ) out.gb = out.rr;
				}
				if( channels >= 2 )
					out.g = calc(1);
				if( channels >= 3 )
					out.b = calc(2);
				if( channels >= 4 )
					out.a = calc(3);
			}
			output.color = out;
		}
	}

}