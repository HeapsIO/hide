package hide.view.shadereditor;

import hide.comp.SVG;
import js.jquery.JQuery;
import hrt.shgraph.ShaderNode;

@:access(hide.view.Graph)
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

	var nodeInstance : ShaderNode;

	var x : Float;
	var y : Float;

	var width : Int = 150;
	var height : Int;
	var propsHeight : Int = 0;

	public var HEADER_HEIGHT = 22;
	@const var NODE_MARGIN = 17;
	public static var NODE_RADIUS = 5;
	@const var NODE_TITLE_PADDING = 10;
	@const var NODE_INPUT_PADDING = 3;
	public var selected : Bool = false;

	public var inputs : Array<JQuery> = [];
	public var outputs : Array<JQuery> = [];

	var hasHeader : Bool = true;
	var hadToShowInputs : Bool = false;
	var color : String;
	var closePreviewBtn : JQuery;

	var element : JQuery;
	var propertiesGroup : JQuery;
	public var comment : hrt.shgraph.nodes.Comment = null;
	static final resizeBorder : Int = 8;
	static final halfResizeBorder : Int = resizeBorder >> 1;

	public function new(editor : Graph, parent : JQuery, x : Float, y : Float, node : ShaderNode) {
		this.nodeInstance = node;

		var metas = haxe.rtti.Meta.getType(Type.getClass(node));
		if (metas.width != null) {
			this.width = metas.width[0];
		}

		if (Reflect.hasField(metas, "color")) {
			color = Reflect.field(metas, "color");
		}
		var className = node.nameOverride ?? ((metas.name != null) ? metas.name[0] : "Undefined");

		element = editor.editor.group(parent).addClass("box").addClass("not-selected");
		element.attr("id", node.id);
		setPosition(x, y);

		comment = Std.downcast(node, hrt.shgraph.nodes.Comment);
		if (comment != null) {
			this.width = comment.width;
			this.height = comment.height;
			HEADER_HEIGHT = 34;
			color = null;
			this.element.addClass("comment");
		}

		if (Reflect.hasField(metas, "noheader")) {
			HEADER_HEIGHT = 0;
			hasHeader = false;
		}

		// Debug: editor.editor.text(element, 2, -6, 'Node ${node.id}').addClass("node-id-indicator");

		// outline of box
		editor.editor.rect(element, -1, -1, width+2, getHeight()+2).addClass("outline");

		if (comment != null) {
			var shaderEditor : ShaderEditor = cast editor;

			function makeResizable(elt: js.html.Element, left: Bool, top: Bool, right: Bool, bottom: Bool) {
				var pressed = false;

				elt.onpointerdown = function(e: js.html.PointerEvent) {
					if (e.button != 0)
						return;
					e.stopPropagation();
					e.preventDefault();
					pressed = true;
					elt.setPointerCapture(e.pointerId);
					shaderEditor.beforeChange();
				};

				elt.onpointermove = function(e: js.html.PointerEvent) {
					if (!pressed)
						return;
					e.stopPropagation();
					e.preventDefault();

					var clientRect = editor.editor.element.get(0).getBoundingClientRect();

					var x0 : Int = Std.int(this.x);
					var y0 : Int = Std.int(this.y);
					var x1 : Int = x0 + comment.width;
					var y1 : Int = y0 + comment.height;

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

					this.x = x0;
					this.y = y0;
					comment.width = x1 - x0;
					comment.height = y1 - y0;

					setPosition(this.x,this.y);
					this.width = comment.width;
					this.height = comment.height;
					refreshBox();
				}

				elt.onpointerup = function (e: js.html.PointerEvent) {
					if (!pressed)
						return;
					pressed = false;
					e.stopPropagation();
					e.preventDefault();
					shaderEditor.afterChange();
					elt.releasePointerCapture(e.pointerId);
				};
			}

			var elt = editor.editor.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "ns-resize";
			elt.id = "resizeBot";
			makeResizable(elt, false,false,false,true);

			var elt = editor.editor.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "ns-resize";
			elt.id = "resizeTop";
			makeResizable(elt, false,true,false,false);

			var elt = editor.editor.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "ew-resize";
			elt.id = "resizeLeft";
			makeResizable(elt, true,false,false,false);

			var elt = editor.editor.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "ew-resize";
			elt.id = "resizeRight";
			makeResizable(elt, false,false,true,false);

			var elt = editor.editor.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "nesw-resize";
			elt.id = "resizeBotLeft";
			makeResizable(elt, true,false,false,true);

			var elt = editor.editor.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "nwse-resize";
			elt.id = "resizeBotRight";
			makeResizable(elt, false,false,true,true);

			var elt = editor.editor.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "nwse-resize";
			elt.id = "resizeTopLeft";
			makeResizable(elt, true,true,false,false);

			var elt = editor.editor.rect(element, 0,0,0,0).addClass("resize").get(0);
			elt.style.cursor = "nesw-resize";
			elt.id = "resizeTopRight";
			makeResizable(elt, false,true,true,false);
		}

		// header

		if (hasHeader) {
			var header = editor.editor.rect(element, 0, 0, this.width, HEADER_HEIGHT).addClass("head-box");
			if (color != null) header.css("fill", color);
			if (comment != null) {
				var fo = editor.editor.foreignObject(element, 7, 2, 0, HEADER_HEIGHT-4);
				fo.get(0).id = "commentTitle";
				var commentTitle = new Element("<span contenteditable spellcheck='false'>Comment</span>").addClass("comment-title").appendTo(fo);
				var html : js.html.SpanElement = cast commentTitle.get(0);
				if (comment.comment.length > 0) {
					html.innerText = comment.comment;
				}

				var wasEdited = false;
				var shaderEditor : ShaderEditor = cast editor;

				html.onfocus = function() {
					var range = js.Browser.document.createRange();
					range.selectNodeContents(html);
					var sel = js.Browser.window.getSelection();
					sel.removeAllRanges();
					sel.addRange(range);
				}
				html.onkeydown = function(e: js.html.KeyboardEvent) {
					if (e.keyCode == 13) {
						html.blur();
					}
					e.stopPropagation();
				}
				html.oninput = function(e) {
					if (!wasEdited) {
						shaderEditor.beforeChange();
						wasEdited = true;
					}
				}
				html.onkeyup = function(e: js.html.KeyboardEvent) {
					e.stopPropagation();
				}
				html.onmousedown = function(e: js.html.PointerEvent) {
					e.stopPropagation();
				}
				html.onmousemove = function(e: js.html.PointerEvent) {
					e.stopPropagation();
				}
				html.onmouseup = function(e: js.html.PointerEvent) {
					e.stopPropagation();
				}

				html.onblur = function() {
					if (js.Browser.window.getSelection != null) {js.Browser.window.getSelection().removeAllRanges();}
					comment.comment = html.innerText;
					if (wasEdited) {
						shaderEditor.afterChange();
						wasEdited = false;
					}
				}
			}
			else {
				editor.editor.text(element, 7, HEADER_HEIGHT-6, className).addClass("title-box");
			}
		}

		if (Reflect.hasField(metas, "alwaysshowinputs")) {
			hadToShowInputs = true;
		}

		propertiesGroup = editor.editor.group(element).addClass("properties-group");

		// nodes div
		var bg = editor.editor.rect(element, 0, HEADER_HEIGHT, this.width, 0).addClass("nodes");
		if (!hasHeader && color != null) {
			bg.css("fill", color);
		}

		if (node.canHavePreview()) {
			closePreviewBtn = editor.editor.foreignObject(element, width / 2 - 16, 0, 32,32);
			closePreviewBtn.append(new JQuery('<div class="close-preview"><span class="ico"></span></div>'));

			refreshCloseIcon();
			closePreviewBtn.on("click", (e) -> {
				e.stopPropagation();
				setPreviewVisibility(!node.showPreview);
			});
		}

		refreshBox();
		//editor.editor.line(element, width/2, HEADER_HEIGHT, width/2, 0, {display: "none"}).addClass("nodes-separator");
	}

	public function setPreviewVisibility(visible: Bool) {
		nodeInstance.showPreview = visible;
		refreshCloseIcon();
	}

	function refreshCloseIcon() {
		if (closePreviewBtn == null)
			return;
		closePreviewBtn.find(".ico").toggleClass("ico-angle-down", !nodeInstance.showPreview);
		closePreviewBtn.find(".ico").toggleClass("ico-angle-up", nodeInstance.showPreview);
	}

	public function addInput(editor : Graph, name : String, valueDefault : String = null, type : hrt.shgraph.ShaderGraph.SgType) {
		var node = editor.editor.group(element).addClass("input-node-group");
		var nodeHeight = HEADER_HEIGHT + NODE_MARGIN * (inputs.length+1) + NODE_RADIUS * inputs.length;
		var style = {fill : ""}
		style.fill = getTypeColor(type);

		var nodeCircle = editor.editor.circle(node, 0, nodeHeight, NODE_RADIUS, style).addClass("node input-node");

		var nameWidth = 0.0;
		if (name.length > 0) {
			var inputName = editor.editor.text(node, NODE_TITLE_PADDING, nodeHeight + 4, name).addClass("title-node");
			var domName : js.html.svg.GraphicsElement = cast inputName.get()[0];
			nameWidth = domName.getBBox().width;
		}
		if (valueDefault != null) {
			var widthInput = width / 2 * 0.7;
			var fObject = editor.editor.foreignObject(
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

	public function addOutput(editor : Graph, name : String, ?type : hrt.shgraph.ShaderGraph.SgType) {
		var node = editor.editor.group(element).addClass("output-node-group");
		var nodeHeight = HEADER_HEIGHT + NODE_MARGIN * (outputs.length+1) + NODE_RADIUS * outputs.length;
		var style = {fill : ""}

		style.fill = getTypeColor(type);

		var nodeCircle = editor.editor.circle(node, width, nodeHeight, NODE_RADIUS, style).addClass("node output-node");

		if (name.length > 0 && name != "output")
			editor.editor.text(node, width - NODE_TITLE_PADDING - (name.length * 6.75), nodeHeight + 4, name).addClass("title-node");

		outputs.push(nodeCircle);

		refreshBox();
		return node;
	}

	public function generateProperties(editor : Graph, config:  hide.Config) {
		var props = nodeInstance.getHTML(this.width, config);

		if (props.length == 0) return;

		if (!hadToShowInputs && inputs.length <= 1 && outputs.length <= 1) {
			element.find(".nodes").remove();
			element.find(".input-node-group > .title-node").html("");
			element.find(".output-node-group > .title-node").html("");
		}

		var children = propertiesGroup.children();
		if (children.length > 0) {
			for (c in children) {
				c.remove();
			}
		}

		// create properties box
		var bgParam = editor.editor.rect(propertiesGroup, 0, 0, this.width, 0).addClass("properties");
		if (!hasHeader && color != null) bgParam.css("fill", color);
		propsHeight = 0;

		for (p in props) {
			var prop = editor.editor.group(propertiesGroup).addClass("prop-group");
			prop.attr("transform", 'translate(0, ${propsHeight})');

			var propWidth = (p.width() > 0 ? p.width() : this.width);
			var fObject = editor.editor.foreignObject(prop, (this.width - propWidth) / 2, 5, propWidth, p.height());
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
		element.find(".outline").attr("height", height+2).width(width);

		if (hasHeader) {
			element.find(".head-box").width(width);
		}

		if (comment != null) {
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
			element.find(".nodes-separator").attr("y2", HEADER_HEIGHT + nodesHeight);
			element.find(".nodes-separator").show();
		} else if (!hadToShowInputs) {
			element.find(".nodes-separator").hide();
		}

		if (propertiesGroup != null) {
			propertiesGroup.attr("transform", 'translate(0, ${HEADER_HEIGHT + nodesHeight})');
			propertiesGroup.find(".properties").attr("height", propsHeight);
		}

		closePreviewBtn?.attr("y",HEADER_HEIGHT + nodesHeight + propsHeight - 16);
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
	public function setTitle(str : String) {
		if (hasHeader) {
			element.find(".title-box").html(str);
		}
	}
	public function getId() {
		return this.nodeInstance.id;
	}
	public function getInstance() {
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
		if ((!hadToShowInputs && maxNb <= 1 && propsHeight > 0) || comment != null) {
			return 0;
		}
		return NODE_MARGIN * (maxNb+1) + NODE_RADIUS * maxNb;
	}
	public function getHeight() {
		if (comment != null) {
			return comment.height;
		}
		return HEADER_HEIGHT + getNodesHeight() + propsHeight;
	}
	public function getElement() {
		return element;
	}
}