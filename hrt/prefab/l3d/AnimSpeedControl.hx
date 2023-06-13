package hrt.prefab.l3d;

// NOTE(ces) : Not Tested

class AnimSpeedControl extends hrt.prefab.Prefab {

	@:s var speed : Float = 1.;
	var targetLocal3d : h3d.scene.Object = null;

	override function makeInstance():Void {
		targetLocal3d = shared.current3d;
		updateInstance();
	}

	override function updateInstance(?propName) {
		if( targetLocal3d != null && targetLocal3d.currentAnimation != null )
			targetLocal3d.currentAnimation.speed = speed;
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return {
			name : "AnimSpeedCtrl",
			icon : "cog",
			allowParent : (p) -> Std.isOfType(p,Object3D),
		};
	}
	override function edit(ctx:hide.prefab.EditContext) {
		ctx.properties.add(new hide.Element('<dl>
			<dt>Speed</dt><dd><input type="range" field="speed"/></dd>
		</dl>'), this, function(p) {
			ctx.onChange(this, p);
		});
	}
	#end

	static var _ = Prefab.register("animSpeedCtrl", AnimSpeedControl);

}