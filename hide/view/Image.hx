package hide.view;

private class ChannelSelectShader extends hxsl.Shader {

	static var SRC = {

		@const var channels : Int;
		var pixelColor : Vec4;

		function fragment() {
			switch( channels ) {
			case 0, 15:
				// nothing
			case 1:
				pixelColor = vec4(pixelColor.rrr, 1.);
			case 2:
				pixelColor = vec4(pixelColor.ggg, 1.);
			case 4:
				pixelColor = vec4(pixelColor.bbb, 1.);
			case 8:
				pixelColor = vec4(pixelColor.aaa, 1.);
			default:
				if( channels & 1 == 0 ) pixelColor.r = 0;
				if( channels & 2 == 0 ) pixelColor.g = 0;
				if( channels & 4 == 0 ) pixelColor.b = 0;
				if( channels & 8 == 0 ) pixelColor.a = 1;
			}
		}

	}

}

class Image extends FileView {

	var bmp : h2d.Bitmap;
	var scene : hide.comp.Scene;

	override function onDisplay() {
		element.html('
			<div class="flex vertical">
				<div class="toolbar"></div>
				<div class="scene">
				</div>
			</div>
		');
		var tools = new hide.comp.Toolbar(null,element.find(".toolbar"));
		var channelSelect = new ChannelSelectShader();
		for( i in 0...4 ) {
			var name = "RGBA".charAt(i);
			tools.addToggle("", "Channel "+name, name, function(b) {
				channelSelect.channels &= ~(1 << i);
				if( b ) channelSelect.channels |= 1 << i;
			});
		}
		scene = new hide.comp.Scene(props, null, element.find(".scene"));
		scene.onReady = function() {
			scene.loadTexture(state.path, state.path, function(t) {
				bmp = new h2d.Bitmap(h2d.Tile.fromTexture(t), scene.s2d);
				bmp.addShader(channelSelect);
				onResize();
			});
		};
	}

	override function onResize() {
		if( bmp == null ) return;
		var scale = Math.min(1,Math.min(contentWidth / bmp.tile.width, contentHeight / bmp.tile.height));
		bmp.setScale(scale * js.Browser.window.devicePixelRatio);
		bmp.x = (scene.s2d.width - Std.int(bmp.tile.width * bmp.scaleX)) >> 1;
		bmp.y = (scene.s2d.height - Std.int(bmp.tile.height * bmp.scaleY)) >> 1;
	}

	static var _ = FileTree.registerExtension(Image,["png","jpg","jpeg","gif"],{ icon : "picture-o" });

}