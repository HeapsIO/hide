package hide.view;

class Gym extends hide.ui.View<{}> {
	override function onDisplay() {
		element.empty();
		element.addClass("hide-gym");

		{
			var toolbar = section(element, "Buttons");

			toolbar.append(new Element("<h1>Size</h1>"));

			toolbar.append(new Element('<fancy-toolbar>
				<fancy-button class="fancy-small make-small">
					<span class="label">Small</span>
				</fancy-button>
				<fancy-button class="fancy-medium make-medium">
					<span class="label">Medium</span>
				</fancy-button>
				<fancy-button class="fancy-big make-big">
					<span class="label">Big</span>
				</fancy-button>
			<fancy-toolbar>'));

			var demo = new Element("<div></div>").appendTo(toolbar);

			var small = toolbar.find(".make-small");
			var med = toolbar.find(".make-medium");
			var big = toolbar.find(".make-big");
			function setSize(newSize: Int) {
				demo.toggleClass("fancy-small", newSize == 0);
				demo.toggleClass("fancy-medium", newSize == 1);
				demo.toggleClass("fancy-big", newSize == 2);

				small.toggleClass("selected", newSize == 0);
				med.toggleClass("selected", newSize == 1);
				big.toggleClass("selected", newSize == 2);
			}

			small.click((e) -> setSize(0));
			med.click((e) -> setSize(1));
			big.click((e) -> setSize(2));

			setSize(1);

			demo.append(new Element("<h1>Button</h1>"));
			demo.append(new Element('<fancy-button><span class="ico ico-gear"></span></fancy-button>'));

			demo.append(new Element("<h1>Selected</h1>"));
			demo.append(new Element('<fancy-button class="selected"><span class="ico ico-gear"></span></fancy-button>'));

			demo.append(new Element("<h1>Text button</h1>"));

			demo.append(new Element('<fancy-button><span class="label">Options</span></fancy-button>'));
			demo.append(new Element('<fancy-separator></fancy-separator>'));
			demo.append(new Element('<fancy-button class="selected"><span class="label">Options</span></fancy-button>'));

			demo.append(new Element("<h1>Icon and text button</h1>"));
			demo.append(new Element('<fancy-button><span class="ico ico-gear"></span><span class="label">Options</span></fancy-button>'));
			demo.append(new Element('<fancy-separator></fancy-separator>'));
			demo.append(new Element('<fancy-button class="selected"><span class="ico ico-gear"></span><span class="label">Options</span></fancy-button>'));


			demo.append(new Element("<h1>Icon and really long text button</h1>"));
			demo.append(new Element('<fancy-button><span class="ico ico-gear"></span><span class="label">Lorem ispum sit dolor amet</span></fancy-button>'));

			demo.append(new Element("<h1>Icon and dropdown aside </h1>"));
			demo.append(new Element('
				<fancy-toolbar>
					<fancy-button>
						<span class="ico ico-eye"></span>
					</fancy-button>
					<fancy-button class="compact">
						<span class="ico ico-chevron-down"></span>
					</fancy-button>

					<fancy-separator></fancy-separator>

					<fancy-button class="selected">
						<span class="ico ico-eye"></span>
					</fancy-button>
					<fancy-button class="compact">
						<span class="ico ico-chevron-down"></span>
					</fancy-button>
				</fancy-toolbar>
				'));

			demo.append(new Element("<h1>With dropdown</h1>"));
			demo.append(new Element('
				<fancy-toolbar>
					<fancy-button class="dropdown">
						<span class="label">Options</span>
					</fancy-button>
					<fancy-separator></fancy-separator>
					<fancy-button class="dropdown">
						<span class="ico ico-filter"></span>
					</fancy-button>
				</fancy-toolbar>
			'
			)
			);

			demo.append(new Element("<h1>Icon text and dropdown aside </h1>"));
			demo.append(new Element('
				<fancy-toolbar>
					<fancy-button>
						<span class="ico ico-gear"></span>
						<span class="label">Options</span>
					</fancy-button>
					<fancy-button class="compact">
						<span class="ico ico-chevron-down"></span>
					</fancy-button>
			'));


			demo.find(".compact, .dropdown").click((e:js.jquery.Event) -> {
				hide.comp.ContextMenu.createDropdown(cast e.currentTarget, getContextMenuContent(), {});
			});

			demo.append(new Element("<h1>Toolbar</h1>"));
			demo.append(new Element(
				'<fancy-toolbar>
					<fancy-button>
						<span class="ico ico-home"></span>
					</fancy-button>
					<fancy-button>
						<span class="ico ico-clipboard"></span>
					</fancy-button>
					<fancy-button>
						<span class="ico ico-gear"></span>
					</fancy-button>
					<fancy-separator></fancy-separator>
					<fancy-button class="selected">
						<span class="ico ico-pencil"></span>
					</fancy-button>
					<fancy-button>
						<span class="ico ico-eraser"></span>
					</fancy-button>
					<fancy-button>
						<span class="ico ico-paint-brush"></span>
					</fancy-button>
				</fancy-toolbar>'));

			demo.append(new Element("<h1>Contenteditable</h1>"));
			var ce = new hide.comp.ContentEditable(demo);
			ce.element.text("Edit me !");

			var ce2 = new Element("<fancy-name>Edit me too !</fancy-name>");
			demo.append(ce2);
			ce2.get(0).contentEditable = "true";
			var ce3 = new hide.comp.ContentEditable(null,ce2);
			ce3.onChange = (v) -> trace(v);
			demo.append(new Element("<fancy-button>Focus</fancy-button>").click((_) -> ce.element.focus()));
		}

		{
			var toolbar = section(element, "Windows");

			var btn = new Element("<fancy-button><span class='label'>Open subwindow 'test'</span></h1>");

			toolbar.append(btn);

			var subwindow : js.html.Window;
			var scene : hide.comp.Scene;

			btn.on("click", (_) -> {
				subwindow = js.Browser.window.open("", "test","popup=true");

					var jq = new Element(subwindow.document.body);
					jq.empty();
					jq.append(new Element("<p>This is a triumph</p>"));
					var container = new Element("<div></div>");
					jq.append(container);

					// var paragraphs = subwindow.document.querySelectorAll("p");
					// for (p in paragraphs) {
					// 	p.textContent = "This is the begining of something great";
					// }

					scene = new hide.comp.Scene(config, container, null);

					scene.onReady = () -> {
						new h3d.scene.CameraController(scene.s3d);
						var box = new h3d.scene.Box(scene.s3d);
						box.material.mainPass.setPassName("overlay");

						var text = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
						text.text = "Hello world";
						text.x = 8;
						text.y = 8;
					};

					var drag = new Element('<div draggable="true">Drag Me</div>').appendTo(jq);
					drag.get(0).addEventListener("dragstart", (ev: js.html.DragEvent) -> {
						ev.dataTransfer.setData("text/plain", "foo");
						ev.dataTransfer.dropEffect = "copy";
					});
			});

			var btn = new Element("<fancy-button><span class='label'>Spawn cube in subwindow</span></h1>");
			toolbar.append(btn);

			btn.on("click", (_) -> {
				var box = new h3d.scene.Box(0xFFFFFFFF, scene.s3d);
				box.setPosition(hxd.Math.random(10),hxd.Math.random(10),hxd.Math.random(10));
				box.material.mainPass.setPassName("overlay");
				box.material.color.r = hxd.Math.random();
				box.material.color.g = hxd.Math.random();
				box.material.color.b = hxd.Math.random();
			});

			var dropZone = new Element("<div>Drop something on me from the other window</div>").appendTo(toolbar);
			dropZone.get(0).addEventListener("drop", (ev : js.html.DragEvent) -> {
				ev.preventDefault();
				var data = ev.dataTransfer.getData("text/plain");
				dropZone.text(data);
			});

			dropZone.get(0).addEventListener("dragover", (ev : js.html.DragEvent) -> {
				ev.preventDefault();
				ev.dataTransfer.dropEffect = "copy";
			});

			var btn2 = new Element("<fancy-button><span class='label'>Localhost 5500</span></h1>").appendTo(toolbar);
			btn2.on("click", (_) -> {
				subwindow = js.Browser.window.open("http://127.0.0.1:5500/", "test","popup=true");
			});
		}


		{
			var toolbar = section(element, "Offscreen Rendering");
			var btn = new Element("<fancy-button><span class='label'>Render test.thumb.png</span>").appendTo(toolbar);

			btn.get(0).onclick = (e) -> {
				var fm = hide.tools.FileManager.inst;
			}

			var btn = new Element("<fancy-button><span class='label'>Test thumbnail generator</span>").appendTo(toolbar);

			var sub : js.node.child_process.ChildProcess = null;

			var remoteSocket : hxd.net.Socket = null;

			btn.get(0).onclick = (e) -> {

				if (sock != null) {
					sock.close();
				}

				sock = new hxd.net.Socket();

				sock.onError = (msg) -> {
					trace("Socket error " + msg);
				}

				sock.onData = () -> {
					trace("sock.onData");
					while(sock.input.available > 0) {
						var data = sock.input.readLine().toString();

						trace("recieved data sock.onData", data);
					}
				}

				sock.bind("localhost", 9669, (rs: hxd.net.Socket) -> {
					trace("new connexion");
					remoteSocket = rs;

					remoteSocket.onError = (msg) -> {
						trace("Socket error " + msg);
					}

					remoteSocket.onData = () -> {
						trace("rawsocket.onData");

						while(remoteSocket.input.available > 0) {
							var data = remoteSocket.input.readLine().toString();

							trace("recieved data", data);
						}
					}
				});

				nw.Window.open('app.html?thumbnail=true', {new_instance: true}, (win: nw.Window) -> {
					win.on("close", () -> {
						sock.close();
						sock = null;
					});
				});
			}

			var btn = new Element("<fancy-button><span class='label'>Send message</span>").appendTo(toolbar);
			btn.get(0).onclick = (e) -> {
				remoteSocket.out.writeString("Test message\n");
			}

			var btn = new Element("<fancy-button><span class='label'>Rethrow test</span>").appendTo(toolbar);
			btn.get(0).onclick = (e) -> {
				rethrowTest1();
			}
		}

		{
			var toolbar = section(element, "Drag & Drop 2");
			var btn = new Element("<fancy-button><span class='label'>Drag Me</span></h1>").appendTo(toolbar);

			hide.tools.DragAndDrop.makeDraggable(btn.get(0), (event: hide.tools.DragAndDrop.DragEvent, data: hide.tools.DragAndDrop.DragData) -> {
				switch (event) {
					case Start:
						data.setThumbnail(btn.get(0));
					case Stop:
				}
			});

			var dropTarget1 = new Element("<fancy-button><span class='label'>Target 1</span></h1>").appendTo(toolbar);
			var dropTarget2 = new Element("<fancy-button><span class='label'>Target 2</span></h1>").appendTo(toolbar);

			for (target in [dropTarget1, dropTarget2]) {
				hide.tools.DragAndDrop.makeDropTarget(target.get(0), (event: hide.tools.DragAndDrop.DropEvent, data: hide.tools.DragAndDrop.DragData) -> {
					var name = target.find("span").text();
					switch(event) {
						case Move:
							trace("move", name);
						case Enter:
							trace("enter", name);
							target.get(0).style.outline = "1px solid blue";
						case Leave:
							trace("leave", name);
							target.get(0).style.outline = null;
						case Drop:
							trace("drop", name);
					}

				});
			}
		}
	}

	function rethrowTest1() {
		try {
			rethrowTest2();
		} catch (e) {
			js.Lib.rethrow();
		}
	}

	function rethrowTest2() {
		try {
			rethrowTest3();
		} catch(e) {
			js.Lib.rethrow();
		}
	}

	function rethrowTest3() {
		throw "Error Lol";
	}

	var subwin: js.html.Window;
	static var sock: hxd.net.Socket;


	static function section(parent: Element, name: String) : Element {
		return new Element('<details><summary>$name</summary></details>').appendTo(parent);
	}

	static public function onBeforeReload() {
		sock?.close();
		sock = null;
	}

	static function getContextMenuContent() : Array<hide.comp.ContextMenu.MenuItem> {

		var radioState = 0;
		return [
			{label: "Label"},

			{isSeparator: true},
			{label: "Basic"},
			{label: "Disabled", enabled: false},
			{label: "Icon", icon: "pencil"},
			{label: "Checked", checked: true},
			{label: "Unchecked", checked: false},
			{label: "Keys", keys: "Ctrl+Z"},
			{label: "Long Keys", keys: "Ctrl+Shift+Alt+Z"},
			{label: "Keys Disabled", keys: "Ctrl+D", enabled: false},

			{label: "Radio", isSeparator: true},
			{label: "Green", radio: () -> radioState == 0, click: () -> radioState = 0, stayOpen: true },
			{label: "Blue", radio: () -> radioState == 1, click: () -> radioState = 1, stayOpen: true },
			{label: "Red", radio: () -> radioState == 2, click: () -> radioState = 2, stayOpen: true },

			{label: "Edit", isSeparator: true},
			{label: "Copy", keys: "Ctrl+C"},
			{label: "Paste", keys: "Ctrl+V"},
			{label: "Cut", keys: "Ctrl+X"},

			{label: "Menus", isSeparator: true},
			{label: "Submenu", menu: [
				{label: "Submenu item 1"},
				{label: "Submenu item 2"},
				{label: "Submenu item 3"},
			]},
			{label: "Very long", menu: [
				for (i in 0...200) {label: 'Item $i'}
			]}
		];
	}

	static var _ = hide.ui.View.register(Gym);
}