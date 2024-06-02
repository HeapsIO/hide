package hrt.prefab.l3d;
import hxd.Math;
import h2d.col.Point;

#if editor
import hide.prefab.EditContext;
import hide.prefab.HideProps;
#end




enum Shape {
	Quad(subdivision : Int);
	Disc(segments: Int, angle: Float, inner: Float, rings:Int);
	Custom;
	Sphere( segsW : Int, segsH : Int );
	Capsule( segsW : Int, segsH : Int );
}

typedef PrimCache = Map<Shape, h3d.prim.Polygon>;

class Polygon extends Object3D {

	@:c public var shape(default, null) : Shape = Quad(0);
	@:c public var points : h2d.col.Polygon;
	@:s public var color : Int = 0xFFFFFFFF;
	
	#if editor
	public var editor : hide.prefab.PolygonEditor;
	@:s public var gridSize:Float = 1;
	public var cachedPrim : h3d.prim.Polygon;
	@:s public var hasDebugColor : Bool = true;
	var prevScale = [1.0, 1.0];
	#end

	override function save() {
		var data = super.save();
		data.kind = shape.getIndex();
		switch(shape){
		case Quad(_), Disc(_), Sphere(_), Capsule(_):
			data.args = shape.getParameters();
		case Custom:
			data.points = [for( p in points ) { x : p.x, y : p.y }];
		}
		return data;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		switch(obj.kind){
			case 0, 1, 3, 4: shape = Type.createEnumIndex(Shape, obj.kind, obj.args == null ? [0] : obj.args);
			case 2:
				shape = Custom;
				var list : Array<Dynamic> = obj.points;
				points = [for(pt in list) new h2d.col.Point(pt.x, pt.y)];
		}
	}

	override function copy(obj:Prefab) {
		super.copy(obj);
		var p : Polygon = cast obj;
		this.shape = p.shape;
		this.points = p.points;
	}

	override function updateInstance(?propName : String) {
		super.updateInstance(propName);
		var mesh : h3d.scene.Mesh = cast local3d;
		mesh.primitive = makePrimitive();
		#if editor
		setColor(color);
		if(editor != null)
			editor.update(propName);
		#else
		mesh.material.color.setColor(color);
		#end
	}

	public static function getPrimCache() {
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

		primitive = createPrimitive(shape);
		primitive.incref();
		cache.set(shape, primitive);
		return primitive;
	}

	override function localRayIntersection(ray:h3d.col.Ray):Float {
		var prim = makePrimitive();
		var col = prim.getCollider();
		return col.rayIntersection(ray, true);
	}

	public function getPolygonBounds() : h2d.col.Polygon {
		return switch( shape ) {
		case Quad(subdivision):
			[
				new Point(-0.5, -0.5),
				new Point(0.5, -0.5),
				new Point(0.5,  0.5),
				new Point(-0.5,  0.5)
			];
		case Disc(segments, angle, _):
			if(angle >= 360)
				angle = 360;
			++segments;
			var anglerad = hxd.Math.degToRad(angle);
			[for(i in 0...segments) {
				var t = i / (segments - 1);
				var a = hxd.Math.lerp(-anglerad/2, anglerad/2, t);
				var ct = hxd.Math.cos(a);
				var st = hxd.Math.sin(a);
				new Point(ct, st);
			}];
		case Custom:
			[for( p in points ) p.clone()];
		case Sphere(_):
			null;
		case Capsule(_):
			null;
		};
	}

