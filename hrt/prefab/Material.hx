package hrt.prefab;

import h3d.scene.Mesh;
import h3d.scene.Object;
import h3d.mat.PbrMaterial;

class Material extends Prefab {

	@:s public var wrapRepeat = false;
	@:s public var diffuseMap : String;
	@:s public var normalMap : String;
	@:s public var specularMap : String;
	@:s public var materialName : String;
	@:c public var color : Array<Float> = [1,1,1,1];
	@:s public var mainPassName : String;
	@:s public var refMatLib : String;
	@:s public var overrides : Array<Dynamic> = [];

	public function new(?parent) {
		super(parent);
		type = "material";
		props = {};
	}

	override function load(obj:Dynamic) {
		super.load(obj);
		color = obj.color != null ? obj.color : [1,1,1,1];
	}

	override function save() {
		var obj : Dynamic = super.save();
		if(color != null && h3d.Vector.fromArray(color).toColor() != 0xffffffff) obj.color = color;
		if(mainPassName == "" || mainPassName == null ) Reflect.deleteField(obj, "mainPassName");
		return obj;
	}

	function renderProps() {
		var cur = h3d.mat.MaterialSetup.current;
		var setupName = cur.name;

		applyOverrides();

		var r = Reflect.field(props, setupName);
		if(r == null) {
			r = cur.getDefaults();
			Reflect.setField(props, setupName, r);
		}

		return r;
	}

	public function getMaterials( ctx : Context ) {
		var mats = ctx.local3d.getMaterials();
		var mat = Lambda.find(mats, m -> m.name == this.name || (m.name != null && m.name == materialName));
		return mat == null ? mats : [mat];
	}

	function update(mat : h3d.mat.Material, props, loadTexture : String -> h3d.mat.Texture) {
		if(color != null)
			mat.color.setColor(h3d.Vector.fromArray(color).toColor());

		inline function getTex(pname: String) {
			var p : String = Reflect.field(this, pname);
			var tex : h3d.mat.Texture = null;
			if(p != null) {
				tex = loadTexture(p);
				if(tex != null)
					tex.wrap = wrapRepeat ? Repeat : Clamp;
			}
			return tex;
		}

		if( getTex("diffuseMap") != null ) mat.texture = getTex("diffuseMap");
		if( getTex("normalMap") != null ) mat.normalMap = getTex("normalMap");
		if( getTex("specularMap") != null ) mat.specularTexture = getTex("specularMap");
		mat.props = props;

		if(mainPassName != null && mainPassName.length > 0 )
			mat.mainPass.setPassName(mainPassName);
	}

	override function updateInstance( ctx : Context, ?propName ) {
		if( ctx.local3d == null )
			return;

		var mats = getMaterials(ctx);

		if (this.refMatLib != null && this.refMatLib != "") {
			// We want to save some infos to reapply them after loading datas from the choosen mat
			var previousRefMatLib = this.refMatLib;
			var previousName = this.name;
			var previousOverrides = this.overrides.copy();

			var refMatLibPath = this.refMatLib.substring(0, this.refMatLib.lastIndexOf("/"));
			var refMatName = this.refMatLib.substring(this.refMatLib.lastIndexOf("/") + 1);

			var prefabLib = hxd.res.Loader.currentInstance.load(refMatLibPath).toPrefab().load().clone(true);

			for(c in prefabLib.children) {
				if (c.name != refMatName)
					continue;

				// Apply shaders to this material if the referenced one has shaders
				var shaders = c.flatten(Shader);
				if (shaders != null) {
					for (s in shaders) {
						var shader = s.makeShader(ctx);

						for( m in mats )
							m.mainPass.addShader(shader);
					}
				}

				this.load(c);

				// Reapply some infos that we don't want to be modified by the load of the new mat
				this.refMatLib = previousRefMatLib;
				this.name = previousName;
				this.overrides = previousOverrides;

				applyOverrides();
				break;
			}
		}


		var props = renderProps();
		#if editor
		if ( mats == null || mats.length == 0 ) {
			var sphere = new h3d.prim.Sphere(1., 64, 48);
			sphere.addUVs();
			sphere.addNormals();
			sphere.addTangents();
			var preview = new h3d.scene.Mesh(sphere);
			preview.name = "materialPreviewSphere";
			ctx.local3d.parent.addChild(preview);
			ctx.local3d = preview;
			ctx.local3d.x = ctx.local3d.getScene().getMaterials().length * 5.0;
			mats = getMaterials(ctx);
		}
		#end
		for( m in mats )
			update(m, props, ctx.loadTexture);
	}

