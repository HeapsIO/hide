package hrt.prefab.l3d;
import h3d.scene.Mesh;
import hrt.prefab.l3d.Spline.SplinePoint;


class SplineMeshShader extends hxsl.Shader {

	static var SRC = {
		@:import h3d.shader.BaseMesh;

		@const var POINT_COUNT : Int;
		@const var CURVE_COUNT : Int;
		@const var CURVE_TYPE : Int;
		@param var points : Array<Vec4, POINT_COUNT>;
		@param var lengths : Array<Vec4, CURVE_COUNT>;
		@param var totalLength : Float;
		@param var splinePos : Float;

		function getCubicBezierPoint( t : Float, p0 : Vec4, p1 : Vec4, p2 : Vec4, p3 : Vec4 ) : Vec3 {
			return (p0 * (1 - t) * (1 - t) * (1 - t) + p1 * t * 3 * (1 - t) * (1 - t) + p2 * t * t * 3 * (1 - t) + p3 * t * t * t).xyz;
		}
		function getCubicBezierTangent( t : Float, p0 : Vec4, p1 : Vec4, p2 : Vec4, p3 : Vec4 ) : Vec3 {
			return (3 * (1 - t) * (1 - t) * (p1 - p0) + 6 * (1 - t) * t * (p2 - p1) + 3 * t * t * (p3 - p2)).xyz.normalize();
		}

		function vertex() {
			var pos = splinePos + relativePosition.y; // TO DO : Add modelView transform
			pos = clamp(pos, 0, totalLength);
			var curlength = 0.0;
			var i = 0;
			while( i < POINT_COUNT - 3 ) {
				var curSegmentLength = lengths[i].r;
				curlength += curSegmentLength;
				if( pos <= curlength ) {
					
					/*var targetL = pos;
					var curL = 0.0;	
					var curT = 0.0;
					var curP = getCubicBezierPoint(curT, points[i * 3 + 1], points[i * 3 + 2], points[i * 3 + 3], points[i * 3 + 4]);
					var dist = curP.distance()
					while( abs(targetL - curL) > 0.1 ) {
						var p = getCubicBezierPoint(curT, points[i * 3 + 1], points[i * 3 + 2], points[i * 3 + 3], points[i * 3 + 4]);
						var dist = curSegmentLength * p;
						true ? curT *= 0.5 : curT *= -0.5;
					}*/

					var t = (pos - (curlength - curSegmentLength)) / curSegmentLength;

					var point = getCubicBezierPoint(t, points[i * 3 + 1], points[i * 3 + 2], points[i * 3 + 3], points[i * 3 + 4]);
					var worldUp = vec3(0,0,1);
					var front = -getCubicBezierTangent(t, points[i * 3 + 1], points[i * 3 + 2], points[i * 3 + 3], points[i * 3 + 4]);
					var right = -front.cross(worldUp).normalize();
					var up = front.cross(right).normalize();			

					var rotation = mat4(	vec4(right.x, front.x, up.x, 0), 
											vec4(right.y, front.y, up.y, 0), 
											vec4(right.z, front.z, up.z, 0), 
											vec4(0,0,0,1));

					var translation = mat4(	vec4(1,0,0, point.x ), 
											vec4(0,1,0, point.y ), 
											vec4(0,0,1, point.z ), 
											vec4(0,0,0,1));

					var transform = rotation * translation;

					var localPos = relativePosition - vec3(0,relativePosition.y,0);

					transformedPosition = localPos* transform.mat3x4(); 
					break;
				}
				i += 3;
			}
		}

		function fragment() {
			//pixelColor = vec4(1,0,0,1);
		}
	}
}


class SplineMesh extends Spline {

	var meshPath : String;
	var meshes : Array<h3d.scene.Mesh> = [];
	var spacing: Float = 0.0;

	override function save() {
		var obj : Dynamic = super.save();
		obj.meshPath = meshPath;
		obj.spacing = spacing;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		meshPath = obj.meshPath;
		spacing = obj.spacing == null ? 0.0 : obj.spacing;
	}

	override function makeInstance( ctx : hrt.prefab.Context ) : hrt.prefab.Context {
		var ctx = ctx.clone(this);

		ctx.local3d = new h3d.scene.Object(ctx.local3d);
		ctx.local3d.name = name;

		for( pd in pointsData ) {
			var sp = new SplinePoint(0, 0, 0, ctx.local3d);
			sp.setTransform(pd);
			points.push(sp);
		}
		pointsData = null;

		if( points == null || points.length == 0 ) {
			points.push(new SplinePoint(0,0,0, ctx.local3d));
		}

		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance( ctx : hrt.prefab.Context , ?propName : String ) {
		super.updateInstance(ctx, propName);

		for( m in meshes ) {
			m.remove();
		}
		meshes = [];
		if( meshPath != null ) {
			var meshTemplate = ctx.loadModel(meshPath).toMesh();
			if( meshTemplate != null ) {
				var step = hxd.Math.abs(meshTemplate.primitive.getBounds().yMax) + hxd.Math.abs(meshTemplate.primitive.getBounds().yMin) + spacing;
				var length = getLength(0.1);
				var stepCount = hxd.Math.ceil(length / step);
				for( i in 0 ... stepCount ) {
					var m : h3d.scene.Mesh = cast meshTemplate.clone();
					//m.material.mainPass.setPassName("beforeTonemapping");
					m.material.castShadows = false;
					m.ignoreParentTransform = true;
					var p = getPoint(i / stepCount, 1.0, 0.001);
					if( p.pos != null ) m.setPosition(p.pos.x, p.pos.y, p.pos.z);
					//var s = createShader();
					//m.material.mainPass.addShader(s);
					//s.splinePos = (i / stepCount) * length;
					ctx.local3d.addChild(m);
					meshes.push(m);
				}
			}
		}
	}

	function createShader() {
		var s = new SplineMeshShader();
		s.CURVE_COUNT = points.length - 1;
		s.totalLength = getLength();
		s.lengths = [ for( i in 0 ...  points.length - 1 ) new h3d.Vector(getLengthBetween(points[i] , points[i + 1])) ];
		switch shape {
			case Linear: 
				s.POINT_COUNT = points.length;
				s.CURVE_TYPE = 0;
				s.points = [ for(sp in points) {
					sp.getPoint().toVector();
				}];
			case Quadratic:
				s.POINT_COUNT = points.length * 3;
				s.CURVE_TYPE = 1;
				s.points = [ for(sp in points) {
					sp.getPoint().toVector();
					sp.getSecondControlPoint().toVector();
				}];
			case Cubic: 
				s.POINT_COUNT = points.length * 3;
				s.CURVE_TYPE = 2;
				for(sp in points) {
					s.points.push(sp.getFirstControlPoint().toVector());
					s.points.push(sp.getPoint().toVector());
					s.points.push(sp.getSecondControlPoint().toVector());
				}
		}
		return s;
	}

	#if editor

	override function setSelected( ctx : hrt.prefab.Context , b : Bool ) {
		super.setSelected(ctx, b);
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		ctx.properties.add( new hide.Element('
			<div class="group" name="Mesh">
				<dl>
					<dt>Mesh</dt><dd><input type="model" field="meshPath"/></dd>
					<dt>Spacing</dt><dd><input type="range" min="0" max="10" field="spacing"/></dd>
				</dl>
			</div>
			'), this, function(pname) { ctx.onChange(this, pname); });
	}

	override function getHideProps() : HideProps {
		return { icon : "arrows-v", name : "SplineMesh" };
	}

	static var _ = hrt.prefab.Library.register("splineMesh", SplineMesh);
	#end
}