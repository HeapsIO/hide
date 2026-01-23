package hide;

typedef LayoutState = {
	var content : Any;
	var fullScreen : { name : String, state : Any };
}
typedef HideProjectConfig = {
	var layouts : Array<{ name : String, state : LayoutState }>;
	var renderer : String;
	var dbCategories : Array<String>;
	var dbProofread : Null<Bool>;
};
