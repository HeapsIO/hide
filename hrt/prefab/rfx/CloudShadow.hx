package hrt.prefab.rfx;

import hxd.res.Loader;

typedef CloudShadowProps = {
	var opacity : Float;
	var scale : Float;
	var speed : Float;
	var angle : Float;
	var texturePath : String;
}

class DirLightWithClouds extends h3d.shader.pbr.Light {

	static var SRC = {

		@param var clouds : Sampler2D;
		@param var scale : Float;
		@param var speed : Vec2;
		@param var opacity : Float;
		@param var rotation : Mat3;

		@param var time : Float;
		@param var cameraPosition : Vec3;

		@param var lightDir : Vec3;

		function fragment() {
			pbrLightDirection = lightDir;
			pbrLightColor = lightColor;
			pbrOcclusionFactor = occlusionFactor;

			var pos = transformedPosition.xy * scale;
			var cloudIntensity = clouds.get(pos + time * speed).r * opacity;
			pbrLightColor *= 1.0 - cloudIntensity.saturate();
		}
	};
}

@:access(h3d.scene.pbr.DirLight)
class CloudShadow extends RendererFX {

	var dlwc = new DirLightWithClouds();

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

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( step == Shadows ) {
			var ctx = r.ctx;
			var props : CloudShadowProps = props;

			var mainLight : h3d.scene.pbr.DirLight = null;
			var l = @:privateAccess ctx.lights;
			while( l != null ) {
				var pbrLight = Std.downcast(l, h3d.scene.pbr.DirLight);
				if( pbrLight != null && pbrLight.isMainLight ) {
					mainLight = pbrLight;
					break;
				}
				l = l.next;
			}
			
			if( mainLight != null ) {
				mainLight.shader = dlwc;
				dlwc.lightDir = mainLight.pbr.lightDir;
				dlwc.lightColor.load(mainLight._color);
				dlwc.lightColor.scale3(mainLight.power * mainLight.power);
				dlwc.occlusionFactor = mainLight.occlusionFactor;
				var angle = props.angle * Math.PI / 180;
				var speed = props.speed / props.scale;
				dlwc.speed.set(Math.cos(angle) * speed, Math.sin(angle) * speed);
				dlwc.scale = 1.0 / props.scale;
				dlwc.opacity = props.opacity;
				dlwc.time = ctx.time;
				if( props.texturePath != null )
					dlwc.clouds = Loader.currentInstance.load(props.texturePath).toTexture();
				if( dlwc.clouds != null ) 
					dlwc.clouds.wrap = Repeat;
			}
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
		'),props);
	}
	#end

	static var _ = Library.register("rfx.cloudShadow", CloudShadow);

}