	override function makeInstance(ctx:Context):Context {
		if(ctx.local3d == null)
			return ctx;
		ctx = ctx.clone(this);

		updateInstance(ctx);
		return ctx;
	}

	function applyOverrides() {
		// We want to break the reference between props of the current material and props of the material we loaded
		var newProps = {};
		var newMaterialSetupObj = {};

		var materialSetupObj = Reflect.getProperty(this.props, h3d.mat.MaterialSetup.current.name);
		for (f in Reflect.fields(materialSetupObj)) {
			Reflect.setField(newMaterialSetupObj, f, Reflect.field(materialSetupObj, f));
		}

		for (o in overrides) {
			if (o.pname.indexOf("/") > 0) {


				var pname = o.pname.substring(o.pname.indexOf("/") + 1);
				var v = o.value;

				if (v == "__toremove") {
					Reflect.deleteField(newMaterialSetupObj, pname);
				}
				else {
					Reflect.setProperty(newMaterialSetupObj, pname, o.value);
				}
			}
			else {
				Reflect.setProperty(this, o.pname, o.value);
			}
		}

		Reflect.setProperty(newProps, h3d.mat.MaterialSetup.current.name, newMaterialSetupObj);
		this.props = newProps;
	}

	#if editor
	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var isPbr = Std.isOfType(ctx.scene.s3d.renderer, h3d.scene.pbr.Renderer);
		var mat = h3d.mat.Material.create();
		mat.props = renderProps();

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
			<dt></dt><dd><input type="button" value="Clear overrides" class="clearOverrides"/></dd>
		</dl></div>');

		var libSelect = materialLibrary.find(".lib");
		var matSelect = materialLibrary.find(".mat");

		function findMat(key:String) {
			var p = key.split("/");
			var name = p.pop();
			var path = p.join("/");
			for ( m in materials ) {
				if ( m.path == path && m.mat.name == name )
					return m;
			}
			return null;
		}

		function updateLibSelect() {
			libSelect.empty();
			new Element('<option value="">None</option>').appendTo(libSelect);

			for (idx in 0...matLibs.length) {
				new Element('<option value="${matLibs[idx].name}" ${(selectedLib == matLibs[idx].path) ? 'selected' : ''}>${matLibs[idx].name}</option>');
			}
		}

		function updateMatSelect() {
			matSelect.empty();
			new Element('<option value="">None</option>').appendTo(matSelect);

			materials = ctx.scene.listMaterialFromLibrary(this.getAbsPath(), libSelect.val());

			for (idx in 0...materials.length) {
				new Element('<option value="${materials[idx].path + "/" + materials[idx].mat.name}" ${(selectedMat == materials[idx].mat.name) ? 'selected' : ''}>${materials[idx].mat.name}</option>').appendTo(matSelect);
			}
		}

		function updateMat() {
			var previousMat = this.clone();
			var mat = findMat(matSelect.val());
			if ( mat != null ) {
				var previousName = this.name;
				this.load(mat.mat);
				this.name = previousName;
				this.refMatLib = mat.path + "/" + mat.mat.name;
				updateInstance(ctx.scene.editor.getContext(this));
				ctx.rebuildProperties();
			} else {
				this.refMatLib = "";
			}

			var newMat = this.clone();

			ctx.properties.undo.change(Custom(function(undo) {
				if( undo ) {
					this.load(previousMat);
				}
				else {
					this.load(newMat);
				}

				updateLibSelect();
				updateMatSelect();
				ctx.rebuildProperties();
				updateInstance(ctx.scene.editor.getContext(this));
			}));
		}

