package hrt.prefab;

class RenderPropsObject extends h3d.scene.Object {

}

class RenderProps extends Prefab {

	@:s var isDefault = false;

	public function new(?parent) {
		super(parent);
		type = "renderProps";
		props = {};
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		ctx.local3d = new RenderPropsObject(ctx.local3d);
		ctx.local3d.name = name;
		updateInstance(ctx);
		return ctx;
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
		for(fx in renderer.effects)
			fx.dispose();
		renderer.effects = [for( v in getAll(hrt.prefab.rfx.RendererFX,true) ) v];
		var env = getOpt(hrt.prefab.l3d.Environment);
		if( env != null )
			env.applyToRenderer(renderer);
		renderer.refreshProps();
		return true;
	}

	#if editor

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
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
		ctx.properties.add(new Element('<dl><dt>Make Default</dt><dd><input type="checkbox" field="isDefault"/></dd></dl>'), this);
		applyProps(renderer);
	}

	override function getHideProps() : HideProps {
		return { icon : "sun-o", name : "RenderProps", allowChildren : function(t) {
			return Library.isOfType(t,hrt.prefab.rfx.RendererFX)
				|| Library.isOfType(t,Light)
				|| Library.isOfType(t,hrt.prefab.l3d.Environment);
		}};
	}

	#end

	static var _ = Library.register("renderProps", RenderProps);
}