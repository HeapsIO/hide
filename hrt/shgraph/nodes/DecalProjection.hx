package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Decal Projection")
@description("Compute decal projection")
@group("UV")
class DecalProjection extends ShaderNodeHxsl {

	@prop() var isWorldUV : Bool = false;

	static var SRC = {
		@sgoutput var output : Vec2;

		@sgconst var isWorldUV : Int;

        @global var camera : {
			var inverseViewProj : Mat4;
		};

		@global var global : {
			@perObject var modelViewInverse : Mat4;
		};

        @global var depthMap : Channel;

        var projectedPosition : Vec4;

		function fragment() {
            var matrix = camera.inverseViewProj * global.modelViewInverse;
            var screenPos = projectedPosition.xy / projectedPosition.w;
            var depth = depthMap.get(screenToUv(screenPos));
            var ruv = vec4( screenPos, depth, 1 );
            var wpos = ruv * matrix;
			if ( isWorldUV == 1 ) {
				var ppos = ruv * camera.inverseViewProj;
				output = ppos.xy / ppos.w;
			} else {
				var lpos = (wpos.xyz / wpos.w);
				output = lpos.xy + 0.5;
			}
		}
	};
	
	override function getConstValue(name: String) : Null<Int> {
		switch (name) {
			case "isWorldUV":
				return isWorldUV ? 1 : 0;
			default:
				return null;
		}
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var container = new hide.Element('<div style="width: ${width * 0.8}px; height:40px"></div>');		
		container.append('<span>&nbspWorld UV</span>');
		var worldUVEl = new hide.Element('<input type="checkbox" id="isWorldUV"></input>');
		worldUVEl.prop('checked', this.isWorldUV);		
		container.append(worldUVEl);
	
		worldUVEl.on("change", function(e) {
			this.isWorldUV = worldUVEl.is(':checked');
		});

		elements.push(container);
		return elements;
	}
	#end

}
