package hrt.prefab2.rfx;

import hxd.res.Loader;

class DirLightWithClouds extends h3d.shader.pbr.Light {

	static var SRC = {

		@param var clouds : Sampler2D;
		@param var scale : Float;
		@param var speed : Vec2;
		@param var opacity : Float;
		@param var rotation : Mat3;

		@const var hasDistort : Bool;
		@param var distort : Sampler2D;
		@param var distortSpeed : Vec2;
		@param var distortScale : Float;
		@param var distortAmount : Float;

		@param var time : Float;
		@param var cameraPosition : Vec3;

		@param var lightDir : Vec3;

		function fragment() {
			pbrLightDirection = lightDir;
			pbrLightColor = lightColor;
			pbrOcclusionFactor = occlusionFactor;

			var pos = transformedPosition.xy * scale;
			var uv = pos + time * speed;
			if( hasDistort )
				uv += (distort.get(pos * distortScale + time * distortSpeed).xy - 0.5) * distortAmount;
			var cloudIntensity = clouds.get(uv).r * opacity;
			pbrLightColor *= 1.0 - cloudIntensity.saturate();
		}
	};
}

@:access(h3d.scene.pbr.DirLight)
class CloudShadow extends RendererFX {

	var dlwc = new DirLightWithClouds();

	@:s public var opacity : Float = 1;
	@:s public var scale : Float = 1;
	@:s public var speed : Float;
	@:s public var angle : Float;
	@:s public var texturePath : String;
	@:s public var distort : {
		var path : String;
		var scale : Float;
		var speed : Float;
		var angle : Float;
		var amount : Float;
	};

	override function makeInstance( ctx : Context ) : Context {
		ctx = super.makeInstance(ctx);
		updateInstance(ctx);
		return ctx;
	}

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( step == Shadows ) {
			var ctx = r.ctx;

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
				var angle = angle * Math.PI / 180;
				var speed = speed / scale;
				dlwc.speed.set(Math.cos(angle) * speed, Math.sin(angle) * speed);
				dlwc.scale = 1.0 / scale;
				dlwc.opacity = opacity;
				dlwc.time = ctx.time;
				if( texturePath != null )
					dlwc.clouds = Loader.currentInstance.load(texturePath).toTexture();
				if( dlwc.clouds != null )
					dlwc.clouds.wrap = Repeat;
				var dist = distort;
				dlwc.hasDistort = dist != null;
				if( dist != null ) {
					var angle = dist.angle * Math.PI / 180;
					dlwc.distort = Loader.currentInstance.load(dist.path).toTexture();
					if( dlwc.distort != null ) dlwc.distort.wrap = Repeat;
					dlwc.distortAmount = dist.amount * 0.01;
					dlwc.distortSpeed.set(Math.cos(angle) * dist.speed * 0.1, Math.sin(angle) * dist.speed * 0.1);
					dlwc.distortScale = dist.scale;
				}
			}
		}
	}

	#if editor
	override function edit( ctx : hide.prefab2.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Cloud">
				<dt>Opacity</dt><dd><input type="range" min="0" max="1" field="opacity"/></dd>
				<dt>Scale</dt><dd><input type="range" min="0" max="50" field="scale"/></dd>
				<dt>Speed</dt><dd><input type="range" min="-1" max="1" field="speed"/></dd>
				<dt>Angle</dt><dd><input type="range" min="-180" max="180" field="angle"/></dd>
				<dt>Texture</dt><dd><input type="texturepath" field="texturePath"/></dd>
			</div>
		'),this);
		var dist = distort;
		if( dist == null )
			dist = {
				path : null,
				scale : 1,
				speed : 0,
				angle : 0,
				amount : 1,
			};
		ctx.properties.add(new hide.Element('
			<div class="group" name="Distort">
				<dt>Texture</dt><dd><input type="texturepath" field="path"/></dd>
				<dt>Amount</dt><dd><input type="range" min="0" max="1" field="amount"/></dd>
				<dt>Scale</dt><dd><input type="range" min="0.1" max="2" field="scale"/></dd>
				<dt>Speed</dt><dd><input type="range" min="-1" max="1" field="speed"/></dd>
				<dt>Angle</dt><dd><input type="range" min="-180" max="180" field="angle"/></dd>
			</div>
		'),dist, function(name) {
			if( name == "path" ) {
				if( dist.path == null )
					distort = js.Lib.undefined;
				else
					distort = dist;
			}
		});
	}
	#end

	static var _ = Prefab.register("rfx.cloudShadow", CloudShadow);

}