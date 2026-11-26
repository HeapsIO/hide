package hrt.prefab.l3d;

class SplineUV extends hxsl.Shader {
	static var SRC = {
		@input var input : {
			var uv : Vec2;
		};
		var calculatedUV : Vec2;
		function __init__() {
			calculatedUV = input.uv;
		}
	}
}

class SplineCapFade extends hxsl.Shader {
	static var SRC = {
		@input var input : {
			var uv : Vec2;
		};
		@param var railEndU : Float;
		@param var invCapLengthU : Float;
		@param var power : Float;
		var pixelColor : Vec4;
		function fragment() {
			var capProgress = max(-input.uv.x, input.uv.x - railEndU) * invCapLengthU;
			pixelColor.a *= pow(saturate(1.0 - capProgress), power);
		}
	}
}

class SplineMeshObject extends h3d.scene.MultiMaterial {
	var spline : Spline;
	var capMaterials = new Map<h3d.mat.Material, h3d.mat.Material>();
	public var railIndexCount = 0;
	public var capFadeShader : SplineCapFade = null;

	override public function new(spline : Spline, primitive : h3d.prim.Primitive, parent : h3d.scene.Object) {
		super(primitive, null, parent);
		this.spline = spline;
		material.mainPass.addShader(new SplineUV());
	}

	override function draw( ctx : h3d.scene.RenderContext ) {
		if ( materials.length == 1 ) {
			super.draw(ctx);
			return;
		}
		if ( primitive.buffer == null || primitive.buffer.isDisposed() )
			primitive.alloc(ctx.engine);
		var isRail = ctx.drawPass.index == 0;
		var start = isRail ? 0 : railIndexCount;
		var indexCount = isRail ? railIndexCount : primitive.indexes.count - railIndexCount;
		ctx.engine.renderIndexed(primitive.buffer, primitive.indexes, Std.int(start / 3), Std.int(indexCount / 3));
	}

	public function setSplineMaterial( base : h3d.mat.Material ) {
		material = base;
		materials[0] = base;
		if ( materials.length > 1 )
			materials[1] = getCapMaterial(base);
	}

	public function rebuildMaterials( hasCaps : Bool ) {
		capMaterials.clear();
		materials = hasCaps ? [material, getCapMaterial(material)] : [material];
	}

	function getCapMaterial( base : h3d.mat.Material ) : h3d.mat.Material {
		var capMaterial = capMaterials.get(base);
		if ( capMaterial == null ) {
			capMaterial = makeCapMaterial(base);
			capMaterials.set(base, capMaterial);
		}
		return capMaterial;
	}

	function makeCapMaterial( base : h3d.mat.Material ) : h3d.mat.Material {
		var capMaterial : h3d.mat.Material = cast base.clone();
		capMaterial.name = "splineCap";
		capMaterial.blendMode = Alpha;
		for ( shader in base.mainPass.getShaders() )
			if ( capMaterial.mainPass.getShader(Type.getClass(shader)) == null )
				capMaterial.mainPass.addShader(shader);
		capMaterial.mainPass.addShader(capFadeShader);
		return capMaterial;
	}
}

typedef CapGeometry = { vertices : hxd.FloatBuffer, indexes : Array<Int>, height : Float };

@:prefabIcon(HuiRes.ui.icons.prefab.spline_mesh)
@:prefabName("Spline Mesh")
class SplineMesh extends hrt.prefab.Object3D {

	static var SPLINE_FMT = hxd.BufferFormat.make([{ name : "position", type : DVec3 }, { name : "normal", type : DVec3 }, { name : "tangent", type : DVec3 }, { name : "uv", type : DVec2 }]);
	static var CAP_FMT = hxd.BufferFormat.make([{ name : "position", type : DVec3 }, { name : "normal", type : DVec3 }, { name : "uv", type : DVec2 }]);
	static var CAP_NORMAL_OFFSET = CAP_FMT.calculateInputOffset("normal") >> 2;
	static var CAP_UV_OFFSET = CAP_FMT.calculateInputOffset("uv") >> 2;

	var spline(get, default) : Spline = null;
	function get_spline() {
		if ( spline == null )
			spline = findParent(Spline, null, false, true);
		return spline;
	}

