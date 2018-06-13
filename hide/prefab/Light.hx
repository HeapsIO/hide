package hide.prefab;

class Light extends Object3D {
	
	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var obj = new h3d.scene.Object(ctx.local3d);
		ctx.local3d = obj;
		ctx.local3d.name = name;
		applyPos(ctx.local3d);
		return ctx;
	}

	override function getHideProps() {
		return { icon : "sun", name : "Light", fileSource : null };
	}

	static var _ = Library.register("light", Light);
}