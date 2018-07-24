package hide.prefab;


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
		if(parent != null && Type.getClass(parent) == hide.prefab.Object3D) {
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

		var mat = h3d.mat.Material.create();
		mat.props = renderProps();
		var group = ctx.properties.add(new hide.Element('<div class="group" name="Material"></div>'));
		ctx.properties.addMaterial(mat, group.find('.group > .content'), function(pname) {
			Reflect.setField(props, h3d.mat.MaterialSetup.current.name, mat.props);
			ctx.onChange(this, "props");
		});

		var isPbr = Std.is(ctx.scene.s3d.renderer, h3d.scene.pbr.Renderer);
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
		return { icon : "cog", name : "Material", allowParent : function(p) return p.to(Object3D) != null };
	}
	#end

	public static function hasOverride(p: Prefab) {
		if(Lambda.exists(p.children, c -> Std.is(c, Material) && c.enabled))
			return true;
		if(Type.getClass(p.parent) == hide.prefab.Object3D)
			return Lambda.exists(p.parent.children, c -> Std.is(c, Material) && c.enabled);
		return false;
	}

	static var _ = hxd.prefab.Library.register("material", Material);
}