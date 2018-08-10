package hide.prefab.l3d;
import h2d.col.Point;

enum Shape {
	Quad;
	Disc(segments: Int, angle: Float, inner: Float, rings:Int);
}

typedef PrimCache = Map<Shape, h3d.prim.Polygon>;

class Polygon extends Object3D {

	var shape : Shape = Quad;

	override function save() {
		var obj : Dynamic = super.save();
		if(shape != Quad) {
			obj.kind = shape.getIndex();
			obj.args = shape.getParameters();
		}
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		if(obj.kind > 0)
			shape = Type.createEnumIndex(Shape, obj.kind, obj.args);
		else
			shape = Quad;
	}

	override function updateInstance( ctx : Context, ?propName : String) {
		super.updateInstance(ctx, propName);
		if(ctx.local3d == null)
			return;

		var mesh : h3d.scene.Mesh = cast ctx.local3d;
		mesh.primitive = makePrimitive();

		if(hide.prefab.Material.hasOverride(this))
			return;

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

	function getPrimCache() {
		var engine = h3d.Engine.getCurrent();
		var cache : PrimCache = @:privateAccess engine.resCache.get(Polygon);
		if(cache == null) {
			cache = new PrimCache();
			@:privateAccess engine.resCache.set(Polygon, cache);
		}
		return cache;
	}

	function makePrimitive() {
		var cache = getPrimCache();
		var primitive : h3d.prim.Polygon = cache.get(shape);
		if(primitive != null)
			return primitive;

		var uvs : Array<Point> = null;
		var points : Array<Point> = null;
		var indices : Array<Int> = null;

		switch(shape) {
			case Quad:
				points = [
					new Point(-0.5, -0.5),
					new Point(0.5, -0.5),
					new Point(0.5,  0.5),
					new Point(-0.5,  0.5)];
				uvs = [for(v in points) new Point(v.y + 0.5, -v.x + 0.5)];  // Setup UVs so that image up (Y) is aligned with forward axis (X)
				indices = [0,1,2,0,2,3];
			case Disc(segments, angle, inner, rings):
				points = [];
				uvs = [];
				indices = [];
				if(angle >= 360)
					angle = 360;
				++segments;
				var anglerad = hxd.Math.degToRad(angle);
				for(i in 0...segments) {
					var t = i / (segments - 1);
					var a = hxd.Math.lerp(-anglerad/2, anglerad/2, t);
					var ct = hxd.Math.cos(a);
					var st = hxd.Math.sin(a);
					for(r in 0...(rings + 2)) {
						var v = r / (rings + 1);
						var r = hxd.Math.lerp(inner, 1.0, v);
						points.push(new Point(ct * r, st * r));
						uvs.push(new Point(t, v));
					}
				}
				for(i in 0...segments-1) {
					for(r in 0...(rings + 1)) {
						var idx = r + i * (rings + 2);
						var nxt = r + (i + 1) * (rings + 2);
						indices.push(idx);
						indices.push(idx + 1);
						indices.push(nxt);
						indices.push(nxt);
						indices.push(idx + 1);
						indices.push(nxt + 1);
					}
				}
			default:
		}

		var verts = [for(p in points) new h3d.col.Point(p.x, p.y, 0.)];
		var idx = new hxd.IndexBuffer(indices.length);
		for(i in indices)
			idx.push(i);
		primitive = new h3d.prim.Polygon(verts, idx);
		primitive.normals = [for(p in points) new h3d.col.Point(0, 0, 1.)];
		primitive.tangents = [for(p in points) new h3d.col.Point(0., 1., 0.)];
		primitive.uvs = [for(uv in uvs) new h3d.prim.UV(uv.x, uv.y)];
		primitive.colors = [for(p in points) new h3d.col.Point(1,1,1)];

		cache.set(shape, primitive);
		return primitive;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var primitive = makePrimitive();
		var mesh = new h3d.scene.Mesh(primitive, ctx.local3d);
		mesh.material.props = h3d.mat.MaterialSetup.current.getDefaults("ui");
		mesh.material.blendMode = Alpha;
		mesh.material.mainPass.culling = None;
		ctx.local3d = mesh;
		ctx.local3d.name = name;
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

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var viewModel = {
			kind: shape.getIndex(),
			segments: 24,
			rings: 4,
			innerRadius: 0.0,
			angle: 360.0
		};

		switch(shape) {
			case Disc(seg, angle, inner, rings):
				viewModel.segments = seg;
				viewModel.angle = angle;
				viewModel.innerRadius = inner;
			default:
		}

		var group = new hide.Element('<div class="group" name="Polygon">
				<dl>
					<dt>Kind</dt><dd>
						<select field="kind">
							<option value="0">Quad</option>
							<option value="1">Disc</option>
						</select>
					</dd>
				</dl>
			</div>
		');

		var discProps = new hide.Element('
			<dt>Segments</dt><dd><input field="segments" type="range" min="0" max="100" step="1" /></dd>
			<dt>Rings</dt><dd><input field="rings" type="range" min="0" max="100" step="1" /></dd>
			<dt>Inner radius</dt><dd><input field="innerRadius" type="range" min="0" max="1" /></dd>
			<dt>Angle</dt><dd><input field="angle" type="range" min="0" max="360" /></dd>');

		group.append(discProps);

		function updateProps() {
			if(viewModel.kind == 1)
				discProps.show();
			else
				discProps.hide();
		}
		updateProps();
		ctx.properties.add(group, viewModel, function(pname) {
			if(pname == "kind") {
				var cache = getPrimCache();
				var prim = cache.get(shape);
				prim.dispose();
				cache.remove(shape);
			}

			switch(viewModel.kind) {
				case 1:
					shape = Disc(viewModel.segments, viewModel.angle, viewModel.innerRadius, viewModel.rings);
				default:
					shape = Quad;
			}
			updateProps();
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Polygon" };
	}

	#end

	static var _ = hxd.prefab.Library.register("polygon", Polygon);
}