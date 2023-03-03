package hrt.prefab.pbr;

class LightVolumeShader extends hxsl.Shader {

	static var SRC = {

		@global var depthMap : Channel;

		@global var camera : {
			var position : Vec3;
			var viewProj : Mat4;
			var inverseViewProj : Mat4;
		};

		@param var ditheringNoise : Sampler2D;
		@param var ditheringIntensity : Float;
		@param var targetSize : Vec2;
		@param var ditheringSize : Vec2;
		@const var USE_DITHERING : Bool;

		@param var lightPos : Vec3;
		@param var lightColor : Vec3;
		@param var opacity : Float;
		@param var range : Float;
		@param var fallOff : Float;
		@const var steps : Int = 10;

		@const var HAS_SHADOW : Bool;

		var transformedPosition : Vec3;
		var projectedPosition : Vec4;
		var pixelColor : Vec4;

		function raymarch(pos : Vec3, distToCam : Float) : Float {
			return 1.0;
		}

		function fragment() {
			var screenPos = projectedPosition.xy / projectedPosition.w;
			var screenUV = screenToUv(screenPos);
			var depth = depthMap.get(screenUV).r;
			var ruv = vec4( screenPos, depth, 1 );
			var ppos = ruv * camera.inverseViewProj;
			var posWS = ppos.xyz / ppos.w;
			var distToCam = length(posWS - camera.position);

			var origin = transformedPosition;
			var rayDir = normalize(camera.position - origin);
			var step = rayDir * 2.0 * range / float(steps);
			if ( USE_DITHERING ) {
				var dithering = ditheringNoise.getLod(screenUV * targetSize / ditheringSize, 0.0).r;
				dithering *= ditheringIntensity;
				origin += dithering * step;
			}

			var fog = 0.0;
			var curPos = origin;
			for ( i in 1...steps ) {
				curPos += step;
				fog += raymarch(curPos, distToCam) / float(steps);
			}
			fog *= smoothstep(0.0, 1.0, distance(camera.position, lightPos) / range);

			pixelColor = vec4(lightColor, fog * opacity);
		}
	};
}

class PointLightVolumeShader extends LightVolumeShader {

	static var SRC = {

		@param var shadowMap : SamplerCube;

		function raymarch(pos : Vec3, distToCam : Float) : Float {
			var posToLight = pos - lightPos;
			var dir = normalize(posToLight);
			var zMax = length(posToLight);
			var d = pow(1.0 - saturate(zMax / range), fallOff);
			if ( distToCam < length(pos - camera.position) )
				d = 0.0;

			if ( HAS_SHADOW ) {
				var depth = shadowMap.getLod(dir, 0).r * range;
				var shadow = zMax > depth ? 0 : 1;
				d *= shadow;
			}
			return d;
		}
	};
}

class SpotLightVolumeShader extends LightVolumeShader {

	static var SRC = {
		@param var shadowMap : Sampler2D;
		@param var shadowProj : Mat4;
		@param var angleFalloff : Float;
		@param var angle : Float;
		@param var lightDir : Vec3;

		function raymarch(pos : Vec3, distToCam : Float) : Float {
			var posToLight = pos - lightPos;
			var zMax = length(posToLight);
			var d = pow(1.0 - saturate(zMax / range), fallOff);
			var dir = normalize(posToLight);
			var theta = dot(dir, lightDir);
			var epsilon = angleFalloff - angle;
			var angleFalloff = saturate((theta - angle) / epsilon);
			d *= angleFalloff;
			if ( distToCam < length(pos - camera.position) )
				d = 0.0;

			if ( HAS_SHADOW ) {
				var shadowPos = vec4(pos, 1.0) * shadowProj;
				shadowPos.xyz = shadowPos.xyz / shadowPos.w;
				var shadowUv = screenToUv(shadowPos.xy);
				var depth = shadowMap.get(shadowUv.xy).r;
				var shadow = shadowPos.z > depth ? 0 : 1;
				d *= shadow;
			}
			return d;
		}
	};
}

class LightVolumeObject extends h3d.scene.Mesh {
	public var USE_SHADOW_MAP : Bool;
	public var shader : LightVolumeShader;

