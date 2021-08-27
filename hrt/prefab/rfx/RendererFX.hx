package hrt.prefab.rfx;

class RendererFX extends Prefab implements h3d.impl.RendererFX {

	@:s var enableInEditor = true;

	public function begin( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
	}

	public function end( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
	}

	public function dispose() {
	}

	override function load(obj:Dynamic) {
		if( obj.props != null ) {
			// backward compatibility : copy all props to object
			for( f in Reflect.fields(obj.props) )
				Reflect.setField(obj, f, Reflect.field(obj.props,f));
			Reflect.deleteField(obj,"props");
		}
		super.load(obj);
	}

	inline function checkEnabled() {
		return enabled #if editor && enableInEditor #end;
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return { name : Type.getClassName(Type.getClass(this)).split(".").pop(), icon : "plus-circle" };
	}
	override function edit(ctx:EditContext) {
		ctx.properties.add(new hide.Element('
		<dl>
			<dt>Enable in Hide</dt><dd><input type="checkbox" field="enableInEditor"/></dd>
		</dl>
		'), this);
	}
	#end

}