package hrt.prefab2.l3d;

// NOTE(ces) : Not Tested

enum abstract DecalMode(String) {
	var Default;
	var BeforeTonemapping;
	var AfterTonemapping;
	var Terrain;
}

class Decal extends Object3D {

	@:s var albedoMap : String;
	@:s var normalMap : String;
	@:s var pbrMap : String;
	@:s var albedoStrength : Float = 1.0;
	@:s var normalStrength: Float = 1.0;
	@:s var pbrStrength: Float = 1.0;
	@:s var emissiveStrength: Float = 0.0;
	@:s var fadePower : Float = 1.0;
	@:s var fadeStart : Float = 0;
	@:s var fadeEnd : Float = 1.0;
	@:s var emissive : Float = 0.0;
	@:s var renderMode : DecalMode = Default;
	@:s var centered : Bool = true;
	@:s var autoAlpha : Bool = true;
	@:c var blendMode : h2d.BlendMode = Alpha;

	override function save(data:Dynamic) : Dynamic {
		var obj : Dynamic = super.save(data);
		if(blendMode != Alpha) obj.blendMode = blendMode.getIndex();
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		blendMode = obj.blendMode != null ? h2d.BlendMode.createByIndex(obj.blendMode) : Alpha;
	}

	override function makeObject3d(parent3d:h3d.scene.Object):h3d.scene.Object {
		var mesh = new h3d.scene.pbr.Decal(h3d.prim.Cube.defaultUnitCube(), parent3d);

		switch (renderMode) {
			case Default, Terrain:
				var shader = mesh.material.mainPass.getShader(h3d.shader.pbr.VolumeDecal.DecalPBR);
				if( shader == null ) {
					shader = new h3d.shader.pbr.VolumeDecal.DecalPBR();
					mesh.material.mainPass.addShader(shader);
				}
			case BeforeTonemapping:
				var shader = mesh.material.mainPass.getShader(h3d.shader.pbr.VolumeDecal.DecalOverlay);
				if( shader == null ) {
					shader = new h3d.shader.pbr.VolumeDecal.DecalOverlay();
					mesh.material.mainPass.addShader(shader);
				}
				mesh.material.mainPass.setPassName("beforeTonemappingDecal");
			case AfterTonemapping:
				var shader = mesh.material.mainPass.getShader(h3d.shader.pbr.VolumeDecal.DecalOverlay);
				if( shader == null ) {
					shader = new h3d.shader.pbr.VolumeDecal.DecalOverlay();
					mesh.material.mainPass.addShader(shader);
				}
				mesh.material.mainPass.setPassName("afterTonemappingDecal");
		}

		mesh.material.mainPass.depthWrite = false;
		mesh.material.mainPass.depthTest = GreaterEqual;
		mesh.material.mainPass.culling = Front;
		mesh.material.shadows = false;
		return mesh;
	}