	@:s var scaleUVy : Float = 1.0;
	@:s var scaleUVx : Float = 1.0;

	@:s var subdivision: Int = 0;
	@:s var thickness: Float = 2;
	@:s var count: Int = 2;
	@:s var spacing: Float = 2;

	@:s var capPrefab : String;
	@:s var capFade : Bool = false;
	@:s var capFadePower : Float = 1.0;

	@:s var previewPointCount = 16;
	@:s var previewRadius = 2;

	var meshPrimitive : h3d.prim.RawPrimitive = null;
	var meshMaterial : h3d.mat.Material = null;

	var vertexPerPoint(get, null) : Int;
	function get_vertexPerPoint() {
		return subdivision + 4;
	}

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		var obj = new SplineMeshObject(spline, null, parent3d);
		obj.material.name = "spline";
		return obj;
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);
		disposeSplineMesh();

		if ( spline != null && spline.localSamples.length >= 2 ) {
			var samples = spline.localSamples;
			computeSplineMesh([for ( s in samples ) s.pos], [for ( s in samples ) s.tangentOut.normalized()], !spline.loop);
		} else if ( capPrefab != null ) {
			var n = hxd.Math.imax(2, previewPointCount);
			var points = [for ( i in 0...n ) new h3d.col.Point(previewRadius * (2 * i / (n - 1) - 1), 0, 0)];
			var tangents = [for ( i in 0...n ) new h3d.Vector(1, 0, 0)];
			computeSplineMesh(points, tangents, true);
		} else
			computeDefaultSplineMesh();
	}

	function getLocalPoints() : Array<Float> {
		var vertexPerPoint = vertexPerPoint;
		var localPoints = [];
		localPoints.resize(3 * vertexPerPoint );
		var angle = 0.0;
		var stepAngle = hxd.Math.degToRad(360.0 / ( vertexPerPoint- 1 ));
		for ( i in 0...vertexPerPoint ) {
			localPoints[i * 3 + 0] = hxd.Math.sin(angle) * thickness;
			localPoints[i * 3 + 1] = hxd.Math.cos(angle) * thickness;
			localPoints[i * 3 + 2] = angle / hxd.Math.degToRad(360);
			angle += stepAngle;
		}
		return localPoints;
	}

	inline function fillPoint( loader : hxd.FloatBufferLoader, localPoints : Array<Float>, trs : h3d.Matrix, uvX : Float, bounds : h3d.col.Bounds ) {
		var vertexPerPoint = vertexPerPoint;
		for ( i in 0...vertexPerPoint ) {
			var pos = new h3d.Vector( 0, localPoints[i * 3 + 0], localPoints[i * 3 + 1] );
			pos.transform(trs);
			bounds.addPos(pos.x, pos.y, pos.z);

			var normal = new h3d.Vector( 0, localPoints[i * 3 + 0], localPoints[i * 3 + 1] );
			normal.transform3x3(trs);
			normal.normalize();

			var tangent = new h3d.Vector(1.0, 0.0, 0.0);
			tangent.transform3x3(trs);
			tangent.normalize();

			loader.loadVec3(pos);
			loader.loadVec3(normal);
			loader.loadVec3(tangent);
			loader.loadFloat(uvX * scaleUVx);
			loader.loadFloat(localPoints[i * 3 + 2] * scaleUVy);
		}
	}

	static inline function readVector( vertices : hxd.FloatBuffer, offset : Int ) {
		return new h3d.Vector(vertices[offset], vertices[offset + 1], vertices[offset + 2]);
	}

	function computeDefaultSplineMesh() {
		var bounds = new h3d.col.Bounds();
		var localPoints = getLocalPoints();

		previewPointCount = hxd.Math.imax(4, previewPointCount);

		var vertexPerPoint = vertexPerPoint;
		var vertexCount = vertexPerPoint * previewPointCount;
		var vertexDataStride = SPLINE_FMT.stride;
		var splineDataSize = vertexDataStride * vertexCount;
		var vertexData = new hxd.FloatBuffer(splineDataSize * count);
		var loader = new hxd.FloatBufferLoader(vertexData, 0);

		for ( s in 0...count ) {
			var spacing = s * spacing - spacing * (count - 1) * 0.5;
			var uv = 0.0;
			var stepAngle = hxd.Math.degToRad(360.0 / ( previewPointCount- 1 ));
			var angle = 0.0;
			for ( i in 0...previewPointCount ) {
				var trs = new h3d.Matrix();
				trs.initTranslation(0.0, previewRadius + spacing);
				trs.rotateAxis(new h3d.Vector(0.0, 0.0, 1.0), angle);
				angle += stepAngle;
				fillPoint(loader, localPoints, trs, uv, bounds);
				uv += hxd.Math.atan(stepAngle) * previewRadius;
			}
		}
		var indexBuffer = new hxd.IndexBuffer();
		for ( s in 0...count ) {
			for ( i in 1...previewPointCount ) {
				for ( j in 1...vertexPerPoint ) {
					indexBuffer.push( s * vertexCount + vertexPerPoint * (i - 1) + j - 1 );
					indexBuffer.push( s * vertexCount + vertexPerPoint * (i - 1) + j);
					indexBuffer.push( s * vertexCount + vertexPerPoint * i + j - 1 );

					indexBuffer.push( s * vertexCount + vertexPerPoint * (i - 1) + j);
					indexBuffer.push( s * vertexCount + vertexPerPoint * i + j);
					indexBuffer.push( s * vertexCount + vertexPerPoint * i + j - 1 );
				}
			}
		}

		meshPrimitive = new h3d.prim.RawPrimitive( { vbuf : vertexData, format : SplineMesh.SPLINE_FMT, ibuf : indexBuffer, bounds : bounds } );
		var mesh : SplineMeshObject = cast local3d;
		mesh.primitive = meshPrimitive;
		mesh.rebuildMaterials(false);
	}

	function computeSplineMesh( points : Array<h3d.col.Point>, tangents : Array<h3d.Vector>, hasEnds : Bool ) {
		var bounds = new h3d.col.Bounds();
		var cap = hasEnds && capPrefab != null ? loadCap(capPrefab) : null;
		var hasCaps = cap != null && cap.indexes.length > 0;
		var capVertexCount = hasCaps ? Std.int(cap.vertices.length / CAP_FMT.stride) : 0;

		var vertexPerPoint = vertexPerPoint;
		var vertexCount = vertexPerPoint * points.length;
		var vertexDataStride = SPLINE_FMT.stride;
		var splineDataSize = vertexDataStride * vertexCount;
		var vertexData = new hxd.FloatBuffer((splineDataSize + vertexDataStride * capVertexCount * 2) * count);
		var railLoader = new hxd.FloatBufferLoader(vertexData, 0);
		var capLoader = new hxd.FloatBufferLoader(vertexData, splineDataSize * count);

		var localPoints = getLocalPoints();

		var railLength = 0.0;
		for ( s in 0...count ) {
			var spacing = s * spacing - spacing * (count - 1) * 0.5;
			var uv = 0.0;
			var prevPos = points[0];
			for ( i in 0...points.length ) {
				var curPos = points[i];
				uv += curPos.distance(prevPos);
				var trs = getPointTransform(curPos, tangents[i], spacing);
				fillPoint(railLoader, localPoints, trs, uv, bounds);
				if ( hasCaps && (i == 0 || i == points.length - 1) )
					fillCap(capLoader, cap, trs, uv, i == 0 ? -1 : 1, bounds);
				prevPos = curPos;
			}
			railLength = uv;
		}

		var indexBuffer = new hxd.IndexBuffer();
		for ( s in 0...count ) {
			for ( i in 1...points.length ) {
				for ( j in 1...vertexPerPoint ) {
					indexBuffer.push( s * vertexCount + vertexPerPoint * (i - 1) + j - 1 );
					indexBuffer.push( s * vertexCount + vertexPerPoint * i + j - 1 );
					indexBuffer.push( s * vertexCount + vertexPerPoint * (i - 1) + j);

					indexBuffer.push( s * vertexCount + vertexPerPoint * (i - 1) + j);
					indexBuffer.push( s * vertexCount + vertexPerPoint * i + j - 1 );
					indexBuffer.push( s * vertexCount + vertexPerPoint * i + j);
				}
			}
		}

		var railIndexCount = indexBuffer.length;
		if ( hasCaps ) {
			for ( c in 0...count * 2 ) {
				var base = count * vertexCount + c * capVertexCount;
				var isStartCap = c % 2 == 0;
				var t = 0;
				while ( t < cap.indexes.length ) {
					indexBuffer.push(base + cap.indexes[t]);
					indexBuffer.push(base + cap.indexes[t + (isStartCap ? 2 : 1)]);
					indexBuffer.push(base + cap.indexes[t + (isStartCap ? 1 : 2)]);
					t += 3;
				}
			}
		}

		meshPrimitive = new h3d.prim.RawPrimitive( { vbuf : vertexData, format : SplineMesh.SPLINE_FMT, ibuf : indexBuffer, bounds : bounds } );
		var mesh : SplineMeshObject = cast local3d;
		mesh.primitive = meshPrimitive;
		mesh.railIndexCount = railIndexCount;
		if ( hasCaps && capFade ) {
			var capFadeShader = mesh.capFadeShader ?? new SplineCapFade();
			capFadeShader.railEndU = railLength * scaleUVx;
			capFadeShader.invCapLengthU = 1.0 / (cap.height * thickness * scaleUVx);
			capFadeShader.power = capFadePower;
			mesh.capFadeShader = capFadeShader;
		} else
			mesh.capFadeShader = null;
		mesh.rebuildMaterials(mesh.capFadeShader != null);
	}

	function getPointTransform( pos : h3d.col.Point, tangent : h3d.Vector, spacing : Float ) {
		var q = new h3d.Quat();
		q.initDirection(tangent);
		var euler = q.toEuler();
		var trs = new h3d.Matrix();
		trs.initTranslation(0.0, spacing, 0.0);
		trs.rotate(euler.x, euler.y, euler.z);
		trs.translate(pos.x, pos.y, pos.z);
		return trs;
	}

	function getCapTransform( pointTransform : h3d.Matrix, dir : Float ) {
		var trs = new h3d.Matrix();
		trs.identity();
		trs._11 = 0; trs._12 = 1; trs._13 = 0;
		trs._21 = 0; trs._22 = 0; trs._23 = 1;
		trs._31 = dir; trs._32 = 0; trs._33 = 0;
		trs.scale(thickness, thickness, thickness);
		trs.multiply(trs, pointTransform);
		return trs;
	}

	function fillCap( loader : hxd.FloatBufferLoader, cap : CapGeometry, pointTransform : h3d.Matrix, uvX : Float, dir : Float, bounds : h3d.col.Bounds ) {
		var trs = getCapTransform(pointTransform, dir);

		var tangent = new h3d.Vector(1.0, 0.0, 0.0);
		tangent.transform3x3(pointTransform);
		tangent.normalize();

		var o = 0;
		while ( o < cap.vertices.length ) {
			var pos = readVector(cap.vertices, o);
			var u = (uvX + dir * pos.z * thickness) * scaleUVx;
			pos.transform(trs);
			bounds.addPos(pos.x, pos.y, pos.z);
			var normal = readVector(cap.vertices, o + CAP_NORMAL_OFFSET);
			normal.transform3x3(trs);
			normal.normalize();
			loader.loadVec3(pos);
			loader.loadVec3(normal);
			loader.loadVec3(tangent);
			loader.loadFloat(u);
			loader.loadFloat(cap.vertices[o + CAP_UV_OFFSET + 1] * scaleUVy);
			o += CAP_FMT.stride;
		}
	}

	function loadCap( path : String ) : CapGeometry {
		var cap : CapGeometry = { vertices : new hxd.FloatBuffer(), indexes : [], height : 0.0 };
		var root = new h3d.scene.Object();
		var instance = hxd.res.Loader.currentInstance.load(path).toPrefab().load().clone(null, new hrt.prefab.ContextShared(root));
		#if editor
		instance.setEditor(shared.editor, shared.scene);
		#end
		instance.make();
		for ( mesh in root.getMeshes() ) {
			var model = Std.downcast(mesh.primitive, h3d.prim.HMDModel);
			if ( model != null )
				appendCapGeometry(cap, model, mesh.getAbsPos());
		}
		instance.dispose();
		return cap;
	}

	function appendCapGeometry( cap : CapGeometry, model : h3d.prim.HMDModel, transform : h3d.Matrix ) {
		var buffers = model.getDataBuffers(CAP_FMT);
		var firstVertex = Std.int(cap.vertices.length / CAP_FMT.stride);
		var normalTransform = new h3d.Matrix();
		normalTransform.initInverse3x3(transform);
		normalTransform.transpose();
		var o = cap.vertices.length;
		for ( i in 0...buffers.vertexes.length )
			cap.vertices.push(buffers.vertexes[i]);
		var loader = new hxd.FloatBufferLoader(cap.vertices, 0);
		while ( o < cap.vertices.length ) {
			var pos = readVector(cap.vertices, o);
			pos.transform(transform);
			cap.height = hxd.Math.max(cap.height, pos.z);
			loader.pos = o;
			loader.loadVec3(pos);
			var normal = readVector(cap.vertices, o + CAP_NORMAL_OFFSET);
			normal.transform3x3(normalTransform);
			normal.normalize();
			loader.pos = o + CAP_NORMAL_OFFSET;
			loader.loadVec3(normal);
			o += CAP_FMT.stride;
		}
		for ( i in 0...buffers.indexes.length )
			cap.indexes.push(firstVertex + buffers.indexes[i]);
	}

	override function postMakeInstance() {
		super.postMakeInstance();
		var mesh : SplineMeshObject = cast local3d;
		mesh.rebuildMaterials(mesh.materials.length > 1);
	}

	function disposeSplineMesh(){
		if ( meshPrimitive != null ) {
			meshPrimitive.dispose();
			meshPrimitive = null;
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);

		var props = new hide.Element('
			<div class="group" name="Material">
				<dl>
					<dt>ScaleUVx</dt><dd><input type="range" min="0.0001" max="10" field="scaleUVx"/></dd>
					<dt>ScaleUVy</dt><dd><input type="range" min="0.0001" max="10" field="scaleUVy"/></dd>
					<dt>Custom Pass</dt><dd><input type="text" field="customPass"/></dd>
					<div align="center"><input type="button" value="Refresh" class="refresh"/></div>
				</dl>
			</div>
			<div class="group" name="Mesh">
				<dl>
					<dt>Subdivision</dt><dd><input type="range" min="0" max="10" step="1" field="subdivision"/></dd>
					<dt>Thickness</dt><dd><input type="range" min="1" max="10" field="thickness"/></dd>
					<dt>Count</dt><dd><input type="range" min="1" max="10" step="1" field="count"/></dd>
					<dt>Spacing</dt><dd><input type="range" min="0" max="10" field="spacing"/></dd>
				</dl>
			</div>
			<div class="group" name="Caps">
				<dl>
					<dt>Prefab</dt><dd><input type="fileselect" extensions="prefab" field="capPrefab"/></dd>
					<dt>Fade</dt><dd><input type="checkbox" field="capFade"/></dd>
					<dt>Fade power</dt><dd><input type="range" min="0" max="10" field="capFadePower"/></dd>
				</dl>
			</div>
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

	override function edit2(ctx:hrt.prefab.EditContext2) {
		super.edit2(ctx);

		ctx.build(
			<root>
				<category("Material")>
					<slider min={0.001} field={scaleUVx}/>
					<slider min={0.001} field={scaleUVy}/>
				</category>
				<category("Mesh")>
					<slider min={1} field={subdivision}/>
					<slider min={0.} field={thickness}/>
					<range(1, 10) field={count}/>
					<slider min={0.} field={spacing}/>
				</category>
				<category("Caps")>
					<file type="prefab" field={capPrefab} label="Prefab"/>
					<checkbox field={capFade} label="Fade"/>
					<range(0, 10) field={capFadePower} label="Fade power"/>
				</category>
				<category("Preview")>
					<range(4, 64) field={previewPointCount}/>
					<range(1, 10) field={previewRadius}/>
				</category>
			</root>
		);
	}

	override function getHideProps() : hide.prefab.HideProps {
		return {
			icon : "arrows-v",
			name : "SplineMesh",
			allowParent : (p) -> Std.isOfType(p, Spline) || p.parent == null
		};
	}
	#end

	static var _ = hrt.prefab.Prefab.register("splineMesh", SplineMesh);
}