package hide.prefab;

class RenderProps extends Prefab {

	public function new(?parent) {
		super(parent);
		type = "renderProps";
		props = {};
	}

	override function load(o:Dynamic) {
	}

	override function save() {
		return {};
	}

	public function getProps(renderer: h3d.scene.Renderer) {
		var p = Reflect.field(this.props, h3d.mat.MaterialSetup.current.name);
		var defaults = renderer.getDefaultProps();
		function loadProps(from: Dynamic, to: Dynamic) {
			for(field in Reflect.fields(from)) {
				var fromVal = Reflect.field(from, field);
				if(fromVal == null)
					continue;
				var toVal = Reflect.field(to, field);
				if(Type.typeof(fromVal) == TObject) {
					if(toVal == null) {
						toVal = {};
						Reflect.setField(to, field, toVal);
					}
					if(Type.typeof(toVal) == TObject) {
						loadProps(fromVal, toVal);
					}
				}
				else if(toVal == null)
					Reflect.setField(to, field, fromVal);
			}
		}
		if(p == null) {
			p = {};
			Reflect.setField(this.props, h3d.mat.MaterialSetup.current.name, p);
		}
		loadProps(defaults, p);
		return p;
	}

	public function setProps( props : Any ) {
		var name = h3d.mat.MaterialSetup.current.name;
		if( props == null )
			Reflect.deleteField(this.props, name);
		else
			Reflect.setField(this.props, name, props);
	}

	public function applyProps(renderer: h3d.scene.Renderer) {
		var props = getProps(renderer);
		if( props == null )
			return false;
		renderer.props = props;
		renderer.refreshProps();
		return true;
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		#if editor
		var renderer = ctx.scene.s3d.renderer;
		var props = getProps(renderer);
		var needSet = false;
		if( props == null ) {
			props = ctx.ide.parseJSON(ctx.ide.toJSON(renderer.props));
			needSet = true;
		}
		ctx.properties.add(renderer.editProps(), props, function(_) {
			if( needSet ) {
				setProps(props);
				needSet = false;
			}
			applyProps(renderer);
		});
		applyProps(renderer);
		#end
	}

	override function getHideProps() {
		return { icon : "sun-o", name : "RenderProps", fileSource : null };
	}

	static var _ = Library.register("renderProps", RenderProps);
}