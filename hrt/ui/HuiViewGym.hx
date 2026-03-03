package hrt.ui;

#if hui

typedef TreeItem = {
	name: String,
	children: Array<TreeItem>,
	id: String,
};

class HuiViewGym extends HuiView<{}> {
	static var SRC =
		<hui-view-gym>
			<hui-tab-container>
				<gym-widgets display-name="Widgets"/>
				<gym-layouts display-name="Layouts"/>
			</hui-tab-container>
		</hui-view-gym>

	override function getDisplayName() : String {
		return "Hui Gym";
	}

	static var _ = HuiView.register("gym", HuiViewGym);
}

class GymWidgets extends HuiElement {
	static var asciiChars = " !&quot;#$%&amp;'()*+,-./0123456789:;&lt;=&gt;?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~'";

	static var SRC =
		<gym-widgets>
			<hui-text("hui-tree")/>
			<hui-element class="example">
				<hui-tree id="tree"/>
			</hui-element>

			<hui-text("hui-text")/>
			<hui-element class="example">
				<hui-text("Example ! This is a text")/>
				<hui-text(asciiChars)/>
				<hui-text("Lorem ipsum dolor sit amet consectetur adipiscing elit. Placerat in id cursus mi pretium tellus duis. Urna tempor pulvinar vivamus fringilla lacus nec metus. Integer nunc posuere ut hendrerit semper vel class. Conubia nostra inceptos himenaeos orci varius natoque penatibus. Mus donec rhoncus eros lobortis nulla molestie mattis. Purus est efficitur laoreet mauris pharetra vestibulum fusce. Sodales consequat magna ante condimentum neque at luctus. Ligula congue sollicitudin erat viverra ac tincidunt nam. Lectus commodo augue arcu dignissim velit aliquam imperdiet. Cras eleifend turpis fames primis vulputate ornare sagittis. Libero feugiat tristique accumsan maecenas potenti ultricies habitant. Cubilia curae hac habitasse platea dictumst lorem ipsum. Faucibus ex sapien vitae pellentesque sem placerat in. Tempus leo eu aenean sed diam urna tempor.")/>
			</hui-element>

			<hui-text("hui-text-input")/>
			<hui-element class="example">
				<hui-input-box/>
				<hui-input-box class="search"/>
			</hui-element>

			<hui-text("hui-background")/>
			<hui-element class="example horizontal">
				<hui-element class="hui-background example-1"></hui-element>
				<hui-element class="hui-background example-2"></hui-element>
				<hui-element class="hui-background example-3"></hui-element>
			</hui-element>


			<hui-text("hui-menu")/>
			<hui-element class="example">
				<hui-button-menu(testMenu)><hui-text("Click me")/></hui-button-menu>
			</hui-element>

			<hui-text("hui-split-container")/>
			<hui-element class="example">
				<hui-split-container direction="horizontal">
					<hui-element class="panel"><hui-text("Left")/></hui-element>
					<hui-element class="panel"><hui-text("Right")/></hui-element>
				</hui-split-container>

				<hui-split-container direction="vertical">
					<hui-element class="panel"><hui-text("Up")/></hui-element>
					<hui-element class="panel"><hui-text("Down")/></hui-element>
				</hui-split-container>
			</hui-element>

			<hui-text("hui-tab-container")/>
			<hui-element class="example">
				<hui-tab-container>
					<hui-element display-name={"Tab 1"}><hui-text("Tab 1")/></hui-element>
					<hui-element display-name={"Tab 2"}><hui-text("Tab 2")/></hui-element>
					<hui-element display-name={"Tab 3"}><hui-text("Tab 3")/></hui-element>
					<hui-element display-name={"Tab 4"}><hui-text("Tab 4")/></hui-element>
					<hui-element display-name={"Tab 5"}><hui-text("Tab 5")/></hui-element>
					<hui-element display-name={"Tab 6"}><hui-text("Tab 6")/></hui-element>
					<hui-element display-name={"Tab 7"}><hui-text("Tab 7")/></hui-element>
					<hui-element display-name={"Tab 8"}><hui-text("Tab 8")/></hui-element>
					<hui-element display-name={"Tab 9"}><hui-text("Tab 9")/></hui-element>
					<hui-element display-name={"Tab 10"}><hui-text("Tab 10")/></hui-element>
					<hui-element display-name={"Tab 11"}><hui-text("Tab 11")/></hui-element>
					<hui-element display-name={"Tab 12"}><hui-text("Tab 12")/></hui-element>
					<hui-element display-name={"Tab 13"}><hui-text("Tab 13")/></hui-element>
					<hui-element display-name={"Tab 14"}><hui-text("Tab 14")/></hui-element>
					<hui-element display-name={"Tab 15"}><hui-text("Tab 15")/></hui-element>
				</hui-tab-container>
			</hui-element>

			<hui-text("hui-sliders")/>
			<hui-element class="example">
				<hui-slider/>
				<hui-slider step={1} min={0} max={10} decimals={2}/>
			</hui-element>

			<hui-text("hui-checkbox")/>
			<hui-element class="example">
				<hui-checkbox/>
			</hui-element>

			<hui-text("hui-buttons")/>
			<hui-element class="example">
				<hui-button/>
				<hui-button><hui-icon("tick")/></hui-button>
				<hui-button><hui-text("Text Button")/></hui-button>
				<hui-button><hui-icon("tick")/><hui-text("Icon Button")/></hui-button>
			</hui-element>

			<hui-text("hui-commands")/>
			<hui-element class="example">
				<hui-text("This is a sandbox for hui-commands and how nested command contexts interacts")/>

