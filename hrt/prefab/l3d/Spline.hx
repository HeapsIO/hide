package hrt.prefab.l3d;

enum CurveShape {
	Linear;
	Quadratic;
	Cubic;
}

typedef SplinePointData = {
	pos : h3d.col.Point,
	prev : SplinePoint,
	next : SplinePoint
}

class SplinePoint extends h3d.scene.Object {

	public var distanceToNextPoint = -1.0;

	public function new(x : Float, y : Float, z : Float, parent : h3d.scene.Object) {
		super(parent);
		setPosition(x,y,z);
	}

	var p = new h3d.col.Point();
	public function getPoint() : h3d.col.Point {
		var absPos = getAbsPos();
		p.set(absPos.tx, absPos.ty, absPos.tz);
		return p;
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

	public var pointsData : Array<h3d.Matrix> = [];
	public var points : Array<SplinePoint> = [];
	public var shape : CurveShape = Quadratic;
	
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
		obj.points = [ for(sp in points) { sp.getAbsPos(); } ];
		obj.shape = shape;
		obj.color = color;
		obj.linePrecision = linePrecision;
		obj.lineThickness = lineThickness;
		obj.loop = loop;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		pointsData = obj.points == null ? [] : obj.points;
		shape = obj.shape == null ? Linear : obj.shape;
		color = obj.color != null ? obj.color : 0xFFFFFFFF;
		linePrecision = obj.linePrecision == null ? 15 : obj.linePrecision;
		lineThickness = obj.lineThickness == null ? 4 : obj.lineThickness;
		loop = obj.loop == null ? false : obj.loop;
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
	function getLengthBetween( p1 : SplinePoint, p2 : SplinePoint, ?precision : Float = 1.0 ) : Float {

		if( shape == Linear ) {
			return getMinLengthBetween(p1, p2);
		}

		if( p1.distanceToNextPoint > 0 ) 
			return p1.distanceToNextPoint;

		var sum = 0.0;
		var maxLength = getMaxLengthBetween(p1, p2);
		var minLength = getMinLengthBetween(p1, p2);
		var stepCount = hxd.Math.ceil(precision * maxLength);

		var curPt : h3d.col.Point = p1.getPoint();
		var step = 1.0 / stepCount;
		var t = step;
		for( i in 0 ... stepCount ) {
			var nextPt = getPointBetween(t, p1, p2);
			sum += curPt.distance(nextPt);
			curPt = nextPt;
			t += step;
		}

		p1.distanceToNextPoint = sum;

		return sum;
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
		var length = getLength();
		var stepCount = hxd.Math.ceil(length * precision);
		var minDist = -1.0;
		var result : SplinePointData = { pos : null, prev : null, next : null };
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

	// Return the point on the spline between p1 and p2 at t ( 0 -> 1 )
	function getPoint( t : Float, ?precision : Float = 1.0 ) : SplinePointData {
		t = hxd.Math.clamp(t, 0, 1);
		if( t == 0 ) return { pos : points[0].getPoint(), prev : points[0], next : points[0] } ;
		if( t == 1 ) return { pos : points[points.length - 1].getPoint(), prev : points[points.length - 1], next : points[points.length - 1] };

		var result : SplinePointData;
		var totalLength = getLength();
		var length = totalLength * t;
		var curlength = 0.0;
		for( i in 0 ... points.length - 1 ) {
			var curSegmentLength = getLengthBetween(points[i], points[i+1], precision);
			curlength += curSegmentLength;
			if( length <= curlength ) 
				return { pos : getPointBetween( (length - (curlength - curSegmentLength)) / curSegmentLength, points[i], points[i+1]), prev : points[i], next : points[i+1] } ;
		}
		return { pos : points[points.length - 1].getPoint(), prev : points[points.length - 1], next : points[points.length - 1] };
	}

	// Return the point on the curve between p1 and p2 at t ( 0 -> 1 )
	inline function getPointBetween( t : Float, p1 : SplinePoint, p2 : SplinePoint ) {
		return switch (shape) {
			case Linear: getLinearBezierPoint( t, p1.getPoint(), p2.getPoint() );
			case Quadratic: getQuadraticBezierPoint( t, p1.getPoint(), p1.getSecondControlPoint(), p2.getPoint() );
			case Cubic: getCubicBezierPoint( t, p1.getPoint(), p1.getSecondControlPoint(), p2.getFirstControlPoint(), p2.getPoint() );
		}
	}

	// Linear Interpolation 
	// p(t) = p0 + (p1 - p0) * t
	inline function getLinearBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point ) : h3d.col.Point {
		return p0.add((p1.sub(p0).multiply(t)));
	}

	// Quadratic Interpolation 
	// p(t) = p0 * (1 - t)² + p1 * t * 2 * (1 - t) + p2 * t²
	inline function getQuadraticBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point) : h3d.col.Point {
		return p0.multiply((1 - t) * (1 - t)).add(p1.multiply(t * 2 * (1 - t))).add(p2.multiply(t * t));
	}

	// Cubic Interpolation
	// p(t) = p0 * (1 - t)³ + p1 * t * 3 * (1 - t)² + p2 * t² * 3 * (1 - t) + p3 * t³
	inline function getCubicBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point, p3 : h3d.col.Point) : h3d.col.Point {
		return p0.multiply((1 - t) * (1 - t) * (1 - t)).add(p1.multiply(t * 3 * (1 - t) * (1 - t))).add(p2.multiply(t * t * 3 * (1 - t))).add(p3.multiply(t * t * t));
	}

	#if editor

	function generateBezierCurve( ctx : hrt.prefab.Context ) {

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

		//lineGraphics.visible = b;
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		ctx.properties.add( new hide.Element('
			<div class="group" name="Spline">
				<dl>
					<dt>Color</dt><dd><input type="color" alpha="true" field="color"/></dd>
					<dt>Thickness</dt><dd><input type="range" min="1" max="10" field="lineThickness"/></dd>
					<dt>Precision</dt><dd><input type="range" step="1" min="1" max="100" field="linePrecision"/></dd>
					<dt>Loop</dt><dd><input type="checkbox" field="loop"/></dd>
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