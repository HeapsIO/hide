package hrt.prefab.l3d;

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
	@:s var drawOrder : String;
	@:s var normalFade : Bool = false;
	@:s var normalFadeStart : Float = 0;
	@:s var normalFadeEnd : Float = 1;
	@:s var refMatLib : String;

	override function save() : Dynamic {
		var obj : Dynamic = super.save();
		if(blendMode != Alpha) obj.blendMode = blendMode.getIndex();
		return obj;
	}

	override function copy( obj : Dynamic ) {
		super.copy(obj);
		blendMode = obj.blendMode;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		if( obj.blendMode != null )
			blendMode = h2d.BlendMode.createByIndex(obj.blendMode);
	}

	override function makeObject(parent3d:h3d.scene.Object):h3d.scene.Object {
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
		if (mesh == null)
			return;

		if (this.refMatLib != null && this.refMatLib != "") {
			// If a decal reference a material in the material library, we only
			// want the decal to apply certain params of the material since
			// some params won't make any sense on a decal.

			var refMatLibPath = this.refMatLib.substring(0, this.refMatLib.lastIndexOf("/"));
			var refMatName = this.refMatLib.substring(this.refMatLib.lastIndexOf("/") + 1);

			var prefabLib = hxd.res.Loader.currentInstance.load(refMatLibPath).toPrefab().load();
			for(c in prefabLib.children) {
				if (c.name != refMatName)
					continue;

				var mat = Std.downcast(c, Material);

				this.albedoMap = mat.diffuseMap;
				this.normalMap = mat.normalMap;
				this.pbrMap = mat.specularMap;

				var materialSetup = Reflect.field(mat.props, h3d.mat.MaterialSetup.current.name);
				this.emissive = Reflect.field(materialSetup, "emissive");

				var blend = Reflect.field(materialSetup, "blend");
				switch (blend)
				{
					case "Add", "Alpha", "Multiply":
						this.blendMode = h2d.BlendMode.createByName(blend);
					default:
						this.blendMode = h2d.BlendMode.None;
				}
			}
		}

		mesh.material.mainPass.setBlendMode(blendMode);
		mesh.material.mainPass.layer = Std.parseInt(drawOrder);

		inline function commonSetup(shader: h3d.shader.pbr.VolumeDecal.BaseDecal) {
			shader.fadePower = fadePower;
			shader.fadeStart = fadeStart;
			shader.fadeEnd = fadeEnd;
			shader.USE_NORMAL_FADE = normalFade;
			shader.normalFadeStart = normalFadeStart;
			shader.normalFadeEnd = normalFadeEnd;
		}

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
					commonSetup(shader);
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
					shader.emissive = emissive;
					commonSetup(shader);
				}
		}
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);
		updateRenderParams();
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "paint-brush", name : "Decal" };
	}

	override function setSelected(b : Bool ) {
		if( b ) {
			var obj = local3d;
			if(obj != null) {
				var wire = new h3d.scene.Box(0xFFFFFFFF,obj);
				wire.name = "_highlight";
				wire.material.setDefaultProps("ui");
				wire.material.mainPass.setPassName("debuggeom");
				wire.ignoreCollide = true;
				wire.material.shadows = false;
				var wireCenter = new h3d.scene.Box(0xFFFF00, obj);
				wireCenter.scaleZ = 0;
				wireCenter.name = "_highlight";
				wireCenter.material.setDefaultProps("ui");
				wireCenter.material.mainPass.setPassName("debuggeom");
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

	override function edit( ctx : hide.prefab.EditContext ) {
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
			var matLibs = ctx.scene.listMatLibraries(this.getAbsPath());
			var selectedLib = this.refMatLib == null ? null : this.refMatLib.substring(0, this.refMatLib.lastIndexOf("/"));
			var selectedMat = this.refMatLib == null ? null : this.refMatLib.substring(this.refMatLib.lastIndexOf("/") + 1);
			var materials = [];

			var materialLibrary = new hide.Element('<div class="group" name="Material Library">
			<dl>
				<dt>Library</dt>
				<dd>
					<select class="lib">
						<option value="">None</option>
						${[for( i in 0...matLibs.length ) '<option value="${matLibs[i].name}" ${(selectedLib == matLibs[i].path) ? 'selected' : ''}>${matLibs[i].name}</option>'].join("")}
					</select>
				</dd>
				<dt>Material</dt>
				<dd>
					<select class="mat">
						<option value="">None</option>
					</select>
				</dd>
				<dt>Mode</dt>
				<dd>
					<select class="mode">
						<option value="folder">Shared by folder</option>
						<option value="modelSpec">Model specific</option>
					</select>
				</dd>
				<dt></dt><dd><input type="button" value="Go to library" class="goTo"/></dd>
			</dl></div>');

			var libSelect = materialLibrary.find(".lib");
			var matSelect = materialLibrary.find(".mat");

			function updateMatSelect() {
				matSelect.empty();
				new hide.Element('<option value="">None</option>').appendTo(matSelect);

				materials = ctx.scene.listMaterialFromLibrary(this.getAbsPath(), libSelect.val());

				for (idx in 0...materials.length) {
					new hide.Element('<option value="${materials[idx].path + "/" + materials[idx].mat.name}" ${(selectedMat == materials[idx].mat.name) ? 'selected' : ''}>${materials[idx].mat.name}</option>').appendTo(matSelect);
				}
			}

			function updateLibSelect() {
				libSelect.empty();
				new hide.Element('<option value="">None</option>').appendTo(libSelect);

				for (idx in 0...matLibs.length) {
					new hide.Element('<option value="${matLibs[idx].name}" ${(selectedLib == matLibs[idx].path) ? 'selected' : ''}>${matLibs[idx].name}</option>');
				}
			}

			function updateMat() {
				var previousData = this.serialize();
				var mat = ctx.scene.findMat(materials, matSelect.val());
				if ( mat != null ) {
					this.refMatLib = mat.path + "/" + mat.mat.name;
					updateInstance();
					ctx.rebuildProperties();
				} else {
					this.refMatLib = "";
				}

				var newDecal = this.serialize();

				ctx.properties.undo.change(Custom(function(undo) {
					if( undo ) {
						this.load(previousData);
					}
					else {
						this.load(newDecal);
					}

					updateLibSelect();
					updateMatSelect();
					ctx.rebuildProperties();
					updateInstance();
				}));
			}

			updateMatSelect();

			libSelect.change(function(_) {
				var previousMatSelect = matSelect.val();
				updateMatSelect();

				if (libSelect.val() == "" || previousMatSelect != "")
					updateMat();
			});

			matSelect.change(function(_) {
				updateMat();
			});

			materialLibrary.find(".goTo").click(function(_) {
				var mat = ctx.scene.findMat(materials, matSelect.val());
				if ( mat != null ) {
					hide.Ide.inst.openFile(Reflect.field(mat, "path"));
				}
			});

			ctx.properties.add(materialLibrary, this);

			var layers : Array< { name : String, value : Int }> = hide.Ide.inst.currentConfig.get("material.drawOrder", []);

			ctx.properties.add(new hide.Element('
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

						<dt>Draw Order</dt>
						<dd>
							<select field="drawOrder">
								<option value="" selected disabled hidden>Default</option>
								${[for( i in 0...layers.length ) '<option value="${layers[i].value}">${layers[i].name}</option>'].join("")}
							</select>
						</dd>
					</dl>
				</div>
				<div class="group" name="Fade">
					<dt>FadePower</dt><dd> <input type="range" min="0" max="3" field="fadePower"/></dd>
					<dt>Start</dt><dd> <input type="range" min="0" max="1" field="fadeStart"/></dd>
					<dt>End</dt><dd> <input type="range" min="0" max="1" field="fadeEnd"/></dd>

					<dt>Fade normal</dt><dd><input type="checkbox" field="normalFade"/></dd>
					<dt>Normal start</dt><dd> <input type="range" min="0" max="1" field="normalFadeStart"/></dd>
					<dt>Normal end</dt><dd> <input type="range" min="0" max="1" field="normalFadeEnd"/></dd>
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