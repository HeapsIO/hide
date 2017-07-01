package hide.view;

class Image extends FileView {

	var bmp : h2d.Bitmap;
	var scene : hide.comp.Scene;

	override function onDisplay( e : Element ) {
		scene = new hide.comp.Scene(e);
		scene.onReady = function() {
			scene.loadTextureFile(state.path, function(t) {
				bmp = new h2d.Bitmap(h2d.Tile.fromTexture(t), scene.s2d);
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