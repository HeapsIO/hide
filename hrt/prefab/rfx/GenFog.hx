package hrt.prefab.rfx;

class GenFogShader extends PbrShader {

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

		function fragment() {
			var origin = getPosition();
			var amount = 0.;

			if( distanceScale != 0 ) {
				var distance = (origin - (usePosition ? position : camera.position)).length() - cameraDistance;
				amount += clamp((distance - startDistance) * distanceScale, 0, 1) * distanceOpacity;
			}

			if( heightScale != 0 ) {
				var height = origin.z;
				if( usePosition ) height -= position.z;
				amount += clamp((height - startHeight) * heightScale, 0, 1) * heightOpacity;
			}

			var fogColor = mix(startColor, endColor, clamp(amount,0,1));
			pixelColor = fogColor;
		}

	};

	public function new() {
		super();
	}

}

typedef GenFogProps = {
 	var startDistance : Float;
	var endDistance : Float;
	var distanceOpacity : Float;
	var distanceFixed : Bool;

	var startHeight : Float;
	var endHeight : Float;
	var heightOpacity : Float;

	var startOpacity : Float;
	var endOpacity : Float;

	var startColor : Int;
	var endColor : Int;
	var renderMode : String;

	var posX : Float;
	var posY : Float;
	var posZ : Float;
	var usePosition : Bool;
}

class GenFog extends RendererFX {

	var fogPass = new h3d.pass.ScreenFx(new GenFogShader());

	public function new(?parent) {
		super(parent);
		props = ({
			startDistance : 0,
			endDistance : 100,
			distanceOpacity : 0,
			distanceFixed : false,

			startHeight : 100,
			endHeight : 0,
			heightOpacity : 0,

			posX : 0,
			posY : 0,
			posZ : 0,
			usePosition : false,

			startOpacity : 0,
			endOpacity : 1,
		 	startColor : 0xffffff,
	    	endColor : 0xffffff,
			renderMode : "AfterTonemapping",
		} : GenFogProps);

		fogPass.pass.setBlendMode(Alpha);
	}

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		var p : GenFogProps = props;
		if( (step == AfterTonemapping && p.renderMode == "AfterTonemapping") || (step == BeforeTonemapping && p.renderMode == "BeforeTonemapping") ) {
			r.mark("DistanceFog");
			var ctx = r.ctx;

			fogPass.shader.startDistance = p.startDistance;
			fogPass.shader.distanceScale = 1 / (p.endDistance - p.startDistance);
			fogPass.shader.distanceOpacity = p.distanceOpacity;
			fogPass.shader.cameraDistance = p.distanceFixed ? r.ctx.camera.pos.sub(r.ctx.camera.target).length() : 0;

			fogPass.shader.startHeight = p.startHeight;
			fogPass.shader.heightScale = 1 / (p.endHeight - p.startHeight);
			fogPass.shader.heightOpacity = p.heightOpacity;

			fogPass.shader.startColor.setColor(p.startColor);
			fogPass.shader.endColor.setColor(p.endColor);
			fogPass.shader.startColor.a = p.startOpacity;
			fogPass.shader.endColor.a = p.endOpacity;

			fogPass.shader.position.set(p.posX, p.posY, p.posZ);
			fogPass.shader.usePosition = p.usePosition;


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

	static var _ = Library.register("rfx.genFog", GenFog);

}