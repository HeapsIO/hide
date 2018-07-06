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

	public function getProps() {
		return Reflect.field(this.props, h3d.mat.MaterialSetup.current.name);
	}

	public function setProps( props : Any ) {
		var name = h3d.mat.MaterialSetup.current.name;
		if( props == null )
			Reflect.deleteField(this.props, name);
		else
			Reflect.setField(this.props, name, props);
	}

	public function applyProps(renderer: h3d.scene.Renderer) {
		var props = getProps();
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
		var props = getProps();
		var needSet = false;
		if( props == null ) {
			props = ctx.ide.parseJSON(ctx.ide.toJSON(renderer.props));
			needSet = true;
		}
		ctx.properties.add(renderer.editProps(), props, function(_) {
			applyProps(renderer);
			if( needSet ) {
				setProps(props);
				needSet = false;
			}
		});
		applyProps(renderer);
		#end
	}

	override function getHideProps() {
		return { icon : "sun-o", name : "RenderProps", fileSource : null };
	}

	static var _ = Library.register("renderProps", RenderProps);
}