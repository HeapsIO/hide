package hide.view;

class Sound extends FileView {

	override function onDisplay( e : Element ) {
		var path = getPath();
		new Element('<audio ${ide.initializing ? '' : 'autoplay="autoplay"'} controls="controls"><source src="file://${getPath()}"/></audio>').appendTo(e);	
	}
	
	static var _ = {
		FileTree.registerExtension(Sound,["wav"],{ icon : "volume-up" });
		FileTree.registerExtension(Sound,["mp3","ogg"],{ icon : "music" });
	};
}