package hrt.prefab.l2d;
import hxd.Math;
using Lambda;

class Flow extends Object2D {

	@:s public var width : Int = 0;
	@:s public var height : Int = 0;

	@:s var vAlign : Int = 0;
	@:s var hAlign : Int = 0;

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		ctx.local2d = new h2d.Flow(ctx.local2d);
		ctx.local2d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, propName);
		var flow = (cast ctx.local2d : h2d.Flow);
		if( height > 0 ) {
			flow.minHeight = flow.maxHeight = height;
		} else {
			flow.minHeight = flow.maxHeight = null;
		}
		if( width > 0 ) {
			flow.minWidth = flow.maxWidth = width;
		} else {
			flow.minWidth = flow.maxWidth = null;
		}
		flow.verticalAlign = switch (vAlign) {
			case 1:
				Middle;
			case 2:
				Bottom;
			default:
				Top;
		}
		flow.horizontalAlign = switch (vAlign) {
			case 1:
				Middle;
			case 2:
				Right;
			default:
				Left;
		}
	}

	#if editor

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var parameters = new hide.Element('<div class="group" name="Parameters"></div>');

		var gr = new hide.Element('<dl></dl>').appendTo(parameters);

		new hide.Element('<dt>Horizontal Align</dt>').appendTo(gr);
		var hElement = new hide.Element('<dd></dd>').appendTo(gr);
		var leftAlign = new hide.Element('<input type="button" style="width: 50px" value="Left" /> ').appendTo(hElement);
		var middleAlign = new hide.Element('<input type="button" style="width: 50px" value="Center" /> ').appendTo(hElement);
		var rightAlign = new hide.Element('<input type="button" style="width: 50px" value="Right" /> ').appendTo(hElement);
		inline function updateDisabled() {
			leftAlign.removeAttr("disabled");
			middleAlign.removeAttr("disabled");
			rightAlign.removeAttr("disabled");
			switch (hAlign) {
				case 1:
					middleAlign.attr("disabled", "true");
				case 2:
					rightAlign.attr("disabled", "true");
				default:
					leftAlign.attr("disabled", "true");
			}
		}
		leftAlign.on("click", function(e) {
			hAlign = 0;
			updateDisabled();
			updateInstance(ctx.getContext(this), "hAlign");
		});
		middleAlign.on("click", function(e) {
			hAlign = 1;
			updateDisabled();
			updateInstance(ctx.getContext(this), "hAlign");
		});
		rightAlign.on("click", function(e) {
			hAlign = 2;
			updateDisabled();
			updateInstance(ctx.getContext(this), "hAlign");
		});
		
		new hide.Element('<dt>Vertical Align</dt>').appendTo(gr);
		var vElement = new hide.Element('<dd></dd>').appendTo(gr);
		var topAlign = new hide.Element('<input type="button" style="width: 50px" value="Top" /> ').appendTo(vElement);
		var middleAlign = new hide.Element('<input type="button" style="width: 50px" value="Center" /> ').appendTo(vElement);
		var bottomAlign = new hide.Element('<input type="button" style="width: 50px" value="Bottom" /> ').appendTo(vElement);
		inline function updateDisabled() {
			topAlign.removeAttr("disabled");
			middleAlign.removeAttr("disabled");
			bottomAlign.removeAttr("disabled");
			switch (vAlign) {
				case 1:
					middleAlign.attr("disabled", "true");
				case 2:
					bottomAlign.attr("disabled", "true");
				default:
					topAlign.attr("disabled", "true");
			}
		}
		topAlign.on("click", function(e) {
			vAlign = 0;
			updateDisabled();
			updateInstance(ctx.getContext(this), "vAlign");
		});
		middleAlign.on("click", function(e) {
			vAlign = 1;
			updateDisabled();
			updateInstance(ctx.getContext(this), "vAlign");
		});
		rightAlign.on("click", function(e) {
			vAlign = 2;
			updateDisabled();
			updateInstance(ctx.getContext(this), "vAlign");
		});
		updateDisabled();

		new hide.Element('<dt>Height</dt><dd><input type="range" min="0" max="500" field="height" /></dd>').appendTo(gr);
		new hide.Element('<dt>Width</dt><dd><input type="range" min="0" max="500" field="width" /></dd>').appendTo(gr);

		ctx.properties.add(parameters, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Flow" };
	}
	#end

	static var _ = Library.register("flow", Flow);

}