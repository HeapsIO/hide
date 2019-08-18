package hrt.prefab.l3d;

enum CurveShape {
	Linear;
	Quadratic;
	Cubic;
}

class SplinePoint extends h3d.scene.Object {

	public function new(x : Float, y : Float, z : Float, parent : h3d.scene.Object) {
		super(parent);
		setPosition(x,y,z);
		scale(1);
	}

	public function getPoint() : h3d.col.Point {
		var absPos = getAbsPos();
		var pos = new h3d.col.Point(absPos.tx, absPos.ty, absPos.tz);
		return pos;
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

	#if editor
	public var editor : hide.prefab.SplineEditor;
	public var lineGraphics : h3d.scene.Graphics;
	public var precision : Int = 15;
	public var color : Int = 0xFFFFFFFF;
	#end

	override function save() {
		var obj : Dynamic = super.save();
		obj.points = [ for(sp in points) { sp.getAbsPos(); } ];
		obj.shape = shape;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		pointsData = obj.points == null ? [] : obj.points;
		shape = obj.shape == null ? Linear : obj.shape;
	}

	override function makeInstance( ctx : hrt.prefab.Context ) : hrt.prefab.Context {
		var ctx = ctx.clone(this);

		ctx.local3d = new h3d.scene.Object(ctx.local3d);
		ctx.local3d.name = name;

		#if editor
		lineGraphics = new h3d.scene.Graphics(ctx.local3d);
		lineGraphics.lineStyle(2, color);
		lineGraphics.material.mainPass.setPassName("overlay");
		lineGraphics.material.mainPass.depth(false, LessEqual);
		lineGraphics.ignoreParentTransform = false;

		/*points = [];
		points.push(new SplinePoint(0,0,0, ctx.local3d));
		points.push(new SplinePoint(5,10,0, ctx.local3d));
		points.push(new SplinePoint(-5,20,5, ctx.local3d));
		points.push(new SplinePoint(-10,30,0, ctx.local3d));
		points.push(new SplinePoint(10,40,-5, ctx.local3d));*/
		#end
	
		for( pd in pointsData ) {
			var sp = new SplinePoint(0, 0, 0, ctx.local3d);
			sp.setTransform(pd);
			points.push(sp);
		}
		pointsData = null;

		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance( ctx : hrt.prefab.Context , ?propName : String ) {
		super.updateInstance(ctx, propName);
		#if editor
		lineGraphics.lineStyle(2, color);
		if( editor != null )
			editor.update(ctx, propName);
		generateBezierCurve(ctx);
		#end
	}

	// Linear Interpolation 
	// p(t) = p0 + (p1 - p0) * t
	function getLinearBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point ) : h3d.col.Point {
		return p0.add((p1.sub(p0).multiply(t)));
	}

	// Quadratic Interpolation 
	// p(t) = p0 * (1 - t)² + p1 * t * 2 * (1 - t) + p2 * t²
	function getQuadraticBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point) : h3d.col.Point {
		return p0.multiply((1 - t) * (1 - t)).add(p1.multiply(t * 2 * (1 - t))).add(p2.multiply(t * t));
	}

	// Cubic Interpolation
	// p(t) = p0 * (1 - t)³ + p1 * t * 3 * (1 - t)² + p2 * t² * 3 *(1 - t) + p3 * t³
	function getCubicBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point, p3 : h3d.col.Point) : h3d.col.Point {
		return p0.multiply((1 - t) * (1 - t) * (1 - t)).add(p1.multiply(t * 3 * (1 - t) * (1 - t))).add(p2.multiply(t * t * 3 * (1 - t))).add(p3.multiply(t * t * t));
	}

	#if editor

	function generateBezierCurve( ctx : hrt.prefab.Context ) {

		if( points == null )
			return;

		var curve : Array<h3d.col.Point> = [];
		switch (shape) {
			case Linear:
				for( sp in points )
					curve.push(sp.getPoint());
			case Quadratic:
				var i = 0;
				while( i < points.length - 1 ) {
					for( v in 0 ... precision + 1 ) {
						curve.push(getQuadraticBezierPoint( v / precision, points[i].getPoint(), points[i].getSecondControlPoint(), points[i+1].getPoint()));
					}
					++i;
				}
			case Cubic:
				var i = 0;
				while( i < points.length - 1 ) {
					for( v in 0 ... precision + 1 ) {
						curve.push(getCubicBezierPoint( v / precision, points[i].getPoint(), points[i].getSecondControlPoint(), points[i+1].getFirstControlPoint(), points[i+1].getPoint()));
					}
					++i;
				}
		}

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
					<dt>Type</dt>
						<dd>
							<select field="shape" >
								<option value="Linear">Linear</option>
								<option value="Quadratic">Quadratic</option>
								<option value="Cubic">Cubic</option>
							</select>
						</dd>
					<dt>Precision</dt><dd><input type="range"step="1" min="1" max="100" field="precision"/></dd>
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