				<hui-element id="commands-first">
					<hui-text("Paste in me") id="commands-first-text"/>
					<hui-element id="commands-second">
						<hui-text("Paste in me") id="commands-second-text"/>
						<hui-input-box/>
					</hui-element>
				</hui-element>
			</hui-element>
		</gym-widgets>

	function new(?parent) {
		super(parent);
		initComponent();

		setupTree();
		setupCommands();
	}

	function testMenu() :  Array<HuiMenu.MenuItem> {
		var submenu: Array<HuiMenu.MenuItem> = [
			{label: "Fire"},
			{label: "Water"},
			{label: "Air"},
		];
		submenu.push({label: "Recursive", menu: submenu});
		var radio = 0;

		var longMenu = [{label: "Lorem"},{label: "proident"},{label: "in"},{label: "quis"},{label: "deserunt"},{label: "magna"},{label: "voluptate"},{label: "sit"},{label: "irure"},{label: "amet"},{label: "deserunt"},{label: "laborum"},{label: "mollit"},{label: "occaecat"},{label: "ullamco"},{label: "id"},{label: "anim"},{label: "reprehenderit"},{label: "laborum"},{label: "aute"},{label: "aliqua"},{label: "minim"},{label: "ea"},{label: "pariatur"},{label: "magna"},{label: "amet"},{label: "cupidatat"},{label: "esse"},{label: "officia"},{label: "ad"},{label: "nostrud"},{label: "labore"},{label: "magna"},{label: "sint"},{label: "proident"},{label: "voluptate"},{label: "ex"},{label: "eiusmod"},{label: "anim"},{label: "et"},{label: "officia"},{label: "quis"},{label: "ullamco"},{label: "nisi"},{label: "id"},{label: "reprehenderit"},{label: "irure"},{label: "deserunt"},{label: "commodo"},{label: "culpa"}];
		return [
					{label: "File"},
					{label: "Edit"},
					{label: "Copy", icon: "ui/icons/copy.png"},
					{label: "Paste"},
					{label: "Disabled", enabled: false},
					{isSeparator: true},
					{label: "Recmenu", menu: submenu,},
					{label: "LongSubmenu", menu: longMenu},
					{label: "Submenu3", menu: [
						{label: "Fire"},
						{label: "Water"},
						{label: "Air"},
						{label: "Earth"},
						{label: "Really long entry that should make the menu grow"},
					]},
					{isSeparator: true, label: "Label"},
					{label: "Bar"},
					{isSeparator: true, label: "Check"},
					{label: "A", checked: false, stayOpen: true},
					{label: "B", checked: true, stayOpen: true},
					{label: "C", checked: false, stayOpen: true},
					{isSeparator: true, label: "Radio"},
					{label: "A", radio: () -> radio == 0, stayOpen: true, click: () -> radio = 0},
					{label: "B", radio: () -> radio == 1, stayOpen: true, click: () -> radio = 1},
					{label: "C", radio: () -> radio == 2, stayOpen: true, click: () -> radio = 2},
			];
	}

	function setupCommands() {
		// Register command is usually only reserved for internal hui usage, but we make
		// an exception here for demo purpose
		@:privateAccess
		{
			commandsFirst.registerCommand(HuiCommands.search, ElementAndChildren, () -> {
				commandsFirstText.text = "Search";
			});

			commandsFirst.registerCommand(HuiCommands.paste, ElementAndChildren, () -> {
				commandsFirstText.text = "Paste";
			});

			commandsFirst.registerCommand(HuiCommands.copy, ElementAndChildren, () -> {
				commandsFirstText.text = "Copy";
			});

			commandsFirst.registerCommand(HuiCommands.undo, ElementAndChildren, () -> {
				commandsFirstText.text = "Undo";
			});

			commandsSecond.registerCommand(HuiCommands.paste, ElementAndChildren, () -> {
				commandsSecondText.text = "Paste";
			});

			commandsSecond.registerCommand(HuiCommands.copy, ElementAndChildren, () -> {
				commandsSecondText.text = "Copy";
			});
		}
	}

	function setupTree() {
		var items: Array<TreeItem> = [];

		var randomNames = ["fig",
			"papaya",
			"lime",
			"pineapple",
			"kiwi",
			"tangerine",
			"cherry",
			"grapefruit",
			"pomegranate",
			"passon_fruit",
			"dragonfruit",
			"strawberry",
			"cantaloupe",
			"grape",
			"kumquat",
			"boysenberry",
			"tomato",
			"satsuma",
			"blackberry",
			"pear",
			"nectarine",
			"clementine",
			"date",
			"huckleberry",
			"star_fruit" ,
			"banana",
			"peach",
			"blueberry",
			"apricot",
			"plum",
			"apple",
			"orange",
			"avocado",
			"raspberry",
			"honeydew",
			"mango",
			"watermelon",
			"jujube",
			"coconut",
			"guava"];

		var rand = hxd.Rand.create();
		rand.init(0x42);

		for (i in 0...5) {
			items.push({
				id: '$i',
				name: randomNames[rand.random(randomNames.length)] + " " + '$i',
				children: [for (j in 0...100) {
					name: randomNames[rand.random(randomNames.length)],
					children: null,
					id: '$i.$j',
				}]
			});
		}

		tree.getItemName = (item) -> {
			return item?.name ?? "";
		}

		tree.getIdentifier = (item) -> {
			return item.id;
		}

		tree.getItemChildren = (item) -> {
			if (item == null)
				return items;
			return item.children;
		};
	}
}

class GymLayouts extends HuiElement {
	static var SRC =
		<gym-layouts>
			<hui-element class="example">
				<hui-split-container direction="vertical">
					<hui-element class="first"/>
					<hui-element class="second"/>
				</hui-split-container>
			</hui-element>
		</gym-layouts>
}


#end