	public function updateRenderParams() {
		var mesh = Std.downcast(local3d, h3d.scene.Mesh);
		mesh.material.mainPass.setBlendMode(blendMode);
		switch (renderMode) {
			case Default, Terrain:
				var shader = mesh.material.mainPass.getShader(h3d.shader.pbr.VolumeDecal.DecalPBR);
				if( shader != null ){
					shader.albedoTexture = albedoMap != null ? shared.loadTexture(albedoMap) : null;
					shader.normalTexture = normalMap != null ? shared.loadTexture(normalMap) : null;
					if(shader.albedoTexture != null) shader.albedoTexture.wrap = Repeat;
					if(shader.normalTexture != null) shader.normalTexture.wrap = Repeat;
					shader.albedoStrength = albedoStrength;
					shader.normalStrength = normalStrength;
					shader.pbrStrength = pbrStrength;
					shader.emissiveStrength = emissiveStrength;
					shader.USE_ALBEDO = albedoStrength != 0&& shader.albedoTexture != null;
					shader.USE_NORMAL = normalStrength != 0 && shader.normalTexture != null;
					shader.CENTERED = centered;
					shader.fadePower = fadePower;
					shader.fadeStart = fadeStart;
					shader.fadeEnd = fadeEnd;
				}
				var pbrTexture = pbrMap != null ? shared.loadTexture(pbrMap) : null;
				if( pbrTexture != null ) {
					var propsTexture = mesh.material.mainPass.getShader(h3d.shader.pbr.PropsTexture);
					if( propsTexture == null )
						propsTexture = mesh.material.mainPass.addShader(new h3d.shader.pbr.PropsTexture());
					propsTexture.texture = pbrTexture;
					propsTexture.texture.wrap = Repeat;
					propsTexture.emissiveValue = emissive;
				}
				else {
					mesh.material.mainPass.removeShader(mesh.material.mainPass.getShader( h3d.shader.pbr.PropsTexture));
				}
				if (renderMode == Default) {
					if (emissiveStrength != 0) {
						mesh.material.mainPass.setPassName("emissiveDecal");
					}
					else
						mesh.material.mainPass.setPassName("decal");
				}
				else {
					mesh.material.mainPass.setPassName("terrainDecal");
				}
			case BeforeTonemapping, AfterTonemapping:
				var shader = mesh.material.mainPass.getShader(h3d.shader.pbr.VolumeDecal.DecalOverlay);
				if( shader != null ){
					shader.colorTexture = albedoMap != null ? shared.loadTexture(albedoMap) : null;
					if(shader.colorTexture != null) shader.colorTexture.wrap = Repeat;
					shader.CENTERED = centered;
					shader.GAMMA_CORRECT = renderMode == BeforeTonemapping;
					shader.AUTO_ALPHA = autoAlpha;
					shader.fadePower = fadePower;
					shader.fadeStart = fadeStart;
					shader.fadeEnd = fadeEnd;
					shader.emissive = emissive;
				}
		}
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);
		updateRenderParams();
	}

	#if editor
	override function getHideProps() : hide.prefab2.HideProps {
		return { icon : "paint-brush", name : "Decal" };
	}

	override function setSelected(b : Bool ) {
		if( b ) {
			var obj = local3d;
			if(obj != null) {
				var wire = new h3d.scene.Box(0xFFFFFFFF,obj);
				wire.name = "_highlight";
				wire.material.setDefaultProps("ui");
				wire.ignoreCollide = true;
				wire.material.shadows = false;
				var wireCenter = new h3d.scene.Box(0xFFFF00, obj);
				wireCenter.scaleZ = 0;
				wireCenter.name = "_highlight";
				wireCenter.material.setDefaultProps("ui");
				wireCenter.ignoreCollide = true;
				wireCenter.material.shadows = false;
				wireCenter.material.mainPass.depthTest = Always;
			}
		} else {
			clearSelection();
		}
		return true;
	}

	function clearSelection() {
		var obj = local3d;
		if(obj == null) return;
		var objs = obj.findAll( o -> if(o.name == "_highlight") o else null );
		for( o in objs )
			o.remove();
	}

	override function edit( ctx : hide.prefab2.EditContext ) {
		super.edit(ctx);

		var pbrParams = '<dt>Albedo</dt><dd><input type="texturepath" field="albedoMap"/>
					<br/><input type="range" min="0" max="1" field="albedoStrength"/></dd>

					<dt>Normal</dt><dd><input type="texturepath" field="normalMap"/>
					<br/><input type="range" min="0" max="1" field="normalStrength"/></dd>

					<dt>PBR</dt><dd><input type="texturepath" field="pbrMap"/>
					<br/><input type="range" min="0" max="1" field="pbrStrength"/></dd>

					<dt>Emissive</dt><dd> <input type="range" min="0" max="10" field="emissive"/>
					<br/><input type="range" min="0" max="1" field="emissiveStrength"/></dd>';


		var overlayParams = '<dt>Color</dt><dd><input type="texturepath" field="albedoMap"/></dd>
						<dt>Emissive</dt><dd> <input type="range" min="0" max="10" field="emissive"/></dd>
						<dt>AutoAlpha</dt><dd><input type="checkbox" field="autoAlpha"/></dd>';

		var params = switch (renderMode) {
			case Default, Terrain: pbrParams;
			case BeforeTonemapping: overlayParams;
			case AfterTonemapping: overlayParams;
		}

		function refreshProps() {
			var props = ctx.properties.add(new hide.Element('
			<div class="decal">
				<div class="group" name="Decal">
					<dl>
						<dt>Centered</dt><dd><input type="checkbox" field="centered"/></dd>'
						+ params +
						'<dt>Render Mode</dt>
						<dd><select field="renderMode">
							<option value="Default">Default</option>
							<option value="BeforeTonemapping">Before Tonemapping</option>
							<option value="AfterTonemapping">After Tonemapping</option>
							<option value="Terrain">Terrain</option>
						</select></dd>

						<dt>Blend Mode</dt>
						<dd><select field="blendMode">
							<option value="Alpha">Alpha</option>
							<option value="Add">Add</option>
							<option value="Multiply">Multiply</option>
						</select></dd>
					</dl>
				</div>
				<div class="group" name="Fade">
					<dt>FadePower</dt><dd> <input type="range" min="0" max="3" field="fadePower"/></dd>
					<dt>Start</dt><dd> <input type="range" min="0" max="1" field="fadeStart"/></dd>
					<dt>End</dt><dd> <input type="range" min="0" max="1" field="fadeEnd"/></dd>
				</div>
			</div>
			'),this, function(pname) {
				if( pname == "renderMode" ) {
					clearSelection();
					ctx.rebuildPrefab(this);
					ctx.rebuildProperties();
				}
				else
					ctx.onChange(this, pname);
			});
		}

		refreshProps();
	}
	#end

	static var _ = Prefab.register("advancedDecal", Decal);

}