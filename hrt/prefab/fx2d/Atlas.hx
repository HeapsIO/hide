package hrt.prefab.fx2d;

class Atlas extends Object2D {

	// parameters
	var src : String;

	var fpsAnimation : Int = 30;
	var delayStart : Float = 0;
	
	var loop : Bool = false;

	var forcePivotCenter : Bool = false;

	var atlas : hxd.res.Atlas;

	override public function load(v:Dynamic) {
		super.load(v);
		this.src = v.src;
		this.fpsAnimation = v.fpsAnimation;
		this.delayStart = v.delayStart;
		this.loop = v.loop;
		this.forcePivotCenter = v.forcePivotCenter;
	}

	override function save() {
		var o : Dynamic = super.save();
		o.src = src;
		o.fpsAnimation = fpsAnimation;
		o.delayStart = delayStart;
		o.loop = loop;
		o.forcePivotCenter = forcePivotCenter;
		return o;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, propName);

		var h2dAnim = (cast ctx.local2d : h2d.Anim);
		
		if (propName == null || propName == "src" || propName == "forcePivotCenter") {
			if (src != null) {
				atlas = hxd.res.Loader.currentInstance.load(src).to(hxd.res.Atlas);
				var tiles = atlas.getAnim();
				if (forcePivotCenter)
					for (t in tiles) t.setCenterRatio(0.5, 0.5);
				h2dAnim.play(tiles);
			} else {
				h2dAnim.play([]);
			}
		}
		if (propName == null || propName == "fpsAnimation") {
			h2dAnim.speed = fpsAnimation;
		}
		if (propName == null || propName == "loop") {
			h2dAnim.loop = loop;
		}
		h2dAnim.pause = !loop;
		h2dAnim.blendMode = blendMode;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var h2dAnim = new h2d.Anim([], fpsAnimation, ctx.local2d);
		ctx.local2d = h2dAnim;
		ctx.local2d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	#if editor
	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var parameters = new hide.Element('<div class="group" name="Parameters"></div>');

		var gr = new hide.Element('<dl></dl>').appendTo(parameters);

		new hide.Element('<dt>Background</dt>').appendTo(gr);
		var element = new hide.Element('<dd></dd>').appendTo(gr);
		var fileInput = new hide.Element('<input type="text" field="src" style="width:165px" />').appendTo(element);

		var tfile = new hide.comp.FileSelect(["atlas"], null, fileInput);
		if (this.src != null && this.src.length > 0) tfile.path = this.src;
		tfile.onChange = function() {
			this.src = tfile.path;
			updateInstance(ctx.getContext(this), "src");
		}
		new hide.Element('<dt>FPS</dt><dd><input type="range" min="0" max="60" step="1" field="fpsAnimation"/></dd>').appendTo(gr);
		new hide.Element('<dt>Delay Start</dt><dd><input type="range" min="0" max="5" field="delayStart"/></dd>').appendTo(gr);
		new hide.Element('<dt>Loop</dt><dd><input type="checkbox" field="loop"/></dd>').appendTo(gr);
		new hide.Element('<dt>Force Pivot Center</dt><dd><input type="checkbox" field="forcePivotCenter"/></dd>').appendTo(gr);
		

		ctx.properties.add(parameters, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Atlas" };
	}

	#end

	static var _ = Library.register("atlas", Atlas);

}