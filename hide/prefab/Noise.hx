package hide.prefab;

class Noise extends Prefab {

	public var seed : Int = Std.random(10000);

	public var scale : Float = 1.;
	public var channels : Int = 1;
	public var normals : Bool = false;
	public var contrast : Float = 0.;
	public var brightness : Float = 0.;

	public var size : Int = 512;
	public var octaves : Int = 1;
	public var persist : Float = 0.5;
	public var lacunarity : Float = 2.;
	public var ridged : Bool = false;
	public var gain : Float = 2.0;
	public var offset : Float = 0.5;
	public var turbulence : Float = 0.;
	public var turbulenceScale : Float = 1.;
	public var inverse : Bool;

	var tex : h3d.mat.Texture;

	override public function load(v:Dynamic) {
		this.seed = v.seed;
		this.size = v.size;
		this.scale = v.scale;
		if( v.channels != null ) this.channels = v.channels else this.channels = 1;
		this.octaves = v.octaves;
		this.persist = v.persist;
		this.lacunarity = v.lacunarity;
		this.ridged = v.ridged;
		if( v.gain != null ) this.gain = v.gain;
		if( v.offset != null ) this.offset = v.offset;
		if( v.contrast != null ) this.contrast = v.contrast else this.contrast = 0;
		if( v.brightness != null ) this.brightness = v.brightness else this.brightness = 0;
		if( v.normals != null ) this.normals = v.normals else this.normals = false;
		if( v.turbulence != null ) this.turbulence = v.turbulence else this.turbulence = 0;
		if( v.turbulenceScale != null ) this.turbulenceScale = v.turbulenceScale;
		if( v.inverse != null ) this.inverse = v.inverse else this.inverse = false;
	}

	override function save() {
		var o : Dynamic = {
			seed : seed,
			size : size,
			scale : scale,
			octaves : octaves,
			persist : persist,
			lacunarity : lacunarity,
		};
		if( channels != 1 )
			o.channels = channels;
		if( ridged ) {
			o.ridged = ridged;
			o.gain = gain;
			o.offset = offset;
		}
		if( contrast != 0 )
			o.contrast = contrast;
		if( brightness != 0 )
			o.brightness = brightness;
		if( normals )
			o.normals = normals;
		if( turbulence != 0 ) {
			o.turbulence = turbulence;
			o.turbulenceScale = turbulenceScale;
		}
		if( inverse )
			o.inverse = inverse;
		return o;
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

		pass.shader.ridged = ridged;
		pass.shader.gain = gain;
		pass.shader.offset = offset;

		pass.shader.contrast = contrast;
		pass.shader.brightness = brightness;
		pass.shader.normals = normals;
		pass.shader.inverse = inverse ? 1 : 0;

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
		tex.realloc = function() updateTexture(tex);
		return tex;
	}

	override function reload(p:Dynamic) {
		if( tex != null ) tex.dispose();
		super.reload(p);
	}

	function makeTile( tex : h3d.mat.Texture ) {
		var t = h2d.Tile.fromTexture(tex);
		if( tex.flags.has(IsNPOT) )
			return t;
		// make wrapping artefacts apparent, if any
		return t.sub(tex.width >> 1, tex.height >> 1, tex.width, tex.height);
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
		ctx.shared.cleanups.push(tex.dispose);
		return ctx;
	}

	#if editor

	override function getHideProps() : HideProps {
		return { icon : "cloud", name : "Noise Generator" };
	}

