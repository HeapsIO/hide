package hide.view.shadereditor;

import hide.comp.SVG;
import js.jquery.JQuery;
import hide.view.GraphInterface;

@:access(hide.view.GraphEditor)
class Box {

	static final boolColor = "#cc0505";
	static final numberColor = "#00ffea";
	static final floatColor = "#00ff73";
	static final intColor = "#00ffea";
	static final vec2Color = "#5eff00";
	static final vec3Color = "#eeff00";
	static final vec4Color = "#fc6703";
	static final samplerColor = "#600aff";
	static final defaultColor = "#c8c8c8";

	var node : IGraphNode;
	var info : GraphNodeInfo;

	var x : Float;
	var y : Float;
	var width : Int;
	var height : Int;
	var propsHeight : Int = 0;

	public var HEADER_HEIGHT = 22;
	public static final NODE_MARGIN = 18;
	public static var NODE_RADIUS = 5;
	@const var NODE_TITLE_PADDING = 10;
	@const var NODE_INPUT_PADDING = 3;
	public var selected : Bool = false;

	public var inputs : Array<JQuery> = [];
	public var outputs : Array<JQuery> = [];

	var hasHeader : Bool = true;
	var color : String;
	var closePreviewBtn : JQuery;

	var element : JQuery;
	var propertiesGroup : JQuery;
	static final resizeBorder : Int = 8;
	static final halfResizeBorder : Int = resizeBorder >> 1;

