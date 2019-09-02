package hrt.prefab.rfx;

typedef HeightFogProps = {
 	var startHeight : Float;
	var endHeight : Float;
	var startOpacity : Float;
	var endOpacity : Float;

	var startColor : Int;
	var endColor : Int;
	var startColorHeight : Float;
	var endColorHeight : Float;
	var renderMode : String;
}

class HeightFog extends RendererFX {

	var fogPass = new h3d.pass.ScreenFx(new hrt.shader.HeightFog());

	public function new(?parent) {
		super(parent);
		props = ({
			startHeight : 0,
			endHeight : 100,
			startOpacity : 1,
			endOpacity : 0,
		 	startColor : 0xffffff,
	    	endColor : 0xffffff,
			startColorHeight : 0,
			endColorHeight : 100,
			renderMode : "AfterTonemapping",
		} : HeightFogProps);

		fogPass.pass.setBlendMode(Alpha);
	}

	override function apply(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		var p : HeightFogProps = props;
		if( (step == AfterTonemapping && p.renderMode == "AfterTonemapping") || (step == BeforeTonemapping && p.renderMode == "BeforeTonemapping") ) {
			r.mark("HeightFog");
			var ctx = r.ctx;
			var depth : hxsl.ChannelTexture = ctx.getGlobal("depthMap");

			fogPass.shader.startHeight = p.startHeight;
			fogPass.shader.endHeight = p.endHeight;
			fogPass.shader.startOpacity = p.startOpacity;
			fogPass.shader.endOpacity = p.endOpacity;
			fogPass.shader.startColorHeight = p.startColorHeight;
			fogPass.shader.endColorHeight = p.endColorHeight;
			fogPass.shader.startColor = h3d.Vector.fromColor(p.startColor);
			fogPass.shader.endColor = h3d.Vector.fromColor(p.endColor);
			fogPass.shader.depthTextureChannel = depth.channel;
			fogPass.shader.depthTexture = depth.texture;

			fogPass.shader.cameraPos = ctx.camera.pos;
			fogPass.shader.cameraInverseViewProj.load(ctx.camera.getInverseViewProj());

			fogPass.render();
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<dl>
				<div class="group" name="Opacity">
					<dt>Start Height</dt><dd><input type="range" min="0" max="100" field="startHeight"/></dd>
					<dt>End Height</dt><dd><input type="range" min="0" max="100" field="endHeight"/></dd>
					<dt>Start Opacity</dt><dd><input type="range" min="0" max="1" field="startOpacity"/></dd>
					<dt>End Opacity</dt><dd><input type="range" min="0" max="1" field="endOpacity"/></dd>
				</div>
				<div class="group" name="Color">
					<dt>Start Height</dt><dd><input type="range" min="0" max="100" field="startColorHeight"/></dd>
					<dt>End Height</dt><dd><input type="range" min="0" max="100" field="endColorHeight"/></dd>
					<dt>Start Color</dt><dd><input type="color" field="startColor"/></dd>
					<dt>End Color</dt><dd><input type="color" field="endColor"/></dd>
				</div>
				<div class="group" name="Rendering">
					<dt>Render Mode</dt>
						<dd><select field="renderMode">
							<option value="BeforeTonemapping">Before Tonemapping</option>
							<option value="AfterTonemapping">After Tonemapping</option>
						</select></dd>
				</div>

			</dl>
		'),props);
	}
	#end

	static var _ = Library.register("rfx.heightFog", HeightFog);

}