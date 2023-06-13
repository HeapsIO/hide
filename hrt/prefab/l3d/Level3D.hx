package hrt.prefab.l3d;

/**
	Alias of Object for compatibility with the old prefab system
**/
@:deprecated("Use hrt.prefab.Library instead")
class Level3d extends Object3D
{
	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "sitemap", name : "Level3D", allowParent: _ -> false};
	}
	#end

	public static var _ = Prefab.register("level3d", Level3d);
}