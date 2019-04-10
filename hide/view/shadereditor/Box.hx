package hide.view.shadereditor;

import hide.comp.SVG;
import js.jquery.JQuery;
import hrt.shgraph.ShaderNode;

class Box {

	var nodeInstance : ShaderNode;

	var x : Float;
	var y : Float;

	var width : Int = 150;
	var height : Int;
	var propsHeight : Int = 0;

	var HEADER_HEIGHT = 27;
	@const var NODE_MARGIN = 17;
	public static var NODE_RADIUS = 5;
	@const var NODE_TITLE_PADDING = 10;
	public var selected : Bool = false;

	public var inputs : Array<JQuery> = [];
	public var outputs : Array<JQuery> = [];

	var element : JQuery;
	var propertiesGroup : JQuery;

	public function new(editor : SVG, parent : JQuery, x : Float, y : Float, node : ShaderNode) {
		this.nodeInstance = node;

		var metas = haxe.rtti.Meta.getType(Type.getClass(node));
		if (metas.width != null) {
			this.width = metas.width[0];
		}
		var className = (metas.name != null) ? metas.name[0] : "Undefined";

		element = editor.group(parent).addClass("box").addClass("not-selected");
		element.attr("id", node.id);
		setPosition(x, y);

		// outline of box
		editor.rect(element, -1, -1, width+2, getHeight()+2).addClass("outline");

		// header

		if (Reflect.hasField(metas, "noheader")) {
			HEADER_HEIGHT = 0;
		} else {
			editor.rect(element, 0, 0, this.width, HEADER_HEIGHT).addClass("head-box");
			editor.text(element, 10, HEADER_HEIGHT-8, className).addClass("title-box");
		}

		propertiesGroup = editor.group(element).addClass("properties-group");

		// nodes div
		editor.rect(element, 0, HEADER_HEIGHT, this.width, 0).addClass("nodes");
		editor.line(element, width/2, HEADER_HEIGHT, width/2, 0, {display: "none"}).addClass("nodes-separator");
	}

	public function addInput(editor : SVG, name : String, valueDefault : String = null) {
		var node = editor.group(element).addClass("input-node-group");
		var nodeHeight = HEADER_HEIGHT + NODE_MARGIN * (inputs.length+1) + NODE_RADIUS * inputs.length;
		var nodeCircle = editor.circle(node, 0, nodeHeight, NODE_RADIUS).addClass("node input-node");

		if (name.length > 0)
			editor.text(node, NODE_TITLE_PADDING, nodeHeight + 4, name).addClass("title-node");
		if (valueDefault != null) {
			var widthInput = width / 2 * 0.7;
			var fObject = editor.foreignObject(node, NODE_TITLE_PADDING, nodeHeight - 9, widthInput, 20).addClass("input-field");
			new Element('<input type="text" style="width: ${widthInput - 7}px" value="${valueDefault}" />').appendTo(fObject);
		}

		inputs.push(nodeCircle);
		refreshHeight();

		return node;
	}

	public function addOutput(editor : SVG, name : String) {
		var node = editor.group(element).addClass("output-node-group");
		var nodeHeight = HEADER_HEIGHT + NODE_MARGIN * (outputs.length+1) + NODE_RADIUS * outputs.length;
		var nodeCircle = editor.circle(node, width, nodeHeight, NODE_RADIUS).addClass("node output-node");

		if (name.length > 0)
			editor.text(node, width - NODE_TITLE_PADDING - (name.length * 6.75), nodeHeight + 4, name).addClass("title-node");

		outputs.push(nodeCircle);

		refreshHeight();
		return node;
	}

	public function generateProperties(editor : SVG) {
		var props = nodeInstance.getPropertiesHTML(this.width);

		if (props.length == 0) return;

		if (inputs.length <= 1 && outputs.length <= 1) {
			element.find(".nodes").remove();
			element.find(".input-node-group > .title-node").html("");
			element.find(".output-node-group > .title-node").html("");
		}

			// create properties box
		editor.rect(propertiesGroup, 0, 0, this.width, 0).addClass("properties");
		propsHeight = 5;

		for (p in props) {
			var prop = editor.group(propertiesGroup).addClass("prop-group");
			prop.attr("transform", 'translate(0, ${propsHeight})');

			var propWidth = (p.width() > 0 ? p.width() : this.width);
			var fObject = editor.foreignObject(prop, (this.width - propWidth) / 2, 5, propWidth, p.height());
			p.appendTo(fObject);
			propsHeight += Std.int(p.height()) + 5;
		}

		refreshHeight();
	}

	public function dispose() {
		element.remove();
	}

	function refreshHeight() {
		var height = getNodesHeight();
		element.find(".nodes").height(height);
		element.find(".outline").attr("height", getHeight()+2);
		if (inputs.length > 1 || outputs.length > 1 || propsHeight == 0) {
			element.find(".nodes-separator").attr("y2", HEADER_HEIGHT + height);
			element.find(".nodes-separator").show();
		} else {
			element.find(".nodes-separator").hide();
		}

		if (propertiesGroup != null) {
			propertiesGroup.attr("transform", 'translate(0, ${HEADER_HEIGHT + height})');
			propertiesGroup.find(".properties").attr("height", propsHeight);
		}
	}

	public function setPosition(x : Float, y : Float) {
		this.x = x;
		this.y = y;
		element.attr({transform: 'translate(${x} ${y})'});
	}

	public function setSelected(b : Bool) {
		selected = b;
		if (b) {
			element.removeClass("not-selected");
			element.addClass("selected");
		} else {
			element.removeClass("selected");
			element.addClass("not-selected");
		}
	}
	public function getId() {
		return this.nodeInstance.id;
	}
	public function getShaderNode() {
		return this.nodeInstance;
	}
	public function getX() {
		return this.x;
	}
	public function getY() {
		return this.y;
	}
	public function getWidth() {
		return this.width;
	}
	public function getNodesHeight() {
		var maxNb = Std.int(Math.max(inputs.length, outputs.length));
		if (maxNb == 1 && propsHeight > 0) {
			return 0;
		}
		return NODE_MARGIN * (maxNb+1) + NODE_RADIUS * maxNb;
	}
	public function getHeight() {
		return HEADER_HEIGHT + getNodesHeight() + propsHeight;
	}
	public function getElement() {
		return element;
	}
}