	public function new(editor : GraphEditor, parent : JQuery, node : IGraphNode) {
		this.node = node;
		info = node.getInfo();


		width = info.width ?? 150;
		width = Std.int(hxd.Math.ceil(width / NODE_MARGIN) * NODE_MARGIN);

		//var metas = haxe.rtti.Meta.getType(Type.getClass(node));
		//if (metas.width != null) {
		//	this.width = metas.width[0];
		//}

		//if (Reflect.hasField(metas, "color")) {
		//	color = Reflect.field(metas, "color");
		//}
		//var className = node.nameOverride ?? ((metas.name != null) ? metas.name[0] : "Undefined");

		element = editor.editorDisplay.group(parent).addClass("box").addClass("not-selected");
		element.attr("id", node.getId());

		if (info.comment != null) {
			info.comment.getSize(tmpPoint);
			this.width = Std.int(tmpPoint.x);
			this.height = Std.int(tmpPoint.y);
			HEADER_HEIGHT = 34;
			color = null;
			this.element.addClass("comment");
		}

		if (info.noHeader ?? false) {
			HEADER_HEIGHT = 0;
			hasHeader = false;
		}

		// Debug: editor.editorDisplay.text(element, 2, -6, 'Node ${node.id}').addClass("node-id-indicator");

		if (info.comment == null) {
			editor.editorDisplay.rect(element, 0,0,width, getHeight()).addClass("background");

		}
		editor.editorDisplay.rect(element, -1, -1, width+2, getHeight()+2).addClass("outline");

		if (info.comment != null) {

			editor.editorDisplay.rect(element, 0,0,width, HEADER_HEIGHT).addClass("head-box");


			function makeResizable(elt: js.html.Element, left: Bool, top: Bool, right: Bool, bottom: Bool) {
				var pressed = false;

				elt.onpointerdown = function(e: js.html.PointerEvent) {
					if (e.button != 0)
						return;
					e.stopPropagation();
					e.preventDefault();
					pressed = true;
					elt.setPointerCapture(e.pointerId);
				};

				elt.onpointermove = function(e: js.html.PointerEvent) {
					if (!pressed)
						return;
					e.stopPropagation();
					e.preventDefault();

					var clientRect = editor.editorDisplay.element.get(0).getBoundingClientRect();

					var x0 : Int = Std.int(x);
					var y0 : Int = Std.int(y);
					var x1 : Int = x0 + width;
					var y1 : Int = y0 + height;

					var mx : Int = Std.int(editor.lX(e.clientX));
					var my : Int = Std.int(editor.lY(e.clientY));

					var minDim = 10;
					if (left) {
						x0 = hxd.Math.imin(mx, x1 - minDim);
					}

					if (top) {
						y0 = hxd.Math.imin(my, y1 - minDim);
					}

					if (right) {
						x1 = hxd.Math.imax(mx, x0 + minDim);
					}

					if (bottom) {
						y1 = hxd.Math.imax(my, y0 + minDim);
					}

					setPosition(x0,y0);

					this.width = x1 - x0;
					this.height = y1 - y0;
					refreshBox();
				}

				elt.onpointerup = function (e: js.html.PointerEvent) {
					if (!pressed)
						return;
					pressed = false;
					e.stopPropagation();
					e.preventDefault();

					this.node.getPos(tmpPoint);
					var current = {x: tmpPoint.x, y:tmpPoint.y, w: this.width, h: this.height};
					editor.opMove(this, this.x, this.y, editor.currentUndoBuffer);
					editor.opResize(this, this.width, this.height, editor.currentUndoBuffer);
					editor.commitUndo();
				};
			}

			var elt = editor.editorDisplay.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "ns-resize";
			elt.id = "resizeBot";
			makeResizable(elt, false,false,false,true);

			var elt = editor.editorDisplay.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "ns-resize";
			elt.id = "resizeTop";
			makeResizable(elt, false,true,false,false);

			var elt = editor.editorDisplay.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "ew-resize";
			elt.id = "resizeLeft";
			makeResizable(elt, true,false,false,false);

			var elt = editor.editorDisplay.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "ew-resize";
			elt.id = "resizeRight";
			makeResizable(elt, false,false,true,false);

			var elt = editor.editorDisplay.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "nesw-resize";
			elt.id = "resizeBotLeft";
			makeResizable(elt, true,false,false,true);

			var elt = editor.editorDisplay.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "nwse-resize";
			elt.id = "resizeBotRight";
			makeResizable(elt, false,false,true,true);

			var elt = editor.editorDisplay.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "nwse-resize";
			elt.id = "resizeTopLeft";
			makeResizable(elt, true,true,false,false);

			var elt = editor.editorDisplay.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "nesw-resize";
			elt.id = "resizeTopRight";
			makeResizable(elt, false,true,true,false);

			var fo = editor.editorDisplay.foreignObject(element, 7, 2, 0, HEADER_HEIGHT-4);
			fo.get(0).id = "commentTitle";
			var commentTitle = new Element("<span contenteditable spellcheck='false'>Comment</span>").addClass("comment-title").appendTo(fo);

			var editable = new hide.comp.ContentEditable(null, commentTitle);
			editable.value = info.comment.getComment();
			editable.onChange = function(v: String) {
				editor.opComment(this, v, editor.currentUndoBuffer);
				editor.commitUndo();
			};

			refreshBox();
			return;
		}

		// header

		if (hasHeader) {
			//var header = editor.editorDisplay.rect(element, 0, 0, this.width, HEADER_HEIGHT).addClass("head-box");
			//if (color != null) header.css("fill", color);
			if (info.comment != null) {

			}
			else {
				editor.editorDisplay.text(element, 7, HEADER_HEIGHT-6, info.name).addClass("title-box");
			}
		}

		propertiesGroup = editor.editorDisplay.group(element).addClass("properties-group");

		// nodes div

		editor.editorDisplay.line(element, 0, HEADER_HEIGHT, width, HEADER_HEIGHT).addClass("separator");

		// var bg = editor.editorDisplay.rect(element, 0, HEADER_HEIGHT, this.width, 0).addClass("nodes");
		// if (!hasHeader && color != null) {
		// 	bg.css("fill", color);
		// }

		if (info.preview != null) {
			closePreviewBtn = editor.editorDisplay.foreignObject(element, width / 2 - 16, 0, 32,32);
			closePreviewBtn.append(new JQuery('<div class="close-preview"><span class="ico"></span></div>'));

			refreshCloseIcon();
			closePreviewBtn.get(0).addEventListener("click", (e) -> {
				e.stopPropagation();
				setPreviewVisibility(!info.preview.getVisible());
			}, {capture: true});
		}

		refreshBox();
		//editor.editorDisplay.line(element, width/2, HEADER_HEIGHT, width/2, 0, {display: "none"}).addClass("nodes-separator");
	}

