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
	public var m : h3d.Matrix; // Relative to the spline
	public var tangentIn : h3d.Vector; // Relative to point
	public var tangentOut : h3d.Vector; // Relative to point
	public var length : Float = 0;
	public var t : Float = 0;

	public function new(?m : h3d.Matrix, ?tangentIn: h3d.Vector, ?tangentOut: h3d.Vector) {
		if (m == null) {
			this.m = new h3d.Matrix();
			this.m.identity();
		}
		else {
			this.m = m.clone();
		}

		this.tangentIn = (tangentIn == null) ? new h3d.Vector(-1, 0, 0) : tangentIn.clone();
		this.tangentOut = (tangentOut == null) ? new h3d.Vector(1, 0, 0) : tangentOut.clone();
	}

	public function save() : Dynamic {
		var pos = m.getPosition();
		var rot = m.getEulerAngles();
		var scale = m.getScale();

		var obj = {
			x: pos.x,
			y: pos.y,
			z: pos.z,
			rotX: rot.x,
			rotY: rot.y,
			rotZ: rot.z,
			tIn: tangentIn,
			tOut: tangentOut,
			t: t,
			length: length,
		}

		return obj;
	}

	public function load(obj : Dynamic) {
		m = new h3d.Matrix();
		m.initRotation(obj.rotX, obj.rotY, obj.rotZ);
		m.translate(obj.x, obj.y, obj.z);

		tangentIn = obj.tIn;
		tangentOut = obj.tOut;

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
	@:c public var length: Float = 0.;
	@:c public var shape : SplineShape = Linear;

	// Spline display
	@:s public var showSpline : Bool = true;
	var graphics : h3d.scene.Graphics;
	var lineThickness : Int = 2;
	var handlesThickness : Int = 4;
	var tangentThickness : Int = 1;
	var lineColor : Int = 0xFF000000;
	var pointColor : Int = 0xFF69B4;
	var tangentColor : Int = 0xFF000000;

	// Spline edition
	var handles : Map<h3d.scene.Graphics, { m : h3d.Matrix, type: HandleType }> = [];
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
					sp.m.initTranslation(children[i].x, children[i].y, children[i].z);

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
				if( samples[s1].t < t )
					sa = s1+1;
				else
					sb = s1-1;
			} while( !(samples[s1].t <= t && samples[s1+1].t > t) );
		}
		var s2 : Int = s1 + 1;
		s2 = hxd.Math.iclamp(s2, 0, samples.length - 1);

		if (out == null)
			out = new h3d.col.Point();

		// End/Beginning of the curve, just return the point
		if( s1 == s2 )
			out.load(samples[s1].m.getPosition());

		// Linear interpolation between the two samples
		var segmentLength = samples[s1].m.getPosition().distance(samples[s2].m.getPosition());
		if (segmentLength == 0) {
			out.load(samples[s1].m.getPosition());
		}
		else {
			var t = (t - samples[s1].t) / (samples[s2].t - samples[s1].t);
			out.lerp(samples[s1].m.getPosition(), samples[s2].m.getPosition(), t);
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
			var a = s1.m.getPosition();
			var b = s2.m.getPosition();

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

	public function localToGlobal(point : h3d.Matrix) {
		return point.multiplied(getAbsPos(true));
	}

	public function globalToLocal(point : h3d.Matrix) {
		return point.multiplied(getAbsPos(true).getInverse());
	}

	public function localToGlobalSplinePoint(sp : SplinePoint) {
		if (sp == null)
			return null;

		var out = new SplinePoint(sp.m, sp.tangentIn, sp.tangentOut);
		out.m = localToGlobal(out.m);
		return out;
	}

	public function drawSpline() {
		if( !showSpline ) {
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

		function getGraphicsHandle(m: h3d.Matrix, type: HandleType) {
			var g : h3d.scene.Graphics = null;
			for (handle => obj in handles)
				if (m == obj.m)
					g = handle;

			if (g == null) {
				g = new h3d.scene.Graphics(local3d);
				g.lineStyle(lineThickness, lineColor);
				g.name = "handle";
				g.material.mainPass.setPassName("overlay");
				g.material.mainPass.depth(false, LessEqual);
				g.ignoreParentTransform = false;
				handles.set(g, { m: m, type: type });
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

		var center = point.m.getPosition().clone();

		var pointHandle = getGraphicsHandle(point.m, Point);
		pointHandle.lineStyle(handlesThickness, pointColor);
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

		pointHandle.setDirection( point.tangentOut.transformed3x3(point.m));
		pointHandle.setPosition(center.x, center.y, center.z);

		if (this.shape == SplineShape.Linear)
			return;

		function drawTangent(point : h3d.Matrix, tangent: h3d.Vector, graphics : h3d.scene.Graphics) {
			var posPoint = point.getPosition();

			var absTan = tangent.transformed(point);
			var relTan = tangent;

			var g = getGraphics();
			g.lineStyle(tangentThickness, tangentColor);
			g.moveTo(0, 0, 0);
			g.lineTo(relTan.x, relTan.y, relTan.z);
			g.setPosition(posPoint.x, posPoint.y, posPoint.z);

			graphics.lineStyle(handlesThickness, pointColor);
			drawCircle(new h3d.Vector(0,0,0), 0.2, graphics);
			graphics.setPosition(absTan.x, absTan.y, absTan.z);
		}

		var tIn = new h3d.Matrix();
		tIn.initTranslation(point.tangentIn.x, point.tangentIn.y, point.tangentIn.z);
		var tInGraphics = getGraphicsHandle(tIn, TangentIn(point));
		drawTangent(point.m.clone(), point.tangentIn.clone(), tInGraphics);

		var tOut = new h3d.Matrix();
		tOut.initTranslation(point.tangentOut.x, point.tangentOut.y, point.tangentOut.z);
		var tOutGraphics = getGraphicsHandle(tOut, TangentOut(point));
		drawTangent(point.m.clone(), point.tangentOut.clone(), tOutGraphics);
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
				colliders.push(getOBCollider(points[idx].m.getPosition(), points[idx + 1].m.getPosition()));
		}
		else {
			var samplePerCollider = 4;
			var idx = 0;
			while (idx < samples.length) {
				var p1 = samples[idx];
				var p2 = idx + samplePerCollider < samples.length ? samples[idx + samplePerCollider] : samples[samples.length - 1];
				colliders.push(getOBCollider(globalToLocal(p1.m).getPosition(), globalToLocal(p2.m).getPosition()));
				idx += samplePerCollider;
			}
		}

		return new h3d.col.Collider.GroupCollider(colliders);
	}

	function sample(numPts: Int) {
		samples = [];

		if( numPts <= 0 ) return;
		if( points == null || points.length <= 1 ) return;

		samples.push(localToGlobalSplinePoint(new SplinePoint(points[0].m, points[0].tangentIn, points[0].tangentOut)));
		var maxI = loop ? points.length : points.length - 1;
		var curP = localToGlobalSplinePoint(points[0]);
		var nextP = localToGlobalSplinePoint(points[1]);
		var stride = 1./numPts;
		for (i in 1...maxI + 1) {
			for (i in 1...numPts-1) {
				var t = stride * i;
				var p = getPointBetween(t, curP, nextP);
				if (p.distance(samples[samples.length - 1].m.getPosition()) >= 1./numPts) {
					var newP = new SplinePoint();
					newP.m.initTranslation(p.x, p.y, p.z);
					var tangent = getTangentBetween(t, curP, nextP);
					newP.tangentIn = -1 * tangent;
					newP.tangentOut = tangent;
					samples.push(newP);
				}
				t += stride;
			}

			samples.push(new SplinePoint(nextP.m, nextP.tangentIn, nextP.tangentOut));

			curP = localToGlobalSplinePoint(points[i]);
			nextP = localToGlobalSplinePoint(points[(i + 1) % points.length]);
		}

		// Compute the average length of the spline
		length = 0.0;
		for( i in 0 ... samples.length - 1 )
			length += samples[i].m.getPosition().distance(samples[i+1].m.getPosition());

		var l = 0.0;
		for( i in 0 ... samples.length - 1 ) {
			samples[i].t = l/length;
			l += samples[i].m.getPosition().distance(samples[i+1].m.getPosition());
		}
		samples[samples.length - 1].t = 1;
	}


	// -- Spline maths -- //
	inline function getPointBetween( t : Float, p1 : SplinePoint, p2 : SplinePoint ) : h3d.col.Point {
		return switch (shape) {
			case Linear: getLinearBezierPoint( t, p1.m.getPosition(), p2.m.getPosition() );
			case Quadratic: getQuadraticBezierPoint( t, p1.m.getPosition(), p1.tangentOut.transformed(p1.m), p2.m.getPosition() );
			case Cubic: getCubicBezierPoint( t, p1.m.getPosition(), p1.tangentOut.transformed(p1.m), p2.tangentIn.transformed(p2.m), p2.m.getPosition() );
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
			case Linear: getLinearBezierTangent( t, p1.m.getPosition(), p2.m.getPosition() );
			case Quadratic: getQuadraticBezierTangent( t, p1.m.getPosition(), p1.tangentOut.clone().transformed(p1.m), p2.m.getPosition() );
			case Cubic: getCubicBezierTangent( t, p1.m.getPosition(), p1.tangentOut.transformed(p1.m), p2.tangentIn.transformed(p2.m), p2.m.getPosition() );
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

		function refreshHandles() {
			clearHandles();
			for (p in points)
				drawHandle(p);
		}

		var props = new hide.Element('
			<div class="group" name="Spline">
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
			</div>
		');

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


		var pointsEl = new hide.Element('
		<div class="group points-inspector">
			<div class="buttons">
				<div class="icon ico ico-plus" id="add"></div>
				<div class="icon ico ico-minus" id="remove"></div>
			</div>
			<div class="points-container">
			</div>
		</div>').appendTo(props);

		pointsEl.find("#add").first().click((e) -> {
			var newP = new SplinePoint();
			if (points.length > 0)
				newP.m = points[points.length -1].m.clone();

			newP.m.translate(1, 0, 0);
			this.addPoint(null, newP);
		});
		pointsEl.find("#remove").first().click((e) -> {
			this.removePoint();
		});

		for (pIdx => p in this.points) {
			var pos = points[pIdx].m.getPosition();
			var rot = points[pIdx].m.getEulerAngles();
			var el = new hide.Element('<div class="point">
				<div class="header">
					<div class="icon ico ico-chevron-down"></div>
					<p>Point [${pIdx}]</p>
				</div>
				<div class="body">
					<dt>Position</dt><dd><input class="pos-x" type="number" value="${pos.x}"/><input class="pos-y" type="number" value="${pos.y}"/><input type="number" class="pos-z" value="${pos.z}"/></dd>
					<dt>Rotation</dt><dd><input type="number" value="${rot.x * 180.0 / hxd.Math.PI}"/><input type="number" value="${rot.y * 180.0 / hxd.Math.PI}"/><input type="number" value="${rot.z * 180.0 / hxd.Math.PI}"/></dd>
				</div>
			</div>').appendTo(pointsEl.find('.points-container'));

			var foldBtn = el.find(".icon");
			foldBtn.click((e) -> {
				var folded = !el.hasClass('folded');
				el.toggleClass("folded", folded);
				foldBtn.toggleClass("ico-chevron-down", !folded);
				foldBtn.toggleClass("ico-chevron-right", folded);
			});

			var px = el.find(".pos-x");
			var py = el.find(".pos-y");
			var pz = el.find(".pos-z");
			function onPosChange(oldPos : h3d.Vector, newPos : h3d.Vector) {
				points[pIdx].m.setPosition(newPos);
				this.updateInstance();
				refreshHandles();
				ctx.properties.undo.change(Custom(function(undo) {
					var v = undo ? oldPos : newPos;
					points[pIdx].m.setPosition(v);
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

		ctx.properties.add(props, null, null);
		refreshHandles();
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "arrows-v", name : "Spline" };
	}
	#end

	static var _ = hrt.prefab.Prefab.register("spline", Spline);
}