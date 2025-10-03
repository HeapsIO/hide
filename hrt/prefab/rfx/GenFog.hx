package hrt.prefab.rfx;

class GenFogShader extends hrt.shader.PbrShader {

	static var SRC = {

		@param var intensity : Float;

		@param var startDistance : Float;
		@param var distanceScale : Float;
		@param var distanceOpacity : Float;
		@param var cameraDistance : Float;

		@param var startHeight : Float;
		@param var heightScale : Float;
		@param var heightOpacity : Float;

		@param var startColor : Vec4;
		@param var endColor : Vec4;

		@const var usePosition : Bool;
		@param var position : Vec3;

		@const var useNoise : Bool;
		@param var noiseTex : Sampler2D;
		@param var noiseScale : Float;
		@param var noiseSpeed : Float;
		@param var noiseAmount : Vec3;

		@param var lightDirection : Vec3;
		@param var lightColor : Vec3;
		@param var dotThreshold : Float;

		function fragment() {
			var origin = getPosition();
			var amount = 0.;

			if( useNoise ) {
				var noise = noiseTex.get( origin.xy * noiseScale + vec2(global.time * noiseSpeed, noiseScale * origin.z) * vec2(1,-1) );
				origin += (noise.rgb - 0.5) * noiseAmount;
			}

			if( distanceOpacity != 0 ) {
				var distance = (origin - (usePosition ? position : camera.position)).length() - cameraDistance;
				amount += smoothstep(0.0, 1.0, (distance - startDistance) * distanceScale) * distanceOpacity;
			}

			if( heightOpacity != 0 ) {
				var height = origin.z;
				if( usePosition ) height -= position.z;
				amount += smoothstep(0.0, 1.0, (height - startHeight) * heightScale) * heightOpacity;
			}

			var fogColor = mix(startColor, endColor, smoothstep(0.0, 1.0, amount));
			fogColor.rgb += smoothstep(0.0, 1.0, ((camera.position - origin).normalize().dot(lightDirection) - dotThreshold) / (1.0 - dotThreshold)) * lightColor;
			pixelColor = mix(pixelColor, fogColor, intensity);
		}

	};

	public function new() {
		super();
	}

}

typedef GenFogNoise = {
	var texture : String;
	var speed : Float;
	var scale : Float;
	var amount : Float;
	var distAmount : Float;
}

enum abstract GenFogRenderMode(String) {
	var Lighting;
	var BeforeTonemapping;
	var AfterTonemapping;
}

@:access(h3d.scene.Renderer)
class GenFog extends RendererFX {

	var fogPass = new h3d.pass.ScreenFx(new GenFogShader());

	@:s public var intensity : Float = 1;

	@:s public var startDistance : Float;
	@:s public var endDistance : Float;
	@:s public var distanceOpacity : Float;
	@:s public var distanceFixed : Bool;

	@:s public var startHeight : Float;
	@:s public var endHeight : Float;
	@:s public var heightOpacity : Float;

	@:s public var startOpacity : Float;
	@:s public var endOpacity : Float;

	@:s public var startColor : Int;
	@:s public var endColor : Int;
	@:s public var renderMode : GenFogRenderMode;

	@:s public var noise : GenFogNoise;

	@:s public var posX : Float;
	@:s public var posY : Float;
	@:s public var posZ : Float;
	@:s public var usePosition : Bool;

	@:s public var lightColor = 0xFFFFFF;
	@:s public var lightColorAmount : Float;
	@:s public var lightAngle : Float = 90.0;

	public function new(parent, shared: ContextShared) {
		super(parent, shared);
		renderMode = AfterTonemapping;
		endDistance = 100;
		startHeight = 100;
		endOpacity = 1;
		startColor = 0xffffff;
	    endColor = 0xffffff;
		fogPass.pass.setBlendMode(Alpha);
	}

