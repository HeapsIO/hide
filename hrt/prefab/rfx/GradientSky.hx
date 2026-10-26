package hrt.prefab.rfx;

typedef GradientSkyKey = {
	var gradient : hrt.impl.Gradient.GradientData;
	var t : Float;
}

class GradientSkyShader extends h3d.shader.ScreenShader {
	static var SRC = {
		@global var camera : {
			var position : Vec3;
			var inverseViewProj : Mat4;
		};
		@param var gradient : Sampler2D;
		@param var tod : Float;
		@param var intensity : Float;
		@const var USE_SATURATION : Bool;
		@param var saturation : Float;
		var normal : Vec3;
		var skyDir : Vec3;
		function fragment() {
			#if MRT_low
			var isSky = normal.dot(normal) > 1.1;
			#else
			var isSky = normal.dot(normal) <= 0;
			#end
			if( !isSky )
				discard;
			var p = vec4(uvToScreen(calculatedUV), 0.5, 1.) * camera.inverseViewProj;
			skyDir = (p.xyz / p.w - camera.position).normalize();
			var color = gradient.get(vec2(saturate(skyDir.z), fract(tod))).rgb;
			color *= color;
			if( USE_SATURATION )
				color = mix(vec3(color.dot(vec3(0.2126, 0.7152, 0.0722))), color, saturation);
			pixelColor = vec4(color * intensity, 1.);
		}
	}
}

class GradientSkyVelocityShader extends hxsl.Shader {
	static var SRC = {
		@global var camera : {
			var previousViewProj : Mat4;
			var jitterOffsets : Vec4;
		};
		var calculatedUV : Vec2;
		var skyDir : Vec3;
		var output : {
			var velocity : Vec2;
		};
		function fragment() {
			var prevClip = vec4(skyDir, 0.) * camera.previousViewProj;
			var prevNdc = prevClip.xy / prevClip.w - camera.jitterOffsets.zw;
			var ndc = uvToScreen(calculatedUV) - camera.jitterOffsets.xy;
			output.velocity = (prevNdc - ndc) * vec2(0.5, -0.5);
		}
	}
}

@:access(h3d.scene.Renderer)
@:access(h3d.scene.pbr.Renderer)
class GradientSky extends RendererFX {

	static inline var TOD_RES = 256;
	static var VELOCITY_OUTPUT : Array<hxsl.Output> = [Value("output.color"), Vec4([Value("output.velocity", 2), Const(0), Const(0)])];

	@:s public var keyframes : Array<GradientSkyKey> = [];
	@:s public var intensity = 1.;
	@:s public var tod = 0.;
	public var saturation = 1.;

	public var texture(get, never) : h3d.mat.Texture;
	var baked : h3d.mat.Texture;
	var blendFrom : h3d.mat.Texture;
	var blendTo : h3d.mat.Texture;
	var blendFactor = 0.;
	var blendDirty = false;
	var pass : h3d.pass.ScreenFx<GradientSkyShader>;
	var velocityPass : h3d.pass.ScreenFx<GradientSkyShader>;

	function get_texture() {
		if( blendFrom != null ) {
			if( blendDirty ) {
				h3d.pass.Merge.run(blendFrom, blendTo, blendFactor, baked);
				blendDirty = false;
			}
			return baked;
		}
		if( baked == null )
			baked = bake();
		return baked;
	}

	override function end( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
		if( step != Lighting || !checkEnabled() )
			return;
		var pbr = Std.downcast(r, h3d.scene.pbr.Renderer);
		if( pbr == null )
			return;
		var tex = texture;
		if( tex == null )
			return;
		r.mark("GradientSky");
		var engine = r.ctx.engine;
		var velocity = r.ctx.computeVelocity ? pbr.textures.velocity : null;
		var fx = getPass(velocity != null);
		if( velocity != null )
			engine.pushTargets([engine.getCurrentTarget(), velocity], NotBound);
		fx.shader.gradient = tex;
		fx.shader.tod = tod;
		fx.shader.intensity = intensity;
		fx.shader.USE_SATURATION = saturation != 1;
		fx.shader.saturation = saturation;
		var props = pbr.pbrProps;
		var prevIsScreen = props.isScreen;
		props.isScreen = true;
		fx.addShader(props);
		fx.render();
		fx.removeShader(props);
		props.isScreen = prevIsScreen;
		if( velocity != null )
			engine.popTarget();
	}

