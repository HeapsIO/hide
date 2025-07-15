package hrt.prefab.l3d;

class SplineMeshSpawnerObject extends h3d.scene.Object {
	var spline : Spline;
	var batches : Array<h3d.scene.MeshBatch> = [];

	override public function new(spline : Spline, parent : h3d.scene.Object) {
		super(parent);
		this.spline = spline;
	}

	public function init() {
		for ( b in batches )
			b.remove();
		batches = [];

		if ( spline == null )
			return;
		var points = spline.points;
		if ( points == null || points.length < 2 )
			return;

		var meshes = findAll(o -> Std.downcast(o, h3d.scene.Mesh));
		for ( mesh in meshes ) {
			var prim = Std.downcast(mesh.primitive, h3d.prim.MeshPrimitive);
			mesh.culled = prim != null;
			if ( prim == null )
				continue;
			var meshRelPos = new h3d.Matrix();
			meshRelPos.multiply3x4inline(mesh.getAbsPos(), this.getAbsPos().getInverse());
			var multi = Std.downcast(mesh, h3d.scene.MultiMaterial);
			var batch = new h3d.scene.MeshBatch(prim, null, this);
			batches.push(batch);
			batch.materials = multi != null ? [for ( m in multi.materials ) m] : [mesh.material];
			batch.worldPosition = new h3d.Matrix();
			batch.begin();

			var primBounds = prim.getBounds();
			var primMin = primBounds.getMin();
			var primMax = primBounds.getMax();
			var primSize = primBounds.getSize();

			var sectionCount = spline.loop ? points.length : points.length-1;
			for ( i in 0...sectionCount ) {
				var from = points[i];
				var to = points[(i+1) % points.length];

				var dist = to.pos.sub(from.pos).length();
				var count = hxd.Math.imax(Math.floor(dist / primSize.x), 1);
				var distPerCount = dist / count;

				for ( j in 0...count ) {
					var dir = to.pos.sub(from.pos).normalized();
					var q = new h3d.Quat();
					q.initDirection(dir, from.up);
					var matRot = q.toMatrix();

					batch.worldPosition.identity();
					batch.worldPosition.load(meshRelPos);
					var scale = distPerCount / primSize.x;
					batch.worldPosition.translate(-primMin.x, 0.0, 0.0);
					batch.worldPosition.scale(scale);
					batch.worldPosition.multiply3x4inline(batch.worldPosition, matRot);
					var start = new h3d.Vector();
					start.lerp(from.pos, to.pos, j/count);
					batch.worldPosition.translate(start.x, start.y, start.z);
					batch.worldPosition.multiply3x4(batch.worldPosition, getAbsPos());
					batch.emitInstance();
				}
			}
		}

	}
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