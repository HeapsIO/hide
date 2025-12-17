package hrt.prefab.l2d;
import hxd.Math;
using Lambda;

class Flow extends Object2D {

	@:s public var width : Int = 0;
	@:s public var height : Int = 0;

	@:s var vAlign : Int = 0;
	@:s var hAlign : Int = 0;

	override function makeObject(parent2d: h2d.Object) : h2d.Object {
		return new h2d.Flow(parent2d);
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);
		var flow = (cast local2d : h2d.Flow);
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

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		super.edit2(ctx);

		ctx.build(
			<category("Parameters")>
				<line label="Horizontal Align">
					<button("Left") id="hLeftBtn"/>
					<button("Center") id="hCenterBtn"/>
					<button("Right") id="hRightBtn"/>
				</line>
				<line label="Vertical Align">
					<button("Top") id="vTopBtn"/>
					<button("Center") id="vCenterBtn"/>
					<button("Bottom") id="vBottomBtn"/>
				</line>
				<range(0, 500) field={height}/>
				<range(0, 500) field={width}/>
			</category>
		);

		function updateHorizontalBtn() {
			hLeftBtn.disabled = false;
			hCenterBtn.disabled = false;
			hRightBtn.disabled = false;
			switch( hAlign ) {
				case 1: hCenterBtn.disabled = true;
				case 2: hRightBtn.disabled = true;
				default: hLeftBtn.disabled = true;
			}
		}
		hLeftBtn.onClick = function() {
			hAlign = 0;
			updateHorizontalBtn();
			updateInstance("hAlign");
		}
		hCenterBtn.onClick = function() {
			hAlign = 1;
			updateHorizontalBtn();
			updateInstance("hAlign");
		}
		hRightBtn.onClick = function() {
			hAlign = 2;
			updateHorizontalBtn();
			updateInstance("hAlign");
		}

		inline function updateVerticalBtn() {
			vTopBtn.disabled = false;
			vCenterBtn.disabled = false;
			vBottomBtn.disabled = false;
			switch( vAlign ) {
				case 1: vCenterBtn.disabled = true;
				case 2: vBottomBtn.disabled = true;
				default: vTopBtn.disabled = true;
			}
		}
		vTopBtn.onClick = function() {
			vAlign = 0;
			updateVerticalBtn();
			updateInstance("vAlign");
		}
		vCenterBtn.onClick = function() {
			vAlign = 1;
			updateVerticalBtn();
			updateInstance("vAlign");
		}
		vBottomBtn.onClick = function() {
			vAlign = 2;
			updateVerticalBtn();
			updateInstance("vAlign");
		}

		updateHorizontalBtn();
		updateVerticalBtn();
	}

	#if editor

	override function edit( ctx : hide.prefab.EditContext ) {
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
			updateInstance("hAlign");
		});
		middleAlign.on("click", function(e) {
			hAlign = 1;
			updateDisabled();
			updateInstance("hAlign");
		});
		rightAlign.on("click", function(e) {
			hAlign = 2;
			updateDisabled();
			updateInstance("hAlign");
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
			updateInstance("vAlign");
		});
		middleAlign.on("click", function(e) {
			vAlign = 1;
			updateDisabled();
			updateInstance("vAlign");
		});
		rightAlign.on("click", function(e) {
			vAlign = 2;
			updateDisabled();
			updateInstance("vAlign");
		});
		updateDisabled();

		new hide.Element('<dt>Height</dt><dd><input type="range" min="0" max="500" field="height" /></dd>').appendTo(gr);
		new hide.Element('<dt>Width</dt><dd><input type="range" min="0" max="500" field="width" /></dd>').appendTo(gr);

		ctx.properties.add(parameters, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "square", name : "Flow" };
	}
	#end

	static var _ = Prefab.register("flow", Flow);

}