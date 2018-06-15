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
		return {
		};
	}
	
	public function applyProps(renderer: h3d.scene.Renderer) {
		renderer.props = this.props;
		renderer.refreshProps();
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		#if editor
		var renderer = ctx.scene.s3d.renderer;
		var group = new Element('<div class="group" name="Renderer"></div>');
		renderer.editProps().appendTo(group);
		ctx.properties.add(group, props, function(_) {
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