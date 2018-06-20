package hide.prefab;

class Box extends Object3D {


	public function setColor(ctx: Context, color: Int) {
		#if editor
		if(ctx.local3d == null)
			return;
		var mesh = Std.instance(ctx.local3d.getChildAt(0), h3d.scene.Mesh);
		if(mesh != null) {
			setDebugColor(color, mesh.material);
		}
		#end
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);

		var obj = new h3d.scene.Object(ctx.local3d);
		var prim = h3d.prim.Cube.defaultUnitCube();
		var mesh = new h3d.scene.Mesh(prim, obj);
		mesh.setPosition(-0.5, -0.5, -0.5);

		#if editor
		setDebugColor(0x60ff00ff, mesh.material);

		var wire = new h3d.scene.Box(obj);
		wire.color = 0;
		wire.ignoreCollide = true;
		wire.material.shadows = false;
		#end
		
		ctx.local3d = obj;
		ctx.local3d.name = name;
		applyPos(ctx.local3d);
		return ctx;
	}

	#if editor
	static public function setDebugColor(color : Int, mat : h3d.mat.Material) {
		mat.color.setColor(color);
		var opaque = (color >>> 24) == 0xff;
		mat.shadows = false;

		if(opaque) {
			var alpha = mat.getPass("debuggeom_alpha");
			if(alpha != null)
				mat.removePass(alpha);
			mat.mainPass.setPassName("default");
		 	mat.mainPass.setBlendMode(None);
		 	mat.mainPass.depthWrite = true;
			mat.mainPass.culling = None;
		}
		else {
			mat.mainPass.setPassName("debuggeom");
			mat.mainPass.setBlendMode(Alpha);
			mat.mainPass.depthWrite = true;
			mat.mainPass.culling = Front;
			var alpha = mat.allocPass("debuggeom_alpha");
			alpha.setBlendMode(Alpha);
			alpha.culling = Back;
			alpha.depthWrite = false;
		}
	}
	#end

	override function getHideProps() {
		return { icon : "square", name : "Box", fileSource : null };
	}

	static var _ = Library.register("box", Box);
}