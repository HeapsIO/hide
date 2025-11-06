package hrt.prefab.rfx;

class GenFogFunc extends hrt.shader.PbrShader {
	static var SRC = {

		var fogParams : {
			var startDistance : Float;
			var distanceScale : Float;
			var distanceOpacity : Float;
			var cameraDistance : Float;

			var startHeight : Float;
			var heightScale : Float;
			var heightOpacity : Float;

			var startColor : Vec4;
			var endColor : Vec4;

			var usePosition : Bool;
			var position : Vec3;

			var useNoise : Bool;
			var noiseScale : Float;
			var noiseSpeed : Float;
			var noiseAmount : Vec3;

			var lightDirection : Vec3;
			var lightColor : Vec3;
			var dotThreshold : Float;
		}

		function applyNoise(origin : Vec3, sampler : Sampler2D) : Vec3 {
			var noise = sampler.get( origin.xy * fogParams.noiseScale + vec2(global.time * fogParams.noiseSpeed, fogParams.noiseScale * origin.z) * vec2(1,-1) );
			return origin + (noise.rgb - 0.5) * fogParams.noiseAmount;
		}

		function applyDistanceOpacity(amount : Float, origin : Vec3) : Float {
			if( fogParams.distanceOpacity != 0 ) {
				var distance = (origin - (fogParams.usePosition ? fogParams.position : camera.position)).length() - fogParams.cameraDistance;
				amount += smoothstep(0.0, 1.0, (distance - fogParams.startDistance) * fogParams.distanceScale) * fogParams.distanceOpacity;
			}
			return amount;
		}

		function applyHeightOpacity(amount : Float, origin : Vec3) : Float {
			if( fogParams.heightOpacity != 0 ) {
				var height = origin.z;
				if( fogParams.usePosition ) height -= fogParams.position.z;
				amount += smoothstep(0.0, 1.0, (height - fogParams.startHeight) * fogParams.heightScale) * fogParams.heightOpacity;
			}
			return amount;
		}

		function getFogColor(amount : Float, origin : Vec3) : Vec4 {
			var fogColor = mix(fogParams.startColor, fogParams.endColor, smoothstep(0.0, 1.0, amount));
			fogColor.rgb += smoothstep(0.0, 1.0, ((camera.position - origin).normalize().dot(fogParams.lightDirection) - fogParams.dotThreshold) / (1.0 - fogParams.dotThreshold)) * fogParams.lightColor;
			return fogColor;
		}
	}
}

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

		@:import GenFogFunc;

		function initFogParams() {
			fogParams.startDistance = startDistance;
			fogParams.distanceScale = distanceScale;
			fogParams.distanceOpacity = distanceOpacity;
			fogParams.cameraDistance = cameraDistance;
			fogParams.startHeight = startHeight;
			fogParams.heightScale = heightScale;
			fogParams.heightOpacity = heightOpacity;
			fogParams.startColor = startColor;
			fogParams.endColor = endColor;
			fogParams.usePosition = usePosition;
			fogParams.position = position;
			fogParams.noiseScale = noiseScale;
			fogParams.noiseSpeed = noiseSpeed;
			fogParams.noiseAmount = noiseAmount;
			fogParams.lightDirection = lightDirection;
			fogParams.lightColor = lightColor;
			fogParams.dotThreshold = dotThreshold;
		}

		function fragment() {
			initFogParams();

			var origin = getPosition();
			var amount = 0.;

			if (useNoise)
				origin = applyNoise(origin, noiseTex);
			amount = applyDistanceOpacity(amount, origin);
			amount = applyHeightOpacity(amount, origin);
			var fogColor = getFogColor(amount, origin);
			pixelColor = mix(pixelColor, fogColor, intensity);
		}

	};

	public function new() {
		super();
	}
}

class GenFogBlendShader extends hrt.shader.PbrShader {

