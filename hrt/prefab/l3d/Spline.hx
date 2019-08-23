package hrt.prefab.l3d;

import hxd.Math;

enum CurveShape {
	Linear;
	Quadratic;
	Cubic;
}

typedef SplinePointData = {
	pos : h3d.col.Point,
	tangent : h3d.col.Point,
	prev : SplinePoint,
	next : SplinePoint,
	?lengthPos : Float
}

class CurveComputedData {
	public var length : Float;
	public var points : Array<h3d.col.Point> = [];
	public function new() {}
}

class SplineComputedData {
	public var length : Float;
	public var precision : Float;
	public var curves : Array<CurveComputedData> = [];
	public function new() {}
}

class SplinePoint extends h3d.scene.Object {

	public var distanceToNextPoint = -1.0;

	public function new(x : Float, y : Float, z : Float, parent : h3d.scene.Object) {
		super(parent);
		setPosition(x,y,z);
	}

	inline public function getPoint() : h3d.col.Point {
		return getAbsPos().getPosition().toPoint();
	}

	public function getFirstControlPoint() : h3d.col.Point {
		var absPos = getAbsPos();
		var right = absPos.front();
		right.scale3(scaleX);
		var pos = new h3d.col.Point(absPos.tx, absPos.ty, absPos.tz);
		pos = pos.add(right.toPoint());
		return pos;
	}

	public function getSecondControlPoint() : h3d.col.Point {
		var absPos = getAbsPos();
		var left = absPos.front();
		left.scale3(-scaleX);
		var pos = new h3d.col.Point(absPos.tx, absPos.ty, absPos.tz);
		pos = pos.add(left.toPoint());
		return pos;
	}
}

class Spline extends Object3D {

	public var points : Array<SplinePoint> = [];
	public var shape : CurveShape = Quadratic;

	// Save/Load the curve as an array of absPos
	public var pointsData : Array<h3d.Matrix> = [];

	// Graphic
	public var showSpline : Bool = true;
	public var lineGraphics : h3d.scene.Graphics;
	public var linePrecision : Int = 15;
	public var lineThickness : Int = 4;
	public var color : Int = 0xFFFFFFFF;
	public var loop : Bool = false;

	#if editor
	public var editor : hide.prefab.SplineEditor;
	#end

	var computedLength = -1.0;

	override function save() {
		var obj : Dynamic = super.save();

		if( points!= null && points.length > 0 ) {
			var parentInv = points[0].parent.getAbsPos().clone();
			parentInv.initInverse(parentInv);
			obj.points = [ for(sp in points) {
								var abs = sp.getAbsPos().clone();
								abs.multiply(abs, parentInv);
								abs;
							} ];
		}
		obj.shape = shape.getIndex();
		obj.color = color;
		obj.linePrecision = linePrecision;
		obj.lineThickness = lineThickness;
		obj.loop = loop;
		obj.showSpline = showSpline;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		pointsData = obj.points == null ? [] : obj.points;
		shape = obj.shape == null ? Linear : CurveShape.createByIndex(obj.shape);
		color = obj.color != null ? obj.color : 0xFFFFFFFF;
		linePrecision = obj.linePrecision == null ? 15 : obj.linePrecision;
		lineThickness = obj.lineThickness == null ? 4 : obj.lineThickness;
		loop = obj.loop == null ? false : obj.loop;
		showSpline = obj.showSpline == null ? true : obj.showSpline;
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
		#if editor
		if( editor != null )
			editor.update(ctx, propName);

		generateBezierCurve(ctx);
		#end
	}

	// Return the length of the spline, use the computed data if available
	function getLength( ?precision : Float = 1.0 ) : Float {
		if( computedLength > 0 )
			return computedLength;
		var sum = 0.0;
		for( i in 0 ... points.length - 1 ) {
			sum += getLengthBetween(points[i], points[i+1], precision);
		}
		return sum;
	}

	// Return the euclidean distance between the two points
	inline function getMaxLengthBetween( p1 : SplinePoint, p2 : SplinePoint) : Float {
		switch shape {
			case Linear: return p1.getPoint().distance(p2.getPoint());
			case Quadratic: return p1.getPoint().distance(p1.getSecondControlPoint()) + p1.getFirstControlPoint().distance(p2.getPoint());
			case Cubic: return p1.getPoint().distance(p1.getSecondControlPoint()) + p1.getFirstControlPoint().distance(p2.getFirstControlPoint()) + p2.getFirstControlPoint().distance(p2.getPoint());
		}
	}

	// Return the sum of the euclidean distances between each control points
	inline function getMinLengthBetween( p1 : SplinePoint, p2 : SplinePoint) : Float {
		return p1.getPoint().distance(p2.getPoint());
	}

