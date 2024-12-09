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

class SplineMeshObject extends h3d.scene.Mesh {
	var spline : Spline;

	override public function new(spline : Spline, primitive : h3d.prim.Primitive, parent : h3d.scene.Object) {
		super(primitive, parent);
		this.spline = spline;
		material.mainPass.addShader(new SplineUV());
	}

	override function addBoundsRec( b : h3d.col.Bounds, relativeTo : h3d.Matrix ) {
		super.addBoundsRec(b, relativeTo);
		if( spline == null || primitive == null || flags.has(FIgnoreBounds) )
			return;

		if (spline.samples == null || spline.samples.length == 0)
			@:privateAccess spline.sample( (spline.shape == hrt.prefab.l3d.Spline.SplineShape.Linear) ? 1 : spline.sampleResolution);

		for (s in @:privateAccess spline.samples) {
			var p = s.pos.transformed(spline.getAbsPos(true));
			p = relativeTo != null ? p.transformed(relativeTo) : p;
			b.addPoint(p);
		}
	}
}

class SplineMesh extends hrt.prefab.Object3D {

	static var SPLINE_FMT = hxd.BufferFormat.make([{ name : "position", type : DVec3 }, { name : "normal", type : DVec3 },  { name : "uv", type : DVec2 }]);

	var spline : Spline = null;

	@:s var scaleUVy : Float = 1.0;
	@:s var scaleUVx : Float = 1.0;

	@:s var subdivision: Int = 0;
	@:s var thickness: Float = 2;
	@:s var count: Int = 2;
	@:s var spacing: Float = 2;

	@:s var previewPointCount = 16;
	@:s var previewRadius = 2;

	var meshPrimitive : h3d.prim.RawPrimitive = null;
	var meshMaterial : h3d.mat.Material = null;

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		if (spline == null)
			spline = findParent(Spline, null, false, true);
		return new SplineMeshObject(spline, null, parent3d);
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);
		disposeSplineMesh();

		if (spline == null)
			spline = findParent(Spline, null, false, true);
		if ( spline == null || spline.samples == null )
			computeDefaultSplineMesh();
		else
			computeSplineMesh();
	}

	function getLocalPoints() : Array<Float> {
		var vertexPerPoint = ( 4 + subdivision );
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

	function computeDefaultSplineMesh() {
		var bounds = new h3d.col.Bounds();
		var localPoints = getLocalPoints();

		previewPointCount = hxd.Math.imax(4, previewPointCount);

		var vertexPerPoint = ( 4 + subdivision );
		var vertexCount = vertexPerPoint * previewPointCount;
		var splineDataSize = 8 * vertexCount;
		var vertexData = new hxd.FloatBuffer(splineDataSize * count);

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

				for ( j in 0...vertexPerPoint ) {
					var pos = new h3d.Vector( 0, localPoints[j * 3 + 0], localPoints[j * 3 + 1] );
					pos.transform(trs);
					var normal = new h3d.Vector( 0, localPoints[j * 3 + 0], localPoints[j * 3 + 1] );
					normal.transform3x3(trs);
					normal.normalize();
					bounds.addPos(pos.x, pos.y, pos.z);

					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 0] = pos.x;
					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 1] = pos.y;
					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 2] = pos.z;

					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 3] = normal.x;
					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 4] = normal.y;
					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 5] = normal.z;

					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 6] = uv * scaleUVx;
					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 7] = localPoints[j * 3 + 2] * scaleUVy;
				}
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
		var mesh : h3d.scene.Mesh = cast local3d;
		mesh.primitive = meshPrimitive;
	}

	function computeSplineMesh() {
		var samples = spline.samples;
		if ( samples.length < 2 || local3d == null )
			return;

		var bounds = new h3d.col.Bounds();

		var vertexPerPoint = ( 4 + subdivision );
		var vertexCount = vertexPerPoint * samples.length;
		var splineDataSize = 8 * vertexCount;
		var vertexData = new hxd.FloatBuffer(splineDataSize * count);

		var localPoints = getLocalPoints();

		for ( s in 0...count ) {
			var spacing = s * spacing - spacing * (count - 1) * 0.5;
			var uv = 0.0;
			var prevPos = spline.globalToLocal(samples[0].pos);
			for ( i in 0...samples.length ) {
				var absPos = spline.globalToLocal(samples[i].pos);
				var curPos = absPos.clone();
				uv += curPos.distance(prevPos);
				var tangent = samples[i].tangentOut.normalized();
				var angle = hxd.Math.acos( tangent.dot(new h3d.Vector(1.0, 0.0, 0.0)) );
				if (tangent.dot(new h3d.Vector(0.0, 1.0, 0.0)) < 0.0)
					angle *= -1.0;
				var trs = new h3d.Matrix();
				trs.initRotationAxis(new h3d.Vector(0.0, 0.0, 1.0), angle);
				trs.translate(absPos.x, absPos.y, absPos.z);

				for ( j in 0...vertexPerPoint ) {
					var pos = new h3d.Vector( 0, localPoints[j * 3 + 0], localPoints[j * 3 + 1] );
					pos.y += spacing;
					pos.transform(trs);
					var normal = new h3d.Vector( 0, localPoints[j * 3 + 0], localPoints[j * 3 + 1] );
					normal.transform3x3(trs);
					normal.normalize();
					bounds.addPos(pos.x, pos.y, pos.z);
					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 0] = pos.x;
					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 1] = pos.y;
					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 2] = pos.z;

					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 3] = normal.x;
					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 4] = normal.y;
					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 5] = normal.z;

					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 6] = uv * scaleUVx;
					vertexData[ s * splineDataSize + i * 8 * vertexPerPoint + j * 8 + 7] = localPoints[j * 3 + 2] * scaleUVy;
				}
				prevPos = curPos;
			}
		}

		var indexBuffer = new hxd.IndexBuffer();
		for ( s in 0...count ) {
			for ( i in 1...samples.length ) {
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

		meshPrimitive = new h3d.prim.RawPrimitive( { vbuf : vertexData, format : SplineMesh.SPLINE_FMT, ibuf : indexBuffer, bounds : bounds } );
		var mesh : h3d.scene.Mesh = cast local3d;
		mesh.primitive = meshPrimitive;
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
			name : "SplineMesh",
			allowParent : (p) -> Std.isOfType(p, Spline) || p.parent == null
		};
	}
	#end

	static var _ = hrt.prefab.Prefab.register("splineMesh", SplineMesh);
}