	public function setPreviewVisibility(visible: Bool) {
		if (info.preview != null) {
			info.preview.setVisible(visible);
			refreshCloseIcon();
		}
	}

	function refreshCloseIcon() {
		if (closePreviewBtn == null)
			return;
		var viz = info.preview.getVisible();
		closePreviewBtn.find(".ico").toggleClass("ico-angle-down", !viz);
		closePreviewBtn.find(".ico").toggleClass("ico-angle-up", viz);
	}

	public function addInput(editor : GraphEditor, name : String, valueDefault : String = null, color : Int) {
		var node = editor.editorDisplay.group(element).addClass("input-node-group");
		var nodeHeight = getNodeHeight(inputs.length);
		var style = {fill : '#${StringTools.hex(color, 6)}'};

		var nodeCircle = editor.editorDisplay.circle(node, 0, nodeHeight, NODE_RADIUS, style).addClass("node input-node");

		var nameWidth = 0.0;
		if (name.length > 0 && name != "input") {
			var inputName = editor.editorDisplay.text(node, NODE_TITLE_PADDING, nodeHeight + 4, name).addClass("title-node");
			var domName : js.html.svg.GraphicsElement = cast inputName.get()[0];
			nameWidth = domName.getBBox().width;
		}
		if (valueDefault != null) {
			var widthInput = width / 2 * 0.7;
			var fObject = editor.editorDisplay.foreignObject(
				node,
				nameWidth + NODE_TITLE_PADDING + NODE_INPUT_PADDING,
				nodeHeight - 9,
				widthInput,
				20
			).addClass("input-field");
			new Element('<input type="text" style="width: ${widthInput - 7}px" value="${valueDefault}" />')
				.mousedown((e) -> e.stopPropagation())
				.appendTo(fObject);
		}

		inputs.push(nodeCircle);
		refreshBox();

		return node;
	}

	public static function getTypeColor(type : hrt.shgraph.ShaderGraph.SgType) {
		return switch (type) {
			case SgBool:
				boolColor;
			case SgInt:
				intColor;
			case SgFloat(1):
				floatColor;
			case SgFloat(2):
				vec2Color;
			case SgFloat(3):
				vec3Color;
			case SgFloat(_):
				vec4Color;
			case SgGeneric(_, _):
				vec4Color;
			case SgSampler:
				samplerColor;
		}
	}

	public function addOutput(editor : GraphEditor, name : String, color : Int) {
		var node = editor.editorDisplay.group(element).addClass("output-node-group");
		var nodeHeight = getNodeHeight(outputs.length);
		var style = {fill : '#${StringTools.hex(color, 6)}'};


		var nodeCircle = editor.editorDisplay.circle(node, width, nodeHeight, NODE_RADIUS, style).addClass("node output-node");

		if (name.length > 0 && name != "output")
			editor.editorDisplay.text(node, width - NODE_TITLE_PADDING, nodeHeight + 4, name).addClass("title-node").attr("text-anchor", "end");

		outputs.push(nodeCircle);

		refreshBox();
		return node;
	}

	public function getNodeHeight(id: Int) {
		return NODE_MARGIN * (id+2);
	}

