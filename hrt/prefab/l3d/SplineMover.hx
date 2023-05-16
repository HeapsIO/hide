package hrt.prefab.l3d;
import hrt.prefab.l3d.Spline;

class SplineMoverObject extends h3d.scene.Object {
	var prefab : SplineMover;
	var ctx : Context;

	var state : Spline.MoveAlongSplineState = new Spline.MoveAlongSplineState();
	public var movables : Array<h3d.scene.Object> = [];


	override public function new(?parent : h3d.scene.Object, prefab : SplineMover, ctx:Context) {
		super(parent);
		this.prefab = prefab;
		this.ctx = ctx;
	}

	override function syncRec(rctx:h3d.scene.RenderContext) {
		super.syncRec(rctx);

		var dt = rctx.elapsedTime;
		if (prefab.points.length <= 1)
			return;

		state = prefab.moveAlongSpline(dt * prefab.speed, state);
		var pt = state.point;

		for (c in movables) {
			// kinda hacky but hey
			if (Std.downcast(c, SplinePointObject) == null && c.name != "pointViewer" && c.name != "controlPointsViewer" && c.name != "lineGraphics") {
				c.setPosition(pt.x, pt.y, pt.z);
			}
		}
	}
}

class SplineMover extends Spline {

	public var speed = 1.0;

	override public function new(?parent) {
		super(parent);
	}


	override function createObject(ctx:Context) {
		var obj = new SplineMoverObject(ctx.local3d, this, ctx);
		return obj;
	}

	override public function make( ctx : Context ) : Context {
		if( !enabled )
			return ctx;
		if( ctx == null ) {
			ctx = new Context();
			ctx.init();
		}
		var fromRef = #if editor ctx.shared.parent != null #else true #end;
		if (fromRef && editorOnly #if editor || inGameOnly #end)
			return ctx;
		ctx = makeInstance(ctx);
		for( c in children ){
			var newCtx = null;
			if( ctx.shared.customMake == null )
				newCtx = c.make(ctx);
			else if( c.enabled )
				ctx.shared.customMake(ctx, c);

			if (newCtx!= null && newCtx.local3d != null && Std.downcast(c, SplinePoint) == null) {
				(cast ctx.local3d:SplineMoverObject).movables.push(newCtx.local3d);
			}
		}

		// Original Spline make
		var curCtx = ctx.shared.getContexts(this)[0];
		updateInstance(curCtx);
		return curCtx;
	}

	override function updateInstance(ctx:Context, ?propName:String) {
		super.updateInstance(ctx, propName);

		trace("UpdateInstance");
	}

	#if editor
	override function getHideProps() : HideProps {
		return { icon : "arrows-v", name : "Spline Mover", allowChildren: function(s) return true};
	}

	override function edit(ctx:EditContext) {
		super.edit(ctx);

		ctx.properties.add( new hide.Element('
		<div class="group" name="Mover">
			<dl>
				<dt>Speed</dt><dd><input type="range" min="-100" max="100" field="speed"/></dd>
			</dl>
		</div>'), this, function(pname) { ctx.onChange(this, pname); });
	}
	#end

	static var _ = hrt.prefab.Library.register("splineMover", SplineMover);

}