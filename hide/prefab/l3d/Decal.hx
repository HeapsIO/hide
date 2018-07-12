package hide.prefab.l3d;

class Decal extends Object3D {

	var diffuseMap : String;
	var normalMap : String;
	var specularMap : String;
	var diffuseStrength : Float = 1.;
	var normalStrength : Float = 1.;
	var specularStrength : Float = 1.;

	override function save() {
		var obj : Dynamic = super.save();
		if(diffuseMap != null) obj.diffuseMap = diffuseMap;
		if(normalMap != null) obj.normalMap = normalMap;
		if(specularMap != null) obj.specularMap = specularMap;
		if(diffuseStrength != 1) obj.diffuseStrength = diffuseStrength;
		if(normalStrength != 1) obj.normalStrength = normalStrength;
		if(specularStrength != 1) obj.specularStrength = specularStrength;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		diffuseMap = obj.diffuseMap;
		normalMap = obj.normalMap;
		specularMap = obj.specularMap;
		diffuseStrength = obj.diffuseStrength != null ? obj.diffuseStrength : 1;
		normalStrength = obj.normalStrength != null ? obj.normalStrength : 1;
		specularStrength = obj.specularStrength != null ? obj.specularStrength : 1;
	}

	override function updateInstance(ctx:Context,?propName:String) {
		super.updateInstance(ctx,propName);

		var mesh = Std.instance(ctx.local3d, h3d.scene.Mesh);
		mesh.material.texture = diffuseMap != null ? ctx.loadTexture(diffuseMap) : null;
		mesh.material.normalMap = normalMap != null ? ctx.loadTexture(normalMap) : null;
		mesh.material.specularTexture = specularMap != null ? ctx.loadTexture(specularMap) : null;
		var sh = mesh.material.mainPass.getShader(h3d.shader.pbr.StrengthValues);
		if( sh != null ) {
			sh.albedoStrength = diffuseStrength;
			sh.normalStrength = normalStrength;
			sh.pbrStrength = specularStrength;
		}
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);

		var mesh = new h3d.scene.Mesh(h3d.prim.Cube.defaultUnitCube(), ctx.local3d);
		mesh.material.setDefaultProps("decal");

		#if editor
		var wire = new h3d.scene.Box(0xFFFFFFFF,mesh);
		wire.name = "_highlight";
		wire.material.setDefaultProps("ui");
		wire.ignoreCollide = true;
		wire.material.shadows = false;
		wire.visible = false;
		#end

		ctx.local3d = mesh;
		ctx.local3d.name = name;
		applyPos(ctx.local3d);
		updateInstance(ctx);

		return ctx;
	}

	override function getHideProps() {
		return { icon : "paint-brush", name : "Decal", fileSource : null };
	}

	#if editor
	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Decal">
				<dl>
					<dt>Diffuse</dt><dd>
						<input type="texturepath" field="diffuseMap"/>
						<br/><input type="range" field="diffuseStrength"/>
					</dd>
					<dt>Normal</dt><dd>
						<input type="texturepath" field="normalMap"/>
						<br/><input type="range" field="normalStrength"/>
					</dd>
					<dt>Specular</dt><dd>
						<input type="texturepath" field="specularMap"/>
						<br/><input type="range" field="specularStrength"/>
					</dd>
				</dl>
			</div>
		'),this, function(pname) {
			ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Library.register("decal", Decal);

}