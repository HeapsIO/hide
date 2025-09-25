package hrt.prefab.rfx;

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
@:access(h3d.scene.Renderer)
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

	override function makeInstance() : Void {
		super.makeInstance();
		updateInstance();
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
				dlwc.lightColor.scale(mainLight.power * mainLight.power);
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

	override function modulate(t : Float) {
		var c : CloudShadow = cast super.modulate(t);
		c.opacity = this.opacity * t;
		return c;
	}

	override function transition( r1 : h3d.impl.RendererFX, r2 : h3d.impl.RendererFX ) : h3d.impl.RendererFX.RFXTransition {
		var c1 : CloudShadow = cast r1;
		var c2 : CloudShadow = cast r2;

		var c = new CloudShadow(null, null);
		c.opacity = c1.opacity;
		c.scale = c1.scale;
		c.speed = c1.speed;
		c.angle = c1.angle;
		c.texturePath = c1.texturePath;
		c.distort = {
			path : c1.distort.path,
			scale : c1.distort.scale,
			speed : c1.distort.speed,
			angle : c1.distort.angle,
			amount : c1.distort.amount
		}

		return { effect : cast c, setFactor : (f : Float) -> {
			c.opacity = hxd.Math.lerp(c1.opacity, c2.opacity, f);
			c.scale = hxd.Math.lerp(c1.scale, c2.scale, f);
			c.speed = hxd.Math.lerp(c1.speed, c2.speed, f);
			c.angle = hxd.Math.lerp(c1.angle, c2.angle, f);
			c.texturePath = f < 0.5 ? c1.texturePath : c2.texturePath;
			c.distort = {
				path : f < 0.5 ? c1.distort.path : c2.distort.path,
				scale : f < 0.5 ? c1.distort.scale : c2.distort.scale,
				speed : f < 0.5 ? c1.distort.speed : c2.distort.speed,
				angle : f < 0.5 ? c1.distort.angle : c2.distort.angle,
				amount : f < 0.5 ? c1.distort.amount : c2.distort.amount
			}
		} };
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
		'),this, function(pname) {
			ctx.onChange(this,pname);
		});
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