	// Approximative length calculation : compute the sum of the euclidean distance between a variable amount of points on the curve
	function getLengthBetween( p1 : SplinePoint, p2 : SplinePoint,  ?stepSize : Float = 1.0, ?threshold : Float = 0.01 ) : Float {

		if( shape == Linear ) 
			return getMinLengthBetween(p1, p2);
		
		if( p1.distanceToNextPoint > 0 )
			return p1.distanceToNextPoint;

		var pointList : Array<h3d.col.Point> = [];
		pointList.push( points[0].getPoint() );

		var sumT = 0.0;
		var t = 1.0;
		while( sumT < 1 ) {
			var p = getPointBetween(t, points[0], points[1]);
			var distance = p.distance(pointList[pointList.length - 1]);

			if( hxd.Math.abs(distance - stepSize) < threshold ) {
				pointList.push( p );
				sumT = t;
				t = 1.0;
			}
			else if( distance > stepSize ) 
				t -= (t - sumT) * 0.5;
			else if( distance < stepSize ) 
				t += (t - sumT) * 0.5;
		}

		var sum = 0.0;
		for( i in 0 ... pointList.length - 1 ) 
			sum += pointList[i].distance(pointList[i + 1]);

		p1.distanceToNextPoint = sum;

		return sum;
	}

	function computeSplineData( ?precision : Float = 1.0 ) {
		var d = new SplineComputedData();
	}

	// Return the closest spline point on the spline from p
	function getClosestSplinePoint( p : h3d.col.Point ) : SplinePoint {
		var minDist = -1.0;
		var curPt : SplinePoint = null;
		for( sp in points ) {
			var dist = p.distance(sp.getPoint());
			if( dist < minDist || minDist == -1 ) {
				minDist = dist;
				curPt = sp;
			}
		}
		return curPt;
	}

	// Return the closest point on the spline from p
	function getClosestPoint( p : h3d.col.Point, ?precision : Float = 1.0 ) : SplinePointData {
		var length = getLength(precision);
		var stepCount = hxd.Math.ceil(length * precision);
		var minDist = -1.0;
		var result : SplinePointData = { pos : null, tangent : null, prev : null, next : null };
		for( i in 0 ... stepCount ) {
			var pt = getPoint( i / stepCount );
			var dist = pt.pos.distance(p);
			if( dist < minDist || minDist == -1 ) {
				minDist = dist;
				result = pt;
			}
		}
		return result;
	}

	// Return the point on the spline at t, 0 <= t <= 1
	function getPoint( l : Float, ?step : Float = 1.0, ?threshold : Float = 0.01 ) : SplinePointData {
		
		// Early return, easy case
		if( points.length == 1 ) return { 	pos : points[0].getPoint(),
											tangent : points[0].getAbsPos().right().toPoint(),
											prev : null, 
											next : null, 
											lengthPos : 0  } ;

		if( l == 0 ) return { 	pos : points[0].getPoint(),
								tangent : points[0].getFirstControlPoint().sub(points[0].getPoint()),
								prev : points[0], 
								next : points[0], 
								lengthPos : 0  } ;

		if( l == 1 ) return { 	pos : points[points.length - 1].getPoint(),
								tangent : points[points.length - 1].getFirstControlPoint().sub(points[points.length - 1].getPoint()),
								prev : points[points.length - 1], 
								next : points[points.length - 1], 
								lengthPos : 1  };

		var targetLength = l * getLength(100);
		//trace("Try to find a point at " + targetLength);

		// Find the curve of the spline wich contain the asked length
		var p0 : SplinePoint = null;
		var p1 : SplinePoint = null;
		var curveLengthSum = 0.0;
		for( i in 0 ... points.length - 1 ) {
			var curveLength = getLengthBetween(points[i], points[i+1], step, threshold);
			// Step on the curve and get the segment wich contain the asked length
			if( targetLength <= curveLengthSum + curveLength ) {
				p0 = points[i];
				p1 = points[i + 1];
				//trace("Try to find a point on the curve " + i + " -> " + (i + 1));
			}
			curveLengthSum += curveLength;
		}

		// Step on the curve and get the segment wich contain the asked length
		var lastP = p0.getPoint();
		var lengthSum = 0.0;
		var minT = 0.0;
		var t = 1.0;
		while( minT < 1 ) {
			var p = getPointBetween(t, p0, p1);
			var curSegmentLength = p.distance(lastP);
			if( curSegmentLength - step < threshold ) {
				//trace("Try to find the point on the segment" + lastP + " - " + p + " of length " + lengthSum + " -> " + (lengthSum + curSegmentLength));	
				// Lerp on the segment wich contain the asked length
				if( curSegmentLength + lengthSum > targetLength ) {
					//trace("Found the segment of the curve " + lastP + " - " + p );
					var finalT = hxd.Math.lerp(minT, t, (targetLength - lengthSum ) / curSegmentLength );
					trace("Found the segment of the curve " + finalT );
					return { 	pos : getPointBetween(finalT, p0, p1),
								tangent : getTangentBetween(finalT, p0, p1),
								prev : p0, 
								next : p1, 
								lengthPos : finalT  };
				}
				lastP = p;
				minT = t;
				lengthSum += curSegmentLength;
				t = 1.0;
			}
			else if( curSegmentLength > threshold ) 
				t -= (t - minT) * 0.5;
			else if( curSegmentLength < threshold ) 
				t += (t - minT) * 0.5;
		}

		return { pos : null, tangent : null, prev : null, next : null };
	}

