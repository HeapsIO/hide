package hrt.ui;

class HuiFmtText extends h2d.HtmlText implements h2d.domkit.Object {
	public function new(?text: String, ?parent: h2d.Object) {
		super(hxd.res.DefaultFont.get(), parent);
		initComponent();
		this.text = text;
	}
}