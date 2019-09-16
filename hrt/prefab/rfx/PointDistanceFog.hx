package hrt.prefab.rfx;

typedef PointDistanceFogProps = {
 	var startDistance : Float;
	var endDistance : Float;
	var startOpacity : Float;
	var endOpacity : Float;

	var startHeight : Float;
	var endHeight : Float;
	var startHeightOpacity : Float;
	var endHeightOpacity : Float;

	var startColor : Int;
	var endColor : Int;
	var startColorDistance : Float;
	var endColorDistance : Float;
	var renderMode : String;
	var pointPosition : Dynamic;
}

class PointDistanceFog extends RendererFX {

	var fogPass = new h3d.pass.ScreenFx(new hrt.shader.PointDistanceFog());
	public var pointPosition : h3d.Vector;

	public function new(?parent) {
		super(parent);
		props = ({
			startDistance : 0,
			endDistance : 100,
			startOpacity : 0,
			endOpacity : 1,
			startHeight : 0,
			endHeight : 100,
			startHeightOpacity : 1,
			endHeightOpacity : 0,
		 	startColor : 0xffffff,
	    	endColor : 0xffffff,
			startColorDistance : 0,
			endColorDistance : 100,
			renderMode : "AfterTonemapping",
			pointPosition : new h3d.Vector(0,0,0),
		} : PointDistanceFogProps);

		fogPass.pass.setBlendMode(Alpha);
	}

	override function apply(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		var p : PointDistanceFogProps = props;
		if( (step == AfterTonemapping && p.renderMode == "AfterTonemapping") || (step == BeforeTonemapping && p.renderMode == "BeforeTonemapping") ) {
			r.mark("PointDistanceFog");
			var ctx = r.ctx;
			var depth : hxsl.ChannelTexture = ctx.getGlobal("depthMap");

			fogPass.shader.startDistance = p.startDistance;
			fogPass.shader.endDistance = p.endDistance;
			fogPass.shader.startOpacity = p.startOpacity;
			fogPass.shader.endOpacity = p.endOpacity;

			fogPass.shader.startHeight = p.startHeight;
			fogPass.shader.endHeight = p.endHeight;
			fogPass.shader.startHeightOpacity = p.startHeightOpacity;
			fogPass.shader.endHeightOpacity = p.endHeightOpacity;

			fogPass.shader.startColorDistance = p.startColorDistance;
			fogPass.shader.endColorDistance = p.endColorDistance;
			fogPass.shader.startColor = h3d.Vector.fromColor(p.startColor);
			fogPass.shader.endColor = h3d.Vector.fromColor(p.endColor);
			fogPass.shader.depthTextureChannel = depth.channel;
			fogPass.shader.depthTexture = depth.texture;

			if( pointPosition != null )
				fogPass.shader.pointPosition.load(pointPosition);
			else
				fogPass.shader.pointPosition.set(p.pointPosition.x, p.pointPosition.y, p.pointPosition.z);

			fogPass.shader.cameraPos = ctx.camera.pos;
			fogPass.shader.cameraInverseViewProj.load(ctx.camera.getInverseViewProj());

			fogPass.render();
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<dl>
				<div class="group" name="Point Position">
					<dt>X</dt><dd><input type="range" min="0" max="10" field="pointPosition.x"/></dd>
					<dt>Y</dt><dd><input type="range" min="0" max="10" field="pointPosition.y"/></dd>
					<dt>Z</dt><dd><input type="range" min="0" max="10" field="pointPosition.z"/></dd>
				</div>
				<div class="group" name="Opacity">
					<dt>Start Distance</dt><dd><input type="range" min="0" max="100" field="startDistance"/></dd>
					<dt>End Distance</dt><dd><input type="range" min="0" max="100" field="endDistance"/></dd>
					<dt>Start Opacity</dt><dd><input type="range" min="0" max="1" field="startOpacity"/></dd>
					<dt>End Opacity</dt><dd><input type="range" min="0" max="1" field="endOpacity"/></dd>
				</div>
				<div class="group" name="Height Opacity">
					<dt>Start Height</dt><dd><input type="range" min="0" max="100" field="startHeight"/></dd>
					<dt>End Height</dt><dd><input type="range" min="0" max="100" field="endHeight"/></dd>
					<dt>Start Opacity</dt><dd><input type="range" min="0" max="1" field="startHeightOpacity"/></dd>
					<dt>End Opacity</dt><dd><input type="range" min="0" max="1" field="endHeightOpacity"/></dd>
				</div>
				<div class="group" name="Color">
					<dt>Start Distance</dt><dd><input type="range" min="0" max="100" field="startColorDistance"/></dd>
					<dt>End Distance</dt><dd><input type="range" min="0" max="100" field="endColorDistance"/></dd>
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

	static var _ = Library.register("rfx.PointDistanceFog", PointDistanceFog);

}