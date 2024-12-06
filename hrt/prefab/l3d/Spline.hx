package hrt.prefab.l3d;

import hxd.Math;

enum HandleType {
	Point;
	TangentIn(point : Spline.SplinePoint);
	TangentOut(point : Spline.SplinePoint);
}

enum SplineShape {
	Linear;
	Quadratic;
	Cubic;
}

class SplinePoint {
	public var pos : h3d.col.Point; // Relative to the spline
	public var up : h3d.Vector; // Relative to the spline
	public var tangentIn : h3d.Vector; // Relative to point
	public var tangentOut : h3d.Vector; // Relative to point
	public var length : Float = 0;
	public var t : Float = 0;

	public function new(?pos: h3d.col.Point, ?up: h3d.Vector, ?tangentIn: h3d.Vector, ?tangentOut: h3d.Vector) {
		this.pos = (pos == null) ? new h3d.col.Point(0, 0, 0) : pos.clone();
		this.up = (up == null) ? new h3d.col.Point(0, 0, 1) : up.clone();
		this.tangentIn = (tangentIn == null) ? new h3d.Vector(-1, 0, 0) : tangentIn.clone();
		this.tangentOut = (tangentOut == null) ? new h3d.Vector(1, 0, 0) : tangentOut.clone();
	}

	public function save() : Dynamic {
		var obj = {
			x: pos.x,
			y: pos.y,
			z: pos.z,
			upX: up.x,
			upY: up.y,
			upZ: up.z,
			tIn: tangentIn,
			tOut: tangentOut,
			t: t,
			length: length,
		}

		return obj;
	}

	public function load(obj : Dynamic) {
		pos = new h3d.col.Point(obj.x, obj.y, obj.z);
		up = new h3d.col.Point(obj.upX, obj.upY, obj.upZ);
		tangentIn = new h3d.Vector(obj.tIn.x, obj.tIn.y, obj.tIn.z);
		tangentOut = new h3d.Vector(obj.tOut.x, obj.tOut.y, obj.tOut.z);
		t = obj.t;
		length = obj.length;
	}
}

@:allow(hrt.prefab.l3d.SplineMesh)
class Spline extends hrt.prefab.Object3D {
	static var OLD_CLASS_POINT = "splinePoint";

	@:c public var points: Array<SplinePoint> = []; // Local to spline
	@:c var samples: Array<SplinePoint> = null; // World relative

	@:s public var loop : Bool = false;
	@:s public var sampleResolution: Int = 16;
	@:c public var shape : SplineShape = Linear;

	#if editor
	static var UPDATE_DELAY_MS = 5;

	var editMode = false;

	var selected = -1;
	var splineUpdateRequested : Bool = false;
	var interactive : h2d.Interactive;
	var grid : h3d.scene.Graphics;
	var mousePos : h3d.Vector;
	var previewSpline : Spline;
	var previewPoint : SplinePoint;
	var draggedObj : { pos: h3d.Vector, type: HandleType };
	var prevPos : h3d.Vector;
	#end

	// Spline display
	@:s public var showSpline : Bool = true;
	var graphics : h3d.scene.Graphics;
	var lineThickness : Int = 2;
	var handlesThickness : Int = 4;
	var tangentThickness : Int = 1;
	var lineColor : Int = 0xFF000000;
	var pointColor : Int = 0xFF69B4;
	var selectedPointColor : Int = 0xFFBA08;
	var tangentColor : Int = 0xFF000000;

	// Spline edition
	var handles : Map<h3d.scene.Graphics, { pos : h3d.col.Point, type: HandleType }> = [];
	var orphanHandles : Array<h3d.scene.Graphics> = [];

	override function save() : Dynamic {
		var obj = super.save();
		obj.points = [ for (p in points) p.save()];
		obj.shape = shape.getIndex();

		if (samples != null)
			obj.samples = [ for (s in samples) s.save()];
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		points = [];

		// Backwards compatibility
		var children = Reflect.field(obj, "children");
		if (children != null) {
			var i = children.length - 1;
			while (i >= 0) {
				if (Reflect.field(children[i], "type") == OLD_CLASS_POINT) {
					var sp = new SplinePoint();
					sp.pos = new h3d.col.Point(children[i].x, children[i].y, children[i].z);

					var m = new h3d.Matrix();
					m.identity();
					m.scale(children[i].scaleX == null ? 1 : children[i].scaleX, children[i].scaleY == null ? 1 : children[i].scaleY, children[i].scaleZ == null ? 1 : children[i].scaleZ);
					m.rotate(children[i].rotationX == null ? 0 : children[i].rotationX * Math.PI / 180.0,
						children[i].rotationY == null ? 0 : children[i].rotationY * Math.PI / 180.0,
						children[i].rotationZ == null ? 0 : children[i].rotationZ * Math.PI / 180.0);

					sp.tangentIn.transform(m);
					sp.tangentOut.transform(m);

					points.push(sp);
					children.remove(children[i]);
				}
				i--;
			}

			if (children.length == 0)
				Reflect.deleteField(obj, "children");
			points.reverse();
		}

		if (obj.points != null) {
			var sPoints : Array<Dynamic> = obj.points;
			for (p in sPoints) {
				var sp = new SplinePoint();
				sp.load(p);
				points.push(sp);
			}
		}

		if (obj.samples != null) {
			samples = [];
			var objSamples : Array<SplinePoint> = obj.samples;
			for (s in objSamples) {
				var objSample = new SplinePoint();
				objSample.load(s);
				samples.push(objSample);
			}
		}

		shape = obj.shape == null ? Linear : SplineShape.createByIndex(obj.shape);
	}