	static var SRC = {
		@param var blendFactor : Float;

		@param var cameraDistance : Float;

		@param var intensity1 : Float;
		@param var startDistance1 : Float;
		@param var distanceScale1 : Float;
		@param var distanceOpacity1 : Float;
		@param var startHeight1 : Float;
		@param var heightScale1 : Float;
		@param var heightOpacity1 : Float;
		@param var startColor1 : Vec4;
		@param var endColor1 : Vec4;
		@const var usePosition1 : Bool;
		@param var position1 : Vec3;
		@const var useNoise1 : Bool;
		@param var noiseTex1 : Sampler2D;
		@param var noiseScale1 : Float;
		@param var noiseSpeed1 : Float;
		@param var noiseAmount1 : Vec3;
		@param var lightDirection1 : Vec3;
		@param var lightColor1 : Vec3;
		@param var dotThreshold1 : Float;

		@param var intensity2 : Float;
		@param var startDistance2 : Float;
		@param var distanceScale2 : Float;
		@param var distanceOpacity2 : Float;
		@param var startHeight2 : Float;
		@param var heightScale2 : Float;
		@param var heightOpacity2 : Float;
		@param var startColor2 : Vec4;
		@param var endColor2 : Vec4;
		@const var usePosition2 : Bool;
		@param var position2 : Vec3;
		@const var useNoise2 : Bool;
		@param var noiseTex2 : Sampler2D;
		@param var noiseScale2 : Float;
		@param var noiseSpeed2 : Float;
		@param var noiseAmount2 : Vec3;
		@param var lightDirection2 : Vec3;
		@param var lightColor2 : Vec3;
		@param var dotThreshold2 : Float;

		@:import GenFogFunc;

		function initFogParams1() {
			fogParams.startDistance = startDistance1;
			fogParams.distanceScale = distanceScale1;
			fogParams.distanceOpacity = distanceOpacity1;
			fogParams.cameraDistance = cameraDistance;
			fogParams.startHeight = startHeight1;
			fogParams.heightScale = heightScale1;
			fogParams.heightOpacity = heightOpacity1;
			fogParams.startColor = startColor1;
			fogParams.endColor = endColor1;
			fogParams.usePosition = usePosition1;
			fogParams.position = position1;
			fogParams.noiseScale = noiseScale1;
			fogParams.noiseSpeed = noiseSpeed1;
			fogParams.noiseAmount = noiseAmount1;
			fogParams.lightDirection = lightDirection1;
			fogParams.lightColor = lightColor1;
			fogParams.dotThreshold = dotThreshold1;
		}

		function initFogParams2() {
			fogParams.startDistance = startDistance2;
			fogParams.distanceScale = distanceScale2;
			fogParams.distanceOpacity = distanceOpacity2;
			fogParams.cameraDistance = cameraDistance;
			fogParams.startHeight = startHeight2;
			fogParams.heightScale = heightScale2;
			fogParams.heightOpacity = heightOpacity2;
			fogParams.startColor = startColor2;
			fogParams.endColor = endColor2;
			fogParams.usePosition = usePosition2;
			fogParams.position = position2;
			fogParams.noiseScale = noiseScale2;
			fogParams.noiseSpeed = noiseSpeed2;
			fogParams.noiseAmount = noiseAmount2;
			fogParams.lightDirection = lightDirection2;
			fogParams.lightColor = lightColor2;
			fogParams.dotThreshold = dotThreshold2;
		}

		function fragment() {
			initFogParams1();
			var origin = getPosition();
			var amount = 0.;
			if (useNoise1)
				origin = applyNoise(origin, noiseTex1);
			amount = applyDistanceOpacity(amount, origin);
			amount = applyHeightOpacity(amount, origin);
			var fogColor1 = getFogColor(amount, origin);

			initFogParams2();
			origin = getPosition();
			amount = 0.;
			if (useNoise2)
				origin = applyNoise(origin, noiseTex2);
			amount = applyDistanceOpacity(amount, origin);
			amount = applyHeightOpacity(amount, origin);
			var fogColor2 = getFogColor(amount, origin);

			pixelColor = mix(fogColor1, fogColor2, blendFactor);
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

	var isBlend : Bool;
	var fogPass : h3d.pass.ScreenFx<GenFogShader> = null;
	var fogPassBlend : h3d.pass.ScreenFx<GenFogBlendShader> = null;

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

		initShader();
	}

	function initShader(blend : Bool = false) {
		if (blend) {
			fogPass?.dispose();
			fogPass = null;

			fogPassBlend = new h3d.pass.ScreenFx(new GenFogBlendShader());
			fogPassBlend.pass.setBlendMode(Alpha);

		}
		else {
			fogPassBlend?.dispose();
			fogPassBlend = null;

			fogPass = new h3d.pass.ScreenFx(new GenFogShader());
			fogPass.pass.setBlendMode(Alpha);
		}

		isBlend = blend;
	}

	function checkPass(step : h3d.impl.RendererFX.Step) {
		return (step == AfterTonemapping && renderMode == AfterTonemapping) || (step == BeforeTonemapping && renderMode == BeforeTonemapping) || (step == Lighting && renderMode == Lighting);
	}

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( !checkEnabled() ) return;
		if( checkPass(step) ) {
			r.mark("DistanceFog");
			var ctx = r.ctx;
			if (isBlend) {
				fogPassBlend.shader.cameraDistance = distanceFixed ? r.ctx.camera.pos.sub(r.ctx.camera.target).length() : 0;
				var ls = r.getLightSystem().shadowLight;
				if( ls == null ) {
					fogPassBlend.shader.lightDirection1.set(0,0,0);
					fogPassBlend.shader.lightDirection2.set(0,0,0);
				}
				else {
					var d = @:privateAccess ls.getShadowDirection();
					fogPassBlend.shader.lightDirection1.load(d);
					fogPassBlend.shader.lightDirection2.load(d);
				}
				fogPassBlend.render();
			}
			else {
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
		@:privateAccess g.initShader(true);

		g.fogPassBlend.shader.intensity1 = g1.intensity;
		g.fogPassBlend.shader.startDistance1 = g1.startDistance;
		g.fogPassBlend.shader.distanceScale1 = 1 / (g1.endDistance - g1.startDistance);
		g.fogPassBlend.shader.distanceOpacity1 = g1.distanceOpacity;
		g.fogPassBlend.shader.startHeight1 = g1.startHeight;
		g.fogPassBlend.shader.heightScale1 = 1 / (g1.endHeight - g1.startHeight);
		g.fogPassBlend.shader.heightOpacity1 = g1.heightOpacity;
		g.fogPassBlend.shader.startColor1.setColor(g1.startColor);
		g.fogPassBlend.shader.endColor1.setColor(g1.endColor);
		g.fogPassBlend.shader.startColor1.a = g1.startOpacity;
		g.fogPassBlend.shader.endColor1.a = g1.endOpacity;
		g.fogPassBlend.shader.position1.set(g1.posX, g1.posY, g1.posZ);
		g.fogPassBlend.shader.usePosition1 = g1.usePosition;
		g.fogPassBlend.shader.useNoise1 = g1.noise != null && g1.noise.texture != null;
		if( g1.noise != null && g1.noise.texture != null ) {
			g.fogPassBlend.shader.noiseTex1 = hxd.res.Loader.currentInstance.load(g1.noise.texture).toTexture();
			g.fogPassBlend.shader.noiseTex1.wrap = Repeat;
			g.fogPassBlend.shader.noiseScale1 = 1 / g1.noise.scale;
			g.fogPassBlend.shader.noiseSpeed1 = g1.noise.speed / g1.noise.scale;
			g.fogPassBlend.shader.noiseAmount1.set(g1.noise.amount * g1.noise.distAmount, g1.noise.amount * g1.noise.distAmount, g1.noise.amount);
		}
		g.fogPassBlend.shader.lightColor1.setColor(g1.lightColor);
		g.fogPassBlend.shader.lightColor1.scale(g1.lightColorAmount);
		g.fogPassBlend.shader.dotThreshold1 = hxd.Math.cos(g1.lightAngle * Math.PI/180);


		g.fogPassBlend.shader.intensity2 = g2.intensity;
		g.fogPassBlend.shader.startDistance2 = g2.startDistance;
		g.fogPassBlend.shader.distanceScale2 = 1 / (g2.endDistance - g2.startDistance);
		g.fogPassBlend.shader.distanceOpacity2 = g2.distanceOpacity;
		g.fogPassBlend.shader.startHeight2 = g2.startHeight;
		g.fogPassBlend.shader.heightScale2 = 1 / (g2.endHeight - g2.startHeight);
		g.fogPassBlend.shader.heightOpacity2 = g2.heightOpacity;
		g.fogPassBlend.shader.startColor2.setColor(g2.startColor);
		g.fogPassBlend.shader.endColor2.setColor(g2.endColor);
		g.fogPassBlend.shader.startColor2.a = g2.startOpacity;
		g.fogPassBlend.shader.endColor2.a = g2.endOpacity;
		g.fogPassBlend.shader.position2.set(g2.posX, g2.posY, g2.posZ);
		g.fogPassBlend.shader.usePosition2 = g2.usePosition;
		g.fogPassBlend.shader.useNoise2 = g2.noise != null && g2.noise.texture != null;
		if( g2.noise != null && g2.noise.texture != null ) {
			g.fogPassBlend.shader.noiseTex2 = hxd.res.Loader.currentInstance.load(g2.noise.texture).toTexture();
			g.fogPassBlend.shader.noiseTex2.wrap = Repeat;
			g.fogPassBlend.shader.noiseScale2 = 1 / g2.noise.scale;
			g.fogPassBlend.shader.noiseSpeed2 = g2.noise.speed / g1.noise.scale;
			g.fogPassBlend.shader.noiseAmount2.set(g2.noise.amount * g2.noise.distAmount, g2.noise.amount * g2.noise.distAmount, g2.noise.amount);
		}
		g.fogPassBlend.shader.lightColor2.setColor(g2.lightColor);
		g.fogPassBlend.shader.lightColor2.scale(g2.lightColorAmount);
		g.fogPassBlend.shader.dotThreshold2 = hxd.Math.cos(g2.lightAngle * Math.PI/180);

		return { effect : cast g, setFactor : (f : Float) -> {
			g.fogPassBlend.shader.blendFactor = f;
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

	override function edit2(ctx : hrt.prefab.EditContext2) {
		super.edit2(ctx);

		ctx.build(
			<root>
				<category("General")>
					<range(0, 1) field={intensity}/>
				</category>
				<category("Distance")>
					<range(0, 100) field={startDistance}/>
					<range(0, 100) field={endDistance}/>
					<range(0, 100) field={distanceOpacity}/>
					<checkbox label="Camera Independant" field={distanceFixed}/>
				</category>
				<category("Height")>
					<range(0, 100) field={startHeight}/>
					<range(0, 100) field={endHeight}/>
					<range(0, 2) field={heightOpacity}/>
				</category>
				<category("Center")>
					<checkbox label="Use Center Point" field={usePosition}/>
					<line label="Center">
						<slider label="X" field={posX}/>
						<slider label="Y" field={posY}/>
						<slider label="Z" field={posZ}/>
					</line>
				</category>
				<category("Color")>
					<color  field={startColor}/>
					<color  field={endColor}/>
					<range(0, 1) field={startOpacity}/>
					<range(0, 1) field={endOpacity}/>
				</category>
				<category("Light")>
					<color  field={lightColor}/>
					<range(0, 1) field={lightColorAmount}/>
					<range(0, 180) field={lightAngle} wrap/>
				</category>
				<category("Rendering")>
					<select(["Lighting", "BeforeTonemapping", "AfterTonemapping"]) field={renderMode}/>
				</category>
				<category("Noise")>
					<button("Add") id="btnAddNoise" if (noise == null)/>
					<block if (noise != null)>
						<file type="texturepath" field={noise.texture}/>
						<range(0, 10) field={noise.amount}/>
						<range(0, 10) field={noise.scale}/>
						<range(0, 10) field={noise.speed}/>
						<range(0, 10) field={noise.distAmount}/>
						<button("Remove") id="btnRemoveNoise"/>
					</block>
				</category>
			</root>
		);

		if (btnAddNoise != null) {
			btnAddNoise.onClick = () -> {
				this.noise = {
					texture : null,
					amount : 1,
					scale : 1,
					speed : 1,
					distAmount : 0.5,
				};
				ctx.rebuildInspector();
			}
		}

		if (btnRemoveNoise != null) {
			btnRemoveNoise.onClick = () -> {
				this.noise = null;
				ctx.rebuildInspector();
			}
		}
	}
	#end

	static var _ = Prefab.register("rfx.genFog", GenFog);

}