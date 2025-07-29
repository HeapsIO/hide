package hrt.prefab.rfx;

class RendererFX extends Prefab implements h3d.impl.RendererFX {

	@:s var enableInEditor = true;

	var instance : RendererFX;

	public function start( r : h3d.scene.Renderer ) {
	}

	public function begin( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
	}

	public function end( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
	}

	public function transition( r1 : h3d.impl.RendererFX, r2 : h3d.impl.RendererFX ) : h3d.impl.RendererFX.RFXTransition {
		var rfx1 = Std.downcast(r1, RendererFX);
		if (rfx1.instance == null)
			rfx1.make();

		var rfx2 = Std.downcast(r2, RendererFX);
		if (rfx2.instance == null)
			rfx2.make();

		return { effect : rfx2, setFactor : (f : Float) -> {} };
	}

	public function modulate( t : Float ) : h3d.impl.RendererFX {
		if (this.instance == null)
			this.make();
		return this.instance;
	}

	inline function checkEnabled() {
		return enabled #if editor && enableInEditor && !inGameOnly #end;
	}

	override public function make( ?sh:hrt.prefab.Prefab.ContextMake ) : Prefab {
		instance = cast this.clone();
		// unlink this.props and instance.props for ScreenShaderGraph
		// because props is cloned by ref
		instance.props = {};

		if (!shouldBeInstanciated())
			return this;

		makeInstance();
		for (c in children)
			makeChild(c);
		postMakeInstance();
		updateInstance();

		return this;
	}

	override function updateInstance(?propName : String) {
		if (instance != null) {
			if (propName != null && propName != "props") {
				Reflect.setField(instance, propName, Reflect.field(this, propName));
				return;
			}

			for (f in Reflect.fields(this)) {
				if (f != "props")
					Reflect.setField(instance, f, Reflect.field(this, f));
			}
		}
	}

	override function dispose() {
		if (this.instance != null) {
			var scene = this.instance.shared.root3d?.getScene();

			if(scene != null)
				scene.renderer.effects.remove(this.instance);

			var i = this.instance;
			this.instance = null;
			i.dispose();
		}

		super.dispose();
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return { name : Type.getClassName(Type.getClass(this)).split(".").pop(), icon : "plus-circle" };
	}

	override function edit(ctx:hide.prefab.EditContext) {
		ctx.properties.add(new hide.Element('
		<dl>
			<dt>Enable in Hide</dt><dd><input type="checkbox" field="enableInEditor"/></dd>
		</dl>
		'), this);
	}
	#end

}