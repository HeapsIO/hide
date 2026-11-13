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
					<fancy-button class="compact"></fancy-button>

					<fancy-separator></fancy-separator>

					<fancy-button class="selected">
						<span class="ico ico-eye"></span>
					</fancy-button>
					<fancy-button class="compact"></fancy-button>
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
					<fancy-button class="compact"></fancy-button>
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
						new h3d.scene.CameraController.OrbitCameraController(scene.s3d);
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
			var sceneSection = section(element, "Scene");
			hide.html.Html.build(sceneSection.get(0),
				<div>
					<hide-toolbar>
						<hide-button id="detachButton" label="Detach"/>
						<hide-button id="newWindowButton" label="New Window"/>
					</hide-toolbar>
					<div id="sceneContainer" style="height: 400px"></div>
				</div>
			);

			function createScene(parent : js.html.Element) {
				var scene = new hide.comp.Scene(config, new Element(parent), null);
				scene.onReady = () -> {
					var cube = new h3d.prim.Cube(1, 1, 1, true);
					cube.addNormals();
					cube.addUVs();
					var mesh = new h3d.scene.Mesh(cube, h3d.mat.Material.create(h3d.mat.Texture.genNoise(64)), scene.s3d);
					scene.resetCamera(mesh, 1.5);
					new h3d.scene.CameraController.OrbitCameraController(scene.s3d).loadFromCamera();

					var tile = h2d.Tile.fromColor(0xFF8000, 24, 24).center();
					var square = new h2d.Bitmap(tile, scene.s2d);
					square.setPosition(24, 24);

					var fps = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
					fps.setPosition(48, 16);

					scene.onUpdate = (dt) -> {
						square.rotation += dt * 2;
						fps.text = 'FPS: ${scene.engine.fps}';
					};
				};
				return scene;
			}

			var scene : hide.comp.Scene = null;
			var detached : hide.comp.SubWindow = null;

			sceneSection.get(0).addEventListener("toggle", () -> {
				if (scene == null)
					scene = createScene(sceneContainer);
			});

			detachButton.onclick = (_) -> {
				if (scene == null || detached != null)
					return;
				var sceneEl = scene.element.get(0);
				detached = new hide.comp.SubWindow(sceneContainer.clientWidth, sceneContainer.clientHeight);
				detached.title = "Scene (detached)";
				detached.anchor = sceneContainer;
				detached.setContent(sceneEl);
				detached.onClose = () -> {
					sceneContainer.append(sceneEl);
					detached = null;
				};
			};

			newWindowButton.onclick = (_) -> {
				var sub = new hide.comp.SubWindow(640, 480);
				sub.title = "Scene";
				sub.anchor = sceneContainer;
				var content = sub.window.document.createDivElement();
				content.style.height = "100%";
				sub.setContent(content);
				createScene(content);
			};
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

				var win = electron.Window.open('app.html?thumbnail=true');
				win.on("closed", () -> {
					sock.close();
					sock = null;
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

		{
			var toolbar = section(element, "Html");
			hide.html.Html.build(toolbar.get(0),
				<hide-split-container style="height: 500px">
					<hide-tab-container anchor="previous" size="250">
						<div label="Scene">Scene tree</div>
						<div label="Files">Files</div>
					</hide-tab-container>
					<hide-split-container direction="vertical">
						<hide-tab-container>
							<div label="Viewport">
								<button onclick={() -> logs.append(js.Browser.document.createDivElement())}>Add log tab</button>
							</div>
						</hide-tab-container>
						<hide-tab-container id="logs" anchor="next" size="150">
							for (i in 0...3)
								<div label={'Log $i'}>Log content</div>
						</hide-tab-container>
					</hide-split-container>
					<hide-tab-container anchor="next" size="300">
						<div label="Properties">Properties</div>
					</hide-tab-container>
				</hide-split-container>
			);
		}

		{
			function buttons(parent : js.html.Element) {
				hide.html.Html.build(parent,
					<div style="display: contents">
						<hide-group>
							<hide-button icon={HideRes.icon.edit}/>
							<hide-button icon={HideRes.icon.clear}/>
							<hide-button checked icon={HideRes.icon.stroke}/>
						</hide-group>
						<hide-button icon={HideRes.icon.settings}/>
						<hide-button label="Options"/>
						<hide-button icon={HideRes.icon.settings} label="Options"/>
						<hide-button class="small-square" icon={HideRes.icon.sort}/>
						<hide-button class="medium-square" icon={HideRes.icon.sort}/>
						<hide-button class="quiet" icon={HideRes.icon.settings}/>
						<hide-button class="quiet" label="Options"/>
						<hide-button class="quiet" icon={HideRes.icon.settings} label="Options"/>

						<hide-button class="transparent" icon={HideRes.icon.settings}/>
						<hide-button class="transparent" label="Options"/>
						<hide-button class="transparent" checked label="Options"/>
						<hide-button class="transparent" icon={HideRes.icon.settings} label="Options"/>

						<hide-button class="quiet transparent" icon={HideRes.icon.settings}/>
						<hide-button class="quiet transparent" label="Options"/>
						<hide-button class="quiet transparent" checked label="Options"/>
						<hide-button class="quiet transparent" icon={HideRes.icon.settings} label="Options"/>

					</div>
				);
			}

			var toolbar = section(element, "Toolbar");
			hide.html.Html.build(toolbar.get(0), <hide-toolbar id="bar"></hide-toolbar>);
			buttons(bar);

			var hideButtons = section(element, "Hide Buttons");
			hide.html.Html.build(hideButtons.get(0), <div id="flex" style="display: flex; flex-direction: row; border: 1px solid red"></div>);
			buttons(flex);

			function openDropdown(e : js.html.MouseEvent) {
				hide.comp.ContextMenu.createDropdown(cast e.currentTarget, getContextMenuContent(), {});
			}

			hide.html.Html.build(hideButtons.get(0),
				<div>
					<h1>Size</h1>
					<hide-toolbar>
						<hide-button class="small-square" icon={HideRes.icon.settings}/>
						<hide-button class="medium-square" icon={HideRes.icon.settings}/>
						<hide-button icon={HideRes.icon.settings}/>
					</hide-toolbar>

					<h1>Button</h1>
					<hide-button icon={HideRes.icon.settings}/>

					<h1>Quiet</h1>
					<hide-button class="quiet" icon={HideRes.icon.settings}/>

					<h1>Text button</h1>
					<hide-button label="Options"/>

					<h1>Icon and text button</h1>
					<hide-button icon={HideRes.icon.settings} label="Options"/>

					<h1>Icon and really long text button</h1>
					<hide-button icon={HideRes.icon.settings} label="Lorem ispum sit dolor amet"/>

					<h1>Icon and dropdown aside</h1>
					<hide-group>
						<hide-button icon={HideRes.icon.visibility}/>
						<hide-button class="small-dropdown" onclick={openDropdown}></hide-button>
					</hide-group>

					<h1>With dropdown</h1>
					<hide-toolbar>
						<hide-button class="dropdown" onclick={openDropdown} label="Options"/>
						<hide-button class="dropdown" onclick={openDropdown} icon={HideRes.icon.sort}/>
					</hide-toolbar>

					<h1>Icon text and dropdown aside</h1>
					<hide-group>
						<hide-button icon={HideRes.icon.settings} label="Options"/>
						<hide-button class="small-dropdown" onclick={openDropdown}></hide-button>
					</hide-group>

					<h1>Toolbar</h1>
					<hide-toolbar>
						<hide-group>
							<hide-button icon={HideRes.icon.folder}/>
							<hide-button icon={HideRes.icon.copy}/>
							<hide-button icon={HideRes.icon.settings}/>
						</hide-group>
						<hide-group>
							<hide-button icon={HideRes.icon.edit}/>
							<hide-button icon={HideRes.icon.clear}/>
							<hide-button icon={HideRes.icon.stroke}/>
						</hide-group>
					</hide-toolbar>
				</div>
			);

			var hideIcons = section(element, "Hide Icons");
			hide.html.Html.build(hideIcons.get(0),
				<div>
					<hide-icon icon={HideRes.icon.add}/>
					<hide-button icon={HideRes.icon.add}/>
					<hide-group>
						<hide-button icon={HideRes.icon.axis}/>
						<hide-button icon={HideRes.icon.rotation}/>
						<hide-button icon={HideRes.icon.scale}/>
					</hide-group>
					<hide-group>
						<hide-button class="small-square" icon={HideRes.icon.axis}/>
						<hide-button class="small-square" icon={HideRes.icon.rotation}/>
						<hide-button class="medium-square" icon={HideRes.icon.scale}/>
					</hide-group>
				</div>
			);
		}

		{
			var search = section(element, "Search Files");
			hide.html.Html.build(search.get(0),
				<div>
					<input id="search-box" type="text" placeholder="Search ..."/>
					<div id="search-time"></div>
					<div id="search-results" style="height: 400px; overflow: auto"></div>
				</div>
			);

			var maxDisplayed = 500;
			var allFiles : Array<String> = [];
			var allFilesLowercase : Array<String> = [];
			var currentSearch = 0;

			function addLine(text: String) {
				var line = js.Browser.document.createDivElement();
				line.textContent = text;
				searchResults.append(line);
				return line;
			}

			function searchFiles() {
				currentSearch++;
				var thisSearch = currentSearch;
				var needle = searchBox.value.toLowerCase();

				searchResults.innerHTML = "";

				if (needle.length == 0) {
					for (i in 0...hxd.Math.imin(allFiles.length, maxDisplayed))
						addLine(allFiles[i]);
					searchTime.textContent = "";
					return;
				}

				hide.Search.batchFuzzySearchAsync(allFilesLowercase, needle, 0.01, 3, (results: Array<hide.Search.BatchFuzzySearchAsyncResult>, progress: Int) -> {
					if (thisSearch != currentSearch)
						return false;

					searchTime.textContent = 'Searching $progress / ${allFiles.length} ( ${Std.int(progress / allFiles.length * 100)}% ) - ${results.length} results';

					searchResults.innerHTML = "";
					if (results.length == 0 && progress == allFiles.length)
						addLine("no matches");

					for (i in 0...hxd.Math.imin(results.length, maxDisplayed)) {
						var r = results[i];
						var str = allFiles[r.pos];
						var start = hxd.Math.imax(0, r.lastCharPos - needle.length + 1);
						var line = addLine(str + ' (${r.distance})');
						hide.Search.cssHighlight(line, [start, r.lastCharPos + 1]);
					}

					return true;
				});
			}

			searchBox.oninput = (_) -> searchFiles();

			search.get(0).addEventListener("toggle", () -> {
				if (allFiles.length > 0)
					return;

				function rec(path: String) {
					for (file in sys.FileSystem.readDirectory(path)) {
						var childPath = path + "/" + file;
						if (sys.FileSystem.isDirectory(childPath)) {
							rec(childPath);
						} else {
							allFiles.push(childPath);
							allFilesLowercase.push(childPath.toLowerCase());
						}
					}
				}

				rec(hide.Ide.inst.resourceDir);
				searchFiles();
			});
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

	static function getContextMenuContent() : Array<hrt.ui.HuiMenu.MenuItem> {

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