	public function generateProperties(editor : GraphEditor) {
		var props = node.getPropertiesHTML(this.width);

		if (props.length == 0) return;

		var children = propertiesGroup.children();
		if (children.length > 0) {
			for (c in children) {
				c.remove();
			}
		}

		// create properties box
		if (!collapseProperties()) {
			editor.editorDisplay.line(propertiesGroup, 0, 0, this.width, 0).addClass("separator");
		}

		//var bgParam = editor.editorDisplay.rect(propertiesGroup, 0, 0, this.width, 0).addClass("properties");
		//if (!hasHeader && color != null) bgParam.css("fill", color);
		propsHeight = 0;

		for (p in props) {
			var prop = editor.editorDisplay.group(propertiesGroup).addClass("prop-group");
			prop.attr("transform", 'translate(0, ${propsHeight})');

			var propWidth = (p.width() > 0 ? p.width() : this.width);
			var fObject = editor.editorDisplay.foreignObject(prop, (this.width - propWidth) / 2, 5, propWidth, p.height());
			p.appendTo(fObject);
			propsHeight += Std.int(p.outerHeight()) + 1;
		}

		propsHeight += 10;

		refreshBox();
	}

	public function dispose() {
		element.remove();
	}

	function refreshBox() {
		var width = width;
		var nodesHeight = getNodesHeight();
		var height = getHeight();
		element.find(".nodes").height(nodesHeight).width(width);
		element.find(".background").attr("height", height).width(width);
		element.find(".outline").attr("height", height+2).width(width+2);

		if (hasHeader) {
			element.find(".head-box").width(width);
		}

		if (info.comment != null) {
			var hB = halfResizeBorder;
			var rB = resizeBorder;
			element.find("#resizeBot").attr("x", hB).attr("y", height - hB).width(width - rB).height(rB);
			element.find("#resizeTop").attr("x", hB).attr("y", - hB).width(width - rB).height(rB);
			element.find("#resizeLeft").attr("x", -hB).attr("y", hB).width(rB).height(height-rB);
			element.find("#resizeRight").attr("x", width-hB).attr("y", hB).width(rB).height(height-rB);
			element.find("#resizeBotLeft").attr("x", -hB).attr("y", height-hB).width(rB).height(rB);
			element.find("#resizeBotRight").attr("x", width-hB).attr("y", height-hB).width(rB).height(rB);
			element.find("#resizeTopLeft").attr("x", -hB).attr("y", -hB).width(rB).height(rB);
			element.find("#resizeTopRight").attr("x", width-hB).attr("y", -hB).width(rB).height(rB);
			element.find("#commentTitle").attr("width", width - 2);
		}

		if (inputs.length >= 1 && outputs.length >= 1) {
			element.find(".nodes-separator").attr("y2", nodesHeight);
			element.find(".nodes-separator").show();
		}

		if (propertiesGroup != null) {
			propertiesGroup.attr("transform", 'translate(0, ${collapseProperties() ? getNodeHeight(0) - 16 : nodesHeight})');
			propertiesGroup.find(".properties").attr("height", propsHeight);
		}

		closePreviewBtn?.attr("y", getHeight() - 12);
	}

	public static var tmpPoint = new h2d.col.Point();
	public function setPosition(x : Float, y : Float) {
		element.attr({transform: 'translate(${x} ${y})'});
		this.x = x;
		this.y = y;
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
	public function setTitle(str : String) {
		if (hasHeader) {
			element.find(".title-box").html(str);
		}
	}

	public function getInstance() {
		return this.node;
	}

	public function collapseProperties() {
		return info.inputs.length <= 1 && info.outputs.length <= 1;
	}

	public function getNodesHeight() {
		var maxNb = Std.int(Math.max(inputs.length, outputs.length));
		if (info.comment != null) {
			return 0;
		}
		return getNodeHeight(maxNb);
	}
	public function getHeight() : Float {
		if (info.comment != null) {
			return height;
		}
		var nodeHeight = getNodesHeight();
		if (collapseProperties()) {
			return hxd.Math.max(nodeHeight, propsHeight);
		}
		return nodeHeight + propsHeight;
	}

	inline public function getBounds() : {x: Float, y: Float, w: Float, h: Float} {
		node.getPos(tmpPoint);
		var x = tmpPoint.x;
		var y = tmpPoint.y;
		var w = this.width;
		var h = getHeight();
		return {x:x,y:y,w:w,h:h};
	}

	public function getElement() {
		return element;
	}
}