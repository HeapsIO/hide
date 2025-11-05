package prefab;

class DemoObject extends h3d.scene.Mesh {

    public var speed : Float;
    override function emit(ctx) {
        super.emit(ctx);
        rotate(0.0, 0.0, speed * ctx.elapsedTime);
    }
}

class Demo extends hrt.prefab.Object3D {

    @:s var speed : Float = 10.0;

    override function makeObject(parent : h3d.scene.Object) {
        return new DemoObject(h3d.prim.Cube.defaultUnitCube(), null, parent);
    }

    override function updateInstance(?propName) {
        super.updateInstance(propName);
        var prefab = cast(local3d, DemoObject);
        prefab.speed = speed;
    }

    #if editor
    override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Params">
				<dl>
					<dt>Speed :)</dt><dd><input type="range" min="0" field="speed"></dd>
				</dl>
			</div>
		'),this, function (pname)
            ctx.onChange(this, pname)
        );
    }
    #end

    static var _ = hrt.prefab.Prefab.register("demo", Demo);
}
