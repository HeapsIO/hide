package hrt.prefab2.l2d;

class Atlas extends Object2D {

	// parameters
	@:s var src : String;
	@:s var fpsAnimation : Int = 30;
	@:s var delayStart : Float = 0;
	@:s var loop : Bool = false;
	@:s var forcePivotCenter : Bool = false;

	var atlas : hxd.res.Atlas;

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);

		var h2dAnim = (cast local2d : h2d.Anim);
		h2dAnim.smooth = true;

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

		#if editor
			var int = Std.downcast(h2dAnim.getChildAt(0),h2d.Interactive);
			if( int != null ) {
				int.width = h2dAnim.getFrame().width;
				int.height = h2dAnim.getFrame().height;
			}
		#end
	}

	override function makeObject(parent2d:h2d.Object): h2d.Object {
		var h2dAnim = new h2d.Anim([], fpsAnimation, parent2d);
		return h2dAnim;
	}

	#if editor

	override function makeInteractive():h2d.Interactive {
		if(local2d == null)
			return null;
		var h2dAnim = cast(local2d, h2d.Anim);
		var frame = h2dAnim.getFrame();
		if( frame == null )
			return null;
		var int = new h2d.Interactive(frame.width, frame.height);
		h2dAnim.addChildAt(int, 0);
		int.propagateEvents = true;
		return int;
	}

	override function edit( ctx : hide.prefab2.EditContext ) {
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
			updateInstance("src");
		}
		new hide.Element('<dt>FPS</dt><dd><input type="range" min="0" max="60" step="1" field="fpsAnimation"/></dd>').appendTo(gr);
		new hide.Element('<dt>Delay Start</dt><dd><input type="range" min="0" max="5" field="delayStart"/></dd>').appendTo(gr);
		new hide.Element('<dt>Loop</dt><dd><input type="checkbox" field="loop"/></dd>').appendTo(gr);
		new hide.Element('<dt>Force Pivot Center</dt><dd><input type="checkbox" field="forcePivotCenter"/></dd>').appendTo(gr);


		ctx.properties.add(parameters, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : hide.prefab2.HideProps {
		return { icon : "square", name : "Atlas" };
	}

	#end

	static var _ = Prefab.register("atlas", Atlas);

}