	public static function createPrimitive( shape : Shape ) : h3d.prim.Polygon {
		var uvs : Array<Point> = null;
		var points : Array<Point> = null;
		var indices : Array<Int> = null;

		switch(shape) {
			case Quad(subdivision):

				var size = subdivision + 1;
				var cellCount = size;
				cellCount *= cellCount;

				points = [];
				for( y in 0 ... size + 1 ) {
					for( x in 0 ... size + 1 ) {
						points.push(new Point(Math.lerp(-0.5, 0.5, x / size), Math.lerp(-0.5, 0.5, y / size)));
					}
				}

				indices = [];
				for( y in 0 ... size ) {
					for( x in 0 ... size ) {
						var i = x + y * (size + 1);
						if( i % 2 == 0 ) {
							indices.push(i);
							indices.push(i + 1);
							indices.push(i + size + 2);
							indices.push(i);
							indices.push(i + size + 2);
							indices.push(i + size + 1);
						}
						else {
							indices.push(i + size + 1);
							indices.push(i);
							indices.push(i + 1);
							indices.push(i + 1);
							indices.push(i + size + 2);
							indices.push(i + size + 1);
						}
					}
				}

				uvs = [for(v in points) new Point(v.x + 0.5, v.y + 0.5)];

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
			case Sphere(sw, sh):
				var sp = new h3d.prim.Sphere(1, sw, sh);
				sp.addUVs();
				sp.addNormals();
				sp.addTangents();
				return sp;
			case Capsule(sw, sh):
				var cp = new h3d.prim.Capsule(1, 1, sw);
				return cp;
			default:
		}

		var verts = [for(p in points) new h3d.col.Point(p.x, p.y, 0.)];
		var idx = new hxd.IndexBuffer();
		for(i in indices)
			idx.push(i);
		var primitive = new h3d.prim.Polygon(verts, idx);
		primitive.normals = [for(p in points) new h3d.col.Point(0, 0, 1.)];
		primitive.tangents = [for(p in points) new h3d.col.Point(0., 1., 0.)];
		primitive.uvs = [for(uv in uvs) new h3d.prim.UV(uv.x, uv.y)];
		primitive.colors = [for(p in points) new h3d.col.Point(1,1,1)];
		return primitive;
	}

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		var primitive = makePrimitive();
		var mesh = new h3d.scene.Mesh(primitive, parent3d);
		mesh.material.props = h3d.mat.MaterialSetup.current.getDefaults("overlay");
		mesh.material.blendMode = Alpha;
		mesh.material.mainPass.culling = None;
		return mesh;
	}

	#if editor
	public function setColor(color: Int) {
		if(hrt.prefab.Material.hasOverride(this))
			return;
		if(local3d == null)
			return;
		var mesh = Std.downcast(local3d, h3d.scene.Mesh);
		if(mesh != null && hasDebugColor)
			hrt.prefab.l3d.Box.setDebugColor(color, mesh.material);
	}
	#end

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

	public function getPrimitive() : h3d.prim.Polygon {
		var mesh : h3d.scene.Mesh = cast local3d;
		return Std.downcast(mesh.primitive, h3d.prim.Polygon);
	}

	#if editor
	function clearCustomPolygonCache() {
		if(cachedPrim != null) {
			cachedPrim.decref();
			cachedPrim = null;
		}
	}

	override function setSelected( b : Bool ) {
		if (!enabled) return true;
		super.setSelected(b);
		if( editor != null && shape == Custom)
			editor.setSelected(b);
		return true;
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
			subdivision: 0,
			segments: 24,
			segmentsH : 24,
			rings: 4,
			innerRadius: 0.0,
			angle: 360.0
		};

		switch(shape) {
			case Quad(subdivision):
				viewModel.subdivision = subdivision;
			case Disc(seg, angle, inner, rings):
				viewModel.segments = seg;
				viewModel.angle = angle;
				viewModel.innerRadius = inner;
			case Custom:
			case Sphere(segw, segh):
				viewModel.segments = segw;
				viewModel.segmentsH = segh;
			case Capsule(segw, segh):
				viewModel.segments = segw;
				viewModel.segmentsH = segh;
		}

		var group = new hide.Element('
		<div class="group" name="Shape">
			<dl>
				<dt>Kind</dt><dd>
					<select field="kind">
						<option value="Quad">Quad</option>
						<option value="Disc">Disc</option>
						<option value="Sphere">Sphere</option>
						<option value="Capsule">Capsule</option>
						<option value="Custom">Custom</option>
					</select>
				</dd>
			</dl>
		</div>
		');

		var quadProps = new hide.Element('
			<dt>Subdivision</dt><dd><input field="subdivision" type="range" min="0" max="100" step="1" /></dd>');

		var discProps = new hide.Element('
			<dt>Segments</dt><dd><input field="segments" type="range" min="0" max="100" step="1" /></dd>
			<dt>Rings</dt><dd><input field="rings" type="range" min="0" max="100" step="1" /></dd>
			<dt>Inner radius</dt><dd><input field="innerRadius" type="range" min="0" max="1" /></dd>
			<dt>Angle</dt><dd><input field="angle" type="range" min="0" max="360" /></dd>');

		var sphereProps = new hide.Element('
			<dt>Segments</dt><dd><input field="segments" type="range" min="0" max="100" step="1" /></dd>
			<dt>SegmentsH</dt><dd><input field="segmentsH" type="range" min="0" max="100" step="1" /></dd>');

		group.append(quadProps);
		group.append(discProps);
		group.append(sphereProps);

		var updateProps = null;

		ctx.properties.add(group, viewModel, function(pname) {
			if (!enabled) return;
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
					var mesh = Std.downcast(local3d, h3d.scene.Mesh);
					if( mesh.primitive != null ) mesh.primitive.dispose(); // Dispose custom prim
				}

				prevKind = this.shape;
			}

			switch( viewModel.kind ) {
				case "Quad":
					shape = Quad(viewModel.subdivision);
				case "Disc":
					shape = Disc(viewModel.segments, viewModel.angle, viewModel.innerRadius, viewModel.rings);
				case "Sphere":
					shape = Sphere(viewModel.segments, viewModel.segmentsH);
				case "Capsule":
					shape = Capsule(viewModel.segments, viewModel.segmentsH);
				case "Custom":
					shape = Custom;
					if(pIsKind) {
						if(prevKind.match(Quad(_))) {
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
				default: shape = Quad(0);
			}

			if(pIsKind && prevKind == Custom && shape != Custom) {
				scaleX = prevScale[0];
				scaleY = prevScale[1];
			}

			updateProps();
			ctx.onChange(this, pname);
		});


		var editorProps = editor.addProps(ctx);

		updateProps = function() {
			quadProps.hide();
			discProps.hide();
			editorProps.hide();
			switch(viewModel.kind){
				case "Quad": quadProps.show();
				case "Disc": discProps.show();
				case "Sphere": sphereProps.show();
				case "Custom":
					editorProps.show();
					setSelected(true);
				default:
			}
		}

		ctx.properties.add( new hide.Element('
			<div class="group" name="Params">
				<dl>
					<dt>Debug</dt><dd><input type="checkbox" field="hasDebugColor"/></dd>
					<dt>Color</dt><dd><input type="color" alpha="true" field="color"/></dd> 
				</dl>
			</div>'), this, function(pname) { ctx.onChange(this, pname); });

		updateProps();

	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Polygon" };
	}

	#end

	static var _ = Prefab.register("polygon", Polygon);
}