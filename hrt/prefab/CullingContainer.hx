package hrt.prefab;

class CullingContainerObject extends h3d.scene.Object {
	public var cullDistanceSq : Float;
	public var forceVisible : Bool = false;

	override function syncRec( ctx : h3d.scene.RenderContext  ) {
		var containerPos = getAbsPos().getPosition();
		var d = containerPos.distanceSq(ctx.camera.pos);

		visible = forceVisible || d < cullDistanceSq;
		super.syncRec(ctx);
	}
}

class CullingContainer extends Object3D {
	@:s var cullDistance : Float = 100;

	#if editor
	var prim : h3d.prim.Primitive;
	var m : h3d.scene.Mesh;
	#end

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		var obj = new CullingContainerObject(parent3d);
		obj.name = "CullingContainer";
		obj.cullDistanceSq = cullDistance * cullDistance;
		#if editor
		obj.forceVisible = true;
		#end
		return obj;
	}

	#if editor
	function createDebugSphere() {
		prim = new h3d.prim.GeoSphere(2);
		m = new h3d.scene.Mesh(prim, null, this.local3d.parent);
		m.x = x;
		m.y = y;
		m.z = z;
		m.setScale(cullDistance);
		m.name = "debugWireframe";
		m.material.name = "$collider";
		m.material.mainPass.wireframe = true;
		m.material.mainPass.culling = None;
		m.material.castShadows = false;
		m.material.color.setColor(0xFFFFFFFF);
		m.material.mainPass.setPassName("afterTonemapping");
	}

	override function setSelected(b:Bool):Bool {
		var obj = Std.downcast(this.local3d, CullingContainerObject);
		super.setSelected(b);
		if(b){
			obj.forceVisible = false;
			createDebugSphere();
		} else {
			obj.forceVisible = true;
			prim.dispose();
			m.remove();
		}
		return b;
	}

	override function updateInstance(?propName : String) {
		super.updateInstance(propName);
		if(m != null){
			m.x = x;
			m.y = y;
			m.z = z;
			m?.setScale(cullDistance);
		}
		var obj = Std.downcast(this.local3d, CullingContainerObject);
		if(obj != null) {
			obj.cullDistanceSq = cullDistance * cullDistance;
		}
	}
	#end

	override function edit2( ctx : EditContext2 ) {
		super.edit2(ctx);
		ctx.build(
			<root>
				<slider min={0.0} field={cullDistance} />
			</root>
		);
	}

	static var _ = Prefab.register("CullingContainer", CullingContainer);
}