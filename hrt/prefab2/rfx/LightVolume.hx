package hrt.prefab2.rfx;

@:access(h3d.pass.PassList)
@:access(h3d.pass.PassObject)
class LightVolume extends RendererFX {

	var blurPass = new h3d.pass.Blur();
	var ssr : h3d.mat.Texture;

	@:s public var steps : Int = 10;
	@:s public var blurRadius : Float = 1.0;
	@:s public var textureSize : Float = 0.5;

	@:s public var ditheringNoise : String;
	@:s public var ditheringIntensity : Float = 1.0;

	var passes : h3d.pass.PassList;
	override function begin( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
		if( step == BeforeTonemapping ) {

			var passes = r.get("lightVolume");
			var pbrRenderer = Std.downcast(r, h3d.scene.pbr.Renderer);
			if ( pbrRenderer == null )
				return;
			@:privateAccess pbrRenderer.cullPasses(passes, function(col) return col.inFrustum(r.ctx.camera.frustum));

			if ( passes.current == null )
				return;

			r.mark("LightVolume");

			var tex = r.allocTarget("lightVolume", false, textureSize, RGBA16F);
			tex.clear(0);

			var it = passes.current;
			while ( it != null ) {
				var shader = it.pass.getShader(hrt.prefab2.pbr.LightVolume.LightVolumeShader);
				if ( shader != null ) {
					shader.steps = steps;
					shader.targetSize.set(tex.width, tex.height);
					shader.ditheringIntensity = ditheringIntensity;
					shader.ditheringNoise = ditheringNoise != null ? hxd.res.Loader.currentInstance.load(ditheringNoise).toTexture() : h3d.mat.Texture.fromColor(0);
					shader.ditheringNoise.wrap = Repeat;
					shader.USE_DITHERING = ditheringNoise != null;
					shader.ditheringSize.set(shader.ditheringNoise.width, shader.ditheringNoise.height);
				}
				it = it.next;
			}

			r.ctx.engine.pushTarget(tex);
			r.defaultPass.draw(passes);
			r.ctx.engine.popTarget();

			blurPass.radius = blurRadius;
			blurPass.apply(r.ctx, tex);

			h3d.pass.Copy.run(tex, h3d.Engine.getCurrent().getCurrentTarget(), Add);
		}
	}

	#if editor
	override function edit( ctx : hide.prefab2.EditContext ) {
		ctx.properties.add(new hide.Element('
		<div class="group" name="Light volume">
			<dl>
				<dt>Steps</dt><dd><input type="range" min="1" max="255" step="1" field="steps"/></dd>
				<dt>Blur radius</dt><dd><input type="range" min="0" max="5" field="blurRadius"/></dd>
				<dt>Texture size</dt><dd><input type="range" min="0" max="1" field="textureSize"/></dd>
				<dt>Blue noise</dt><dd><input type="texturepath" field="ditheringNoise"/></dd>
				<dt>Dithering intensity</dt><dd><input type="range" min="0" max="1" field="ditheringIntensity"/></dd>
			</dl>
		</div>
		'),this);
	}
	#end

	static var _ = Prefab.register("rfx.lightVolume", LightVolume);

}