	override function edit( ctx : EditContext ) {
		var e = ctx.properties.add(new hide.Element('
			<dl>
				<dt>Size</dt><dd><input type="range" min="16" max="2048" step="16" field="size"/></dd>
				<dt>Scale</dt><dd><input type="range" min="0" max="2" field="scale"/></dd>
				<dt>Channels</dt><dd><input type="range" min="1" max="4" step="1" field="channels"/></dd>
				<dt>NormalMap</dt><dd><input type="checkbox" field="normals"/></dd>
			</dl>
			<br/>
			<dl>
				<dt>Octaves</dt><dd><input type="range" min="1" max="8" step="1" field="octaves"/></dd>
				<dt>Persistence</dt><dd><input type="range" min="0.01" max="1" field="persist"/></dd>
				<dt>Lacunarity</dt><dd><input type="range" min="1" max="5" field="lacunarity"/></dd>
			</dl>
			<br/>
			<dl>
				<dt>Ridged</dt><dd><input type="checkbox" field="ridged"/></dd>
				<dt>Offset</dt><dd><input type="range" min="-1" max="1" field="offset"/></dd>
				<dt>Gain</dt><dd><input type="range" min="0.01" max="5" field="gain"/></dd>
			</dl>
			<br/>
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
				<dt>Seed</dt><dd><input type="range" step="1" min="0" max="9999" field="seed"/></dd>
				<dt>&nbsp;</dt><dd><input type="button" value="Download" name="dl"/></dd>
			</dl>
		'),this,function(_) {
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
		});
		var bmp = cast(ctx.getContext(this).local2d, h2d.Bitmap);
		bmp.visible = true;
		ctx.cleanups.push(function() bmp.visible = false);
		e.find("[name=dl]").click(function(_) {
			ctx.ide.chooseFileSave("noise.png", function(f) if( f != null ) {
				try {
					var data = cast(ctx.getContext(this).local2d, h2d.Bitmap).tile.getTexture().capturePixels().toPNG();
					sys.io.File.saveBytes(f, data);
				} catch( e : Dynamic ) {
					js.Browser.alert(e);
				}
			});
		});
	}

	#end

	static var _ = hxd.prefab.Library.register("noise", Noise);

}

class NoiseShader extends h3d.shader.ScreenShader {

	static var SRC = {

		@:import h3d.shader.NoiseLib;

		@const var channels : Int = 1;
		@const var octaves : Int = 1;
		@const var ridged : Bool;
		@const var normals : Bool;

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

		function perturb( uv : Vec2, scale : Float, seed : Int ) : Vec2 {
			if( turbulence > 0. ) {
				var turbScaleRepeat = int(scale * turbulenceScale * 0.5) * 2.;
				noiseSeed = channels * octaves + 1 + seed;
				uv.x += psnoise(calculatedUV * turbScaleRepeat, turbScaleRepeat.xx) * turbulence;
				noiseSeed = channels * octaves + 1025 + seed;
				uv.y += psnoise(calculatedUV * turbScaleRepeat, turbScaleRepeat.xx) * turbulence;
			}
			return uv;
		}

		function noise( seed : Int, scale : Float ) : Float {
			var scaleRepeat = int(scale * 0.5) * 2.;
			var uv = perturb(calculatedUV,scale,seed);
			noiseSeed = seed;
			return psnoise(uv * scaleRepeat, scaleRepeat.xx);
		}

		function noiseNormal( seed : Int, scale : Float ) : Vec3 {
			var scaleRepeat = int(scale * 0.5) * 2.;
			var uv = perturb(calculatedUV, scale,seed);
			noiseSeed = seed;
			return psrdnoise(uv * scaleRepeat, scaleRepeat.xx, 0.).yzx;
		}

		function calc( channel : Int ) : Float {
			var v = 0.;
			var seed = seed + channel * octaves;
			var scale = scale;
			if( ridged ) {
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
			} else {
				var k = 1.;
				for( i in 0...octaves ) {
					v += noise(seed + i, scale) * k;
					k *= persist;
					scale *= lacunarity;
				}
			}
			v = (v * (1 + contrast) + 1) * 0.5 + brightness;
			if( inverse > 0 ) v = 1 - v;
			return v;
		}

		function calcNormal() : Vec3 {
			var v = vec3(0.);
			var scale = scale;
			if( ridged ) {
				// TODO
				v.z = 1.;
			} else {
				var k = 1.;
				for( i in 0...octaves ) {
					v += noiseNormal(seed + i, scale) * k;
					k *= persist;
					scale *= lacunarity;
				}
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