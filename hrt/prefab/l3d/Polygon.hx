package hrt.prefab.l3d;
import h2d.col.Point;

enum Shape {
	Quad;
	Disc(segments: Int, angle: Float, inner: Float, rings:Int);
	Custom;
}

typedef PrimCache = Map<Shape, h3d.prim.Polygon>;

class Polygon extends Object3D {

	public var shape(default, null) : Shape = Quad;
	public var points : h2d.col.Polygon;
	#if editor
	public var debugColor : Int = 0xFFFFFFFF;
	public var editor : hide.prefab.PolygonEditor;
	public var cachedPrim : h3d.prim.Polygon;
	var prevScale = [1.0, 1.0];
	#end

	override function save() {
		var obj : Dynamic = super.save();
		switch(shape){
			case Quad:
			case Disc(segments, angle, inner, rings):
				obj.kind = shape.getIndex();
				obj.args = shape.getParameters();
			case Custom:
				obj.kind = 2;
				obj.points = [for( p in points ) { x : p.x, y : p.y }];
		}
		#if editor
		obj.debugColor = debugColor;
		#end
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		switch(obj.kind){
			case 0: shape = Quad;
			case 1: shape = Type.createEnumIndex(Shape, obj.kind, obj.args);
			case 2:
				shape = Custom;
				var list : Array<Dynamic> = obj.points;
				points = [for(pt in list) new h2d.col.Point(pt.x, pt.y)];
		}
		#if editor
		debugColor = obj.debugColor != null ? obj.debugColor : 0xFFFFFF;
		if((debugColor >> 24) == 0)
			debugColor = 0x80000000 | debugColor;
		#end
	}

