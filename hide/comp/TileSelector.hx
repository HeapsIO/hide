package hide.comp;

class TileSelector extends Component {

	public var file(default,set) : String;
	public var size(default,set) : Int;
	public var value(default,set) : Null<{ x : Int, y : Int, width : Int, height : Int }>;
	public var allowRectSelect(default,set) : Bool;
	public var allowSizeSelect(default,set) : Bool;
	public var allowFileChange(default,set) : Bool;

    var valueDisp : Element;
    var cursor : Element;
    var image : Element;
	var movePos = { x : 0, y : 0, moving : false, moved : false };
    var cursorPos : { x : Int, y : Int, x2 : Int, y2 : Int, select : Bool };
    var width : Int;
    var height : Int;
	var zoom : Float;
	var imageElt : js.html.ImageElement;

	public function new(file,size,?parent,?el) {
		super(parent,el);
		element.addClass("hide-tileselect");
		this.file = file;
		this.size = size;
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
        var k = size * zoom;
        var width = hxd.Math.abs(cursorPos.x2 - cursorPos.x) + 1;
        var height = hxd.Math.abs(cursorPos.y2 - cursorPos.y) + 1;
        cursor.css({left: hxd.Math.min(cursorPos.x,cursorPos.x2)*k,top:hxd.Math.min(cursorPos.y,cursorPos.y2)*k,width:width*k,height:height*k});
        cursor.toggle(cursorPos.x >= 0);
        if( value != null ) {
            valueDisp.show();
            valueDisp.css({left:value.x*k,top:value.y*k,width:value.width*k,height:value.height*k});
        } else
            valueDisp.hide();
    }

    function rescale() {
        image.height(height*zoom).width(width*zoom);
        image.css("background-size",(width*zoom)+"px "+(height*zoom)+"px");
        updateCursor();
    }

	function rebuild() {

		element.empty();
		element.off();
		element.click((e) -> e.stopPropagation());
		element.attr("tabindex","0");
		element.focus();
		element.on("keydown", function(e) {
			if( e.keyCode == 27 ) {
				onChange(true);
			}
		});

		var tool = new Toolbar(element);
		if( allowFileChange ) {
			var tex = new hide.comp.TextureSelect(tool.element);
			tex.path = file;
			tex.onChange = function() this.file = tex.path;
		}
		if( allowSizeSelect ) {
			var size = new Element('<span><input type="number" value="$size">px</span>').appendTo(tool.element);
			size.find("input").on("blur",function(e:js.jquery.Event) {
                var nsize = Std.parseInt(e.getThis().val());
                if( this.size != nsize && nsize != null && nsize > 0 )
				    this.size = nsize;
			}).on("keydown", function(e:js.jquery.Event) {
				if( e.keyCode == 13 ) size.find("input").blur();
			});
		}
		if( tool.element.children().length == 0 )
			tool.remove();

		var url = "file://" + ide.getPath(file);
		var scroll = new Element("<div class='flex-scroll'><div class='scroll'>").appendTo(element).find(".scroll");
		image = new Element('<div class="tile" style="background-image:url(\'$url\')"></div>').appendTo(scroll);

        valueDisp = new Element('<div class="valueDisp">').appendTo(image);
		cursor = new Element('<div class="cursor">').appendTo(image);
        cursorPos = { x : -1, y : -1, x2 : -1, y2 : -1, select : false };
		var i = js.Browser.document.createImageElement();
		this.imageElt = i;

		i.onload = function(_) {
			if( imageElt != i ) return;
            width = i.width;
            height = i.height;
			zoom = Math.floor(hxd.Math.min(800 / width, 580 / height));
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
				if( e.button == 0 ) {
					movePos.moving = true;
					movePos.x = e.offsetX;
					movePos.y = e.offsetY;
				}
			});
			scroll.parent().on("mousemove", function(e) {
				if( movePos.moving ) {
					var dx = e.offsetX - movePos.x;
					var dy = e.offsetY - movePos.y;
					scroll[0].scrollBy(-dx,-dy);
					movePos.moved = true;
				}
			});
			image.on("mousemove", function(e:js.jquery.Event) {
				if( movePos.moving )
					return;
				var k = zoom * size;
				var x = Math.floor(e.offsetX / k);
				var y = Math.floor(e.offsetY / k);
				if( (x+1) * size > i.width ) x--;
				if( (y+1) * size > i.height ) y--;
				if( cursorPos.select ) {
					cursorPos.x2 = x;
					cursorPos.y2 = y;
				} else {
					cursorPos.x = cursorPos.x2 = x;
					cursorPos.y = cursorPos.y2 = y;
				}
				updateCursor();
			});
            image.on("mousedown", function(e:js.jquery.Event) {
				if( e.button == 2 && allowRectSelect )
					cursorPos.select = true;
            });
            image.on("mouseup", function(e:js.jquery.Event) {
				e.preventDefault();
				var moved = movePos.moved;
				movePos.moved = false;
				movePos.moving = false;
                cursorPos.select = false;
				if( e.button == 0 && moved )
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
            });
			image.on("contextmenu", function(e) {
				e.preventDefault();
			});
			rescale();
		};
		i.src = url;
	}

	public dynamic function onChange( cancel : Bool ) {
	}

}