package hrt.prefab.l3d;

/**
	Alias of Object for compatibility with the old prefab system
**/
@:deprecated("Use hrt.prefab.Library instead")
class Level3D extends Object3D
{
	override function edit2(ctx:hrt.prefab.EditContext2) {
		super.edit2(ctx);
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "sitemap", name : "Level3D", allowParent: _ -> false};
	}
	#end

	public static var _ = Prefab.register("level3d", Level3D, "l3d");
}