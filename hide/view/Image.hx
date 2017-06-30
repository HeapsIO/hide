package hide.view;

class Image extends hide.ui.View<{ path : String }> {

	static var _ = FileTree.registerExtension(Image,["png","jpg","jpeg","gif"],{ icon : "picture-o" });

}