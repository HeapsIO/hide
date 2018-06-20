package hide.prefab;


class Material extends Prefab {

	public function new(?parent) {
		super(parent);
		props = {};
	}
	
	override function load(o:Dynamic) {
	}

	override function save() {
		return {
		};
	}

	function renderProps() {
		var cur = h3d.mat.MaterialSetup.current;
		var setupName = cur.name;
		var r = Reflect.field(props, setupName);
		if(r == null) {
			r = {};
			Reflect.setField(props, setupName, r);
		}
		return r;
	}

	function updateInstance(ctx: Context) {
		if(ctx.local3d == null)
			return;

		inline function update(mat : h3d.mat.Material, props) {
			mat.props = props;
			var diff : String = Reflect.field(props, "diffuseMap");
			if(diff != null) {
				mat.texture = ctx.loadTexture(diff);
			}
		}

		var mats = ctx.local3d.getMaterials();
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

	override function makeInstance(ctx:Context):Context {
		if(ctx.local3d == null)
			return ctx;
		ctx = ctx.clone(this);

		updateInstance(ctx);
		return ctx;
	}

	override function edit( ctx : EditContext ) {
		#if editor		
		super.edit(ctx);

		var mat = h3d.mat.Material.create();
		mat.props = renderProps();
		var group = ctx.properties.add(new hide.Element('<div class="group" name="Material"></div>'));
		ctx.properties.addMaterial(mat, group.find('.group > .content'), function(pname) {
			Reflect.setField(props, h3d.mat.MaterialSetup.current.name, mat.props);
			ctx.onChange(this, "props");
			var inst = ctx.getContext(this);
			if(inst != null)
				updateInstance(inst);
		});

		var isPbr = Std.is(ctx.scene.s3d.renderer, h3d.scene.pbr.Renderer);
		ctx.properties.add(new hide.Element('<div class="group" name="Overrides">
			<dl>
				<dt>${isPbr ? "Albedo" : "Diffuse"}</dt><dd><input type="texturepath" field="diffuseMap" style="width:165px"/></dd>
				<dt>Normal</dt><dd><input type="texturepath" field="normalMap" style="width:165px"/></dd>
				<dt>Specular</dt><dd><input type="texturepath" field="specularMap" style="width:165px"/></dd>
			</dl></div>'), renderProps(), function(_) {
			ctx.onChange(this, "props");
			var inst = ctx.getContext(this);
			if(inst != null)
				updateInstance(inst);
		});
		#end
	}

	override function getHideProps() : HideProps {
		return { icon : "cog", name : "Material" };
	}

	static var _ = Library.register("material", Material);
}