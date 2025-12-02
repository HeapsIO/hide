package hide.kit;

#if domkit

class List<T> extends Widget<Array<T>> {
	var openState : Bool;

	#if js
	var fancyArray : hide.comp.FancyArray<T>;
	var listElement: NativeElement;
	#end
	public dynamic function makeLine(header: hide.kit.Element, content: hide.kit.Element, item: T) : Void {

	}

	public dynamic function createItem() : T {
		return cast {};
	}

	public function new(parent: Element, id: String, makeLine: (header: hide.kit.Element, content: hide.kit.Element, item: T) -> Void, createItem: () -> Dynamic) {
		super(parent, id);
		this.makeLine = makeLine;
		this.createItem = createItem;
	}

	override function makeSelf() {
		if (isIndeterminate()) {
			makeIndeterminateWidget();
			return;
		}

		#if js
		native = new hide.Element('
			<kit-collapse-line>
				<kit-line><kit-label class="first">$label</kit-label><kit-text class="info"></kit-text><kit-button class="add square"><kit-image style="background-image: url(\'res/icons/svg/add.svg\')"/></kit-button><kit-button class="clear square"><kit-image style="background-image: url(\'res/icons/svg/delete.svg\')"/></kit-button></kit-line>
				<kit-content>
					<kit-content>
						<kit-list>
						</kit-list>
					</kit-content>
				</kit-content>
			</kit-collapse-line>
		'
		)[0];

		var line = native.querySelector("kit-line");
		listElement = native.querySelector("kit-list");

		line.addEventListener("mousedown", (event: js.html.MouseEvent) -> {
			if (event.button != 0)
				return;
			openState = !openState;
			saveSetting(SameKind, "openState", openState ? true : null);
			refresh();
		});

		var add = native.querySelector(".add");
		add.onmousedown = (e) -> {
			e.stopPropagation();
		}
		add.onclick = (e) -> {
			e.stopPropagation();

			parent?.change(() -> {
				value.push(createItem());
				changeBehaviorInternal(false);
			}, false);

			syncValueUI();
		}

		var clear = native.querySelector(".clear");
		clear.onmousedown = (e) -> {
			e.stopPropagation();
		}
		clear.onclick = (e) -> {
			e.stopPropagation();

			parent?.change(() -> {
				value.resize(0);
				changeBehaviorInternal(false);
			}, false);

			syncValueUI();
		}

		listElement.ondragstart = (e: js.html.DragEvent) -> {
			var target : js.html.Element = cast e.target;
			if (!target.classList.contains("drag"))
				return;
			var id = Std.parseInt(target.dataset.id);
			trace(id);
			var header = target.closest("kit-line");
			e.dataTransfer.setDragImage(header, 0,11);
		};


		function dragOverHandler(over: Bool, e: js.html.DragEvent) {
			var target : js.html.Element = cast e.target;
			var element = target.closest("kit-collapse-line") ?? target.closest("kit-line");
			element.classList.toggle("dragover", over);
		}

		listElement.ondragenter = dragOverHandler.bind(true);
		listElement.ondragleave = dragOverHandler.bind(false);
		listElement.ondragover = dragOverHandler.bind(true);

		openState = getSetting(SameKind, "openState") ?? false;
		refresh();
		syncValueUI();
		#end
	}

	override function makeChildren() {
		// skip making children
	}

	function regenerateItems() {
		#if js
		untyped listElement.replaceChildren();
		for (i => item in value) {
			var header = new KitListHeader(this, 'item_header_$i');
			var content = new Element(this, 'item_content_$i');
			makeLine(header, content, item);

			var headerString = '<kit-line><kit-label class="first"><kit-image draggable="true" data-id="$i" class="drag" style="background-image: url(\'res/icons/svg/drag.svg\')"></kit-image>$i</kit-label><kit-div class="header-content"></kit-div><kit-button class="square"><kit-image style="background-image: url(\'res/icons/svg/substract.svg\')"/></kit-button></kit-line>';

			var itemElement = if (content.children.length == 0) {
				new hide.Element('
					$headerString
				')[0];
			} else {
				var itemElement = new hide.Element('
					<kit-collapse-line>
						$headerString
						<kit-content>
							<kit-content>
							</kit-content>
						</kit-content>
					</kit-collapse-line>
				'
				)[0];

				var lineElement = itemElement.querySelector("kit-line");
				header.target = lineElement;


				var lineOpenState = getSetting(SameKind, 'openState.list.$i') ?? false;

				function refreshLine() {
					itemElement.classList.toggle("open", lineOpenState);
				}

				lineElement.addEventListener("click", (event: js.html.MouseEvent) -> {
					if (event.button != 0)
						return;
					lineOpenState = !lineOpenState;
					saveSetting(SameKind, 'openState.list.$i', lineOpenState ? true : null);
					refreshLine();
				});

				refreshLine();

				var contentElement = itemElement.querySelector("kit-content>kit-content");

				content.make(false);
				contentElement.appendChild(content.native);

				itemElement;
			}

			header.target = itemElement.querySelector(".header-content");
			header.make(false);

			var removeButton = itemElement.querySelector("kit-button");

			removeButton.onclick = (e) -> {
				parent?.change(() -> {
					value.splice(i, 1);
					changeBehaviorInternal(false);
					syncValueUI();
				}, false);

				e.stopPropagation();
				e.preventDefault();
			}

			var drag = itemElement.querySelector(".drag");

			listElement.appendChild(itemElement);
		}
		#end
	}

	override function change(callback: () -> Void, isTemporaryEdit: Bool) {
		parent?.change(() -> {
			callback();
			changeBehaviorInternal(isTemporaryEdit);
		}, isTemporaryEdit);
	}

	// override function propagateChange(kind:hide.kit.Element.ChangeKind) {
	// 	switch(kind) {
	// 		case Value(inputs, temporary):
	// 			for(input in inputs) {
	// 				@:privateAccess input.onFieldChange(isTemporaryEdit);
	// 				input.onValueChange(isTemporaryEdit);
	// 			}

	// 	}
	// 	}
	// }

	override function syncValueUI() {
		#if js
		var info = native.querySelector(".info");
		info.innerHTML = '${value.length} element(s)';
		#end
		regenerateItems();
	}

	function makeInput():NativeElement {
		throw new haxe.exceptions.NotImplementedException();
	}

	function stringToValue(str:String):Null<Array<T>> {
		throw new haxe.exceptions.NotImplementedException();
	}


	function getDefaultFallback():Null<Array<T>> {
		return [];
	}

	function refresh() {
		#if js
		native.classList.toggle("open", openState);
		#end
	}

	override function valueEqual(a:Array<T>, b:Array<T>):Bool {
		return hrt.prefab.Diff.diffArray(a, b) == Skip;
	}
}

class KitListHeader extends hide.kit.Line {
	public var target : NativeElement;

	override function get_nativeContent():NativeElement {
		return target;
	}

	override function makeSelf():Void {

	}
}

#end