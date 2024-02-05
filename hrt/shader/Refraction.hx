package hrt.shader;

class RefractionPropsShader extends hxsl.Shader {
	static var SRC = {
		@param var intensityInput : Float;
		@param var albedoMultInput : Float;

		var intensity : Float;
		var albedoMult : Float;

		function fragment() {
			intensity = intensityInput;
			albedoMult = albedoMultInput;
		}
	}
}
class Refraction extends hrt.prefab.Shader {

	@:s var intensity : Float = 0.25;
	@:s var albedoMult : Float = 1.0;

	var refractionShader : RefractionPropsShader;
	public function new(parent, shared) {
		super(parent, shared);

		refractionShader = new RefractionPropsShader();
	}

	override function makeInstance() {
		updateInstance();
	}

	function getMaterials() {
		if( Std.isOfType(parent, hrt.prefab.Material) ) {
			var material : hrt.prefab.Material = cast parent;
			return material.getMaterials();
		}
		else {
			return findFirstLocal3d().getMaterials();
		}
	}

	override function updateInstance(?propName : String ) {
		refractionShader.intensityInput = intensity * 0.025;
		refractionShader.albedoMultInput = albedoMult;
		for( m in getMaterials() ) {
			var s = m.mainPass.getShader(RefractionPropsShader);
			if( s == null ) {
				m.mainPass.addShader(refractionShader);
				m.mainPass.setPassName("refraction");
			}
		}
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return { 	icon : "cog",
					name : "Refraction",
					allowParent : function(p) return p.to(hrt.prefab.Material) != null };
	}

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);

		var props = new hide.Element('
			<div class="group" name="Refraction props">
				<dl>
					<dt>Intensity</dt><dd><input type="range" min="0" max="1" field="intensity"/>
					<dt>Albedo mult</dt><dd><input type="range" min="0" max="1" field="albedoMult"/></dd>
				</dl>
			</div>
		');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = hrt.prefab.Prefab.register("refraction", Refraction);
}