	// Return the point on the spline at t, 0 <= t <= 1
	/*function getPoint( t : Float, ?precision : Float = 1.0 ) : SplinePointData {
		t = hxd.Math.clamp(t, 0, 1);

		if( points.length == 1 ) return { 	pos : points[0].getPoint(),
											tangent : points[0].getAbsPos().right().toPoint(),
											prev : null, 
											next : null } ;

		if( t == 0 ) return { 	pos : points[0].getPoint(),
								tangent : points[0].getFirstControlPoint().sub(points[0].getPoint()),
								prev : points[0], 
								next : points[0] } ;

		if( t == 1 ) return { 	pos : points[points.length - 1].getPoint(),
								tangent : points[points.length - 1].getFirstControlPoint().sub(points[points.length - 1].getPoint()),
								prev : points[points.length - 1], 
								next : points[points.length - 1] };

		var totalLength = getLength(precision);
		var length = totalLength * t;
		var curlength = 0.0;
		for( i in 0 ... points.length - 1 ) {
			var curSegmentLength = getLengthBetween(points[i], points[i+1], precision);
			curlength += curSegmentLength;
			if( length <= curlength ) {
				var t = (length - (curlength - curSegmentLength)) / curSegmentLength;
				return { pos : getPointBetween(t, points[i], points[i+1]), tangent : getTangentBetween(t, points[i], points[i+1]), prev : points[i], next : points[i+1] };
			}
		}
		return { pos : null, tangent : null, prev : null, next : null };
	}*/

	// Return the point on the curve between p1 and p2 at t, 0 <= t <= 1
	inline function getPointBetween( t : Float, p1 : SplinePoint, p2 : SplinePoint ) : h3d.col.Point {
		return switch (shape) {
			case Linear: getLinearBezierPoint( t, p1.getPoint(), p2.getPoint() );
			case Quadratic: getQuadraticBezierPoint( t, p1.getPoint(), p1.getSecondControlPoint(), p2.getPoint() );
			case Cubic: getCubicBezierPoint( t, p1.getPoint(), p1.getSecondControlPoint(), p2.getFirstControlPoint(), p2.getPoint() );
		}
	}

	// Return the tangen on the curve between p1 and p2 at t, 0 <= t <= 1
	inline function getTangentBetween( t : Float, p1 : SplinePoint, p2 : SplinePoint ) : h3d.col.Point {
		return switch (shape) {
			case Linear: getLinearBezierTangent( t, p1.getPoint(), p2.getPoint() );
			case Quadratic: getQuadraticBezierTangent( t, p1.getPoint(), p1.getSecondControlPoint(), p2.getPoint() );
			case Cubic: getCubicBezierTangent( t, p1.getPoint(), p1.getSecondControlPoint(), p2.getFirstControlPoint(), p2.getPoint() );
		}
	}

