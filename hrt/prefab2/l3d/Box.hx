package hrt.prefab2.l3d;

class Box extends Object3D {


    public function setColor(color: Int) {
        #if editor
        if(local3d == null)
            return;
        var mesh = Std.downcast(local3d, h3d.scene.Mesh);
        if(mesh != null) {
            setDebugColor(color, mesh.material);
        }
        #end
    }

    override function makeInstance(ctx: hrt.prefab2.Prefab.InstanciateParams) {
        var mesh = new h3d.scene.Mesh(h3d.prim.Cube.defaultUnitCube(), ctx.local3d);

        #if editor
        setDebugColor(0x60ffffff, mesh.material);

        var wire = new h3d.scene.Box(mesh);
        wire.color = 0;
        wire.ignoreCollide = true;
        wire.material.shadows = false;
        #end

        local3d = mesh;
        local3d.name = name;
        updateInstance();
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

    override function getHideProps() : hide.prefab2.HideProps {
        return { icon : "square", name : "Box" };
    }
    #end

    static var _ = Prefab.register("box", Box);
}