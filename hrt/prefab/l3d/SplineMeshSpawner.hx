package hrt.prefab.l3d;

class SplineMeshSpawnerObject extends h3d.scene.Object {
	var spline : Spline;
	var batches : Array<h3d.scene.MeshBatch> = [];

	override public function new(spline : Spline, parent : h3d.scene.Object) {
		super(parent);
		this.spline = spline;
	}

	public function getInstances() {
		if ( spline == null )
			return [];
		var points = spline.points;
		if ( points == null || points.length < 2 )
			return [];

		var meshes = findAll(o -> Std.downcast(o, h3d.scene.Mesh));

		var instances : Array<InstanceData> = [];
		for ( mesh in meshes ) {
			var prim = Std.downcast(mesh.primitive, h3d.prim.HMDModel);
			mesh.culled = prim != null;
			if ( prim == null )
				continue;
			var positions = [];
			instances.push({mesh : mesh, path : @:privateAccess prim.lib.resource.entry.path, positions : positions});
			var meshRelPos = new h3d.Matrix();
			meshRelPos.multiply3x4inline(mesh.getAbsPos(), this.getAbsPos().getInverse());

			var primBounds = prim.getBounds();
			var primMin = primBounds.getMin();
			var primMax = primBounds.getMax();
			var primSize = primBounds.getSize();

			var splineLength = spline.getSplineLength();
			var count = hxd.Math.imax(Math.floor(splineLength / primSize.x), 1);

			var prevPos = spline.localToGlobal(spline.getPoint(0.0));
			for ( i in 0...count ) {
				var t = (i+1) / count;
				var toPos = spline.localToGlobal(spline.getPoint(t));

				var dir = toPos.sub(prevPos).normalized();
				var q = new h3d.Quat();
				q.initDirection(dir, new h3d.Vector(0.0, 0.0, 1.0));
				var matRot = q.toMatrix();

				var instanceAbsPos = h3d.Matrix.I();
				instanceAbsPos.load(meshRelPos);
				var scale = toPos.sub(prevPos).length() / primSize.x;
				instanceAbsPos.translate(-primMin.x, 0.0, 0.0);
				instanceAbsPos.scale(scale);
				instanceAbsPos.multiply3x4inline(instanceAbsPos, matRot);
				instanceAbsPos.translate(prevPos.x, prevPos.y, prevPos.z);
				instanceAbsPos.multiply3x4(instanceAbsPos, getAbsPos());
				positions.push(instanceAbsPos);

				prevPos = toPos;
			}
		}

		return instances;
	}

	public function init() {
		for ( b in batches )
			b.remove();
		batches = [];

		var instances = getInstances();
		if ( instances == null )
			return;
		for ( meshInstances in instances ) {
			var mesh = meshInstances.mesh;
			var prim = cast(mesh.primitive, h3d.prim.HMDModel);
			var multi = Std.downcast(mesh, h3d.scene.MultiMaterial);
			var batch = new h3d.scene.MeshBatch(prim, null, this);
			batches.push(batch);
			batch.materials = multi != null ? [for ( m in multi.materials ) m] : [mesh.material];
			batch.worldPosition = new h3d.Matrix();
			batch.begin();

			for ( pos in meshInstances.positions ) {
				batch.worldPosition.load(pos);
				batch.emitInstance();
			}
		}
	}
}

typedef InstanceData = {
	var positions : Array<h3d.Matrix>;
	var mesh : h3d.scene.Mesh;
	var path : String;
}

class SplineMeshSpawner extends hrt.prefab.Object3D {

	var spline(get, default) : Spline = null;
	function get_spline() {
		if ( spline == null )
			spline = findParent(Spline, null, false, true);
		return spline;
	}

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		return new SplineMeshSpawnerObject(spline, parent3d);
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);

		if ( spline != null && spline.samples != null )
			init();
	}

	override function postMakeInstance() {
		super.postMakeInstance();
		init();
	}

	function init() {
		if ( local3d != null )
			cast(local3d, SplineMeshSpawnerObject).init();
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);

		var props = new hide.Element('
			<div class="group" name="Preview">
				<dl>
					<dt>Points</dt><dd><input type="range" min="4" max="64" step="1" field="previewPointCount"/></dd>
					<dt>Radius</dt><dd><input type="range" min="1" max="10" field="previewRadius"/></dd>
				</dl>
			</div>
			');

		props.find(".refresh").click(function(_) { ctx.onChange(this, null); });
		ctx.properties.add(props, this, function(pname) { ctx.onChange(this, pname); });
	}

	override function getHideProps() : hide.prefab.HideProps {
		return {
			icon : "arrows-v",
			name : "SplineMeshSpawner",
			allowParent : (p) -> Std.isOfType(p, Spline) || p.parent == null,
			onChildUpdate : (p) -> init(),
		};
	}
	#end

	static var _ = hrt.prefab.Prefab.register("splineMeshSpawner", SplineMeshSpawner);
}