	override function copy(obj : hrt.prefab.Prefab) {
		super.copy(obj);

		var s : Spline = cast obj;
		this.load(s.save());
	}

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		#if editor graphics = null; #end
		return super.makeObject(parent3d);
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);

		#if editor
		samples = null;
		drawSpline();
		#end

		var splineMeshes = findAll(SplineMesh, true);
		for ( s in splineMeshes )
			s.updateInstance();
	}


	inline public function getPoint(t: Float, ?out: h3d.col.Point) : h3d.col.Point {
		if (samples == null)
			sample( (this.shape == SplineShape.Linear) ? 1 : sampleResolution);

		if (samples.length <= 1)
			return null;

		t = hxd.Math.clamp(t, 0, 1);
		var s1 = 0;
		var sa = 0;
		var sb = samples.length-1;
		if( t >= 1 )
			s1 = sb;
		else {
			do {
				s1 = Math.floor((sa+sb)/2);
				if (s1 == -1)
					break;
				if( samples[s1].t < t )
					sa = s1+1;
				else
					sb = s1-1;
			} while( !(samples[s1].t <= t && samples[s1+1].t >= t) );
		}
		var s2 : Int = s1 + 1;
		s2 = hxd.Math.iclamp(s2, 0, samples.length - 1);

		if (out == null)
			out = new h3d.col.Point();

		if (s1 == -1)
			return null;

		// End/Beginning of the curve, just return the point
		if( s1 == s2 )
			out.load(samples[s1].pos);

		// Linear interpolation between the two samples
		var segmentLength = samples[s1].pos.distance(samples[s2].pos);
		if (segmentLength == 0) {
			out.load(samples[s1].pos);
		}
		else {
			var t = (t - samples[s1].t) / (samples[s2].t - samples[s1].t);
			out.lerp(samples[s1].pos, samples[s2].pos, t);
		}

		return out;
	}

	inline public function getNearestPointProgressOnSpline(p: h3d.col.Point) : Float {
		if (samples == null)
			sample((this.shape == SplineShape.Linear) ? 1 : sampleResolution);

		var closestSq = hxd.Math.POSITIVE_INFINITY;
		var closestT = 0.;
		var c = p;
		for (i in 0...samples.length-1) {
			var s1 = samples[i];
			var s2 = samples[i+1];
			var a = s1.pos;
			var b = s2.pos;

			var d = inline new h3d.col.Point();

			var ab = inline b.sub(a);
			var ca = inline c.sub(a);
			var t = inline ca.dot(ab);

			if (t <= 0.0) {
				t = 0.0;
				d.load(a);
			} else {
				var denom = ab.dot(ab);
				if (t >= denom) {
					t = 1.0;
					d.load(b);
				} else {
					t /= denom;
					d.load(inline a.add(inline ab.scaled(t)));
				}
			}

			var cd = inline d.sub(c);
			var lenSq = cd.lengthSq();
			if (lenSq < closestSq) {
				closestSq = lenSq;
				var tLength = s2.t - s1.t;
				closestT = s1.t + t * tLength;
			}
		}
		return closestT;
	}

	public function getLength() {
		if (samples == null)
			sample( (this.shape == SplineShape.Linear) ? 1 : sampleResolution);
		if (samples == null || samples.length == 0)
			return 0.0;
		return samples[samples.length - 1].length;
	}

	public function recomputeTangents() {
		for (idx in 1...points.length) {
			var tan : h3d.Vector;
			if (idx == points.length - 1) {
				tan = (points[idx].pos - points[idx - 1].pos).normalized();
				points[idx].tangentIn = tan * -1.;
				points[idx].tangentOut = tan;
				continue;
			}

			if (idx == 1) {
				tan = (points[1].pos - points[0].pos).normalized();
				points[0].tangentIn = tan * -1.;
				points[0].tangentOut = tan;
			}

			tan = (points[idx + 1].pos - points[idx - 1].pos).normalized();
			points[idx].tangentIn = tan * -1;
			points[idx].tangentOut = tan;
		}
	}

	public function recenterSpline() {
		var centroid = new h3d.col.Point();
		for (p in points) {
			centroid += p.pos;
		}
		centroid *= 1./points.length;

		x += centroid.x;
		y += centroid.y;
		z += centroid.z;

		for (p in points) {
			p.pos.x -= centroid.x;
			p.pos.y -= centroid.y;
			p.pos.z -= centroid.z;
		}
	}


	public function addPoint(?idx : Int, ?point : SplinePoint) {
		var newPoint = point;
		if (newPoint == null)
			newPoint = new SplinePoint();

		if (idx == null)
			idx = points.length;

		points.insert(idx, newPoint);
		this.updateInstance();
	}

	public function removePoint(?idx : Int) {
		if (points.length == 0 || points.length - 1 < idx)
			return;

		var idxToDelete = idx == null ? points.length - 1 : idx;
		points.remove(points[idxToDelete]);
		this.updateInstance();
	}

	public function localToGlobal(point : h3d.col.Point) {
		return point.transformed(getAbsPos(true));
	}

	public function globalToLocal(point : h3d.col.Point) {
		return point.transformed(getAbsPos(true).getInverse());
	}

	public function localToGlobalSplinePoint(sp : SplinePoint) {
		if (sp == null)
			return null;

		var out = new SplinePoint(sp.pos, sp.up, sp.tangentIn, sp.tangentOut);
		out.pos = localToGlobal(out.pos);
		return out;
	}

	public function drawSpline() {
		if( !showSpline || points == null || points.length <= 1) {
			if( graphics != null ) {
				graphics.remove();
				graphics = null;
			}
			return;
		}

		if( graphics == null ) {
			graphics = new h3d.scene.Graphics(local3d);
			graphics.lineStyle(lineThickness, lineColor);
			graphics.name = "lineGraphics";
			graphics.material.mainPass.setPassName("overlay");
			graphics.material.mainPass.depth(false, LessEqual);
			graphics.ignoreParentTransform = false;
		}

		graphics.lineStyle(lineThickness, lineColor);
		graphics.clear();

		var precision = 100;
		var b = true;
		for (idx in 0...(precision)) {
			var point = getPoint(idx/precision);
			if (point == null)
				continue;
			point = point.transformed(getAbsPos(true).getInverse());
			b ? graphics.moveTo(point.x, point.y, point.z) : graphics.lineTo(point.x, point.y, point.z);
			b = false;
		}

		if (loop) {
			var point = points[0].pos;
			graphics.lineTo(point.x, point.y, point.z);
		}
	}

	public function drawHandle(point: SplinePoint) {
		var precision = 100;

		function getPointOnCircle(center : h3d.Vector, radius : Float, t : Float) {
			var angle = t * 2 * Math.PI;
			var x = Math.sin(angle) * radius;
			var y = Math.cos(angle) * radius;

			return new h3d.Vector(center.x + x, center.y + y, center.z);
		}

		function drawCircle(center : h3d.Vector, radius : Float, g : h3d.scene.Graphics) {
			for (idx in 0...precision) {
				var pos = getPointOnCircle(center, radius, 1.0 / precision * idx);
				if (idx == 0)
					g.moveTo(pos.x, pos.y, pos.z);
				else
					g.lineTo(pos.x, pos.y, pos.z);
			}
		}

		function getGraphicsHandle(pos: h3d.col.Point, type: HandleType) {
			var g : h3d.scene.Graphics = null;
			for (handle => obj in handles)
				if (pos == obj.pos)
					g = handle;

			if (g == null) {
				g = new h3d.scene.Graphics(local3d);
				g.lineStyle(lineThickness, lineColor);
				g.name = "handle";
				g.material.mainPass.setPassName("overlay");
				g.material.mainPass.depth(false, LessEqual);
				g.ignoreParentTransform = false;
				handles.set(g, { pos: pos, type: type });
			}

			g.clear();
			return g;
		}

		function getGraphics() {
			var g = new h3d.scene.Graphics(local3d);
			g.lineStyle(lineThickness, lineColor);
			g.name = "orphan_handle";
			g.material.mainPass.setPassName("overlay");
			g.material.mainPass.depth(false, LessEqual);
			g.ignoreParentTransform = false;
			orphanHandles.push(g);
			return g;
		}

		var center = point.pos.clone();

		var pointHandle = getGraphicsHandle(point.pos, Point);
		pointHandle.lineStyle(handlesThickness, #if editor selected == points.indexOf(point) ? selectedPointColor : #end pointColor);
		pointHandle.moveTo(0, 0, 0);
		pointHandle.lineTo(0, 0, 0.5);

		var b = true;
		var radius = 0.3;
		var i = precision;
		while (i > 0) {
			var t = 1.0 / precision * i;
			var center = new h3d.Vector(0, 0, 0);

			if (t == 0.5) {
				var direction = new h3d.Vector(1, 0, 0);
				pointHandle.lineTo(direction.x, direction.y, direction.z);

				var end = getPointOnCircle(center, radius, 1);
				pointHandle.lineTo(end.x, end.y, end.z);
				break;
			}

			var pos = getPointOnCircle(center, radius, 1.0 / precision * i);
			b ? pointHandle.moveTo(pos.x, pos.y, pos.z) : pointHandle.lineTo(pos.x, pos.y, pos.z);
			b = false;
			i--;
		}

		pointHandle.setDirection(point.tangentOut);
		pointHandle.setPosition(center.x, center.y, center.z);

		if (this.shape == SplineShape.Linear)
			return;

		function drawTangent(pos : h3d.col.Point, tangent: h3d.Vector, graphics : h3d.scene.Graphics) {
			var g = getGraphics();
			g.lineStyle(tangentThickness, tangentColor);
			g.moveTo(0, 0, 0);
			g.lineTo(tangent.x, tangent.y, tangent.z);
			g.setPosition(pos.x, pos.y, pos.z);

			graphics.lineStyle(handlesThickness, pointColor);
			drawCircle(new h3d.Vector(0,0,0), 0.2, graphics);

			var abs = pos + tangent;
			graphics.setPosition(abs.x, abs.y, abs.z);
		}

		var tInGraphics = getGraphicsHandle(point.tangentIn, TangentIn(point));
		drawTangent(point.pos, point.tangentIn, tInGraphics);

		var tOutGraphics = getGraphicsHandle(point.tangentOut, TangentOut(point));
		drawTangent(point.pos, point.tangentOut, tOutGraphics);
	}

	public function clearHandles(onlyOrphans = false) {
		while(orphanHandles.length > 0) {
			var h = orphanHandles[orphanHandles.length - 1];
			h.clear();
			orphanHandles.remove(h);
			h.remove();
		}

		if (onlyOrphans)
			return;

		for (handle => obj in handles) {
			handle.clear();
			handles.remove(handle);
			handle.remove();
		}
	}

	public function getLocalCollider() : h3d.col.Collider {
		if (points == null || points.length <= 1)
			return new h3d.col.Bounds();

		var colliders : Array<h3d.col.Collider> = [];

		function getOBCollider(p1: h3d.Vector, p2: h3d.Vector) {
			var col = new h3d.col.OrientedBounds();

			var direction = p2 - p1;
			var q = new h3d.Quat();
			q.initDirection(direction);

			var m = new h3d.Matrix();
			m.initScale(direction.length() + 0.5, 1, 1);
			m = m.multiplied(q.toMatrix());
			m.setPosition(p1 + direction * 0.5);

			col.setMatrix(m);
			return col;
		}

		if (shape == Linear) {
			for (idx in 0...points.length - 1)
				colliders.push(getOBCollider(points[idx].pos, points[idx + 1].pos));
		}
		else {
			var samplePerCollider = 4;
			var idx = 0;
			while (idx < samples.length) {
				var p1 = samples[idx];
				var p2 = idx + samplePerCollider < samples.length ? samples[idx + samplePerCollider] : samples[samples.length - 1];
				colliders.push(getOBCollider(globalToLocal(p1.pos), globalToLocal(p2.pos)));
				idx += samplePerCollider;
			}
		}

		return new h3d.col.Collider.GroupCollider(colliders);
	}

	function sample(numPts: Int) {
		samples = [];

		if( numPts <= 0 ) return;
		if( points == null || points.length <= 1 ) return;

		samples.push(localToGlobalSplinePoint(new SplinePoint(points[0].pos, points[0].up, points[0].tangentIn, points[0].tangentOut)));
		var maxI = loop ? points.length : points.length - 1;
		var curP = localToGlobalSplinePoint(points[0]);
		var nextP = localToGlobalSplinePoint(points[1]);
		var stride = 1./numPts;
		for (i in 1...maxI + 1) {
			for (i in 1...numPts-1) {
				var t = stride * i;
				var p = getPointBetween(t, curP, nextP);
				if (p.distance(samples[samples.length - 1].pos) >= 1./numPts) {
					var newP = new SplinePoint();
					newP.pos = p;
					var tangent = getTangentBetween(t, curP, nextP);
					newP.tangentIn = -1 * tangent;
					newP.tangentOut = tangent;
					samples.push(newP);
				}
				t += stride;
			}

			samples.push(new SplinePoint(nextP.pos, nextP.up, nextP.tangentIn, nextP.tangentOut));

			curP = localToGlobalSplinePoint(points[i]);
			nextP = localToGlobalSplinePoint(points[(i + 1) % points.length]);
		}

		// Compute the average length of the spline
		var length = 0.0;
		for( i in 0 ... samples.length - 1 )
			length += samples[i].pos.distance(samples[i+1].pos);

		var l = 0.0;
		for( i in 0 ... samples.length - 1 ) {
			samples[i].t = l/length;
			samples[i].length = length;
			l += samples[i].pos.distance(samples[i+1].pos);
		}
		samples[samples.length - 1].t = 1;
		samples[samples.length - 1].length = length;
	}


	// -- Spline maths -- //
	inline function getPointBetween( t : Float, p1 : SplinePoint, p2 : SplinePoint ) : h3d.col.Point {
		return switch (shape) {
			case Linear: getLinearBezierPoint( t, p1.pos, p2.pos );
			case Quadratic: getQuadraticBezierPoint( t, p1.pos, p1.tangentOut + p1.pos, p2.pos );
			case Cubic: getCubicBezierPoint( t, p1.pos, p1.tangentOut + p1.pos, p2.tangentIn + p2.pos, p2.pos );
		}
	}

	inline function getLinearBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point ) : h3d.col.Point {
		// Linear Interpolation : p(t) = p0 + (p1 - p0) * t
		return p0.add((p1.sub(p0).scaled(t)));
	}

	inline function getQuadraticBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point) : h3d.col.Point {
		// Quadratic Interpolation : p(t) = p0 * (1 - t)² + p1 * t * 2 * (1 - t) + p2 * t²
		return p0.scaled((1 - t) * (1 - t)).add(p1.scaled(t * 2 * (1 - t))).add(p2.scaled(t * t));
	}

	inline function getCubicBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point, p3 : h3d.col.Point) : h3d.col.Point {
		// Cubic Interpolation : p(t) = p0 * (1 - t)³ + p1 * t * 3 * (1 - t)² + p2 * t² * 3 * (1 - t) + p3 * t³
		return p0.scaled((1 - t) * (1 - t) * (1 - t)).add(p1.scaled(t * 3 * (1 - t) * (1 - t))).add(p2.scaled(t * t * 3 * (1 - t))).add(p3.scaled(t * t * t));
	}

	inline function getTangentBetween( t : Float, p1 : SplinePoint, p2 : SplinePoint ) : h3d.col.Point {
		return switch (shape) {
			case Linear: getLinearBezierTangent( t, p1.pos, p2.pos );
			case Quadratic: getQuadraticBezierTangent( t, p1.pos, p1.tangentOut + p1.pos, p2.pos );
			case Cubic: getCubicBezierTangent( t, p1.pos, p1.tangentOut + p1.pos, p2.tangentIn + p2.pos, p2.pos );
		}
	}

	inline function getLinearBezierTangent( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point ) : h3d.col.Point {
		// Linear Interpolation : p'(t) = (p1 - p0)
		return p1.sub(p0).normalized();
	}

	inline function getQuadraticBezierTangent( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point) : h3d.col.Point {
		// Quadratic Interpolation : p'(t) = 2 * (1 - t) * (p1 - p0) + 2 * t * (p2 - p1)
		return p1.sub(p0).scaled(2 * (1 - t)).add(p2.sub(p1).scaled(2 * t)).normalized();
	}

	inline function getCubicBezierTangent( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point, p3 : h3d.col.Point) : h3d.col.Point {
		// Cubic Interpolation : p'(t) = 3 * (1 - t)² * (p1 - p0) + 6 * (1 - t) * t * (p2 - p1) + 3 * t² * (p3 - p2)
		return p1.sub(p0).scaled(3 * (1 - t) * (1 - t)).add(p2.sub(p1).scaled(6 * (1 - t) * t)).add(p3.sub(p2).scaled(3 * t * t)).normalized();
	}


	#if editor
	override function edit(ctx : hide.prefab.EditContext) {
		super.edit(ctx);

		var props = new hide.Element('
			<div class="group" name="Spline" class="spline">
				<dl>
					<dt>Type</dt>
					<dd>
						<select id="shape">
							<option ${this.shape == SplineShape.Linear ? "selected" : ""} value="0">Linear</option>
							<option ${this.shape == SplineShape.Quadratic ? "selected" : ""} value="1">Quadratic</option>
							<option ${this.shape == SplineShape.Cubic ? "selected" : ""} value="2">Cubic</option>
						</select>
					</dd>
				</dl>
				<dl><dt>Loop</dt><dd><input type="checkbox" field="loop"/></dd></dl>
				<dl><dt>Sample resolution</dt><dd><input type="range" field="sampleResolution" step="1"></dd></dl>
			</div>
			<div class="group spline-editor" name="Spline Editor">
				<div align="center">
					<input type="button" value="Edit Mode : Disabled" class="editModeButton" />
				</div>
				<div class="group points-inspector">
					<div class="buttons">
						<div class="icon ico ico-plus" id="add"></div>
						<div class="icon ico ico-minus" id="remove"></div>
					</div>
					<div class="points-container">
					</div>
				</div>
				<div align="center">
					<input type="button" value="Recompute tangents" class="btn recompute" />
					<input type="button" value="Recenter spline" class="btn recenter" />
				</div>
			</div>
		');

		var editModeButton = props.find(".editModeButton");
		props.find(".editModeButton").click(function(_) {
			if (!enabled) return;
			editMode = !editMode;
			editModeButton.val(editMode ? "Edit Mode : Enabled" : "Edit Mode : Disabled");
			editModeButton.toggleClass("editModeEnabled", editMode);
			setSelected(true);
			clearInteractive();
			if(editMode)
				createInteractive(ctx);
		});

		props.find(".recompute").click(function(_) {
			var prevPoints = [ for (p in points) p.save() ];
			recomputeTangents();
			this.updateInstance();
			refreshHandles();
			var newPoints = [ for (p in points) p.save() ];
			ctx.properties.undo.change(Custom(function(undo) {
				if (undo) {
					points = [];
					for (obj in prevPoints) {
						var p = new SplinePoint();
						p.load(obj);
						points.push(p);
					}
				}
				else {
					points = [];
					for (obj in newPoints) {
						var p = new SplinePoint();
						p.load(obj);
						points.push(p);
					}
				}
				this.updateInstance();
				refreshHandles();
			}));
		});

		props.find(".recenter").click(function(_) {
			var prevPos = new h3d.col.Point(x, y, z);
			var prevPoints = [ for (p in points) p.save() ];
			recenterSpline();
			this.updateInstance();
			refreshHandles();
			refreshPointList(ctx);
			var newPos = new h3d.col.Point(x, y, z);
			var newPoints = [ for (p in points) p.save() ];

			function replaceChildren(offset : h3d.Vector) {
				for (c in children) {
					var obj = Std.downcast(c, Object3D);
					if (obj == null)
						continue;
					obj.x += offset.x;
					obj.y += offset.y;
					obj.z += offset.z;
					obj.updateInstance();
				}
			}
			replaceChildren(prevPos - newPos);

			ctx.properties.undo.change(Custom(function(undo) {
				if (undo) {
					points = [];
					for (obj in prevPoints) {
						var p = new SplinePoint();
						p.load(obj);
						points.push(p);
					}
					x = prevPos.x;
					y = prevPos.y;
					z = prevPos.z;
					replaceChildren(newPos - prevPos);
				}
				else {
					points = [];
					for (obj in newPoints) {
						var p = new SplinePoint();
						p.load(obj);
						points.push(p);
					}
					x = newPos.x;
					y = newPos.y;
					z = newPos.z;
					replaceChildren(prevPos - newPos);
				}
				this.updateInstance();
				refreshHandles();
				refreshPointList(ctx);
			}));
		});

		var selShape = props.find("#shape");
		selShape.change((e) -> {
			var oldV = this.shape;
			var v = Std.parseInt(selShape.val());
			var newV = haxe.EnumTools.createByIndex(SplineShape, v);
			this.shape = newV;
			this.updateInstance();
			refreshHandles();
			ctx.properties.undo.change(Custom(function(undo) {
				this.shape = undo ? oldV : newV;
				selShape.val(this.shape.getIndex());
				this.updateInstance();
				refreshHandles();
			}));
		});

		props.find("#add").first().click((e) -> {
			editorAddPoint(ctx, selected == -1 ? points.length - 1 : selected + 1);
		});

		props.find("#remove").first().click((e) -> {
			editorRemovePoint(ctx, selected == -1 ? points.length - 1 : selected);
		});

		ctx.properties.add(props, this, function(pname) {ctx.onChange(this, pname); });

		refreshPointList(ctx);
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "arrows-v", name : "Spline" };
	}

	override function setSelected(b: Bool) : Bool {
		if (!b)
			clearInteractive();

		return b;
	}


	function refreshPointList(ctx: hide.prefab.EditContext) {
		var pointsContainer = ctx.properties.element.find(".points-container");
		pointsContainer.empty();

		for (pIdx => p in this.points) {
			var pos = points[pIdx].pos;
			var el = new hide.Element('<div class="point folded ${selected == pIdx ? "selected" : ""}">
				<div class="header">
					<div id="fold" class="icon ico ico-chevron-right"></div>
					<p>Point [${pIdx}]</p>
					<div id="remove" class="icon ico ico-close"></div>
				</div>
				<div class="body">
					<dt>Position</dt><dd><input class="pos-x" type="number" value="${pos.x}"/><input class="pos-y" type="number" value="${pos.y}"/><input type="number" class="pos-z" value="${pos.z}"/></dd>
				</div>
			</div>').appendTo(pointsContainer);

			el.find(".header").click((e) -> {
				pointsContainer.find('.point').toggleClass("selected", false);
				el.toggleClass("selected", true);
				selected = pIdx;
				refreshHandles();
			});

			var foldBtn = el.find("#fold");
			foldBtn.click((e) -> {
				var folded = !el.hasClass('folded');
				el.toggleClass("folded", folded);
				foldBtn.toggleClass("ico-chevron-down", !folded);
				foldBtn.toggleClass("ico-chevron-right", folded);
			});

			var removeBtn = el.find("#remove");
			removeBtn.click((e) -> {
				editorRemovePoint(ctx, pIdx);
			});

			var px = el.find(".pos-x");
			var py = el.find(".pos-y");
			var pz = el.find(".pos-z");
			function onPosChange(oldPos : h3d.Vector, newPos : h3d.Vector) {
				points[pIdx].pos.load(newPos);
				this.updateInstance();
				refreshHandles();
				ctx.properties.undo.change(Custom(function(undo) {
					var v = undo ? oldPos : newPos;
					points[pIdx].pos.load(v);
					pos = v;
					this.updateInstance();
					refreshHandles();
					px.val(v.x);
					py.val(v.y);
					pz.val(v.z);
				}));
			}

			px.change((e) -> {
				var newPos = pos.clone();
				newPos.x = Std.parseFloat(px.val());
				onPosChange(pos, newPos);
				pos = newPos;
			});

			py.change((e) -> {
				var newPos = pos.clone();
				newPos.y = Std.parseFloat(py.val());
				onPosChange(pos, newPos);
				pos = newPos;
			});

			pz.change((e) -> {
				var newPos = pos.clone();
				newPos.z = Std.parseFloat(pz.val());
				onPosChange(pos, newPos);
				pos = newPos;
			});
		}
	}

	function editorAddPoint(ctx: hide.prefab.EditContext, pIdx : Int) {
		addPoint(pIdx);
		this.updateInstance();
		refreshHandles();
		refreshPointList(ctx);
		ctx.properties.undo.change(Custom(function(undo) {
			if (undo) {
				removePoint(pIdx);
			}
			else {
				addPoint(pIdx);
			}
			this.updateInstance();
			refreshHandles();
			refreshPointList(ctx);
		}));
	}

	function editorRemovePoint(ctx: hide.prefab.EditContext, pIdx : Int) {
		var p = points[pIdx];
		removePoint(pIdx);
		this.updateInstance();
		refreshHandles();
		refreshPointList(ctx);
		if (selected == pIdx)
			selected = -1;
		ctx.properties.undo.change(Custom(function(undo) {
			if (undo) {
				addPoint(pIdx, p);
			}
			else {
				removePoint(pIdx);
			}
			this.updateInstance();
			refreshHandles();
			refreshPointList(ctx);
		}));
	}

	function refreshHandles() {
		clearHandles();
		if (!editMode)
			return;
		for (p in points)
			drawHandle(p);
	}

	function createInteractive(ctx : hide.prefab.EditContext) {
		var s2d = shared.root2d.getScene();
		var s3d = shared.root3d.getScene();
		var cam = s3d.camera;

		clearInteractive();
		for (p in points)
			drawHandle(p);

		interactive = new h2d.Interactive(s2d.width, s2d.height, s2d);
		interactive.propagateEvents = true;
		interactive.cancelEvents = false;

		interactive.onKeyDown = function(e) {
			if (e.keyCode == hxd.Key.ALT) {
				if (previewPoint == null) {
					previewSpline = cast this.clone(this.parent, this.shared).make();
					previewPoint = new SplinePoint();
					previewSpline.addPoint(null, previewPoint);

					this.local3d.visible = false;
					if (mousePos == null)
						mousePos = new h3d.Vector(e.relX, e.relY);

					var splinePos = local3d.getAbsPos().getPosition();
					var engine = ctx.scene.engine;
					var width = engine.width;
					var height = engine.height;
					function updatePreview() {
						if (previewSpline == null)
							return;

						var nearestSample = getClosestSplinePointFromMouse(mousePos, cam);
						var nearestSamplePos = nearestSample == null ? splinePos : nearestSample.pos;
						var plane = h3d.col.Plane.fromNormalPoint(getCameraClosestEulerPlaneNormal(cam), nearestSamplePos);

						var r = getRay(mousePos.x, mousePos.y, cam, s2d);
						var worldMousePos = r.intersect(plane);

						// Find nearest point on spline
						var nearestSampleScreenPos = cam.projectInline(nearestSamplePos.x, nearestSamplePos.y, nearestSamplePos.z, width, height);
						nearestSampleScreenPos.z = 0;
						if (nearestSampleScreenPos.distance(mousePos) < 20) {
							worldMousePos = nearestSamplePos; // If user's mouse is near the spline, snap the new point on spline
						}
						else {
							var addToEnd = false;
							if (points != null && points.length > 0) {
								var startP = points[0];
								var endP = points[points.length - 1];
								addToEnd = localToGlobal(startP.pos).distanceSq(nearestSamplePos) > localToGlobal(endP.pos).distanceSq(nearestSamplePos);
								var previousP = addToEnd ? endP : startP;
								previousP = localToGlobalSplinePoint(previousP);
								nearestSamplePos = previousP.pos;
							}

							plane = h3d.col.Plane.fromNormalPoint(getCameraClosestEulerPlaneNormal(cam), worldMousePos);
							drawGrid(nearestSamplePos, plane.getNormal(), cam, s3d);
							previewSpline.points.remove(previewPoint);
							previewSpline.addPoint(addToEnd ? previewSpline.points.length : 0, previewPoint);
						}

						worldMousePos = worldMousePos.transformed(getAbsPos(true).getInverse());
						previewPoint.pos = worldMousePos;
						updateSpline(previewSpline);
					}

					updatePreview();
					@:privateAccess s3d.window.mouseMode = Relative(function(e) {
						mousePos.x += e.relX;
						mousePos.y += e.relY;
						updatePreview();
					}, false);
				}

				e.propagate = false;
			}
		}

		interactive.onKeyUp = function(e) {
			if (e.keyCode == hxd.Key.ALT && previewPoint != null) {
				local3d.visible = true;
				clearGrid();
				clearPreviewSpline();
				mousePos = null;
				hxd.Window.getInstance().mouseMode = Absolute;
			}
		}

		interactive.onClick = function(e) {
			if (previewPoint != null) {
				var p = previewPoint;
				var pidx = previewSpline.points.indexOf(previewPoint);
				addPoint(pidx, previewPoint);

				ctx.properties.undo.change(Custom(function(undo) {
					if (undo) {
						removePoint(pidx);
					}
					else {
						addPoint(pidx, p);
					}

					updateSpline(this);
					refreshPointList(ctx);
				}));

				refreshPointList(ctx);
				updateSpline(this);
				clearPreviewSpline();
			}

			e.propagate = false;
		}

		interactive.onPush = function(e) {
			var ray = getRay(e.relX, e.relY, cam, s2d);
			for (handle => obj in handles) {
				var b = handle.getBounds();
				if (b.rayIntersection(ray, true) >= 0.0) {
					mousePos = new h3d.Vector(e.relX, e.relY, 0);
					var plane = h3d.col.Plane.fromNormalPoint(getCameraClosestEulerPlaneNormal(cam), handle.getAbsPos().getPosition());
					draggedObj = obj;
					prevPos = obj.pos.clone();
					drawGrid(handle.getAbsPos().getPosition(), plane.getNormal(), cam, s3d);

					@:privateAccess s3d.window.mouseMode = Relative(function(e) {
						mousePos.x += e.relX;
						mousePos.y += e.relY;

						var r = getRay(mousePos.x, mousePos.y, cam, s2d);
						var pos = r.intersect(plane);
						switch (obj.type) {
							case HandleType.Point:
								var newPos = pos.transformed(getAbsPos(true).getInverse());
								obj.pos.set(newPos.x, newPos.y, newPos.z);
							case HandleType.TangentIn(p):
								var globalToSpline = pos.transformed(getAbsPos(true).getInverse());
								var newPos = globalToSpline - p.pos;
								obj.pos.set(newPos.x, newPos.y, newPos.z);
								p.tangentOut = newPos * -1.;
							case HandleType.TangentOut(p):
								var globalToSpline = pos.transformed(getAbsPos(true).getInverse());
								var newPos = globalToSpline - p.pos;
								obj.pos.set(newPos.x, newPos.y, newPos.z);
								p.tangentIn = newPos * -1.;
						}

						updateSpline(this);
					}, false);
				}
			}

			e.propagate = false;
		}

		interactive.onRelease = function(e) {
			if (draggedObj != null) {
				clearGrid();
				var oldPos = prevPos.clone();
				var newPos = draggedObj.pos.clone();
				var obj = draggedObj;
				@:privateAccess s3d.window.mouseMode = Absolute;
				draggedObj = null;

				ctx.properties.undo.change(Custom(function(undo) {
					if (undo) {
						obj.pos.set(oldPos.x, oldPos.y, oldPos.z);
						switch(obj.type) {
							case HandleType.TangentIn(p):
								p.tangentOut = oldPos * -1.;
							case HandleType.TangentOut(p):
								p.tangentIn = oldPos * -1.;
							default:
						}
					}
					else {
						obj.pos.set(newPos.x, newPos.y, newPos.z);
						switch(obj.type) {
							case HandleType.TangentIn(p):
								p.tangentOut = newPos * -1.;
							case HandleType.TangentOut(p):
								p.tangentIn = newPos * -1.;
							default:
						}
					}

					updateSpline(this);
				}));
			}
		}

		function cancelEventPropagation(e : hxd.Event) {
			if (previewPoint != null)
				e.propagate = false;
		}

		interactive.onWheel = cancelEventPropagation;
		interactive.onMove = cancelEventPropagation;
	}

	function clearInteractive() {
		interactive.remove();
		interactive = null;
		clearHandles();
	}

	function updateSpline(splineToUpdate : Spline) {
		if (splineToUpdate == null)
			splineToUpdate = this;

		if (splineUpdateRequested)
			return;

		splineUpdateRequested = true;
		haxe.Timer.delay(() -> {
			@:privateAccess splineToUpdate.updateInstance();
			splineToUpdate.clearHandles();
				for (p in splineToUpdate.points)
					@:privateAccess splineToUpdate.drawHandle(p);
			splineUpdateRequested = false;
		}, UPDATE_DELAY_MS);
	}

	function clearPreviewSpline() {
		previewSpline?.graphics?.clear();
		previewSpline?.local3d.remove();
		previewSpline?.parent.children.remove(previewSpline);
		previewSpline = null;
		previewPoint = null;
	}

	function drawGrid(center : h3d.col.Point, normal : h3d.Vector, cam : h3d.Camera, s3d : h3d.scene.Scene) {
		var gridStep = 1;
		var gridSize = 100;

		clearGrid();
		if (grid == null) {
			grid = new h3d.scene.Graphics(s3d);
			grid.name = "gridGraphics";
			grid.material.mainPass.setPassName("afterTonemapping");
			grid.material.mainPass.depthWrite = false;
			grid.material.mainPass.depthTest = LessEqual;
			grid.ignoreParentTransform = false;
		}

		grid.lineStyle(0.5, 0xC5C5C5);
		var start = -1 * gridSize / 2;
		for(i in 0...(hxd.Math.floor(gridSize / gridStep) + 1)) {
			grid.moveTo(0, start + (i * gridStep), start);
			grid.lineTo(0, start + (i * gridStep), start + gridSize);

			grid.moveTo(0, start, start + (i * gridStep));
			grid.lineTo(0, start + gridSize, start + (i * gridStep));
		}

		// Draw the two axis of the plane
		var colorX = 0xFF0000;
		var colorY = 0x9DFF00;
		var colorZ = 0x003CFF;

		var vAxisColor = colorX;
		var hAxisColor = colorX;

		if (normal.x != 0) {
			vAxisColor = colorZ;
			hAxisColor = colorY;
		}

		if (normal.y != 0) {
			vAxisColor = colorZ;
			hAxisColor = colorX;
		}

		if (normal.z != 0) {
			vAxisColor = colorX;
			hAxisColor = colorY;
		}

		grid.lineStyle(1.5, hAxisColor);
		grid.moveTo(0, start, 0);
		grid.lineTo(0, -start, 0);

		grid.lineStyle(1.5, vAxisColor);
		grid.moveTo(0, 0, start);
		grid.lineTo(0, 0, -start);

		grid.setPosition(center.x, center.y, center.z);
		grid.setDirection(normal * -1.0, new h3d.Vector(0, 0, 1));

		grid.setScale(getScaleWithCam(grid.getAbsPos().getPosition(), 70, cam));
	}

	function clearGrid() {
		grid?.clear();
		grid?.remove();
		grid = null;
	}

	function getScaleWithCam(origin : h3d.col.Point, ratio : Float, cam : h3d.Camera) {
		var distToCam = cam.pos.sub(origin).length();
		if (hxd.Math.isNaN(distToCam))
			distToCam = 1000000000.0;
		var objRatio = ratio / h3d.Engine.getCurrent().height;
		var scale = objRatio * distToCam * Math.tan(cam.fovY * 0.5 * Math.PI / 180.0);
		if (cam.orthoBounds != null)
			scale = objRatio * (cam.orthoBounds.xSize) * 0.5;
		return scale;
	}

	function getClosestSplinePointFromMouse(mousePos: h3d.Vector, cam : h3d.Camera) : SplinePoint {
		if (samples == null)
			return null;

		var result : SplinePoint = null;
		var minDist = -1.0;
		var engine = h3d.Engine.getCurrent();
		var height = engine.height;
		var width =  engine.width;
		for( sp in samples ) {
			var screenPos = cam.projectInline(sp.pos.x, sp.pos.y, sp.pos.z, width, height);
			screenPos.z = 0;
			var dist = screenPos.distance(mousePos);
			if( dist < minDist || minDist == -1 ) {
				minDist = dist;
				result = sp;
			}
		}
		return result;
	}

	function getCameraClosestEulerPlaneNormal(cam : h3d.Camera) {
		var x = new h3d.Vector(1,0,0);
		var y = new h3d.Vector(0,1,0);
		var z = new h3d.Vector(0,0,1);

		var normal = x;
		var forward = cam.getForward();
		var dot = Math.abs(forward.dot(x));

		var tmpDot = Math.abs(forward.dot(y));
		if (tmpDot > dot) {
			normal = y;
			dot = tmpDot;
		}

		tmpDot = Math.abs(forward.dot(z));
		if (tmpDot > dot) {
			normal = z;
			dot = tmpDot;
		}

		return normal;
	}

	function getRay(mx : Float, my : Float, cam : h3d.Camera, s2d : h2d.Scene) {
		var screenPt = new h2d.col.Point( -1 + 2 * mx / s2d.width, 1 - 2 * my / s2d.height);
		var nearPt = cam.unproject(screenPt.x, screenPt.y, 0);
		var farPt = cam.unproject(screenPt.x, screenPt.y, 1);
		var rayDir = farPt.sub(nearPt).normalized();
		return h3d.col.Ray.fromValues(nearPt.x, nearPt.y, nearPt.z, rayDir.x, rayDir.y, rayDir.z);
	}
	#end

	static var _ = hrt.prefab.Prefab.register("spline", Spline);
}