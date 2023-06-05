package hrt.prefab.rfx;

class RefractionShader extends hxsl.Shader {

	static var SRC = {

		@global var camera : {
			var viewProj : Mat4;
		};

		@param var texture:Sampler2D;

		var pixelColor : Vec4;
		var transformedNormal : Vec3;
		var screenUV : Vec2;

		var intensity : Float;
		var albedoMult : Float;

		function fragment() {
			var displacement = (vec4(-transformedNormal, 0.0) * camera.viewProj);
			displacement = normalize(displacement) / displacement.w;
			// TODO : Edge artifacts
			pixelColor.rgb = texture.get(screenUV + displacement.xy * intensity).rgb * mix(vec3(1.0), pixelColor.rgb, albedoMult);
			pixelColor.a = 1.0;
		}
	}
}

@:access(h3d.pass.PassList)
@:access(h3d.scene.Renderer)
@:access(h3d.pass.PassObject)
class Refraction extends RendererFX {

	var refractionShader : RefractionShader;
	function new(?parent, shared: ContextShared) {
		super(parent, shared);

		refractionShader = new RefractionShader();
	}

	inline function cullPasses( passes : h3d.pass.PassList, f : h3d.col.Collider -> Bool ) {
		var prevCollider = null;
		var prevResult = true;
		passes.filter(function(p) {
			var col = p.obj.cullingCollider;
			if( col == null )
				return true;
			if( col != prevCollider ) {
				prevCollider = col;
				prevResult = f(col);
			}
			return prevResult;
		});
	}

	var tex : h3d.mat.Texture;
	var passes : h3d.pass.PassList;
	override function begin( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
		if( step == BeforeTonemapping ) {

			passes = r.get("refraction");
			cullPasses(passes, function(col) {
				return col.inFrustum(r.ctx.camera.frustum);
			});

			r.mark("Refraction");

			var it = passes.current;
			 while (it != null) {
				if ( it.pass.getShaderByName("hrt.prefab.rfx.RefractionShader") == null)
					it.pass.addShader(refractionShader);
				it = it.next;
			}

			if ( passes.current == null )
				return;
			var ldrMap = r.ctx.engine.getCurrentTarget();
			tex = r.allocTarget("refraction", false, 1.0, RGBA);
			h3d.pass.Copy.run(ldrMap, tex);
			refractionShader.texture = tex;
		}
	}

	override function end( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
		if ( step == BeforeTonemapping ) {
			r.defaultPass.draw(passes);
		}
	}

	static var _ = Prefab.register("rfx.refraction", Refraction);
}
