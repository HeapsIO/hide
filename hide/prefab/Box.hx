package hide.prefab;

class Box extends Object3D {

    var mesh : h3d.scene.Mesh = null;
    
    public function setColor(col: Int) {
        if(mesh != null) {
            mesh.material.color.setColor(col | (80 << 24));
        }
    }

	override function makeInstance(ctx:Context):Context {
        ctx = ctx.clone(this);

        var obj = new h3d.scene.Object(ctx.local3d);
        var prim = h3d.prim.Cube.defaultUnitCube();
        mesh = new h3d.scene.Mesh(prim, obj);
        var mat = mesh.material;
		mat.color.setColor(0x60ff00ff);
        mat.mainPass.depthWrite = false;
        mat.mainPass.setPassName("alpha");
        mat.shadows = false;
        mat.blendMode = Alpha;

        var wire = new h3d.scene.Box(obj);
        wire.color = 0;
        wire.ignoreCollide = true;
        wire.setPos(0.5, 0.5, 0.5);

		ctx.local3d = obj;
		ctx.local3d.name = name;
		applyPos(ctx.local3d);
		return ctx;
	}

    override function getHideProps() {
		return { icon : "square", name : "Box", fileSource : null };
	}

	static var _ = Library.register("box", Box);
}