package hrt.prefab.l3d;

class AnimSpeedControl extends hrt.prefab.Prefab {

	@:s var speed : Float = 1.;

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance(ctx:Context,?propName) {
		if( ctx.local3d != null && ctx.local3d.currentAnimation != null )
			ctx.local3d.currentAnimation.speed = speed;
	}

	#if editor
	override function getHideProps() : HideProps {
		return {
			name : "AnimSpeedCtrl",
			icon : "cog",
			allowParent : (p) -> Std.isOfType(p,Object3D),
		};
	}
	override function edit(ctx:EditContext) {
		ctx.properties.add(new Element('<dl>
			<dt>Speed</dt><dd><input type="range" field="speed"/></dd>
		</dl>'), this, function(p) {
			ctx.onChange(this, p);
		});
	}
	#end

	static var _ = Library.register("animSpeedCtrl", AnimSpeedControl);

}