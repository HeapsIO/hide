package hrt.ui.hide;

#if hui

typedef Item = {id: Int, phrase: String, icon: String};

class HideViewTest extends HuiView<{}> {

	static var phrases = [
		"Lorem ipsum dolor sit amet consectetur adipiscing elit. Placerat in id cursus mi pretium tellus duis.",
		"Lorem ipsum dolor sit amet consectetur adipiscing elit. Placerat in id cursus mi pretium tellus duis. Urna tempor pulvinar vivamus fringilla lacus nec metus. Integer nunc posuere ut hendrerit semper vel class. Conubia nostra inceptos himenaeos orci varius natoque penatibus. Mus donec rhoncus eros lobortis nulla molestie mattis. Purus est efficitur laoreet mauris pharetra vestibulum fusce.",
		"Lorem ipsum dolor sit amet consectetur adipiscing elit. Placerat in id cursus mi pretium tellus duis. Urna tempor pulvinar vivamus fringilla lacus nec metus. Integer nunc posuere ut hendrerit semper vel class. Conubia nostra inceptos himenaeos orci varius natoque penatibus. Mus donec rhoncus eros lobortis nulla molestie mattis. Purus est efficitur laoreet mauris pharetra vestibulum fusce. Sodales consequat magna ante condimentum neque at luctus. Ligula congue sollicitudin erat viverra ac tincidunt nam. Lectus commodo augue arcu dignissim velit aliquam imperdiet. Cras eleifend turpis fames primis vulputate ornare sagittis. Libero feugiat tristique accumsan maecenas potenti ultricies habitant. Cubilia curae hac habitasse platea dictumst lorem ipsum. Faucibus ex sapien vitae pellentesque sem placerat in. Tempus leo eu aenean sed diam urna tempor."
	];

	static var icons = [
		"ui/icons/check.png",
		"ui/icons/checkBlank.png",
		"ui/icons/copy.png",
		"ui/icons/radio.png",
		"ui/icons/radioBlank.png",
		"ui/icons/search.png",
	];

	function new(?parent) {
		super(parent);
		initComponent();

		for (i in 0...10000) {
			items.push({id: i, phrase: phrases[Std.int(hxd.Math.random(1.0) * phrases.length)], icon: icons[Std.int(hxd.Math.random(1.0) * icons.length)]});
		}

		regen();
	}

	var items : Array<Item> = [];

	function regen() {
		removeChildElements();

		@:privateAccess
		{
			var list = new HuiVirtualList(this);
			list.items = items;
			list.generateItem = genItem;
		}

	}

	function genItem(item: Item) : HuiElement {
		var element = new HuiElement();
		var text = new HuiFmtText(Std.string(item.id), element);
		var text = new HuiFmtText(item.phrase, element);
		var image = new HuiElement(element);
		image.backgroundType = "hui";
		image.huiBg.image = {path: item.icon, mode: Fit};
		return element;
	}

	static var _ = HuiView.register("test", HideViewTest);
}

#end