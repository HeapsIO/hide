package hrt.prefab.l3d;

enum abstract SplineCapShape(String) {
	var None;
	var Sphere;
	var Cone;
}

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
}

@:prefabIcon(HuiRes.ui.icons.prefab.spline_mesh)
@:prefabName("Spline Mesh")
class SplineMesh extends hrt.prefab.Object3D {

	static var SPLINE_FMT = hxd.BufferFormat.make([{ name : "position", type : DVec3 }, { name : "normal", type : DVec3 }, { name : "tangent", type : DVec3 }, { name : "uv", type : DVec2 }]);

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

	@:s var capShape : SplineCapShape = None;
	@:s var capRadius : Float = 1.0;
	@:s var capLength : Float = 1.0;
	@:s var capSegments : Int = 3;

	@:s var previewPointCount = 16;
	@:s var previewRadius = 2;

	var meshPrimitive : h3d.prim.RawPrimitive = null;
	var meshMaterial : h3d.mat.Material = null;

	var vertexPerPoint(get, null) : Int;
	function get_vertexPerPoint() {
		return subdivision + 4;
	}

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		return new SplineMeshObject(spline, null, parent3d);
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);
		disposeSplineMesh();

		if ( spline != null && spline.localSamples.length >= 2 ) {
			var samples = spline.localSamples;
			computeSplineMesh([for ( s in samples ) s.pos], [for ( s in samples ) s.tangentOut.normalized()], !spline.loop);
		} else if ( capShape != None ) {
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

	inline function fillPoint( vertexData : hxd.FloatBuffer, dataPos : Int, localPoints : Array<Float>, trs : h3d.Matrix, uvX : Float, bounds : h3d.col.Bounds ) {
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

			var uvX = uvX * scaleUVx;
			var uvY = localPoints[i * 3 + 2] * scaleUVy;

			vertexData[dataPos++] = pos.x;
			vertexData[dataPos++] = pos.y;
			vertexData[dataPos++] = pos.z;

			vertexData[dataPos++] = normal.x;
			vertexData[dataPos++] = normal.y;
			vertexData[dataPos++] = normal.z;

			vertexData[dataPos++] = tangent.x;
			vertexData[dataPos++] = tangent.y;
			vertexData[dataPos++] = tangent.z;

			vertexData[dataPos++] = uvX;
			vertexData[dataPos++] = uvY;
		}
	}

	function getCapProfile() : Array<Float> {
		var radius = thickness * capRadius;
		var length = radius * capLength;
		var halfPi = hxd.Math.PI * 0.5;
		var profile = [];
		inline function add( offset : Float, rad : Float, normalAngle : Float ) {
			profile.push(offset);
			profile.push(rad);
			profile.push(normalAngle);
		}
		if ( radius < thickness ) {
			add(0, thickness, halfPi);
			add(0, radius, halfPi);
		}
		switch ( capShape ) {
		case None:
		case Sphere:
			var start = radius > thickness ? -hxd.Math.acos(thickness / radius) : 0.0;
			var segments = hxd.Math.imax(1, capSegments);
			for ( i in 0...segments + 1 ) {
				var phi = start + (halfPi - start) * i / segments;
				var s = hxd.Math.sin(phi);
				var c = hxd.Math.cos(phi);
				add(length * s, radius * c, hxd.Math.atan2(s * radius, c * length));
			}
		case Cone:
			if ( radius > thickness ) {
				add(0, thickness, -halfPi);
				add(0, radius, -halfPi);
			}
			var normalAngle = hxd.Math.atan2(radius, length);
			add(0, radius, normalAngle);
			add(length, 0, normalAngle);
		}
		return profile;
	}

	function fillCap( vertexData : hxd.FloatBuffer, dataPos : Int, profile : Array<Float>, trs : h3d.Matrix, uvX : Float, dir : Float, bounds : h3d.col.Bounds ) {
		var vertexPerPoint = vertexPerPoint;
		var stepAngle = hxd.Math.degToRad(360.0 / ( vertexPerPoint - 1 ));
		var tangent = new h3d.Vector(1.0, 0.0, 0.0);
		tangent.transform3x3(trs);
		tangent.normalize();
		for ( r in 0...Std.int(profile.length / 3) ) {
			var offset = profile[r * 3] * dir;
			var rad = profile[r * 3 + 1];
			var normalAngle = profile[r * 3 + 2];
			var nr = hxd.Math.cos(normalAngle);
			var nx = hxd.Math.sin(normalAngle) * dir;
			for ( i in 0...vertexPerPoint ) {
				var angle = i * stepAngle;
				var s = hxd.Math.sin(angle);
				var c = hxd.Math.cos(angle);

				var pos = new h3d.Vector(offset, s * rad, c * rad);
				pos.transform(trs);
				bounds.addPos(pos.x, pos.y, pos.z);

				var normal = new h3d.Vector(nx, s * nr, c * nr);
				normal.transform3x3(trs);
				normal.normalize();

				vertexData[dataPos++] = pos.x;
				vertexData[dataPos++] = pos.y;
				vertexData[dataPos++] = pos.z;

				vertexData[dataPos++] = normal.x;
				vertexData[dataPos++] = normal.y;
				vertexData[dataPos++] = normal.z;

				vertexData[dataPos++] = tangent.x;
				vertexData[dataPos++] = tangent.y;
				vertexData[dataPos++] = tangent.z;

				vertexData[dataPos++] = (uvX + offset) * scaleUVx;
				vertexData[dataPos++] = angle / (hxd.Math.PI * 2) * scaleUVy;
			}
		}
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

		var dataPos = 0;
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
				fillPoint(vertexData, dataPos, localPoints, trs, uv, bounds);
				dataPos += vertexDataStride * vertexPerPoint;
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

	function computeSplineMesh( points : Array<h3d.col.Point>, tangents : Array<h3d.Vector>, hasEnds : Bool ) {
		var bounds = new h3d.col.Bounds();

		var vertexPerPoint = vertexPerPoint;
		var vertexCount = vertexPerPoint * points.length;
		var vertexDataStride = SPLINE_FMT.stride;
		var splineDataSize = vertexDataStride * vertexCount;
		var capProfile = hasEnds && capShape != None ? getCapProfile() : [];
		var capRings = Std.int(capProfile.length / 3);
		var capVertexCount = capRings * vertexPerPoint;
		var vertexData = new hxd.FloatBuffer((splineDataSize + vertexDataStride * capVertexCount * 2) * count);

		var localPoints = getLocalPoints();

		var dataPos = 0;
		var capDataPos = splineDataSize * count;
		for ( s in 0...count ) {
			var spacing = s * spacing - spacing * (count - 1) * 0.5;
			var uv = 0.0;
			var prevPos = points[0];
			for ( i in 0...points.length ) {
				var curPos = points[i];
				uv += curPos.distance(prevPos);
				var tangent = tangents[i];
				var q = new h3d.Quat();
				q.initDirection(tangent);
				var euler = q.toEuler();
				var trs = new h3d.Matrix();
				trs.initTranslation(0.0, spacing, 0.0);
				trs.rotate(euler.x, euler.y, euler.z);
				trs.translate(curPos.x, curPos.y, curPos.z);
				fillPoint(vertexData, dataPos, localPoints, trs, uv, bounds);
				dataPos += vertexDataStride * vertexPerPoint;
				prevPos = curPos;
				if ( capRings > 0 && (i == 0 || i == points.length - 1) ) {
					fillCap(vertexData, capDataPos, capProfile, trs, uv, i == 0 ? -1 : 1, bounds);
					capDataPos += vertexDataStride * capVertexCount;
				}
			}
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
			for ( side in 0...(capRings > 0 ? 2 : 0) ) {
				var base = count * vertexCount + (s * 2 + side) * capVertexCount;
				var flip = side == 0;
				for ( r in 1...capRings ) {
					for ( j in 1...vertexPerPoint ) {
						var a = base + vertexPerPoint * (r - 1) + j - 1;
						var b = base + vertexPerPoint * r + j - 1;
						var c = base + vertexPerPoint * (r - 1) + j;
						var d = base + vertexPerPoint * r + j;
						indexBuffer.push(a);
						indexBuffer.push(flip ? c : b);
						indexBuffer.push(flip ? b : c);

						indexBuffer.push(c);
						indexBuffer.push(flip ? d : b);
						indexBuffer.push(flip ? b : d);
					}
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
			<div class="group" name="Caps">
				<dl>
					<dt>Shape</dt><dd><select field="capShape"><option value="None">None</option><option value="Sphere">Sphere</option><option value="Cone">Cone</option></select></dd>
					<dt>Radius</dt><dd><input type="range" min="0" max="5" field="capRadius"/></dd>
					<dt>Length</dt><dd><input type="range" min="0" max="5" field="capLength"/></dd>
					<dt>Segments</dt><dd><input type="range" min="1" max="10" step="1" field="capSegments"/></dd>
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
					<select field={capShape}/>
					<slider min={0.} field={capRadius}/>
					<slider min={0.} field={capLength}/>
					<range(1, 10) field={capSegments}/>
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