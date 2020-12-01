package hide.view;

private class ChannelSelectShader extends hxsl.Shader {

	static var SRC = {

		@param var texture : Sampler2D;
		@param var textureCube : SamplerCube;
		@param var mipLod : Float;

		@const var channels : Int;
		@const var isCube : Bool;

		var pixelColor : Vec4;
		var calculatedUV : Vec2;
		var transformedNormal : Vec3;

		function fragment() {
			pixelColor = isCube ? textureCube.getLod(transformedNormal, mipLod) : texture.getLod(calculatedUV, mipLod);
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
				<div class="heaps-scene">
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
		scene = new hide.comp.Scene(config, null, element.find(".heaps-scene"));
		scene.onReady = function() {
			scene.loadTexture(state.path, state.path, function(t) {
				if( !t.flags.has(Cube) ) {
					bmp = new h2d.Bitmap(h2d.Tile.fromTexture(t), scene.s2d);
					bmp.addShader(channelSelect);
					channelSelect.texture = t;
				} else {
					var r = new h3d.scene.fwd.Renderer();
					scene.s3d.lightSystem.ambientLight.set(1,1,1,1);
					scene.s3d.renderer = r;
					var sp = new h3d.prim.Sphere(1,64,64);
					sp.addNormals();
					sp.addUVs();
					channelSelect.textureCube = t;
					channelSelect.isCube = true;
					var sp = new h3d.scene.Mesh(sp, scene.s3d);
					sp.material.texture = t;
					sp.material.mainPass.addShader(channelSelect);
					new h3d.scene.CameraController(4,scene.s3d);
				}
				if( t.flags.has(MipMapped) ) {
					t.mipMap = Linear;
					tools.addRange("MipMap", function(f) channelSelect.mipLod = f, 0, 0, t.mipLevels);
				}
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

	static var _ = FileTree.registerExtension(Image,hide.Ide.IMG_EXTS,{ icon : "picture-o" });

}