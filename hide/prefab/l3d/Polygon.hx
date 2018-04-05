package hide.prefab.l3d;
import h3d.col.Point;

class Polygon extends Object3D {

	var data : Array<Float> = null;
	var mesh : h3d.scene.Mesh = null;

	override function save() {
		var obj : Dynamic = super.save();
		obj.data = data;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		data = obj.data;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
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
		var prim = new h3d.prim.Polygon(verts, cast indices);
		var n = new h3d.col.Point(0, 0, 1.);
		prim.normals = [for(p in points) n];

		var obj = new h3d.scene.Object(ctx.local3d);
		mesh = new h3d.scene.Mesh(prim, obj);
		var mat = mesh.material;
		mat.color.setColor(0x40ff00ff);
		mat.mainPass.culling = None;
		mat.mainPass.setPassName("ground");
		mat.mainPass.setBlendMode(Alpha);
		mat.mainPass.depthWrite = true;

		var alpha = mat.allocPass("ground_alpha");
		alpha.setBlendMode(Alpha);
		alpha.depthWrite = false;
		mat.shadows = false;
		ctx.local3d = obj;
		ctx.local3d.name = name;
		applyPos(ctx.local3d);
		return ctx;
	}

	override function getHideProps() {
		return { icon : "square", name : "Polygon", fileSource : null };
	}

	static var _ = Library.register("polygon", Polygon);
}