	function checkPass(step : h3d.impl.RendererFX.Step) {
		return (step == AfterTonemapping && renderMode == AfterTonemapping) || (step == BeforeTonemapping && renderMode == BeforeTonemapping) || (step == Lighting && renderMode == Lighting);
	}

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( !checkEnabled() ) return;
		if( checkPass(step) ) {
			r.mark("DistanceFog");
			var ctx = r.ctx;

			fogPass.shader.intensity = intensity;

			fogPass.shader.startDistance = startDistance;
			fogPass.shader.distanceScale = 1 / (endDistance - startDistance);
			fogPass.shader.distanceOpacity = distanceOpacity;
			fogPass.shader.cameraDistance = distanceFixed ? r.ctx.camera.pos.sub(r.ctx.camera.target).length() : 0;

			fogPass.shader.startHeight = startHeight;
			fogPass.shader.heightScale = 1 / (endHeight - startHeight);
			fogPass.shader.heightOpacity = heightOpacity;

			fogPass.shader.startColor.setColor(startColor);
			fogPass.shader.endColor.setColor(endColor);
			fogPass.shader.startColor.a = startOpacity;
			fogPass.shader.endColor.a = endOpacity;

			fogPass.shader.position.set(posX, posY, posZ);
			fogPass.shader.usePosition = usePosition;

			fogPass.shader.useNoise = noise != null && noise.texture != null;
			if( noise != null && noise.texture != null ) {
				fogPass.shader.noiseTex = hxd.res.Loader.currentInstance.load(noise.texture).toTexture();
				fogPass.shader.noiseTex.wrap = Repeat;
				fogPass.shader.noiseScale = 1 / noise.scale;
				fogPass.shader.noiseSpeed = noise.speed / noise.scale;
				fogPass.shader.noiseAmount.set(noise.amount * noise.distAmount, noise.amount * noise.distAmount, noise.amount);
			}

			var ls = r.getLightSystem().shadowLight;
			if( ls == null )
				fogPass.shader.lightDirection.set(0,0,0);
			else
				fogPass.shader.lightDirection.load(@:privateAccess ls.getShadowDirection());
			fogPass.shader.lightColor.setColor(lightColor);
			fogPass.shader.lightColor.scale(lightColorAmount);
			fogPass.shader.dotThreshold = hxd.Math.cos(lightAngle * Math.PI/180);
			fogPass.render();
		}
	}

	override function modulate(t : Float) {
		var g : GenFog = cast super.modulate(t);
		g.intensity = this.intensity * t;
		return g;
	}

	override function transition( r1 : h3d.impl.RendererFX, r2 : h3d.impl.RendererFX ) : h3d.impl.RendererFX.RFXTransition {
		var g1 : GenFog = cast r1;
		var g2 : GenFog = cast r2;

		var g = new GenFog(null, null);
		g.intensity = g1.intensity;
		g.startDistance = g1.startDistance;
		g.endDistance = g1.endDistance;
		g.distanceOpacity = g1.distanceOpacity;
		g.distanceFixed = g1.distanceFixed;
		g.startHeight = g1.startHeight;
		g.endHeight = g1.endHeight;
		g.heightOpacity = g1.heightOpacity;
		g.startOpacity = g1.startOpacity;
		g.endOpacity = g1.endOpacity;
		g.startColor = g1.startColor;
		g.endColor = g1.endColor;
		g.renderMode = g1.renderMode;
		g.noise = g1.noise;
		g.posX = g1.posX;
		g.posY = g1.posY;
		g.posZ = g1.posZ;
		g.usePosition = g1.usePosition;
		g.lightColor = g1.lightColor;
		g.lightColorAmount = g1.lightColorAmount;
		g.lightAngle = g1.lightAngle;

		return { effect : cast g, setFactor : (f : Float) -> {
			g.intensity = hxd.Math.lerp(g1.intensity, g2.intensity, f);
			g.startDistance = hxd.Math.lerp(g1.startDistance, g2.startDistance, f);
			g.endDistance = hxd.Math.lerp(g1.endDistance, g2.endDistance, f);
			g.distanceOpacity = hxd.Math.lerp(g1.distanceOpacity, g2.distanceOpacity, f);
			g.startHeight = hxd.Math.lerp(g1.startHeight, g2.startHeight, f);
			g.endHeight = hxd.Math.lerp(g1.endHeight, g2.endHeight, f);
			g.heightOpacity = hxd.Math.lerp(g1.heightOpacity, g2.heightOpacity, f);
			g.startOpacity = hxd.Math.lerp(g1.startOpacity, g2.startOpacity, f);
			g.endOpacity = hxd.Math.lerp(g1.endOpacity, g2.endOpacity, f);
			g.posX = hxd.Math.lerp(g1.posX, g2.posX, f);
			g.posY = hxd.Math.lerp(g1.posY, g2.posY, f);
			g.posZ = hxd.Math.lerp(g1.posZ, g2.posZ, f);
			g.lightColorAmount = hxd.Math.lerp(g1.lightColorAmount, g2.lightColorAmount, f);
			g.lightAngle = hxd.Math.lerp(g1.lightAngle, g2.lightAngle, f);

			function lerpColor(c1 : Int, c2 : Int, f : Float) : Int {
				var a1 = (c1 >> 24) & 0xFF;
				var r1 = (c1 >> 16) & 0xFF;
				var g1 = (c1 >> 8) & 0xFF;
				var b1 = c1 & 0xFF;

				var a2 = (c2 >> 24) & 0xFF;
				var r2 = (c2 >> 16) & 0xFF;
				var g2 = (c2 >> 8) & 0xFF;
				var b2 = c2 & 0xFF;

    			inline function lerp(v1:Int, v2:Int, f:Float) : Int return Std.int(v1 * (1 - f) + v2 * f);
    			return (lerp(a1, a2, f) << 24) | (lerp(r1, r2, f) << 16) | (lerp(g1, g2, f) << 8) | lerp(b1, b2, f);
			}

			g.startColor = lerpColor(g1.startColor, g2.startColor, f);
			g.endColor = lerpColor(g1.endColor, g2.endColor, f);
			g.lightColor = lerpColor(g1.lightColor, g2.lightColor, f);

			g.noise = f < 0.5 ? g1.noise : g2.noise;

			g.renderMode = f < 0.5 ? g1.renderMode : g2.renderMode;
			g.usePosition = f < 0.5 ? g1.usePosition : g2.usePosition;
			g.distanceFixed = f < 0.5 ? g1.distanceFixed : g2.distanceFixed;
		} };
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<dl>
				<div class="group" name="General">
					<dt>Intensity</dt><dd><input type="range" min="0" max="1" field="intensity"/></dd>
				</div>
				<div class="group" name="Distance">
					<dt>Start Distance</dt><dd><input type="range" min="0" max="100" field="startDistance"/></dd>
					<dt>End Distance</dt><dd><input type="range" min="0" max="100" field="endDistance"/></dd>
					<dt>Distance Opacity</dt><dd><input type="range" min="0" max="2" field="distanceOpacity"/></dd>
					<dt>Camera Independant</dt><dd><input type="checkbox" field="distanceFixed"/></dd>
				</div>
				<div class="group" name="Height">
					<dt>Start Height</dt><dd><input type="range" min="0" max="100" field="startHeight"/></dd>
					<dt>End Height</dt><dd><input type="range" min="0" max="100" field="endHeight"/></dd>
					<dt>Height Opacity</dt><dd><input type="range" min="0" max="2" field="heightOpacity"/></dd>
				</div>
				<div class="group" name="Center">
					<dt>X</dt><dd><input type="range" min="-100" max="100" field="posX"/></dd>
					<dt>Y</dt><dd><input type="range" min="-100" max="100" field="posY"/></dd>
					<dt>Z</dt><dd><input type="range" min="-100" max="100" field="posZ"/></dd>
					<dt>Use Center Point</dt><dd><input type="checkbox" field="usePosition"/></dd>
				</div>
				<div class="group" name="Color">
					<dt>Start Color</dt><dd><input type="color" field="startColor"/></dd>
					<dt>End Color</dt><dd><input type="color" field="endColor"/></dd>
					<dt>Start Opacity</dt><dd><input type="range" min="0" max="1" field="startOpacity"/></dd>
					<dt>End Opacity</dt><dd><input type="range" min="0" max="1" field="endOpacity"/></dd>
				</div>
				<div class="group" name="Light">
					<dt>Light Color</dt><dd><input type="color" field="lightColor"/></dd>
					<dt>Amount</dt><dd><input type="range" min="0" max="1" field="lightColorAmount"/></dd>
					<dt>Angle</dt><dd><input type="range" min="0" max="180" field="lightAngle"/></dd>
				</div>
				<div class="group" name="Rendering">
					<dt>Render Mode</dt>
						<dd><select field="renderMode">
							<option value="Lighting">Lighting</option>
							<option value="BeforeTonemapping">Before Tonemapping</option>
							<option value="AfterTonemapping">After Tonemapping</option>
						</select></dd>
				</div>

			</dl>
		'),this, function(pname) {
			ctx.onChange(this,pname);
		});
		if( noise == null ) {
			var e = ctx.properties.add(new hide.Element('
			<div class="group" name="Noise">
			<dl><dt></dt><dd><a class="button" href="#">Add</a></dd></dl>
			</div>
			'));
			e.find("a.button").click(function(_) {
				noise = {
					texture : null,
					amount : 1,
					scale : 1,
					speed : 1,
					distAmount : 0.5,
				};
				ctx.rebuildProperties();
			});
		} else {
			var e = ctx.properties.add(new hide.Element('
			<div class="group" name="Noise">
			<dl>
				<dt>Texture</dt><dd><input type="texturepath" field="texture"/></dd>
				<dt>Amount</dt><dd><input type="range" min="0" max="10" field="amount"/></dd>
				<dt>Scale</dt><dd><input type="range" min="0" max="10" field="scale"/></dd>
				<dt>Speed</dt><dd><input type="range" min="0" max="10" field="speed"/></dd>
				<dt>Dist.Amount</dt><dd><input type="range" min="0" max="10" field="distAmount"/></dd>
				<dt></dt><dd><a class="button" href="#">Remove</a></dd>
			</dl>
			</div>
			'),noise);
			e.find("a.button").click(function(_) {
				noise = null;
				ctx.rebuildProperties();
			});
		}
		super.edit(ctx);
	}
	#end

	static var _ = Prefab.register("rfx.genFog", GenFog);

}