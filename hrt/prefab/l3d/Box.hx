package hrt.prefab.l3d;

class Box extends Object3D {


	public function setColor(ctx: Context, color: Int) {
		#if editor
		if(ctx.local3d == null)
			return;
		var mesh = Std.downcast(ctx.local3d, h3d.scene.Mesh);
		if(mesh != null) {
			setDebugColor(color, mesh.material);
		}
		#end
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);

		var mesh = new h3d.scene.Mesh(h3d.prim.Cube.defaultUnitCube(), ctx.local3d);

		#if editor
		setDebugColor(0x60ffffff, mesh.material);

		var wire = new h3d.scene.Box(mesh);
		wire.color = 0;
		wire.ignoreCollide = true;
		wire.material.shadows = false;
		#end

		ctx.local3d = mesh;
		ctx.local3d.name = name;
		updateInstance(ctx);
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

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Box" };
	}
	#end

	static var _ = Library.register("box", Box);
}