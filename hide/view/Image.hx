package hide.view;

private class ChannelSelectShader extends hxsl.Shader {

	static var SRC = {

		@param var texture : Sampler2D;
		@param var textureCube : SamplerCube;
		@param var textureArray : Sampler2DArray;
		@param var layer : Float;
		@param var mipLod : Float;
		@param var exposure : Float;

		@const var channels : Int;
		@const var isCube : Bool;
		@const var isArray : Bool;

		var pixelColor : Vec4;
		var calculatedUV : Vec2;
		var transformedNormal : Vec3;

		function fragment() {
			if( isCube )
				pixelColor = textureCube.getLod(transformedNormal, mipLod);
			else if( isArray )
				pixelColor = textureArray.getLod(vec3(calculatedUV, layer), mipLod);
			else
				pixelColor = texture.getLod(calculatedUV, mipLod);
			pixelColor.rgb *= pow(2, exposure);
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
					if( t.layerCount > 1 ) {
						channelSelect.isArray = true;
						channelSelect.textureArray = cast(t, h3d.mat.TextureArray);
						tools.addRange("Layer", function(f) channelSelect.layer = f, 0, 0, t.layerCount-1, 1);
					} else
						channelSelect.texture = t;
					new hide.view.l3d.CameraController2D(scene.s2d);
				} else {
					var r = new h3d.scene.fwd.Renderer();
					var ls = new h3d.scene.fwd.LightSystem();
					ls.ambientLight.set(1,1,1,1);
					scene.s3d.lightSystem = ls;
					scene.s3d.renderer = r;
					var sp = new h3d.prim.Sphere(1,64,64);
					sp.addNormals();
					sp.addUVs();
					channelSelect.textureCube = t;
					channelSelect.isCube = true;
					var sp = new h3d.scene.Mesh(sp, scene.s3d);
					sp.material.texture = t;
					sp.material.mainPass.addShader(channelSelect);
					sp.material.shadows = false;
					new h3d.scene.CameraController(5,scene.s3d);
				}
				if( t.flags.has(MipMapped) ) {
					t.mipMap = Linear;
					tools.addRange("MipMap", function(f) channelSelect.mipLod = f, 0, 0, t.mipLevels - 1);
				}
				if( hxd.Pixels.isFloatFormat(t.format) ) {
					tools.addRange("Exposure", function(f) channelSelect.exposure = f, 0, -10, 10);
				}
				onResize();
			});
		};
	}

	override function onRebuild() {
		if ( scene != null )
			scene.dispose();
		super.onRebuild();
	}

	override function onResize() {
		if( bmp == null ) return;
		var scale = Math.min(1,Math.min((contentWidth - 20) / bmp.tile.width, (contentHeight - 20) / bmp.tile.height));
		bmp.setScale(scale * js.Browser.window.devicePixelRatio);
		bmp.x = -Std.int(bmp.tile.width * bmp.scaleX) >> 1;
		bmp.y = -Std.int(bmp.tile.height * bmp.scaleY) >> 1;
	}

	static var _ = FileTree.registerExtension(Image,hide.Ide.IMG_EXTS.concat(["envd","envs"]),{ icon : "picture-o" });

}