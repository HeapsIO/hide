package hide.comp;

class TileSelector extends Component {

	public var file(default,set) : String;
	public var size(default,set) : {width: Int, height: Int};
	public var value(default,set) : Null<{ x : Int, y : Int, width : Int, height : Int }>;

	public var allowRectSelect(default,set) : Bool;
	public var allowSizeSelect(default,set) : Bool;
	public var allowFileChange(default,set) : Bool;

	var cursorPos : { x : Int, y : Int, x2 : Int, y2 : Int, dragSelect : Bool };
	var movePos = { x : 0, y : 0, dragScrolling : false };
	var valueDisp : Element;
	var cursor : Element;
	var image : Element;
	var imageWidth : Int;
	var imageHeight : Int;
	var zoom : Float;
	var imageElt : js.html.ImageElement;
	var modal : Element;

	public function new(file,size,?parent,?el) {
		super(parent,el);
		element.addClass("hide-tileselect");
		this.file = file;
		this.size = size;
		this.modal = parent.parent();
	}

	function set_file(file) {
		this.file = file;
		rebuild();
		return file;
	}

	function set_value(v) {
		value = v;
		if( cursorPos != null ) updateCursor();
		return v;
	}

	function set_size(size) {
		this.size = size;
		rebuild();
		return size;
	}

	function set_allowRectSelect(b) {
		allowRectSelect = b;
		rebuild();
		return b;
	}

	function set_allowSizeSelect(b) {
		allowSizeSelect = b;
		rebuild();
		return b;
	}

	function set_allowFileChange(b) {
		allowFileChange = b;
		rebuild();
		return b;
	}

	function updateCursor() {
		var k = { w: size.width * zoom, h: size.height * zoom };
		var width = hxd.Math.abs(cursorPos.x2 - cursorPos.x) + 1;
		var height = hxd.Math.abs(cursorPos.y2 - cursorPos.y) + 1;
		cursor.css({
			left: hxd.Math.min(cursorPos.x,cursorPos.x2)*k.w,
			top:hxd.Math.min(cursorPos.y,cursorPos.y2)*k.h,
			width:width*k.w - 1,
			height:height*k.h - 1,
		});
		cursor.toggle(cursorPos.x >= 0);
		if( value != null ) {
			valueDisp.show();
			valueDisp.css({
				left:value.x*k.w,
				top:value.y*k.h,
				width:value.width*k.w - 1,
				height:value.height*k.h - 1,
			});
		} else
			valueDisp.hide();
	}

	function rescale() {
		image.height(imageHeight*zoom).width(imageWidth*zoom);
		image.css("background-size",(imageWidth*zoom)+"px "+(imageHeight*zoom)+"px");
		updateCursor();
	}

