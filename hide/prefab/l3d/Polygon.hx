package hide.prefab.l3d;
import h3d.col.Point;

class Polygon extends Object3D {

	var data : Array<Float> = null;
	var primitive : h3d.prim.Polygon;  // TODO: When to dispose? https://github.com/HeapsIO/heaps/issues/336

	override function save() {
		var obj : Dynamic = super.save();
		if(data != null) obj.data = data;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		data = obj.data;
	}

	override function updateInstance( ctx : Context, ?propName : String) {
		super.updateInstance(ctx, propName);
		if(ctx.local3d == null)
			return;

		if(hide.prefab.Material.hasOverride(this))
			return;

		var mesh : h3d.scene.Mesh = cast ctx.local3d;
		var mat = mesh.material;
		mat.mainPass.culling = None;

		var layer = getParent(Layer);
		if(layer != null) {
			setColor(ctx, layer != null ? (layer.color | 0x40000000) : 0x40ff00ff);
		}
		else {
			mat.props = h3d.mat.MaterialSetup.current.getDefaults("opaque");
			mat.color.setColor(0xffffffff);
		}

		mat.castShadows = false;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);

		if(primitive == null) {
			var points = [];
			var d = this.data;
			if(d == null) {
				d = [-0.5, -0.5,
					0.5, -0.5,
					0.5,  0.5,
					-0.5,  0.5];
			}
			var npts = Std.int(d.length / 2);
			for(i in 0...npts) {
				var x = d[(i<<1)];
				var y = d[(i<<1) + 1];
				var vert = new h2d.col.Point(x, y);
				points.push(vert);
			}
			var poly2d = new h2d.col.Polygon(points);
			var indices = poly2d.fastTriangulate();
			var verts = [for(p in points) new h3d.col.Point(p.x, p.y, 0.)];
			var idx = new hxd.IndexBuffer(indices.length);
			for(i in indices)
				idx.push(i);
			primitive = new h3d.prim.Polygon(verts, idx);
			primitive.normals = [for(p in points) new h3d.col.Point(0, 0, 1.)];
			primitive.tangents = [for(p in points) new h3d.col.Point(0., 1., 0.)];
			primitive.uvs = [for(p in points) new h3d.prim.UV(p.y + 0.5, -p.x + 0.5)];  // Setup UVs so that image up (Y) is aligned with forward axis (X)
			primitive.colors = [for(p in points) new h3d.col.Point(1,1,1)];
		}

		var mesh = new h3d.scene.Mesh(primitive, ctx.local3d);
		mesh.material.props = h3d.mat.MaterialSetup.current.getDefaults("ui");
		mesh.material.blendMode = Alpha;
		mesh.material.mainPass.culling = None;
		ctx.local3d = mesh;
		ctx.local3d.name = name;
		applyPos(ctx.local3d);
		updateInstance(ctx);
		return ctx;
	}

	function setColor(ctx: Context, color: Int) {
		#if editor
		if(hide.prefab.Material.hasOverride(this))
			return;
		if(ctx.local3d == null)
			return;
		var mesh = Std.instance(ctx.local3d, h3d.scene.Mesh);
		if(mesh != null) {
			hide.prefab.Box.setDebugColor(color, mesh.material);
		}
		#end
	}

	#if editor

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Polygon" };
	}

	#end

	static var _ = hxd.prefab.Library.register("polygon", Polygon);
}