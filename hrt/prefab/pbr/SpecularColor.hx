package hrt.prefab.pbr;

import hrt.shader.SpecularColor;
import hrt.shader.SpecularColor.SpecularColorAlbedo;
import hrt.shader.SpecularColor.SpecularColorFlat;
import hrt.shader.SpecularColor.SpecularColorTexture;

enum abstract SpecularColorMode(String) {
	var Albedo;
	var Flat;
	var Texture;
}

class SpecularColor extends Prefab {

	// Amount of dielectric specular reflection. Specifies facing (along normal) reflectivity in the most common 0 - 8% range.
	public var specular : Float = 0.5;

	// Tints the facing specular reflection using the base color, while glancing reflection remains white.
	// Normal dielectrics have colorless reflection, so this parameter is not technically physically correct 
	// and is provided for faking the appearance of materials with complex surface structure.
	public var specularTint : Float = 0.0;

	public var specularColorPath : String;
	public var specularColorCustomValue : Int;
	public var mode : SpecularColorMode = Albedo;

	public function new(?parent) {
		super(parent);
		type = "specularColor";
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		if( obj.specularTint != null ) specularTint = obj.specularTint;
		if( obj.specular != null ) specular = obj.specular;
		if( obj.specularColorCustomValue != null ) specularColorCustomValue = obj.specularColorCustomValue;
		if( obj.mode != null ) mode = obj.mode;
		if( obj.specularColorPath != null ) specularColorPath = obj.specularColorPath;
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.specularTint = specularTint;
		obj.specular = specular;
		obj.specularColorPath = specularColorPath;
		obj.specularColorCustomValue = specularColorCustomValue;
		obj.mode = mode;
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
			var sca = m.mainPass.getShader(hrt.shader.SpecularColorAlbedo);
			if( sca != null ) {
				// No params
			}
			var scf = m.mainPass.getShader(hrt.shader.SpecularColorFlat);
			if( scf != null ) {
				scf.specularColorValue = h3d.Vector.fromColor(specularColorCustomValue);
			}
			var sct = m.mainPass.getShader(hrt.shader.SpecularColorTexture);
			if( sct != null ) {
				sct.specularColorTexture = ctx.loadTexture(specularColorPath);
			}
			var sc = m.mainPass.getShader(hrt.shader.SpecularColor);
			if( sc != null ) {
				sc.specular = specular;
				sc.specularTint = specularTint;
			}
		}
	}

	function refreshShaders( ctx : Context ) {

		var sca = new SpecularColorAlbedo();
		var scf = new SpecularColorFlat();
		var sct = new SpecularColorTexture();
		var sc = new hrt.shader.SpecularColor();

		var specularColorTexture = specularColorPath != null ? ctx.loadTexture(specularColorPath) : null;

		var o = ctx.local3d;
		for( m in o.getMaterials() ) {
			m.mainPass.removeShader(m.mainPass.getShader(SpecularColorAlbedo));
			m.mainPass.removeShader(m.mainPass.getShader(SpecularColorFlat));
			m.mainPass.removeShader(m.mainPass.getShader(SpecularColorTexture));
			m.mainPass.removeShader(m.mainPass.getShader(hrt.shader.SpecularColor));
		}
		for( m in o.getMaterials() ) {

			if( m.mainPass.name != "forward" )
				continue;

			switch mode {
				case Albedo: m.mainPass.addShader(sca);
				case Flat: m.mainPass.addShader(scf);
				case Texture: specularColorTexture == null ? m.mainPass.addShader(scf) : m.mainPass.addShader(sct);
			}

			m.mainPass.addShader(sc);
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

		var flatParams = 	'<dt>Color</dt><dd><input type="color" field="specularColorCustomValue"/></dd>';

		var textureParams = '<dt>Color</dt><dd><input type="texturepath" field="specularColorPath"/>';

		var albedoParams =	'';

		var params = switch mode {
			case Albedo: albedoParams;
			case Texture: textureParams;
			case Flat: flatParams;
		};

		var props = new hide.Element('
			<div class="group" name="Specular Color">
				<dl>
					<dt>Reflection Amount</dt><dd><input type="range" min="0" max="1" field="specular"/>
					<dt>Tint Amount</dt><dd><input type="range" min="0" max="1" field="specularTint"/></dd>
					<dt>Color Mode</dt>
						<dd>
							<select field="mode">
								<option value="Albedo">Albedo</option>
								<option value="Flat">Flat</option>
								<option value="Texture">Texture</option>
							</select>
						</dd>
					' + params + '
				</dl>
			</div>
		');

		ctx.properties.add(props, this, function(pname) {
			if( pname == "mode" || pname == "specularColorPath" ) {
				ctx.rebuildProperties();
				refreshShaders(ctx.getContext(this));
			}
			ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Library.register("specularColor", SpecularColor);
}