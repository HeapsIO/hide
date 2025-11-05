package hrt.ui;

#if domkit

class HuiFmtText extends h2d.HtmlText #if domkit implements h2d.domkit.Object #end {
	public function new(?text: String, ?parent: h2d.Object) {
		super(hxd.res.DefaultFont.get(), parent);
		initComponent();
		this.text = text;
	}
}

#end
