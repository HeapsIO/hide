package hrt.prefab2.l3d;

// NOTE(ces) : Not Tested

class AnimSpeedControl extends hrt.prefab2.Prefab {

	@:s var speed : Float = 1.;
    var targetLocal3d : h3d.scene.Object = null;

	override function makeInstance(ctx: hrt.prefab2.Prefab.InstanciateContext):Void {
		targetLocal3d = ctx.local3d;
        updateInstance();
	}

	override function updateInstance(?propName) {
		if( targetLocal3d != null && targetLocal3d.currentAnimation != null )
			targetLocal3d.currentAnimation.speed = speed;
	}

	#if editor
	override function getHideProps() : hide.prefab2.HideProps {
		return {
			name : "AnimSpeedCtrl",
			icon : "cog",
			allowParent : (p) -> Std.isOfType(p,Object3D),
		};
	}
	override function edit(ctx:hide.prefab2.EditContext) {
		ctx.properties.add(new hide.Element('<dl>
			<dt>Speed</dt><dd><input type="range" field="speed"/></dd>
		</dl>'), this, function(p) {
			ctx.onChange(this, p);
		});
	}
	#end

	static var _ = Prefab.register("animSpeedCtrl", AnimSpeedControl);

}