		function updateHighlightOverrides() {
			ctx.properties.element.find(".override").removeClass("override");
			ctx.properties.element.find(".remove-override-btn").remove();

			var e = overrides;

			// Highlight field that are overrides
			for (o in overrides) {
				var idxStart = o.pname.indexOf("/");
				var fieldName = o.pname.substring(idxStart + 1);
				var el = ctx.properties.element.find('[field=${fieldName}]');
				if (el.length != 1)
					continue;

				var parentDiv = el.parent();
				while (!parentDiv.parent().is("dl") && parentDiv != null)
					parentDiv = parentDiv.parent();

				parentDiv.addClass("override");

				var label = parentDiv.children().first();
				var removeOverrideBtn = new Element('<i title="Remove override" class="remove-override-btn icon ico ico-remove"></i>').insertBefore(label);
				removeOverrideBtn.css({ "cursor":"pointer" });
				removeOverrideBtn.on("click", function(_){
					overrides.remove(o);
					updateInstance(ctx.scene.editor.getContext(this));
					ctx.rebuildProperties();
				});
			}
		}

		function addOverrideProperty(pname : String, isMatSetupProp : Bool) {
			// Remove previous value of this props name in overrides
			var idx = 0;
			while (idx < overrides.length) {
				if (overrides[idx].pname == (isMatSetupProp ? h3d.mat.MaterialSetup.current.name+"/"+pname : pname)) {
					overrides.remove(overrides[idx]);
					continue;
				}

				idx++;
			}

			if (isMatSetupProp) {
				var materialSetupObj = Reflect.getProperty(this.props, h3d.mat.MaterialSetup.current.name);
				var v = Reflect.getProperty(materialSetupObj, pname);
				overrides.push( { pname:h3d.mat.MaterialSetup.current.name+"/"+pname, value:v == null ? "__toremove" : v } );
			}
			else {
				overrides.push( { pname:pname, value:Reflect.field(this, pname) } );
			}

			updateHighlightOverrides();
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
			var mat = findMat(matSelect.val());
			if ( mat != null ) {
				hide.Ide.inst.openFile(mat.path);
			}
		});

		materialLibrary.find(".clearOverrides").click(function(_) {
			this.overrides = [];
			updateMatSelect();
			updateMat();
		});

		ctx.properties.add(materialLibrary, this);

		var group = ctx.properties.add(new hide.Element('<div class="group" name="Material"></div>'));
		ctx.properties.addMaterial(mat, group.find('.group > .content'), function(pname) {
			if (this.refMatLib != null && this.refMatLib != "")
				addOverrideProperty(pname, true);

			Reflect.setField(props, h3d.mat.MaterialSetup.current.name, mat.props);
			ctx.onChange(this, "props");

			var fx = getParent(hrt.prefab.fx.FX);
			if(fx != null)
				ctx.rebuildPrefab(fx, true);
		});

		if( isPbr ) {
			var pbrProps : h3d.mat.PbrMaterial.PbrProps = mat.props;

			var colorMask = new hide.Element('
			<div class="group" name="Color Mask">
				<dt>Channels</dt>
					<dd>
						R <input type="checkbox" class="colorMaskR"/>
						G <input type="checkbox" class="colorMaskG"/>
						B <input type="checkbox" class="colorMaskB"/>
						A <input type="checkbox" class="colorMaskA"/>
					</dd>
			</div>');
			ctx.properties.add(colorMask, this, function(pname) {
				ctx.onChange(this, pname);
				var fx = getParent(hrt.prefab.fx.FX);
				if(fx != null)
					ctx.rebuildPrefab(fx, true);
			});

			function setBit( e : Element, field : String, className : String, bitIndex : Int ) {
				var mask = e.find(className);
				var val : Int = cast Reflect.field(pbrProps, field);
				mask.prop("checked", val & (1<<bitIndex) > 0 ? true : false);
				mask.on("change", function(_) {
					var val : Int = cast Reflect.field(pbrProps, field);
					var checked : Bool = mask.prop("checked");
					Reflect.setField(pbrProps, field, checked ? val | (1 << bitIndex) : val & ~(1 << bitIndex));
					ctx.onChange(this, "props");

					ctx.properties.undo.change(Custom(function(undo) {
						if( undo )
							Reflect.setField(pbrProps, field, checked ? val & ~(1 << bitIndex) : val | (1 << bitIndex));
						else
							Reflect.setField(pbrProps, field, checked ? val | (1 << bitIndex) : val & ~(1 << bitIndex));
						mask.prop("checked", val & (1<<bitIndex) > 0 ? true : false);
					}));

					var fx = getParent(hrt.prefab.fx.FX);
					if(fx != null)
						ctx.rebuildPrefab(fx, true);
				});
			}

			setBit(colorMask, "colorMask", ".colorMaskR", 0);
			setBit(colorMask, "colorMask", ".colorMaskG", 1);
			setBit(colorMask, "colorMask", ".colorMaskB", 2);
			setBit(colorMask, "colorMask", ".colorMaskA", 3);

			var stencilParams = '
			<dt>Compare</dt>
				<dd>
					<select field="stencilCompare">
						<option value="Always">Always</option>
						<option value="Never">Never</option>
						<option value="Equal">Equal</option>
						<option value="NotEqual">NotEqual</option>
						<option value="Greater">Greater</option>
						<option value="GreaterEqual">GreaterEqual</option>
						<option value="Less">Less</option>
						<option value="LessEqual">LessEqual</option>
					</select>
				</dd>
				<dt>Stencil Fail</dt>
				<dd>
					<select field="stencilFailOp">
						<option value="Keep">Keep</option>
						<option value="Zero">Zero</option>
						<option value="Replace">Replace</option>
						<option value="Increment">Increment</option>
						<option value="IncrementWrap">IncrementWrap</option>
						<option value="Decrement">Decrement</option>
						<option value="DecrementWrap">DecrementWrap</option>
						<option value="Invert">Invert</option>
					</select>
				</dd>
				<dt>Depth Fail</dt>
				<dd>
					<select field="depthFailOp">
						<option value="Keep">Keep</option>
						<option value="Zero">Zero</option>
						<option value="Replace">Replace</option>
						<option value="Increment">Increment</option>
						<option value="IncrementWrap">IncrementWrap</option>
						<option value="Decrement">Decrement</option>
						<option value="DecrementWrap">DecrementWrap</option>
						<option value="Invert">Invert</option>
					</select>
				</dd>
				<dt>Stencil Pass</dt>
				<dd>
					<select field="stencilPassOp">
						<option value="Keep">Keep</option>
						<option value="Zero">Zero</option>
						<option value="Replace">Replace</option>
						<option value="Increment">Increment</option>
						<option value="IncrementWrap">IncrementWrap</option>
						<option value="Decrement">Decrement</option>
						<option value="DecrementWrap">DecrementWrap</option>
						<option value="Invert">Invert</option>
					</select>
				</dd>
				<dt>Read Mask</dt>
					<dd>
						<input type="checkbox" class="read7"/>
						<input type="checkbox" class="read6"/>
						<input type="checkbox" class="read5"/>
						<input type="checkbox" class="read4"/>
						<input type="checkbox" class="read3"/>
						<input type="checkbox" class="read2"/>
						<input type="checkbox" class="read1"/>
						<input type="checkbox" class="read0"/>
					</dd>
				<dt>Write Mask</dt>
					<dd>
						<input type="checkbox" class="write7"/>
						<input type="checkbox" class="write6"/>
						<input type="checkbox" class="write5"/>
						<input type="checkbox" class="write4"/>
						<input type="checkbox" class="write3"/>
						<input type="checkbox" class="write2"/>
						<input type="checkbox" class="write1"/>
						<input type="checkbox" class="write0"/>
					</dd>
				<dt>Value</dt>
					<dd>
						<input type="checkbox" class="value7"/>
						<input type="checkbox" class="value6"/>
						<input type="checkbox" class="value5"/>
						<input type="checkbox" class="value4"/>
						<input type="checkbox" class="value3"/>
						<input type="checkbox" class="value2"/>
						<input type="checkbox" class="value1"/>
						<input type="checkbox" class="value0"/>
					</dd>';
			var stencil = new hide.Element('
			<div class="group" name="Stencil">
				<dt>Enable</dt><dd><input type="checkbox" field="enableStencil"/></dd>'
				+ (pbrProps.enableStencil ? stencilParams : "") +'
			</div>');

			ctx.properties.add(stencil, pbrProps, function(pname) {
				ctx.onChange(this, "props");
				if( pname == "enableStencil" )
					ctx.rebuildProperties();
			});

			for( i in 0 ... 8 ) {
				setBit(stencil, "stencilWriteMask", ".write"+i, i);
				setBit(stencil, "stencilReadMask", ".read"+i, i);
				setBit(stencil, "stencilValue", ".value"+i, i);
			}
		}

		var dropDownMaterials = new hide.Element('
				<dl>
					<dt>Name</dt><dd><select><option value="any">Any</option></select>
				</dl> ');
		var select = dropDownMaterials.find("select");
		var materialList = ctx.rootContext.local3d.getMaterials();
		for( m in materialList )
			if( m.name != null && m.name != "" )
				new hide.Element('<option>').attr("value", m.name).text(m.name).appendTo(select);

		select.change(function(_) {
			var previous = materialName;
			materialName = select.val();
			var actual = materialName;
			ctx.properties.undo.change(Custom(function(undo) {
				materialName = undo ? previous : actual;
				ctx.onChange(this, null);
				ctx.rebuildProperties();
				ctx.scene.editor.refresh(Partial);
			}));
			ctx.onChange(this, null);
			ctx.rebuildProperties();
			ctx.scene.editor.refresh(Partial);

			var fx = getParent(hrt.prefab.fx.FX);
			if(fx != null)
				ctx.rebuildPrefab(fx, true);
		});
		select.val(materialName == null ? "any" : materialName);

		var matProps = new hide.Element('<div class="group" name="Overrides">
		<dl>
			<dt>${isPbr ? "Albedo" : "Diffuse"}</dt><dd><input type="texturepath" field="diffuseMap" style="width:165px"/></dd>
			<dt>Normal</dt><dd><input type="texturepath" field="normalMap" style="width:165px"/></dd>
			<dt>Specular</dt><dd><input type="texturepath" field="specularMap" style="width:165px"/></dd>
			<dt>Wrap</dt><dd><input type="checkbox" field="wrapRepeat"/></dd>
			<dt>Color</dt><dd><input type="color" field="color"/></dd>
			<dt>Pass Name</dt><dd><input type="text" field="mainPassName"/></dd>
		</dl></div>');

		dropDownMaterials.appendTo(matProps);
		ctx.properties.add(matProps, this, function(pname) {

			if (this.refMatLib != null && this.refMatLib != "")
				addOverrideProperty(pname, false);

			ctx.onChange(this, pname);

			var fx = getParent(hrt.prefab.fx.FX);
			if(fx != null)
				ctx.rebuildPrefab(fx, true);
		});

		updateHighlightOverrides();
	}

	override function getHideProps() : HideProps {
		return {
			icon : "cog",
			name : "Material",
			onResourceRenamed : function(f) {
				diffuseMap = f(diffuseMap);
				normalMap = f(normalMap);
				specularMap = f(specularMap);
			},
		};
	}
	#end

	public static function hasOverride(p: Prefab) {
		if(Lambda.exists(p.children, c -> Std.isOfType(c, Material) && c.enabled))
			return true;
		if(Type.getClass(p.parent) == Object3D)
			return Lambda.exists(p.parent.children, c -> Std.isOfType(c, Material) && c.enabled);
		return false;
	}

	static var _ = Library.register("material", Material);
}