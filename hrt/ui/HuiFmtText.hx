package hrt.ui;

#if hui

/**
	Don't use directly, use HuiInputBox instead
**/
class HuiFmtText extends h2d.HtmlText #if hui implements h2d.domkit.Object #end {
	public function new(?text: String, ?parent: h2d.Object) {
		super(hxd.res.DefaultFont.get(), parent);
		initComponent();
		this.text = text;
	}
}

#end
