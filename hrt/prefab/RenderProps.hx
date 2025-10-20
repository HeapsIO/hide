package hrt.prefab;

class RenderPropsObject extends h3d.scene.Object {

}

class RenderProps extends Object3D {

	@:s var isDefault = false;

	public function new(parent, shared: ContextShared) {
		super(parent, shared);
		props = {};
	}

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		return new RenderPropsObject(parent3d);
	}

	#if editor
	override function postMakeInstance() {
		super.postMakeInstance();

		// force the refresh of the renderProps
		shared.editor?.queueRefreshRenderProps();
	}
	#end

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
			if ( fx != null )
				fx.dispose();

		renderer.effects = [];
		for (v in findAll(hrt.prefab.rfx.RendererFX, true)) {
			if (!v.enabled) continue;

			if (@:privateAccess v.instance != null) {
				renderer.effects.push(@:privateAccess v.instance);
				continue;
			}

			renderer.effects.push(v);
		}

		if (shared.root3d != null) {
			var scene = shared.root3d.getScene();
			if (scene != null) {
				var fxAnims = scene.findAll(f -> Std.downcast(f, hrt.prefab.fx.FX.FXAnimation));
				for (fxAnim in fxAnims) {
					var visible = true;
					var p : h3d.scene.Object = fxAnim;
					while (p != null) {
						if (!p.visible) {
							visible = false;
							break;
						}
						p = p.parent;
					}

					if (fxAnim.effects == null || visible == false)
						continue;
					for (e in fxAnim.effects) {
						if (@:privateAccess e.instance == null)
							continue;
						renderer.effects.push(cast @:privateAccess e.instance);
					}
				}
			}
		}

		var env = getOpt(hrt.prefab.l3d.Environment);
		if( env != null )
			env.applyToRenderer(renderer);
		// #if editor
		// else {
		// 	var r = Std.downcast(renderer, h3d.scene.pbr.Renderer);
		// 	if( r != null )
		// 		r.env = hide.Renderer.PbrSetup.getEnvMap();
		// }
		// #end
		renderer.refreshProps();
		return true;
	}

	#if editor
	override function updateInstance(?propName:String) {
		super.updateInstance(propName);
		if (propName == "visible") {
			shared.editor?.queueRefreshRenderProps();
		}
	}

	override function editorRemoveInstanceObjects() {
		shared.editor?.queueRefreshRenderProps();
	}

	override function edit(ctx) {
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
			shared.editor?.queueRefreshRenderProps();
		});
		ctx.properties.add(new hide.Element('<dl><dt>Make Default</dt><dd><input type="checkbox" field="isDefault"/></dd></dl>'), this, (_) -> {
			shared.editor?.queueRefreshRenderProps();
		});
		shared.editor?.queueRefreshRenderProps();
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "sun-o", name : "RenderProps", allowChildren : function(p) {
			return Prefab.isOfType(p,hrt.prefab.rfx.RendererFX)
				|| Prefab.isOfType(p,Light)
				|| Prefab.isOfType(p,hrt.prefab.l3d.Environment);
		}};
	}

	#end

	static var _ = Prefab.register("renderProps", RenderProps);
}