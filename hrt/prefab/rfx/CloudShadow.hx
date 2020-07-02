package hrt.prefab.rfx;

typedef CloudShadowProps = {
	var opacity : Float;
	var scale : Float;
	var speed : Float;
	var angle : Float;
	var texturePath : String;
}

private class CloudShader extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var clouds : Sampler2D;
		@param var scale : Float;
		@param var speed : Vec2;
		@param var opacity : Float;
		@param var rotation : Mat3;

		@global var global : { time : Float };
		@param var cameraInverse : Mat4;
		@param var cameraPosition : Vec3;

		function getPosition() : Vec2 {
			var uv = uvToScreen(calculatedUV);
			var near = vec4(uv, 0, 1) * cameraInverse;
			var far = vec4(uv, 0.5, 1) * cameraInverse;
			var ray = (far.xyz - near.xyz).normalize();
			return near.xy + ray.xy * near.z;
		}

		function fragment() {
			var pos = getPosition() * scale;
			pixelColor = clouds.get(pos + global.time * speed) * opacity;
		}

	}
}

class CloudShadow extends RendererFX {

	var fx = new h3d.pass.ScreenFx(new CloudShader());
	var texture : h3d.mat.Texture;

	public function new(?parent) {
		super(parent);
		props = ({
			opacity : 1,
			scale : 1,
			speed : 0,
			angle : 0,
			texturePath : null,
		}:CloudShadowProps);
	}

	override function makeInstance( ctx : Context ) : Context {
		ctx = super.makeInstance(ctx);
		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance(ctx:Context, ?propName:Null<String>) {
		var path = (props:CloudShadowProps).texturePath;
		texture = path == null ? h3d.mat.Texture.fromColor(0xFFFFFF) : ctx.loadTexture(path);
		texture.wrap = Repeat;
	}

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( step == Shadows ) {
			var props : CloudShadowProps = props;
			var shadowMap = r.ctx.getGlobal("mainLightShadowMap");
			var shadowCam : h3d.Matrix = r.ctx.getGlobal("mainLightViewProj");
			var shadowCamPos : h3d.Vector = r.ctx.getGlobal("mainLightPos");
			if( shadowMap == null ) return;
			var engine = r.ctx.engine;
			engine.pushTarget(shadowMap);
			shadowCam = shadowCam.clone();
			shadowCam.invert();

			var angle = props.angle * Math.PI / 180;
			var speed = props.speed / props.scale;
			fx.shader.speed.set(Math.cos(angle) * speed, Math.sin(angle) * speed);
			fx.shader.scale = 1 / props.scale;
			fx.shader.opacity = props.opacity;
			fx.shader.clouds = texture;
			fx.shader.cameraInverse = shadowCam;
			fx.shader.cameraPosition = shadowCamPos;
			fx.setGlobals(r.ctx);
			fx.pass.blend(Zero, OneMinusSrcColor);
			fx.render();
			engine.popTarget();
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Cloud">
				<dt>Opacity</dt><dd><input type="range" min="0" max="1" field="opacity"/></dd>
				<dt>Scale</dt><dd><input type="range" min="0" max="50" field="scale"/></dd>
				<dt>Speed</dt><dd><input type="range" min="-1" max="1" field="speed"/></dd>
				<dt>Angle</dt><dd><input type="range" min="-180" max="180" field="angle"/></dd>
				<dt>Texture</dt><dd><input type="texturepath" field="texturePath"/></dd>
			</div>
		'),props, function(n) {
			if( n == "texturePath" ) updateInstance(ctx.getContext(this));
		});
	}
	#end

	static var _ = Library.register("rfx.cloudShadow", CloudShadow);

}