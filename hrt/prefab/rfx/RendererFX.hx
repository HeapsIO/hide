package hrt.prefab.rfx;

class RendererFX extends Prefab implements h3d.impl.RendererFX {

	var enableInEditor = true;

	public function begin( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
	}

	public function end( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
	}

	override function save() {
		var obj : Dynamic = {};
		if( !enableInEditor ) obj.enableInEditor = false;
		return obj;
	}

	override function load(v:Dynamic) {
		enableInEditor = v.enableInEditor != false;
	}

	public function dispose() {
	}

	inline function checkEnabled() {
		#if editor
		return enableInEditor;
		#else
		return true;
		#end
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