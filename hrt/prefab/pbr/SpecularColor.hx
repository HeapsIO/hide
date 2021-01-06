package hrt.prefab.pbr;

class SpecularColor extends Prefab {

	// Amount of dielectric specular reflection. Specifies facing (along normal) reflectivity in the most common 0 - 8% range.
	public var specular : Float = 0.5;

	// Tints the facing specular reflection using the base color, while glancing reflection remains white.
	// Normal dielectrics have colorless reflection, so this parameter is not technically physically correct 
	// and is provided for faking the appearance of materials with complex surface structure.
	public var specularTint : Float = 0.0;

	public function new(?parent) {
		super(parent);
		type = "specularColor";
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		if( obj.specularTint != null ) specularTint = obj.specularTint;
		if( obj.specular != null ) specular = obj.specular;
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.specularTint = specularTint;
		obj.specular = specular;
		return obj;
	}

	override function makeInstance( ctx : Context ):Context {
		ctx = ctx.clone(this);
		refreshShaders(ctx);
		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance( ctx : Context, ?propName : String ) {
		for( m in ctx.local3d.getMaterials() ) {
			var sc = m.mainPass.getShader(hrt.shader.SpecularColor);
			if( sc != null ) {
				sc.specular = specular;
				sc.specularTint = specularTint;
			}
		}
	}

	function refreshShaders( ctx : Context ) {
		var sc = new hrt.shader.SpecularColor();
		var o = ctx.local3d;
		for( m in o.getMaterials() ) {
			m.mainPass.removeShader(m.mainPass.getShader(hrt.shader.SpecularColor));
		}
		for( m in o.getMaterials() ) {

			if( m.mainPass.name != "forward" )
				continue;

			if( m.mainPass.getShader(hrt.shader.SpecularColor) == null ) {
				m.mainPass.addShader(sc);
			}
		}
	}

	#if editor
	override function getHideProps() : HideProps {
		return { 	icon : "cube", 
					name : "SpecularColor",
					allowParent : function(p) return p.to(Material) != null };
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var props = new hide.Element('
			<div class="group" name="Specular Color">
				<dl>
					<dt>Tint</dt><dd><input type="range" min="0" max="1" field="specularTint"/></dd>
					<dt>Amount</dt><dd><input type="range" min="0" max="1" field="specular"/>
				</dl>
			</div>
		');

		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Library.register("specularColor", SpecularColor);
}