	// Linear Interpolation
	// p(t) = p0 + (p1 - p0) * t
	inline function getLinearBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point ) : h3d.col.Point {
		return p0.add((p1.sub(p0).multiply(t)));
	}
	// p'(t) = (p1 - p0)
	inline function getLinearBezierTangent( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point ) : h3d.col.Point {
		return p1.sub(p0).normalizeFast();
	}

	// Quadratic Interpolation
	// p(t) = p0 * (1 - t)² + p1 * t * 2 * (1 - t) + p2 * t²
	inline function getQuadraticBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point) : h3d.col.Point {
		return p0.multiply((1 - t) * (1 - t)).add(p1.multiply(t * 2 * (1 - t))).add(p2.multiply(t * t));
	}
	// p'(t) = 2 * (1 - t) * (p1 - p2) + 2 * t * (p2 - p1)
	inline function getQuadraticBezierTangent( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point) : h3d.col.Point {
		return p1.sub(p2).multiply(2 * (1 - t)).add(p2.sub(p1).multiply(2 * t)).normalizeFast();
	}

	// Cubic Interpolation
	// p(t) = p0 * (1 - t)³ + p1 * t * 3 * (1 - t)² + p2 * t² * 3 * (1 - t) + p3 * t³
	inline function getCubicBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point, p3 : h3d.col.Point) : h3d.col.Point {
		return p0.multiply((1 - t) * (1 - t) * (1 - t)).add(p1.multiply(t * 3 * (1 - t) * (1 - t))).add(p2.multiply(t * t * 3 * (1 - t))).add(p3.multiply(t * t * t));
	}
	// p'(t) = 3 * (1 - t)² * (p1 - p0) + 6 * (1 - t) * t * (p2 - p1) + 3 * t² * (p3 - p2)
	inline function getCubicBezierTangent( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point, p3 : h3d.col.Point) : h3d.col.Point {
		return p1.sub(p0).multiply(3 * (1 - t) * (1 - t)).add(p2.sub(p1).multiply(6 * (1 - t) * t)).add(p3.sub(p2).multiply(3 * t * t)).normalizeFast();
	}

	#if editor

	function generateBezierCurve( ctx : hrt.prefab.Context ) {
		
		if( !showSpline ) {
			if( lineGraphics != null ) {
				lineGraphics.remove();
				lineGraphics = null;
			}
			return;
		}

		if( points == null )
			return;

		if( lineGraphics == null ) {
			lineGraphics = new h3d.scene.Graphics(ctx.local3d);
			lineGraphics.lineStyle(lineThickness, color);
			lineGraphics.material.mainPass.setPassName("overlay");
			lineGraphics.material.mainPass.depth(false, LessEqual);
			lineGraphics.ignoreParentTransform = false;
		}

		computedLength = -1;
		for( sp in points ) {
			sp.distanceToNextPoint = -1;
		}

		var curve : Array<h3d.col.Point> = [];
		switch (shape) {
			case Linear:
				for( sp in points )
					curve.push(sp.getPoint());
				if( loop && points.length > 1 )
					curve.push(points[0].getPoint());
			case Quadratic:
				var i = 0;
				while( i < points.length - 1 ) {
					for( v in 0 ... linePrecision + 1 ) {
						curve.push(getQuadraticBezierPoint( v / linePrecision, points[i].getPoint(), points[i].getSecondControlPoint(), points[i+1].getPoint()));
					}
					++i;
				}
				if( loop && points.length > 1 ) {
					for( v in 0 ... linePrecision + 1 ) {
						curve.push(getQuadraticBezierPoint( v / linePrecision, points[points.length - 1].getPoint(), points[points.length - 1].getSecondControlPoint(), points[0].getPoint()));
					}
				}
			case Cubic:
				var i = 0;
				while( i < points.length - 1 ) {
					for( v in 0 ... linePrecision + 1 ) {
						curve.push(getCubicBezierPoint( v / linePrecision, points[i].getPoint(), points[i].getSecondControlPoint(), points[i+1].getFirstControlPoint(), points[i+1].getPoint()));
					}
					++i;
				}
				if( loop && points.length > 1 ) {
					for( v in 0 ... linePrecision + 1 ) {
						curve.push(getCubicBezierPoint( v / linePrecision, points[points.length - 1].getPoint(), points[points.length - 1].getSecondControlPoint(), points[0].getFirstControlPoint(), points[0].getPoint()));
					}
				}
		}

		lineGraphics.lineStyle(lineThickness, color);
		lineGraphics.clear();
		var b = true;
		for( p in curve ) {
			var localPos = ctx.local3d.globalToLocal(p.toVector());
			b ? lineGraphics.moveTo(localPos.x, localPos.y, localPos.z) : lineGraphics.lineTo(localPos.x, localPos.y, localPos.z);
			b = false;
		}
	}

	override function setSelected( ctx : hrt.prefab.Context , b : Bool ) {
		super.setSelected(ctx, b);

		if( editor != null )
			editor.setSelected(ctx, b);
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		ctx.properties.add( new hide.Element('
			<div class="group" name="Spline">
				<dl>
					<dt>Color</dt><dd><input type="color" alpha="true" field="color"/></dd>
					<dt>Thickness</dt><dd><input type="range" min="1" max="10" field="lineThickness"/></dd>
					<dt>Precision</dt><dd><input type="range" step="1" min="1" max="100" field="linePrecision"/></dd>
					<dt>Show Spline</dt><dd><input type="checkbox" field="showSpline"/></dd>
					<dt>Type</dt>
						<dd>
							<select field="shape" >
								<option value="Linear">Linear</option>
								<option value="Quadratic">Quadratic</option>
								<option value="Cubic">Cubic</option>
							</select>
						</dd>
				</dl>
			</div>'), this, function(pname) { ctx.onChange(this, pname); });

		if( editor == null ) {
			editor = new hide.prefab.SplineEditor(this, ctx.properties.undo);
		}

		editor.editContext = ctx;
		editor.edit(ctx);
	}

	override function getHideProps() : HideProps {
		return { icon : "arrows-v", name : "Spline" };
	}
	#end

	static var _ = hrt.prefab.Library.register("spline", Spline);
}