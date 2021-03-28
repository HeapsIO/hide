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
	?t : Float
}

class SplineData {
	public var length : Float;
	public var step : Float;
	public var threshold : Float;
	public var samples : Array<SplinePointData> = [];
	public function new() {}
}

class SplinePoint extends h3d.scene.Object {

	public function new(x : Float, y : Float, z : Float, parent : h3d.scene.Object) {
		super(parent);
		setPosition(x,y,z);
	}

	inline public function getPoint() : h3d.col.Point {
		return getAbsPos().getPosition().toPoint();
	}

	public function getTangent() : h3d.col.Point {
		var tangent = getAbsPos().front().toPoint();
		tangent.scale(-1);
		return tangent;
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
	@:c public var shape : CurveShape = Quadratic;

	var data : SplineData;
	@:s var step : Float = 1.0;
	@:s var threshold : Float = 0.01;

	// Save/Load the curve as an array of absPos
	@:c public var pointsData : Array<h3d.Matrix> = [];

	// Graphic
	@:s public var showSpline : Bool = true;
	public var lineGraphics : h3d.scene.Graphics;
	@:s public var lineThickness : Int = 4;
	@:s public var color : Int = 0xFFFFFFFF;
	@:s public var loop : Bool = false;

	#if editor
	public var editor : hide.prefab.SplineEditor;
	#end
	public var wasEdited = false;

	override function save() {
		var obj : Dynamic = super.save();

		var tmp = new h3d.Matrix();
		inline function getTransform( o : h3d.scene.Object, m : h3d.Matrix ) : h3d.Matrix {
			m.identity();
			@:privateAccess o.qRot.toMatrix(m);
			m._11 *= o.scaleX;
			m._12 *= o.scaleX;
			m._13 *= o.scaleX;
			m._21 *= o.scaleY;
			m._22 *= o.scaleY;
			m._23 *= o.scaleY;
			m._31 *= o.scaleZ;
			m._32 *= o.scaleZ;
			m._33 *= o.scaleZ;
			m._41 = o.x;
			m._42 = o.y;
			m._43 = o.z;
			return m;
		}

		if( points != null && points.length > 0 && wasEdited ) {
			obj.points = [ for(sp in points) {
								var m = getTransform(sp, tmp);
								[for(f in m.getFloats()) hxd.Math.fmt(f) ];
							} ];
		}
		// Clone support
		else if( pointsData != null && pointsData.length > 0 ) {
			obj.points =  [ for(abs in pointsData) {
								[for(f in abs.getFloats()) hxd.Math.fmt(f) ];
							} ];
		}
		obj.shape = shape.getIndex();
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		pointsData = [];
		if( obj.points != null ) {
			var points : Array<Dynamic> = obj.points;
			for( p in points ) {
				var m = new h3d.Matrix();
				m.loadValues(p);
				pointsData.push(m);
			}
		}
		shape = obj.shape == null ? Linear : CurveShape.createByIndex(obj.shape);
	}

	// Generate the splineData from a matrix, can't move the spline after that
	public function makeFromMatrix( m : h3d.Matrix ) {
		var tmp = new h3d.Matrix();
		points = [];
		for( pd in pointsData ) {
			var sp = new SplinePoint(0, 0, 0, null);
			tmp.load(pd);
			tmp.multiply(tmp, m);
			sp.setTransform(tmp);
			sp.getAbsPos();
			points.push(sp);
		}
		computeSplineData();
	}

	override function makeInstance( ctx : hrt.prefab.Context ) : hrt.prefab.Context {
		var ctx = ctx.clone(this);
		ctx.local3d = new h3d.scene.Object(ctx.local3d);
		ctx.local3d.name = name;

		points = [];
		for( pd in pointsData ) {
			var sp = new SplinePoint(0, 0, 0, ctx.local3d);
			sp.setTransform(pd);
			sp.getAbsPos();
			points.push(sp);
		}

		if( points.length == 0 )
			points.push(new SplinePoint(0,0,0, ctx.local3d));

		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance( ctx : hrt.prefab.Context , ?propName : String ) {
		super.updateInstance(ctx, propName);
		computeSplineData();

		#if editor
		if( editor != null )
			editor.update(ctx, propName);
		generateSplineGraph(ctx);
		#end
	}

	// Return an interpolation of two samples at t, 0 <= t <= 1
	public function getPointAt( t : Float, ?pos: h3d.col.Point, ?tangent: h3d.col.Point ) : h3d.col.Point {
		if( data == null )
			computeSplineData();

		var l = t * data.length;

		// The last point is not at the same distance, be aware of that case
		t = hxd.Math.clamp(t);
		var s1 : Int = hxd.Math.floor(l / step);
		var s2 : Int = hxd.Math.ceil(l / step);
		s1 = hxd.Math.iclamp(s1, 0, data.samples.length - 1);
		s2 = hxd.Math.iclamp(s2, 0, data.samples.length - 1);

		if(pos == null)
			pos = new h3d.col.Point();

		// End/Beginning of the curve, just return the point
		if( s1 == s2 ) {
			pos.load(data.samples[s1].pos);
			if(tangent != null)
				tangent.load(data.samples[s1].tangent);
		}
		// Linear interpolation between the two samples
		else {
			var segmentLength = data.samples[s1].pos.distance(data.samples[s2].pos);
			var t = (l - (s1 * step)) / segmentLength;
			pos.lerp(data.samples[s1].pos, data.samples[s2].pos, t);
			if(tangent != null)
				tangent.lerp(data.samples[s1].tangent, data.samples[s2].tangent, t);
		}
		return pos;
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

	// Return the sum of the euclidean distances between each samples
	public function getLength() {
		if( data == null )
			computeSplineData();
		return data.length;
	}

	// Sample the spline with the step and threshold
	function computeSplineData() {

		var sd = new SplineData();
		data = sd;

		if( step <= 0 || threshold <= 0 )
			return;

		if( points == null || points.length <= 1 )
			return;

		// Sample the spline
		var samples : Array<SplinePointData> = [{ pos : points[0].getPoint(), tangent : points[0].getTangent(), prev : points[0], next : points[1] }];
		var i = 0;
		var sumT = 0.0;
		var maxT = 1.0;
		var minT = 0.0;
		var maxI = loop ? points.length : points.length - 1;
		var curP = points[0];
		var nextP = points[1];
		while( i < maxI ) {
			var t = (maxT + minT) * 0.5;

			var p = getPointBetween(t, curP, nextP);
			var curSegmentLength = p.distance(samples[samples.length - 1].pos);

			// Point found
			if( hxd.Math.abs(curSegmentLength - step) <= threshold ) {
				samples.insert(samples.length, { pos : p, tangent : getTangentBetween(t, curP, nextP), prev : curP, next : nextP });
				sumT = t;
				maxT = 1.0;
				minT = sumT;
				// Last point of the curve too close from the last sample
				if( nextP.getPoint().distance(samples[samples.length - 1].pos) < step ) {
					// End of the spline
					if( i == maxI - 1 ) {
						samples.insert(samples.length, { pos : nextP.getPoint(), tangent : nextP.getTangent(), prev : curP, next : nextP, t : 1.0 });
						break;
					}
					// End of the current curve
					else {
						i++;
						curP = points[i];
						nextP = points[(i+1) % points.length];
						sumT = 0.0;
						minT = 0.0;
						maxT = 1.0;
					}
				}
			}
			// Point not found
			else if( curSegmentLength > step ) {
				maxT = maxT - (maxT - minT) * 0.5;
			}
			else if( curSegmentLength < step ) {
				minT = minT + (maxT - minT) * 0.5;
			}
		}
		sd.samples = samples;

		// Compute the average length of the spline
		var lengthSum = 0.0;
		for( i in 0 ... samples.length - 1 ) {
			lengthSum += samples[i].pos.distance(samples[i+1].pos);
		}
		var l = 0.0;
		for( i in 0 ... samples.length - 1 ) {
			samples[i].t = l/lengthSum;
			l += samples[i].pos.distance(samples[i+1].pos);
		}
		sd.length = lengthSum;
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
	function getClosestPoint( p : h3d.col.Point ) : SplinePointData {

		if( data == null )
			computeSplineData();

		var minDist = -1.0;
		var result : SplinePointData = null;
		for( s in data.samples ) {
			var dist = s.pos.distance(p);
			if( dist < minDist || minDist == -1 ) {
				minDist = dist;
				result = s;
			}
		}
		return result;
	}

	// Return the point on the curve between p1 and p2 at t, 0 <= t <= 1
	inline function getPointBetween( t : Float, p1 : SplinePoint, p2 : SplinePoint ) : h3d.col.Point {
		return switch (shape) {
			case Linear: getLinearBezierPoint( t, p1.getPoint(), p2.getPoint() );
			case Quadratic: getQuadraticBezierPoint( t, p1.getPoint(), p1.getSecondControlPoint(), p2.getPoint() );
			case Cubic: getCubicBezierPoint( t, p1.getPoint(), p1.getSecondControlPoint(), p2.getFirstControlPoint(), p2.getPoint() );
		}
	}

	// Return the tangent on the curve between p1 and p2 at t, 0 <= t <= 1
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
		return p1.sub(p0).normalized();
	}

	// Quadratic Interpolation
	// p(t) = p0 * (1 - t)² + p1 * t * 2 * (1 - t) + p2 * t²
	inline function getQuadraticBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point) : h3d.col.Point {
		return p0.multiply((1 - t) * (1 - t)).add(p1.multiply(t * 2 * (1 - t))).add(p2.multiply(t * t));
	}
	// p'(t) = 2 * (1 - t) * (p1 - p0) + 2 * t * (p2 - p1)
	inline function getQuadraticBezierTangent( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point) : h3d.col.Point {
		return p1.sub(p0).multiply(2 * (1 - t)).add(p2.sub(p1).multiply(2 * t)).normalized();
	}

	// Cubic Interpolation
	// p(t) = p0 * (1 - t)³ + p1 * t * 3 * (1 - t)² + p2 * t² * 3 * (1 - t) + p3 * t³
	inline function getCubicBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point, p3 : h3d.col.Point) : h3d.col.Point {
		return p0.multiply((1 - t) * (1 - t) * (1 - t)).add(p1.multiply(t * 3 * (1 - t) * (1 - t))).add(p2.multiply(t * t * 3 * (1 - t))).add(p3.multiply(t * t * t));
	}
	// p'(t) = 3 * (1 - t)² * (p1 - p0) + 6 * (1 - t) * t * (p2 - p1) + 3 * t² * (p3 - p2)
	inline function getCubicBezierTangent( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point, p3 : h3d.col.Point) : h3d.col.Point {
		return p1.sub(p0).multiply(3 * (1 - t) * (1 - t)).add(p2.sub(p1).multiply(6 * (1 - t) * t)).add(p3.sub(p2).multiply(3 * t * t)).normalized();
	}

	function generateSplineGraph( ctx : hrt.prefab.Context ) {

		if( !showSpline ) {
			if( lineGraphics != null ) {
				lineGraphics.remove();
				lineGraphics = null;
			}
			return;
		}

		if( lineGraphics == null ) {
			lineGraphics = new h3d.scene.Graphics(ctx.local3d);
			lineGraphics.lineStyle(lineThickness, color);
			lineGraphics.material.mainPass.setPassName("overlay");
			lineGraphics.material.mainPass.depth(false, LessEqual);
			lineGraphics.ignoreParentTransform = false;
		}

		lineGraphics.lineStyle(lineThickness, color);
		lineGraphics.clear();
		var b = true;
		for( s in data.samples ) {
			var localPos = ctx.local3d.globalToLocal(s.pos);
			b ? lineGraphics.moveTo(localPos.x, localPos.y, localPos.z) : lineGraphics.lineTo(localPos.x, localPos.y, localPos.z);
			b = false;
		}
	}

	#if editor

	public function onEdit( b : Bool ) {
		if( b ) wasEdited = true;
	}

	override function setSelected( ctx : hrt.prefab.Context , b : Bool ) {
		super.setSelected(ctx, b);

		if( editor != null )
			editor.setSelected(ctx, b);

		return true;
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		ctx.properties.add( new hide.Element('
			<div class="group" name="Spline">
				<dl>
					<dt>Color</dt><dd><input type="color" alpha="true" field="color"/></dd>
					<dt>Thickness</dt><dd><input type="range" min="1" max="10" field="lineThickness"/></dd>
					<dt>Step</dt><dd><input type="range" min="0.1" max="1" field="step"/></dd>
					<dt>Threshold</dt><dd><input type="range" min="0.001" max="1" field="threshold"/></dd>
					<dt>Loop</dt><dd><input type="checkbox" field="loop"/></dd>
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