package hide.prefab;

class Scene extends Prefab {

	override function load(obj:Dynamic) {
	}

	override function save() {
		return {};
	}

	override function makeInstance( ctx : Context ) {
		#if editor
		var scene = hide.comp.Scene.getCurrent();
		var obj = scene.loadModel(source, true);
		var cam = @:privateAccess scene.defaultCamera;

		// allow to add sub elements relative to camera target
		var root = new h3d.scene.Object(ctx.local3d);
		root.x = cam.target.x;
		root.y = cam.target.y;
		root.z = cam.target.z;
		obj.x -= root.x;
		obj.y -= root.y;
		obj.z -= root.z;
		root.addChild(obj);

		ctx = ctx.clone(this);
		ctx.local3d = root;
		#end
		return ctx;
	}

	#if editor
	override function getHideProps() : HideProps {
		return { icon : "cube", name : "Scene", fileSource : ["hsd"] };
	}
	#end

	static var _ = hxd.prefab.Library.register("scene", Scene);

}