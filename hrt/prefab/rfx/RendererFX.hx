package hrt.prefab.rfx;

class RendererFX extends Prefab implements h3d.impl.RendererFX {

	public function begin( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
	}

	public function end( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
	}

	override function save() {
		return {};
	}

	override function load(v:Dynamic) {
	}

	public function dispose() {
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return { name : Type.getClassName(Type.getClass(this)).split(".").pop(), icon : "plus-circle" };
	}
	#end

}