	override function sync(ctx : h3d.scene.RenderContext) {
		super.sync(ctx);

		shader.lightPos = this.getAbsPos().getPosition();

		var pointLight = Std.downcast(parent, h3d.scene.pbr.PointLight);
		if ( pointLight != null ) {
			var shader : PointLightVolumeShader = cast shader;
			shader.range = pointLight.range;
			shader.HAS_SHADOW = USE_SHADOW_MAP && pointLight.shadows != null && pointLight.shadows.enabled && pointLight.shadows.mode != None;
			if ( shader.HAS_SHADOW ) {
				shader.shadowMap = pointLight.shadows.getShadowTex();
			}
			shader.lightColor = pointLight.color;
		} else {
			var spotLight = Std.downcast(parent, h3d.scene.pbr.SpotLight);
			if ( spotLight != null) {
				var shader : SpotLightVolumeShader = cast shader;
				var spotShader = @:privateAccess spotLight.pbr;
				shader.range = spotLight.range;
				shader.angleFalloff = spotShader.fallOff;
				shader.angle = spotShader.angle;
				shader.lightDir.load(spotShader.spotDir);
				shader.HAS_SHADOW = USE_SHADOW_MAP && spotLight.shadows != null && spotLight.shadows.enabled && spotLight.shadows.mode != None;
				if ( shader.HAS_SHADOW ) {
					shader.shadowMap = spotLight.shadows.getShadowTex();
					shader.shadowProj.load(spotLight.shadows.getShadowProj());
				}
				shader.lightColor = spotLight.color;
			}
		}
	}
}

class LightVolume extends hrt.prefab.Prefab {

	@:s var fallOff : Float = 1.0;
	@:s var opacity : Float = 1.0;
	@:s var USE_SHADOW_MAP : Bool = false;

	override function makeInstance(ctx : hrt.prefab.Context ) : hrt.prefab.Context {
		ctx = ctx.clone(this);

		var pbrLight = Std.downcast(ctx.local3d, h3d.scene.pbr.Light);
		if ( pbrLight == null )
			return ctx;

		var mesh = new LightVolumeObject(@:privateAccess pbrLight.primitive, ctx.local3d);
		var pointLight = Std.downcast(ctx.local3d, h3d.scene.pbr.PointLight);
		if ( pointLight != null ) {
			var shader = new PointLightVolumeShader();
			mesh.shader = shader;
			mesh.material.mainPass.addShader(shader);
		} else {
			var spotLight = Std.downcast(ctx.local3d, h3d.scene.pbr.SpotLight);
			if ( spotLight != null ) {
				var shader = new SpotLightVolumeShader();
				mesh.shader = shader;
				mesh.material.mainPass.addShader(shader);
			}
		}
		ctx.local3d = mesh;
		mesh.material.shadows = false;
		mesh.material.mainPass.setBlendMode(Add);
		mesh.material.mainPass.depthTest = Always;
		mesh.material.mainPass.culling = Front;
		mesh.material.mainPass.depthWrite = false;
		mesh.material.mainPass.setPassName("lightVolume");
		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance(ctx : hrt.prefab.Context, ?propName : String) {
		super.updateInstance(ctx, propName);
		var lvo = Std.downcast(ctx.local3d, LightVolumeObject);
		lvo.USE_SHADOW_MAP = USE_SHADOW_MAP;
		lvo.shader.fallOff = fallOff;
		lvo.shader.opacity = opacity;
	}

	#if editor

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);
		ctx.properties.add(new hide.Element(
			'<div class="group" name="Fog">
				<dl>
					<dt>USE SHADOW MAP</dt><dd><input type="checkbox" field="USE_SHADOW_MAP"/></dd>
					<dt>Opacity</dt><dd><input type="range" min="0" max="1" field="opacity"/></dd>
					<dt>Falloff</dt><dd><input type="range" min="0.2" max="4" field="fallOff"/></dd>
				</dl>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : HideProps {
		return { icon : "sun-o", name : "Light volume" };
	}

	#end

	static var _ = hrt.prefab.Library.register("lightVolume", LightVolume);

}