	function getPass( velocity : Bool ) {
		if( pass == null ) {
			pass = new h3d.pass.ScreenFx(new GradientSkyShader());
			pass.pass.setColorMask(true, true, true, false);
		}
		if( !velocity )
			return pass;
		if( velocityPass == null ) {
			velocityPass = new h3d.pass.ScreenFx(pass.shader, VELOCITY_OUTPUT);
			velocityPass.addShader(new GradientSkyVelocityShader());
			velocityPass.pass.setColorMask(true, true, true, false);
		}
		return velocityPass;
	}

	override function updateInstance( ?propName : String ) {
		var sky : GradientSky = cast instance;
		var prevTexture = sky?.baked;
		super.updateInstance(propName);
		prevTexture?.dispose();
		if( sky != null )
			sky.baked = null;
	}

	override function transition( r1 : h3d.impl.RendererFX, r2 : h3d.impl.RendererFX ) : h3d.impl.RendererFX.RFXTransition {
		var s1 : GradientSky = cast r1;
		var s2 : GradientSky = cast r2;
		var c = new GradientSky(null, null);
		c.tod = s1.tod;
		c.intensity = s1.intensity;
		c.saturation = s1.saturation;
		var from = s1.bake();
		var to = s2.bake();
		if( from != null && to != null ) {
			var target = new h3d.mat.Texture(hxd.Math.imax(from.width, to.width), TOD_RES, [Target]);
			target.wrap = Clamp;
			target.realloc = () -> c.blendDirty = true;
			c.baked = target;
			c.blendFrom = from;
			c.blendTo = to;
			c.blendDirty = true;
		} else
			c.baked = from ?? to;
		return { effect : cast c, setFactor : (f : Float) -> {
			c.intensity = hxd.Math.lerp(s1.intensity, s2.intensity, f);
			c.saturation = hxd.Math.lerp(s1.saturation, s2.saturation, f);
			c.blendFactor = f;
			c.blendDirty = true;
		}, dispose : c.dispose };
	}

	function bake() : h3d.mat.Texture {
		if( keyframes.length == 0 )
			return null;
		var keys = keyframes.copy();
		keys.sort((a, b) -> Reflect.compare(a.t, b.t));
		var width = 2;
		for( k in keys )
			width = hxd.Math.imax(width, k.gradient.resolution);
		var rows = [for( k in keys ) [for( x in 0...width ) hrt.impl.Gradient.evalData(k.gradient, x / (width - 1))]];
		var pixels = hxd.Pixels.alloc(width, TOD_RES, RGBA);
		var color = new h3d.Vector4();
		for( y in 0...TOD_RES ) {
			var t = (y + 0.5) / TOD_RES;
			var next = 0;
			while( next < keys.length && keys[next].t < t )
				next++;
			var prev = next - 1;
			var t0 = prev < 0 ? keys[keys.length - 1].t - 1 : keys[prev].t;
			var t1 = next == keys.length ? keys[0].t + 1 : keys[next].t;
			var a = rows[(prev + keys.length) % keys.length];
			var b = rows[next % keys.length];
			var f = t1 > t0 ? (t - t0) / (t1 - t0) : 0.;
			for( x in 0...width ) {
				color.lerp(a[x], b[x], f);
				pixels.setPixelF(x, y, color);
			}
		}
		var tex = h3d.mat.Texture.fromPixels(pixels);
		tex.wrap = Clamp;
		tex.realloc = () -> tex.uploadPixels(pixels);
		return tex;
	}

	override function dispose() {
		baked?.dispose();
		baked = null;
		blendFrom?.dispose();
		blendFrom = null;
		blendTo?.dispose();
		blendTo = null;
		super.dispose();
	}

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		function makeKey( header : hide.kit.Element, content : hide.kit.Element, key : GradientSkyKey, index : Int ) {
			header.build(<root><text('Key ' + index)/></root>);
			content.build(
				<root>
					<gradient field={key.gradient}/>
					<range(0, 1) label="Time" field={key.t}/>
				</root>
			);
		}
		ctx.build(
			<root>
				<range(0, 1) label="Time of day" field={tod}/>
				<range(0, 4) field={intensity}/>
				<list(makeKey, () -> { gradient : hrt.impl.Gradient.getDefaultGradientData(), t : 0. }) field={keyframes}/>
			</root>
		);
		super.edit2(ctx);
	}

	static var _ = Prefab.register("rfx.gradientSky", GradientSky);

}
