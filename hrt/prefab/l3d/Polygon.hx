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
	Capsule( segsW : Int, segsH : Int, axis: h3d.prim.Capsule.Axis);
	Box;
}

typedef PrimCache = Map<Shape, h3d.prim.Polygon>;


@:prefabIcon(HuiRes.ui.icons.prefab.polygon)
class Polygon extends Object3D {

	@:c public var shape(default, null) : Shape = Quad(0);
	@:c public var points : h2d.col.Polygon;
	@:s public var color : Int = 0xFFFFFFFF;

	var cachedCollider : h3d.col.Collider;
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
		case Quad(_), Disc(_), Sphere(_), Capsule(_), Box:
			data.args = shape.getParameters();
		case Custom:
			data.points = [for( p in points ) { x : p.x, y : p.y }];
		}
		return data;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		switch(obj.kind){
			case 0, 1, 3, 5: shape = Type.createEnumIndex(Shape, obj.kind, obj.args == null ? [0] : obj.args);
			case 4: {
				var params : Array<Dynamic> = cast obj.args;
				if (params == null)
					params = [0,0,0];
				if (params.length == 2) // backwards compat for when axis didn't exist
					params.push(0);
				shape = Type.createEnumIndex(Shape, obj.kind, params);
			}
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

	public function setShape(newShape: Shape) {
		shape = newShape;
		points = [];
	}

	override function updateInstance(?propName : String) {
		super.updateInstance(propName);
		var mesh : h3d.scene.Mesh = cast local3d;
		if (mesh != null) {
			mesh.primitive = makePrimitive();
		}

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
		cachedCollider = null;
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
		if ( cachedCollider == null ) {
			var prim = makePrimitive();
			cachedCollider = prim.getCollider();
		}
		return cachedCollider.rayIntersection(ray, true);
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
		case Box:
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
			case Capsule(sw, sh, axis):
				var cp = new h3d.prim.Capsule(1, 1, sw, axis);
				return cp;
			case Box:
				var bp = new h3d.prim.Cube(true);
				bp.addUVs();
				bp.addNormals();
				bp.addTangents();
				return bp;
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
		primitive.setUVCount(1);
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

	override public function edit2(ctx: EditContext2) {
		super.edit2(ctx);

		var viewModel = {
			kind: shape.getName(),
			subdivision: 0,
			segments: 16,
			segmentsH : 16,
			rings: 4,
			innerRadius: 0.0,
			angle: 360.0,
			axis: 2, // default to Z axis
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
			case Capsule(segw, segh, axis):
				viewModel.segments = segw;
				viewModel.segmentsH = segh;
				viewModel.axis = axis ?? 0;
			case Box:
		}

		function onChange(isTemp) {
			switch( viewModel.kind ) {
				case "Quad":
					shape = Quad(viewModel.subdivision);
				case "Disc":
					shape = Disc(viewModel.segments, viewModel.angle, viewModel.innerRadius, viewModel.rings);
				case "Sphere":
					shape = Sphere(viewModel.segments, viewModel.segmentsH);
				case "Capsule":
					shape = Capsule(viewModel.segments, viewModel.segmentsH, cast viewModel.axis);
				case "Box":
					shape = Box;
				case "Custom":
					shape = Custom;
				default:
					throw "???";
			}
		}

		function changeShape(isTemp: Bool) {
			var prevShape = shape;
			onChange(isTemp);
			if (prevShape.getIndex() == shape.getIndex())
				return;
			if (shape == Custom) {
				if (prevShape.match(Quad(_))) {
					points = [
						new Point(-scaleX/2, -scaleY/2),
						new Point(-scaleX/2, scaleY/2),
						new Point(scaleX/2, scaleY/2),
						new Point(scaleX/2, -scaleY/2)
					];
					scaleX = 1.0; scaleY = 1.0;
				} else {
					points = [];
				}
			} else {
				points = null;
			}
			ctx.rebuildInspector();
		}

		var editorTool = new PolygonEditor2(ctx, this);
		if (viewModel.kind == "Custom")
			editorTool.enter();

		ctx.build(
			<category("Shape")>
				<select(["Quad", "Disc", "Sphere", "Capsule", "Box", "Custom"]) field={kind} onValueChange={changeShape}/>

				<range(0, 100) int field={segments}/>
				<range(0, 100) int field={segmentsH} if (viewModel.kind != "Quad" && viewModel.kind != "Disc")/>

				<block if(viewModel.kind == "Disc")>
					<range(0, 100) field={rings}/>
					<range(0.0, 1.0) field={innerRadius}/>
					<range(0.0, 360.0) field={angle}/>
				</block>

				<block if(viewModel.kind == "Capsule")>
					<select([{value: 0, label: "X"},{value: 1, label: "Y"} , {value: 2, label: "Z"}]) field={axis}/>
				</block>
			</category>
		, viewModel, onChange);
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
			segments: 16,
			segmentsH : 16,
			rings: 4,
			innerRadius: 0.0,
			angle: 360.0,
			axis: "2", // default to Z axis
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
			case Capsule(segw, segh, axis):
				viewModel.segments = segw;
				viewModel.segmentsH = segh;
				viewModel.axis = '${axis ?? 0}';
			case Box:
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
						<option value="Box">Box</option>
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

		var capsuleProps = new hide.Element('
			<dt>Axis</dt>
			<dd>
				<select field="axis"/>
					<option value="0">X</option>
					<option value="1">Y</option>
					<option value="2">Z</option>
				</select>
			</dd>
		');

		group.append(quadProps);
		group.append(discProps);
		group.append(sphereProps);
		group.append(capsuleProps);

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
					shape = Capsule(viewModel.segments, viewModel.segmentsH, cast Std.parseInt(viewModel.axis));
				case "Box":
					shape = Box;
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
			sphereProps.hide();
			editorProps.hide();
			capsuleProps.hide();
			switch(viewModel.kind){
				case "Quad": quadProps.show();
				case "Disc": discProps.show();
				case "Sphere": sphereProps.show();
				case "Capsule": capsuleProps.show();
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

class GenSDF extends hxsl.Shader {
	var SRC = {
		var calculatedUV : Vec2;
		@param var points : Array<Vec4,256>;
		@param var len: Int = 0;
		var pixelColor : Vec4;

		function sdPolygon() : Float
		{
			var d = dot(calculatedUV-points[0].xy,calculatedUV-points[0].xy);
			var s = 1.0;
			var j = len-1;
			for(i in 0...len)
			{
				var e = points[j].xy - points[i].xy;
				var w =    calculatedUV - points[i].xy;
				var b = w - e*clamp( dot(w,e)/dot(e,e), 0.0, 1.0 );
				d = min( d, dot(b,b) );

				var cond = (calculatedUV.y>=points[i].y ? 1 : 0) + (calculatedUV.y<points[j].y ? 1 : 0) + (e.x*w.y>e.y*w.x ? 1 : 0);
				if (cond == 3 || cond == 0) s*=-1.0;
				j = i;
			}
			return s*sqrt(d);
		}

		function fragment() {
			pixelColor = vec4((-sdPolygon() * 8.0 + 0.5));
			pixelColor.a = 1.0;
		}
	}
}

@:access(hrt.prefab.l3d.ProjectedDisplay)
@:access(hrt.prefab.l3d.Polygon)
class WorldProjectedCollider extends h3d.col.Collider {
	var polygon : Polygon;
	var groundCollide : (ray: h3d.col.Ray) -> Float;


	public function new(polygon: Polygon, groundCollide : (ray: h3d.col.Ray) -> Float) {
		this.polygon = polygon;
		this.groundCollide = groundCollide;
	}

	function rayIntersection(ray: h3d.col.Ray, bestMatch : Bool) : Float {
		var groundCollision = groundCollide(ray);
		if (groundCollision < 0.0)
			return -1.0;

		var pos = ray.getPoint(groundCollision);

		if (contains(pos))
			return groundCollision - 0.01;

		return -1;
	}

	function contains(pos: h3d.Vector) : Bool {
		var inv = polygon.local3d.getInvPos();
		pos = pos.transformed(inv);

		return polygon.points.contains(new h2d.col.Point(pos.x, pos.y));
	}

	function inFrustum(f : h3d.col.Frustum, ?localMatrix : h3d.Matrix) : Bool {
		throw "implement";
	}

	function inSphere(s : h3d.col.Sphere) : Bool {
		throw "implement";
	}

	function dimension() : Float {
		return Std.downcast(polygon.local3d, ProjectedDisplay).decal.scaleX;
	}

	public function closestPoint(p : h3d.col.Point) {
		throw "implement";
		return new h3d.col.Point();
	}

	#if !macro
	function makeDebugObj() {
		return null;
	}
	#end
}

@:access(hrt.prefab.l3d.Polygon)
class ProjectedDisplay extends h3d.scene.Object {
	var polygon : Polygon;
	var texture : h3d.mat.Texture;

	var decal : h3d.scene.pbr.Decal;
	var sdf : hrt.shader.SDF;
	final texWidth = 128;

	public function new(polygon: Polygon, parent: h3d.scene.Object) {
		super(parent);
		this.polygon = polygon;

		var decalPrefab = new hrt.prefab.l3d.Decal(null, null);

		@:privateAccess decalPrefab.renderMode = Terrain;
		@:privateAccess decalPrefab.blendMode = Alpha;
		var r = decalPrefab.make(new ContextShared(null, null, this));
		decal = Std.downcast(r.local3d, h3d.scene.pbr.Decal);
		decal.ignoreCollide = true;

		var e = h3d.Engine.getCurrent();
		sdf = new hrt.shader.SDF();
		texture = new h3d.mat.Texture(texWidth,texWidth, [Target], R8);
		texture.realloc = () -> {
			e.setCurrent();
			regenerate();
		}
		sdf.sampler = texture;
		sdf.pxRange = 8.0;
		decal.material.mainPass.addShader(sdf);

		var shader = decal.material.mainPass.getShader(h3d.shader.pbr.VolumeDecal.DecalPBR);
		shader.USE_ALBEDO = true;
	}

	#if editor
	var prevEngine : h3d.Engine;
	#end

	override function sync(ctx) {
		if (dirty) {
			#if editor
			prevEngine = h3d.Engine.getCurrent();
			haxe.Timer.delay(regenerateImpl, 0); // for some reason 2d texture generation is bugged during the sync in hide
			#else
			regenerateImpl();
			#end
		}
		super.sync(ctx);
	}

	var dirty = false;
	function regenerate() {
		dirty = true;
	}

	function regenerateImpl() {
		dirty = false;
		#if editor
		if (prevEngine != h3d.Engine.getCurrent()) {
			return;
		}
		#end
		var points = polygon.points.points;

		if (points == null)
			return;

		sdf.bgColor.setColor(polygon.color);
		sdf.bgColor.a = 0.0;
		sdf.fgColor.setColor(polygon.color);
		sdf.fgColor.a *= .5;

		var bounds = new h2d.col.Bounds();
		for (point in points) {
			bounds.addPoint(point);
		}

		var min, max;
		if (bounds.width > bounds.height) {
			min = bounds.xMin;
			max = bounds.xMax;
		} else {
			min = bounds.yMin;
			max = bounds.yMax;
		}

		decal.scaleX = max - min;
		decal.scaleY = max - min;
		decal.scaleZ = 100.0;
		var center = bounds.getCenter();
		decal.setPosition(center.x, center.y, 0);

		var center = bounds.getCenter();

		// Perpendicular point for segment [i, i+1]
		var perps : Array<h2d.col.Point> = [];

		function localToTexCoord(point: h2d.col.Point) {
			point = point.clone();
			point = point - center;
			var scale = 1.0 / (max - min);
			point *= scale;
			point.x += 0.5;
			point.y += 0.5;
			//point = point * texWidth;
			return point;
		}

		var shader = new GenSDF();
		for (i in 0...256) {
			var pt = new h3d.Vector4();
			shader.points[i] = pt;
			if (i < points.length) {
				var local = localToTexCoord(points[i]);
				pt.set(local.x, local.y, 0,0);
			}
		}
		shader.len = points.length;

		var bitmap = new h2d.Bitmap(h2d.Tile.fromColor(0xFF00FF, 1, 1));
		bitmap.scale(texWidth);
		bitmap.addShader(shader);

		bitmap.drawTo(texture);
	}

	override function onRemove() {
		texture?.dispose();
		super.onRemove();
	}
}

#if domkit
@:access(hrt.prefab.l3d.Polygon)
class PolygonEditor2 extends hrt.prefab.editor.Tool {
	var polygon : Polygon;
	var handles : Array<PolygonEditorHandle2> = [];
	var dragStart : h2d.col.Point = null;
	var dragging : Bool = false;

	public function new(ctx, polygon: Polygon) {
		super(ctx);
		this.polygon = polygon;
	}

	override function onEnter() {
		debugText = new h2d.Text(hxd.res.DefaultFont.get(), ctx.s2d);
		debugText.dropShadow = {
			dx: 1,
			dy: 1,
			color: 0,
			alpha: 0.5,
		};

		dragStart = null;
		debugText.text = "Polygon editor";
	}

	override function postInitInteractive() {
		super.postInitInteractive();

		//interactive.cursor = ResizeNWSE;

		// interactive.onPush = (e) -> {
		// 	if (e.button == 0) {
		// 		e.propagate = false;
		// 	}
		// }

		// interactive.onRelease = (e) -> {
		// 	if (e.button == 0)
		// 		e.propagate = false;
		// }

		// interactive.onClick = (e) -> {
		// 	if (e.button == 0) {
		// 		e.propagate = false;
		// 	}
		// }

	}

	override function onDeleteCommand() {
		var anyDeleted = false;
		@:privateAccess ctx.root.change({recordUndo: true, callback: () -> {
			for (i in 0...handles.length) {
				var index = handles.length - i - 1;
				if (handles[index].selected) {
					anyDeleted = true;
					(polygon.points:Array<Point>).splice(index, 1);
				}
			}
			polygon.updateInstance();
		}, isTemporaryEdit: false});

		return anyDeleted;
	}

	override function onQuit() {
		debugText.remove();
		clearHandles();
		cleanupDrag();
	}

	override function update(dt:Float) {

		updateHandles();



		// Get selection
		var x = ctx.s2d.mouseX;
		var mousePos = inline new h2d.col.Point(ctx.s2d.mouseX, ctx.s2d.mouseY);
		var ray = s3d.camera.rayFromScreen(ctx.s2d.mouseX, ctx.s2d.mouseY, ctx.s2d.width, ctx.s2d.height);

		var sphereCol = inline new h3d.col.Sphere();

		var nearestDistance = hxd.Math.POSITIVE_INFINITY;
		var nearestHandleIndex = -1;

		var polygonAbsPos = polygon.getAbsPos();

		var normal = new h3d.Vector(0,0,1);
		normal.transform3x3(polygonAbsPos);
		var d = normal.dot(polygonAbsPos.getPosition());
		var worldMousePos = ray.intersect(new h3d.col.Plane(normal.x,normal.y,normal.z,d));

		debugText.text = 'Polygon editor ${hxd.Math.round(ctx.s2d.mouseX)} ${hxd.Math.round(ctx.s2d.mouseY)} / ${ctx.s2d.width} ${ctx.s2d.height} -> wmp : $worldMousePos';


		for (i => handle in handles) {
			sphereCol.x = handle.x;
			sphereCol.y = handle.y;
			sphereCol.z = handle.z;
			sphereCol.r = handle.scaleX * 0.5;

			var dist = inline sphereCol.rayIntersection(ray, true);
			if (dist > 0 && dist < nearestDistance) {
				nearestDistance = dist;
				nearestHandleIndex = i;
			}
		}

		var nearestEdgeHandleIndex = -1;
		{
			var nearestDistance = hxd.Math.POSITIVE_INFINITY;
			for (i => handle in handles) {
				var next = handles[(i + 1) % handles.length];
				var abs1 = handle.getAbsPos();
				var abs2 = next.getAbsPos();
				var x = (abs1.tx + abs2.tx) * 0.5;
				var y = (abs1.ty + abs2.ty) * 0.5;
				var z = (abs1.tz + abs2.tz) * 0.5;

				var distance = hxd.Math.distance(x - worldMousePos.x, y - worldMousePos.y, z - worldMousePos.z);
				if (distance < nearestDistance) {
					nearestEdgeHandleIndex = i;
					nearestDistance = distance;
				}
			}
		}

		for (i => handle in handles) {
			handle.setHover(i == nearestHandleIndex);
		}



		if (hxd.Key.isDown(hxd.Key.MOUSE_LEFT)) {
			if (dragStart != null) {
				if (!dragging) {
					if (inline dragStart.distance(mousePos) > 5.0) {
						// begin undo
						@:privateAccess ctx.root.change({recordUndo: true, callback: () -> {}, isTemporaryEdit: true});
						dragging = true;
					}
				} else {
					var inv = polygonAbsPos.getInverse();
					var localPoint = worldMousePos.clone();
					localPoint.transform(inv);
					for (pid => handle in this.handles) {
						if (handle.selected) {
							polygon.points[pid].x = localPoint.x;
							polygon.points[pid].y = localPoint.y;
						}
					}
					refreshPolygon();
				}
			}
		} else {
			cleanupDrag();
		}

		if (hxd.Key.isPressed(hxd.Key.MOUSE_LEFT)) {
			var shouldQuit = true;

			dragStart = mousePos.clone();

			// if (nearestHandleIndex != -1) {
			// 	shouldQuit = false;
			// 	unselectAll();
			// 	handles[nearestHandleIndex].selected = true;
			// }

			if (hxd.Key.isDown(hxd.Key.CTRL)) {
				shouldQuit = false;
				var inv = polygonAbsPos.getInverse();
				var localPoint = worldMousePos.clone();
				var index = nearestEdgeHandleIndex + 1;
				localPoint.transform(inv);
				var pt = new h2d.col.Point(localPoint.x, localPoint.y);
				@:privateAccess ctx.root.change({recordUndo: true, callback: () -> {polygon.points.insert(index, pt);}, isTemporaryEdit: false});
				updateHandles();
				unselectAll();
				handles[index].selected = true;
				refreshPolygon();
			}

			// shouldQuit = shouldQuit && polygon.localRayIntersection(ray) <= -1;

			// if (shouldQuit) {
			// 	quit();
			// }
		}
	}

	public function getMousePos() : h3d.Vector {
		var polygonAbsPos = polygon.getAbsPos();
		var ray = s3d.camera.rayFromScreen(ctx.s2d.mouseX, ctx.s2d.mouseY, ctx.s2d.width, ctx.s2d.height);

		var normal = new h3d.Vector(0,0,1);
		normal.transform3x3(polygonAbsPos);
		var d = normal.dot(polygonAbsPos.getPosition());
		return ray.intersect(new h3d.col.Plane(normal.x,normal.y,normal.z,d));
	}

	/*public function getLocalPolygonPoint() : h2d.col.Point {

	}*/

	function cleanupDrag() {
		if (dragging) {
			// record undo
			@:privateAccess ctx.root.change({recordUndo: true, callback: () -> {}, isTemporaryEdit: false, sideEffects: (isUndo: Bool) -> ctx.rebuildPrefabInteractive(polygon)});
		}

		dragStart = null;
		dragging = false;
	}

	function updateHandles() {
		while(handles.length > polygon.points.length) {
			handles.pop()?.remove();
		}

		while(handles.length < polygon.points.length) {
			handles.push(new PolygonEditorHandle2(this, ctx.s3d));
		}

		var polygonAbsPos = polygon.getAbsPos();

		for (i => handle in handles) {
			var point = polygon.points.points[i];
			var worldPoint = inline new h3d.Vector(point.x, point.y, 0.0);
			worldPoint = worldPoint.transformed(polygonAbsPos);

			handle.setPosition(worldPoint.x, worldPoint.y, worldPoint.z);
		}
	}

	/** Return true if a handle was selected**/
	public function unselectAll() {
		var anySelected = false;
		for (handle in handles) {
			if (handle.selected) {
				anySelected = true;
				handle.setSelected(false);
			}
		}
		return anySelected;
	}

	function clearHandles() {
		for (handle in handles) {
			handle.remove();
		}
		handles.resize(0);
	}

	function refreshPolygon() {
		if(!polygon.points.isClockwise())
			polygon.points.reverse();  // Ensure poly is always clockwise
		polygon.updateInstance();
	}

}



class PolygonEditorHandle2 extends h3d.scene.Object {
	public var tool : PolygonEditor2 = null;
	public var sphere : h3d.scene.Mesh = null;
	public var baseScale : Float = 1.0;
	public var selected : Bool = false;
	var interactive : h3d.scene.Interactive;

	static var prim: h3d.prim.Primitive;

	public function new(tool: PolygonEditor2, parent: h3d.scene.Object) {
		super(parent);
		this.tool = tool;

		if (prim == null) {
			var prim = new h3d.prim.Sphere(0.5,16,8);
			prim.addNormals();
			PolygonEditorHandle2.prim = prim;
		}

		sphere = new h3d.scene.Mesh(prim, null, this);
		sphere.material.setDefaultProps("ui");
		//sphere.material.mainPass.depthTest = GreaterEqual;
		sphere.material.mainPass.depthWrite = true;
		setSelected(false);
		setHover(false);

		interactive = new h3d.scene.Interactive(prim.getCollider(), this);
		interactive.propagateEvents = false;

		interactive.onOver = (e) -> {
			setHover(true);
		}

		interactive.onOut = (e) -> {
			setHover(false);
		}

		interactive.onPush = (e) -> {
			if (e.button == 0) {
				if (!hxd.Key.isDown(hxd.Key.CTRL)) {
					tool.unselectAll();
				}
				setSelected(true);
				e.propagate = false;
			}
		}

		var outline = new h3d.scene.Mesh(prim, null, this);
		outline.scale(1.2);
		outline.material.setDefaultProps("ui");
		//outline.material.mainPass.depthTest = GreaterEqual;
		outline.material.mainPass.culling = Front;
		outline.material.mainPass.depthWrite = true;

		outline.material.color.set(0,0,0, 1.0);
	}

	override function sync(ctx:h3d.scene.RenderContext) {
		var cam = ctx.camera;
		var gpos = getAbsPos().getPosition();
		var distToCam = cam.pos.sub(gpos).length();
		var engine = h3d.Engine.getCurrent();
		var ratio = 35 / engine.height;
		// Ignore parent scale
		var tmp = parent.getAbsPos().getScale();
		var scale = ratio * distToCam * Math.tan(cam.fovY * 0.5 * Math.PI / 180.0) * baseScale;
		scaleX = scale / tmp.x;
		scaleY = scale / tmp.y;
		scaleZ = scale / tmp.z;
		calcAbsPos();
		super.sync(ctx);
	}

	public function setSelected(selected: Bool) {
		this.selected = selected;
		if (selected) {
			sphere.material.color.set(1.0,0.0,0.0,1.0);
		} else {
			sphere.material.color.set(1.0,1.0,1.0,1.0);
		}
	}

	public function setHover(hover: Bool) {
		if (hover) {
			baseScale = 1.1;
		} else {
			baseScale = 1.0;
		}
	}

}

#end