	override function updateInstance( ctx : Context, ?propName : String) {
		super.updateInstance(ctx, propName);
		var mesh : h3d.scene.Mesh = cast ctx.local3d;
		mesh.primitive = makePrimitive();
		#if editor
		setColor(ctx, debugColor);
		if(editor != null)
			editor.update(propName);
		#end
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

	public function makePrimitive() {

		if(shape == Custom) {
			#if editor
			if(cachedPrim != null) return cachedPrim;
			#end
			return generateCustomPolygon();
		}

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
		var idx = new hxd.IndexBuffer();
		for(i in indices)
			idx.push(i);
		primitive = new h3d.prim.Polygon(verts, idx);
		primitive.normals = [for(p in points) new h3d.col.Point(0, 0, 1.)];
		primitive.tangents = [for(p in points) new h3d.col.Point(0., 1., 0.)];
		primitive.uvs = [for(uv in uvs) new h3d.prim.UV(uv.x, uv.y)];
		primitive.colors = [for(p in points) new h3d.col.Point(1,1,1)];
		primitive.incref();
		cache.set(shape, primitive);
		return primitive;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var primitive = makePrimitive();
		var mesh = new h3d.scene.Mesh(primitive, ctx.local3d);
		mesh.material.props = h3d.mat.MaterialSetup.current.getDefaults("overlay");
		mesh.material.blendMode = Alpha;
		mesh.material.mainPass.culling = None;
		ctx.local3d = mesh;
		ctx.local3d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	public function setColor(ctx: Context, color: Int) {
		#if editor
		if(hrt.prefab.Material.hasOverride(this))
			return;
		if(ctx.local3d == null)
			return;
		var mesh = Std.downcast(ctx.local3d, h3d.scene.Mesh);
		if(mesh != null)
			hrt.prefab.Box.setDebugColor(color, mesh.material);
		#end
	}

	public function generateCustomPolygon(){
		var polyPrim : h3d.prim.Polygon = null;
		if( points != null ){
			var indexes = points.fastTriangulate();
			var idx : hxd.IndexBuffer = new hxd.IndexBuffer();
			for( i in indexes ) #if js if( i != null ) #end idx.push(i);
			var pts = [for( p in points ) new h3d.col.Point(p.x, p.y, 0)];
			polyPrim = new h3d.prim.Polygon(pts, idx);
			polyPrim.addNormals();
			polyPrim.addUVs();
			polyPrim.addTangents() ;
			polyPrim.alloc(h3d.Engine.getCurrent());
		}
		#if editor
		clearCustomPolygonCache();
		cachedPrim = polyPrim;
		cachedPrim.incref();
		#end
		return polyPrim;
	}

	public function clearCustomPolygonCache() {
		if(cachedPrim != null) {
			cachedPrim.decref();
			cachedPrim = null;
		}
	}

	public function getPrimitive( ctx : Context ) : h3d.prim.Polygon {
		var mesh = Std.downcast(ctx.local3d, h3d.scene.Mesh);
		return Std.downcast(mesh.primitive, h3d.prim.Polygon);
	}

	#if editor

	override function setSelected( ctx : Context, b : Bool ) {
		super.setSelected(ctx, b);
		if( editor != null && shape == Custom)
			editor.setSelected(ctx, b);
	}

	function createEditor( ctx : EditContext ){
		if( editor == null )
			editor = new hide.prefab.PolygonEditor(this, ctx.properties.undo);
		editor.editContext = ctx;
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		createEditor(ctx);

		var prevKind : Shape = this.shape;
		var viewModel = {
			kind: shape.getName(),
			segments: 24,
			rings: 4,
			innerRadius: 0.0,
			angle: 360.0
		};

		switch(shape) {
			case Quad:
			case Disc(seg, angle, inner, rings):
				viewModel.segments = seg;
				viewModel.angle = angle;
				viewModel.innerRadius = inner;
			case Custom:
			default:
		}

		var group = new hide.Element('
		<div class="group" name="Shape">
			<dl>
				<dt>Kind</dt><dd>
					<select field="kind">
						<option value="Quad">Quad</option>
						<option value="Disc">Disc</option>
						<option value="Custom">Custom</option>
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

		var updateProps = null;

		ctx.properties.add(group, viewModel, function(pname) {
			var pIsKind = pname == "kind";
			if( pIsKind ) {
				editor.reset();

				if( prevKind != Custom ){
					var cache = getPrimCache();
					var prim = cache.get(shape);
					if(prim != null){
						prim.dispose();
						cache.remove(shape);
					}
				}
				else if( prevKind == Custom ){
					var mesh = Std.downcast(ctx.getContext(this).local3d, h3d.scene.Mesh);
					if( mesh.primitive != null ) mesh.primitive.dispose(); // Dispose custom prim
				}

				prevKind = this.shape;
			}

			switch( viewModel.kind ) {
				case "Quad": 
					shape = Quad;
					if(pIsKind && prevKind == Custom) {
						scaleX = prevScale[0]; 
						scaleY = prevScale[1];
					}
				case "Disc": 
					shape = Disc(viewModel.segments, viewModel.angle, viewModel.innerRadius, viewModel.rings);
					if(pIsKind && prevKind == Custom) {
						scaleX = prevScale[0]; 
						scaleY = prevScale[1];
					}
				case "Custom":
					shape = Custom;
					if(pIsKind) {
						if(prevKind == Quad) {
							prevScale = [scaleX, scaleY];
							function apply() {
								points = [
									new Point(-scaleX/2, -scaleY/2),
									new Point(-scaleX/2, scaleY/2),
									new Point(scaleX/2, scaleY/2),
									new Point(scaleX/2, -scaleY/2)
								];
								scaleX = 1.0; scaleY = 1.0;
							}
							ctx.properties.undo.change(Custom(function(undo) {
								if(undo) {
									scaleX = prevScale[0];
									scaleY = prevScale[1];
									points = null;
								}
								else apply();
								ctx.onChange(this, null);
							}));
							clearCustomPolygonCache();
							apply();
							ctx.onChange(this, null);
						}
						else
							points = [];
					}
				default: shape = Quad;
			}

			updateProps();
			ctx.onChange(this, pname);
		});


		var editorProps = editor.addProps(ctx);

		updateProps = function() {
			discProps.hide();
			editorProps.hide();
			switch(viewModel.kind){
				case "Quad":
				case "Disc": discProps.show();
				case "Custom":
					editorProps.show();
					setSelected(ctx.getContext(this), true);
				default:
			}
		}

		ctx.properties.add( new hide.Element('
			<div class="group" name="Params">
				<dl><dt>Color</dt><dd><input type="color" alpha="true" field="debugColor"/></dd> </dl>
			</div>'), this, function(pname) { ctx.onChange(this, pname); });

		updateProps();

	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Polygon" };
	}

	#end

	static var _ = Library.register("polygon", Polygon);
}