	function rebuild() {

		element.empty();
		element.off();
		element.click((e) -> e.stopPropagation());
		element.attr("tabindex","0");
		element.focus();

		var el = new Element(element[0].ownerDocument.body);
		el.off('keydown.tileselector');
		el.on('keydown.tileselector', function(e) {
			if( e.keyCode == 27 ) {
				onChange(true);
				el.off('keydown.tileselector');
			}
		});
		element.on("keydown", function(e) {
			if( e.keyCode == 27 ) {
				onChange(true);
				el.off('keydown.tileselector');
			}
		});

		var tool = new Toolbar(element);
		if( allowFileChange ) {
			var tex = new hide.comp.TextureSelect(tool.element);
			tex.path = file;
			tex.onChange = function() this.file = tex.path;
		}
		if (allowSizeSelect) {
			var tooltipText = 'Different value types are accepted :
			- Values in pixels (100 - it will take 100px of the image),
			- Values in percent (100% - it will take the max size of the image),
			- Values in ratio (1/2 - it will take half of the image size)';

			var widthEdit = new Element('<span class="dim-edit">Width:<input type="text" title="$tooltipText" value="${size.width}">px</span>')
				.appendTo(tool.element);
			widthEdit.find("input").on("blur", (e:js.jquery.Event) -> {
				this.size.width = setSizeEdit(e.getThis(), this.size.width, imageWidth);
				widthEdit.find("input").val(this.size.width);
			}).on("keydown", function(e:js.jquery.Event) {
				if (e.keyCode == 13)
					widthEdit.find("input").blur();
			});
			var heightEdit = new Element('<span class="dim-edit">Height:<input type="text" title="$tooltipText" value="${size.height}">px</span>')
				.appendTo(tool.element);
			heightEdit.find("input").on("blur", (e:js.jquery.Event) -> {
				this.size.height = setSizeEdit(e.getThis(), this.size.height, imageHeight);
				heightEdit.find("input").val(this.size.height);
			}).on("keydown", function(e:js.jquery.Event) {
				if (e.keyCode == 13)
					heightEdit.find("input").blur();
			});

			widthEdit.find("input").on("blur", updateCursor);
			heightEdit.find("input").on("blur", updateCursor);
		}
		if( tool.element.children().length == 0 )
			tool.remove();

		var url = ide.getUnCachedUrl(file);
		var scroll = new Element("<div class='flex-scroll'><div class='scroll'>").appendTo(element).find(".scroll");
		image = new Element('<div class="tile" style="background-image:url(\'$url\')"></div>').appendTo(scroll);

		valueDisp = new Element('<div class="valueDisp">').appendTo(image);
		cursor = new Element('<div class="cursor">').appendTo(image);
		cursorPos = { x : -1, y : -1, x2 : -1, y2 : -1, dragSelect : false };
		var i = js.Browser.document.createImageElement();
		this.imageElt = i;

		i.onload = function(_) {
			if( imageElt != i ) return;
			imageWidth = i.width;
			imageHeight = i.height;
			zoom = Math.floor(hxd.Math.min(800 / imageWidth, 580 / imageHeight));
			if( zoom <= 0 ) zoom = 1;

			scroll.on("mousewheel", function(e:js.jquery.Event) {
				if( untyped e.originalEvent.wheelDelta > 0 )
					zoom++;
				else if( zoom > 1 )
					zoom--;
				rescale();
				e.preventDefault();
			});

			scroll.parent().on("mousedown", function(e) {
				if( e.button == 2 ) {
					movePos.dragScrolling = true;
					movePos.x = e.pageX;
					movePos.y = e.pageY;
				}
			});

			modal.on("mousemove", function(e) {
				if( movePos.dragScrolling ) {
					var dx = e.pageX - movePos.x;
					var dy = e.pageY - movePos.y;

					element.find(".scroll")[0].scrollBy(-dx,-dy);
					movePos.x = e.pageX;
					movePos.y = e.pageY;
				}
			});

			image.on("mousemove", function(e:js.jquery.Event) {
				if( movePos.dragScrolling )
					return;
				var k = { w: size.width * zoom, h: size.height * zoom };
				var x = Math.floor(e.offsetX / k.w);
				var y = Math.floor(e.offsetY / k.h);
				if( (x+1) * size.width > i.width ) x--;
				if( (y+1) * size.height > i.height ) y--;

				if( cursorPos.dragSelect ) {
					cursorPos.x2 = x;
					cursorPos.y2 = y;
				} else {
					cursorPos.x = cursorPos.x2 = x;
					cursorPos.y = cursorPos.y2 = y;
				}
				updateCursor();
			});
			image.on("mousedown", function(e:js.jquery.Event) {
				if( movePos.dragScrolling )
					return;
				var k = { w: size.width * zoom, h: size.height * zoom };
				var x = Math.floor(e.offsetX / k.w);
				var y = Math.floor(e.offsetY / k.h);
				if( (x+1) * size.width > i.width ) x--;
				if( (y+1) * size.height > i.height ) y--;
				cursorPos.x = cursorPos.x2 = x;
				cursorPos.y = cursorPos.y2 = y;

				if( e.button == 0 && allowRectSelect )
					cursorPos.dragSelect = true;
			});
			modal.on("mouseup", function(e) {
				movePos.dragScrolling = false;
				cursorPos.dragSelect = false;
			});
			image.on("mouseup", function(e:js.jquery.Event) {
				e.preventDefault();
				movePos.dragScrolling = false;
				cursorPos.dragSelect = false;
				if( e.button != 0 )
					return;
				if( cursorPos.x2 >= cursorPos.x ) {
					value.x = cursorPos.x;
					value.width = cursorPos.x2 - cursorPos.x + 1;
				} else {
					value.x = cursorPos.x2;
					value.width = cursorPos.x - cursorPos.x2 + 1;
				}
				if( cursorPos.y2 >= cursorPos.y ) {
					value.y = cursorPos.y;
					value.height = cursorPos.y2 - cursorPos.y + 1;
				} else {
					value.y = cursorPos.y2;
					value.height = cursorPos.y - cursorPos.y2 + 1;
				}
				onChange(false);
				e.stopPropagation();
			});
			modal.on("contextmenu", function(e) {
				e.preventDefault();
				e.stopPropagation();
			});
			rescale();
		};
		i.src = url;
	}

	function setSizeEdit(element:Element, sizeValue:Int, maxValue:Int):Int {
		var val = element.val();
		var isRatio = StringTools.contains(Std.string(val), '/');
		var isPercent = StringTools.contains(Std.string(val), '%');

		if (isRatio || isPercent) {
			if (isRatio) {
				var ratio = Std.string(val).split('/');
				sizeValue = Std.int((Std.parseFloat(ratio[0]) / Std.parseFloat(ratio[1])) * maxValue);
			}

			if (isPercent) {
				var percent = Std.string(val).split('%');
				sizeValue = Std.int((Std.parseFloat(percent[0]) / 100.0) * maxValue);
			}
		} else {
			var nsize = Std.parseInt(element.val());
			if (sizeValue != nsize && nsize != null && nsize > 0)
				sizeValue = nsize;
		}

		return sizeValue;
	}

	public dynamic function onChange( cancel : Bool ) {
	}

}