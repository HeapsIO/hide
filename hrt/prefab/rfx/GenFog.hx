package hrt.prefab.rfx;

class GenFogShader extends hrt.shader.PbrShader {

	static var SRC = {

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
			pixelColor = fogColor;
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
	var BeforeTonemapping;
	var AfterTonemapping;
}

class GenFog extends RendererFX {

	var fogPass = new h3d.pass.ScreenFx(new GenFogShader());

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

	public function new(?parent) {
		super(parent);
		renderMode = AfterTonemapping;
		endDistance = 100;
		startHeight = 100;
		endOpacity = 1;
		startColor = 0xffffff;
	    endColor = 0xffffff;
		fogPass.pass.setBlendMode(Alpha);
	}

	function checkPass(step : h3d.impl.RendererFX.Step) {
		return (step == AfterTonemapping && renderMode == AfterTonemapping) || (step == BeforeTonemapping && renderMode == BeforeTonemapping);
	}

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( !checkEnabled() ) return;
		if( checkPass(step) ) {
			r.mark("DistanceFog");
			var ctx = r.ctx;

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
			fogPass.shader.lightColor.scale3(lightColorAmount);
			fogPass.shader.dotThreshold = hxd.Math.cos(lightAngle * Math.PI/180);

			fogPass.setGlobals(ctx);
			fogPass.render();
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<dl>
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
							<option value="BeforeTonemapping">Before Tonemapping</option>
							<option value="AfterTonemapping">After Tonemapping</option>
						</select></dd>
				</div>

			</dl>
		'),this);
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

	static var _ = Library.register("rfx.genFog", GenFog);

}