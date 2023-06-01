package hrt.prefab2.l2d;

class Anim2D extends Object2D {

	// parameters
	@:s var src : String;
	@:s var widthFrame : Int = 10;
	@:s var heightFrame : Int = 10;
	@:s var fpsAnimation : Int = 30;
	@:s var nbFrames : Int = 30;
	@:s var delayStart : Float = 0;
	@:s var loop : Bool = false;

	var tex : h3d.mat.Texture;

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);

		var h2dAnim = (cast local2d : h2d.Anim);

		if (propName == null || (propName == "src" || propName == "widthFrame" || propName == "heightFrame" || propName == "nbFrames")) {
			if (tex != null) {
				tex = null;
			}
			if (src != null) {
				tex = shared.loadTexture(src);
				var t = h2d.Tile.fromTexture(tex);
				var tiles = [];
				var nbFrameRow = Std.int(t.width / widthFrame);
				for( y in 0...Std.int(t.height / heightFrame) )
					for( x in 0...nbFrameRow)
						if (y * nbFrameRow + x <= nbFrames)
							tiles.push( t.sub(x * widthFrame, y * heightFrame, widthFrame, heightFrame, -(widthFrame / 2), -(heightFrame / 2)) );
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

	override function makeObject(parent2d: h2d.Object) : h2d.Object {
		var h2dAnim = new h2d.Anim([], fpsAnimation, parent2d);
		return h2dAnim;
	}

	#if editor
	override function edit( ctx : hide.prefab2.EditContext ) {
		super.edit(ctx);

		ctx.properties.add(new hide.Element('<div class="group" name="Frames">
			<dl>
				<dt>Background</dt><dd><input type="texturepath" field="src" style="width:165px"/></dd>
				<dt>Width Frame</dt><dd><input type="range" min="0" max="100" step="1" field="widthFrame"/></dd>
				<dt>Height Frame</dt><dd><input type="range" min="0" max="100" step="1" field="heightFrame"/></dd>
				<dt>FPS</dt><dd><input type="range" min="0" max="60" step="1" field="fpsAnimation"/></dd>
				<dt>nbFrames</dt><dd><input type="range" min="0" max="120" step="1" field="nbFrames"/></dd>
				<dt>Delay Start</dt><dd><input type="range" min="0" max="10" field="delayStart"/></dd>
				<dt>Loop</dt><dd><input type="checkbox" field="loop"/></dd>
			</dl></div>'), this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : hide.prefab2.HideProps {
		return { icon : "square", name : "Anim2D" };
	}

	#end

	static var _ = Prefab.register("anim2D", Anim2D);

}