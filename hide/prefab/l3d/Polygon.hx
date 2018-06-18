package hide.prefab.l3d;
import h3d.col.Point;

class Polygon extends Object3D {

	var data : Array<Float> = null;
	public var diffuseMap : String;
	public var normalMap : String;
	public var specularMap : String;
	
	override function save() {
		var obj : Dynamic = super.save();
		if(data != null) obj.data = data;
		if(diffuseMap != null) obj.diffuseMap = diffuseMap;
		if(normalMap != null) obj.normalMap = normalMap;
		if(specularMap != null) obj.specularMap = specularMap;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		data = obj.data;
		diffuseMap = obj.diffuseMap;
		normalMap = obj.normalMap;
		specularMap = obj.specularMap;
	}

	public function applyProps(ctx: Context) { // Idea: make common to all Prefabs
		if(ctx.local3d == null)
			return;
		var mesh : h3d.scene.Mesh = cast ctx.local3d;
		var mat = mesh.material;
		mat.mainPass.culling = None;
		mat.shadows = false;

		if(diffuseMap == null || diffuseMap.length == 0) {
			var layer = getParent(Layer);
			setColor(ctx, layer != null ? (layer.color | 0x40000000) : 0x40ff00ff);
		}
		else {
			setColor(ctx, 0xffffffff);

			inline function getTex(path: String) {
				var t = path != null && path.length > 0 ? ctx.loadTexture(path) : null;
				if(t != null)
					t.wrap = Repeat;
				return t;
			}
			mat.texture = getTex(diffuseMap);
			mat.normalMap = getTex(normalMap);
			mat.specularTexture = getTex(specularMap);
		}
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var layer = getParent(Layer);
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
		prim.uvs = [for(p in points) new h3d.prim.UV(p.x, p.y)];
		prim.colors = [for(p in points) new h3d.col.Point(1,1,1)];

		var mesh = new h3d.scene.Mesh(prim, ctx.local3d);
		ctx.local3d = mesh;
		ctx.local3d.name = name;
		applyPos(ctx.local3d);
		applyProps(ctx);
		return ctx;
	}

	function setColor(ctx: Context, color: Int) {
		#if editor
		if(ctx.local3d == null)
			return;
		var mesh = Std.instance(ctx.local3d, h3d.scene.Mesh);
		if(mesh != null) {
			hide.prefab.Box.setDebugColor(color, mesh.material);
		}
		#end
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		#if editor
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Polygon">
				<dl>
					<dt>Diffuse</dt><dd><input type="texturepath" field="diffuseMap" style="width:165px"/></dd>
					<dt>Normal</dt><dd><input type="texturepath" field="normalMap" style="width:165px"/></dd>
					<dt>Specular</dt><dd><input type="texturepath" field="specularMap" style="width:165px"/></dd>
				</dl>
			</div>
		'),this, function(pname) {
			ctx.onChange(this, pname);
			applyProps(ctx.getContext(this));
		});
		#end
	}

	override function getHideProps() {
		return { icon : "square", name : "Polygon", fileSource : null };
	}

	static var _ = Library.register("polygon", Polygon);
}