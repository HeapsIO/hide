package hrt.shgraph.nodes;

using hxsl.Ast;


enum abstract TexFilter(String) from String to String {
	var Nearest;
	var Linear;
}

var filters = [Nearest, Linear];

enum abstract TexWrap(String) from String to String {
	var Clamp;
	var Repeat;
	var ClampX;
	var ClampY;
}

var wraps = [Clamp, Repeat, ClampX, ClampY];

@name("Sample Texture 2D")
@description("Get color from texture and UV")
@group("Property")
class Sampler extends ShaderNodeHxsl {

	@prop() var filter : TexFilter = Linear;
	@prop() var wrap : TexWrap = Repeat;


	static var SRC = {
		@sginput var texture : Sampler2D;
		@sginput(calculatedUV) var uv : Vec2;
		@sgoutput var RGBA : Vec4;

		@sgconst var wrap : Int;
		@sgconst var filter : Int;

		function fragment() {
			var uv2 = uv;

			var size = texture.size();
			if (wrap == 0) // Clamp
				uv2 = clamp(uv2, 0.5 / size, (size - vec2(0.5)) / size);
			if (wrap == 2) // Clamp X
				uv2.x = clamp(uv2.x, 0.5 / size.x, (size.x - 0.5) / size.x);
			if (wrap == 3) // Clamp Y
				uv2.y = clamp(uv2.y, 0.5 / size.y, (size.y - 0.5) / size.y);

			if (filter == 0) {
				var size = texture.size();
				uv2 = (floor( size * uv2 ) + 0.5) / size ;
			}
			RGBA = texture.get(uv2);
		}
	}

	override function getConstValue(name: String) : Null<Int> {
		switch (name) {
			case "wrap":
				if ( wrap == Clamp ) return 0;
				if ( wrap == ClampX ) return 2;
				if ( wrap == ClampY ) return 3;
				return 1;
			case "filter":
				return filter == Nearest ? 0 : 1;
			default:
				return null;
		}
	}


	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);


		{
			var element = new hide.Element('<div style="width: ${width * 0.8}px; height: 40px"></div>');
			element.append('<span>Wrap</span>');
			element.append(new hide.Element('<select id="wrap"></select>'));

			if (this.wrap == null) {
				this.wrap = wraps[1];
			}
			var input = element.children("#wrap");
			var indexOption = 0;
			for (i => currentWrap in wraps) {
				input.append(new hide.Element('<option value="${i}">${currentWrap}</option>'));
				if (this.wrap == currentWrap) {
					input.val(i);
				}
				indexOption++;
			}

			input.on("change", function(e) {
				var value = input.val();
				this.wrap = wraps[value];
			});

			elements.push(element);
		}

		{
			var element = new hide.Element('<div style="width: ${width * 0.8}px; height: 40px"></div>');
			element.append('<span>Filter</span>');
			element.append(new hide.Element('<select id="filter"></select>'));

			if (this.filter == null) {
				this.filter = filters[1];
			}
			var input = element.children("#filter");
			var indexOption = 0;
			for (i => currentfilter in filters) {
				input.append(new hide.Element('<option value="${i}">${currentfilter}</option>'));
				if (this.filter == currentfilter) {
					input.val(i);
				}
				indexOption++;
			}

			input.on("change", function(e) {
				var value = input.val();
				this.filter = filters[value];
			});

			elements.push(element);
		}


		return elements;
	}
	#end
}