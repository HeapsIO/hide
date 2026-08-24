package hrt.prefab;

@:prefabName("Render Profile")
@:prefabIcon(hrt.ui.HuiRes.ui.icons.prefab.render_props)
@:prefabHideInAddMenu
class RenderProfile extends Object3D {
	public var renderProps(get, never) : RenderProps;
	function get_renderProps() {
		return this.getOpt(RenderProps);
	}

	static var _ = Prefab.register("rp", RenderProfile, "rp");
}
