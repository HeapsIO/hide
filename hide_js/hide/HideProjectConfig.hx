package hide;

typedef HideProjectConfig = {
	var layouts : Array<{ name : String, state : LayoutState }>;
	var renderer : String;
	var dbCategories : Array<String>;
	var dbProofread : Null<Bool>;
};
