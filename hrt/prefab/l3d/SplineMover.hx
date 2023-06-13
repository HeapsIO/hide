package hrt.prefab.l3d;
import hrt.prefab.l3d.Spline;

class SplineMoverObject extends h3d.scene.Object {
	var prefab : SplineMover;

	var state : Spline.MoveAlongSplineState = new Spline.MoveAlongSplineState();
	public var movables : Array<h3d.scene.Object> = [];

	#if editor
	var debugViz : h3d.scene.Mesh = null;
	#end


	override public function new(?parent : h3d.scene.Object, prefab : SplineMover) {
		super(parent);
		this.prefab = prefab;

		#if editor
		var prim = new h3d.prim.Sphere();
		prim.addNormals();
		debugViz = new h3d.scene.Mesh(prim, this);
		debugViz.material.color.setColor(0xFF0000);
		debugViz.material.shadows = false;
		movables.push(debugViz);
		#end
	}

	override function syncRec(rctx:h3d.scene.RenderContext) {
		super.syncRec(rctx);

		#if editor
		debugViz.visible = prefab.showDebug;
		#end

		updatePoint(rctx.elapsedTime);
	}

	public function updatePoint(dt: Float) {
		if (prefab.points.length <= 1)
			return;

		state = prefab.moveAlongSpline(dt * prefab.speed, state);
		var pt = state.point;

		for (c in movables) {
			if (c.follow == null) {
				// We attach the object to this parent because moveAlongSpline already includes the transform of
				// this spline
				c.follow = this.parent;
			}
			c.setPosition(pt.x, pt.y, pt.z);
		}
	}
}

class SplineMover extends Spline {

	@:s public var speed = 1.0;
	#if editor
	@:s public var showDebug : Bool = true;
	#end

	override public function new(parent, shared) {
		super(parent, shared);
	}


	override function makeObject(parent:h3d.scene.Object) {
		return new SplineMoverObject(parent, this);
	}

	override function makeChild(p:Prefab) {
		super.makeChild(p);
		var l3d = Object3D.getLocal3d(p);
		if (l3d != null && p.to(SplinePoint) == null) {
			(cast local3d:SplineMoverObject).movables.push(l3d);
		}
	}

	override function postMakeInstance() {
		super.postMakeInstance();
		(cast local3d:SplineMoverObject).updatePoint(1.0);
	}

	override function updateInstance(?propName:String) {
		super.updateInstance(propName);

	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "arrows-v", name : "Spline Mover", allowChildren: function(s) return true};
	}

	override function edit(ctx:hide.prefab.EditContext) {
		ctx.properties.add( new hide.Element('
			<p>Important ! Save then reload when you add a child prefab to animate in order to see the animation ! It\'s a known bug.</p>
		'));
		super.edit(ctx);

		ctx.properties.add( new hide.Element('
		<div class="group" name="Mover">
			<dl>
				<dt>Speed</dt><dd><input type="range" min="-100" max="100" field="speed"/></dd>
				<dt>Show Debug</dt><dd><input type="checkbox" field="showDebug"/></dd>
			</dl>
		</div>'), this, function(pname) { ctx.onChange(this, pname); });
	}
	#end

	static var _ = hrt.prefab.Prefab.register("splineMover", SplineMover);

}