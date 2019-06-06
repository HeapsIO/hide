package hrt.prefab;

import h3d.mat.PbrMaterial;

class Material extends Prefab {

	public var wrapRepeat = false;
	public var diffuseMap : String;
	public var normalMap : String;
	public var specularMap : String;
	public var color : Array<Float> = [1,1,1,1];

	public function new(?parent) {
		super(parent);
		type = "material";
		props = {};
	}

	override function load(o:Dynamic) {
		if(o.wrapRepeat) wrapRepeat = o.wrapRepeat;
		if(o.diffuseMap != null) diffuseMap = o.diffuseMap;
		if(o.normalMap != null) normalMap = o.normalMap;
		if(o.specularMap != null) specularMap = o.specularMap;
		if(o.color != null) color = o.color;

		// Backward compat
		if(o.props != null && Reflect.hasField(o.props, "PBR")) {
			var pbrProps = Reflect.field(o.props, "PBR");
			for(pname in ["diffuseMap", "normalMap", "specularMap"]) {
				var p : String = Reflect.field(pbrProps, pname);
				if(p != null) {
					Reflect.setField(this, pname, p);
				}
				Reflect.deleteField(pbrProps, pname);
			}
		}
	}

	override function save() {
		var o : Dynamic = {};
		if(wrapRepeat) o.wrapRepeat = true;
		if(diffuseMap != null) o.diffuseMap = diffuseMap;
		if(normalMap != null) o.normalMap = normalMap;
		if(specularMap != null) o.specularMap = specularMap;
		if(color != null && h3d.Vector.fromArray(color).toColor() != 0xffffffff) o.color = color;
		return o;
	}

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

	function updateObject(ctx: Context, obj: h3d.scene.Object) {
		function update(mat : h3d.mat.Material, props) {
			mat.props = props;
			if(color != null)
				mat.color.setColor(h3d.Vector.fromArray(color).toColor());

			inline function getTex(pname: String) {
				var p : String = Reflect.field(this, pname);
				var tex : h3d.mat.Texture = null;
				if(p != null) {
					tex = ctx.loadTexture(p);
					if(tex != null)
						tex.wrap = wrapRepeat ? Repeat : Clamp;
				}
				return tex;
			}

			mat.texture = getTex("diffuseMap");
			mat.normalMap = getTex("normalMap");
			mat.specularTexture = getTex("specularMap");
		}

		var mats = obj.getMaterials();
		var mat = Lambda.find(mats, m -> m.name == this.name);
		var props = renderProps();
		if(mat != null) {
			update(mat, props);
		}
		else {
			for(m in mats)
				update(m, props);
		}
	}

	override function updateInstance(ctx: Context, ?propName) {
		if(ctx.local3d == null)
			return;

		var obj = ctx.local3d;
		if(parent != null && Type.getClass(parent) == Object3D) {
			for(i in 0...obj.numChildren) {
				updateObject(ctx, obj.getChildAt(i));
			}
		}
		else
			updateObject(ctx, obj);
	}

	override function makeInstance(ctx:Context):Context {
		if(ctx.local3d == null)
			return ctx;
		ctx = ctx.clone(this);

		updateInstance(ctx);
		return ctx;
	}

	#if editor
	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		var isPbr = Std.is(ctx.scene.s3d.renderer, h3d.scene.pbr.Renderer);
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

		ctx.properties.add(new hide.Element('<div class="group" name="Overrides">
			<dl>
				<dt>${isPbr ? "Albedo" : "Diffuse"}</dt><dd><input type="texturepath" field="diffuseMap" style="width:165px"/></dd>
				<dt>Normal</dt><dd><input type="texturepath" field="normalMap" style="width:165px"/></dd>
				<dt>Specular</dt><dd><input type="texturepath" field="specularMap" style="width:165px"/></dd>
				<dt>Wrap</dt><dd><input type="checkbox" field="wrapRepeat"/></dd>
				<dt>Color</dt><dd><input type="color" field="color"/></dd>
			</dl></div>'), this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : HideProps {
		return {
			icon : "cog",
			name : "Material",
			allowParent : function(p) return p.to(Object3D) != null,
			onResourceRenamed : function(f) {
				diffuseMap = f(diffuseMap);
				normalMap = f(normalMap);
				specularMap = f(specularMap);
			},
		};
	}
	#end

	public static function hasOverride(p: Prefab) {
		if(Lambda.exists(p.children, c -> Std.is(c, Material) && c.enabled))
			return true;
		if(Type.getClass(p.parent) == Object3D)
			return Lambda.exists(p.parent.children, c -> Std.is(c, Material) && c.enabled);
		return false;
	}

	static var _ = Library.register("material", Material);
}