package hrt.prefab2;

import h3d.scene.Mesh;
import h3d.scene.Object;
import h3d.mat.PbrMaterial;
import hide.prefab2.HideProps;

import hide.Element;

class Material extends Prefab {

	@:s public var wrapRepeat = false;
	@:s public var diffuseMap : String;
	@:s public var normalMap : String;
	@:s public var specularMap : String;
	@:s public var materialName : String;
	@:c public var color : Array<Float> = [1,1,1,1];
	@:s public var mainPassName : String;

	public function new(?parent) {
		super(parent);
		props = {};
	}

	override function load(obj:Dynamic) {
		super.load(obj);
		color = obj.color != null ? obj.color : [1,1,1,1];
	}

	/*override function save(data: Dynamic) {
		super.save(data);
		if(color != null && h3d.Vector.fromArray(color).toColor() != 0xffffffff) data.color = color;
	}*/

	function renderProps() {
		var cur = h3d.mat.MaterialSetup.current;
		var setupName = cur.name;
		var r = Reflect.field(props, setupName);
		if(r == null) {
			r = cur.getDefaults();
			Reflect.setField(props, setupName, r);
		}
		return r;
	}

	public function getMaterials() {
		var mats = findFirstLocal3d().getMaterials();
		var mat = Lambda.find(mats, m -> m.name == this.name || m.name == materialName);
		return mat == null ? mats : [mat];
	}

	function update(mat : h3d.mat.Material, props, loadTexture : String -> h3d.mat.Texture) {
		mat.props = props;
		if(color != null)
			mat.color.setColor(h3d.Vector.fromArray(color).toColor());
		if(mainPassName != null)
			mat.mainPass.setPassName(mainPassName);

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
	}
	
	override function updateInstance(?propName ) {
		var local3d = findFirstLocal3d();
		if( local3d == null )
			return;

		var mats = getMaterials();
		var props = renderProps();
		#if editor
		if ( mats == null || mats.length == 0 ) {
			try {
				var path = hide.Ide.inst.currentConfig.get("material.preview", []);
				var preview = Object3D.modelCache.loadModel(path);
				local3d.parent.addChild(preview);
				local3d = preview;
				local3d.x = local3d.getScene().getMaterials().length * 5.0;
				mats = getMaterials();
			} catch ( e:Dynamic) {

			}
		}
		#end
		for( m in mats )
			update(m, props, loadTexture);
	}

	function loadTexture( path : String ) : h3d.mat.Texture {
		return Object3D.modelCache.loadTexture(null, path, false);
	}

	override function makeInstance(ctx: hrt.prefab2.Prefab.InstanciateParams) {
		updateInstance();
	}

	#if editor
	override function edit( ctx : hide.prefab2.EditContext ) {
		super.edit(ctx);
		var isPbr = Std.isOfType(ctx.scene.s3d.renderer, h3d.scene.pbr.Renderer);
		var mat = h3d.mat.Material.create();
		mat.props = renderProps();
		var group = ctx.properties.add(new hide.Element('<div class="group" name="Material"></div>'));
		ctx.properties.addMaterial(mat, group.find('.group > .content'), function(pname) {
			Reflect.setField(props, h3d.mat.MaterialSetup.current.name, mat.props);
			ctx.onChange(this, "props");
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
			ctx.properties.add(colorMask, this, function(pname) { ctx.onChange(this, pname); });

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
		var materialList = findFirstLocal3d().getMaterials();
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
			ctx.onChange(this, pname);
		});
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

	static var _ = Prefab.register("material", Material);
}