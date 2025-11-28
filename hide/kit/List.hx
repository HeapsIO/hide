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
		#if js
		native = new hide.Element('
			<kit-collapse-line>
				<kit-line><kit-label class="first">$label</kit-label><kit-text class="info"></kit-text><kit-button class="add square">+</kit-button><kit-button class="clear square">X</kit-button></kit-line>
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
		var info = native.querySelector(".info");
		listElement = native.querySelector("kit-list");

		info.innerHTML = '${value.length} element(s)';

		line.addEventListener("mousedown", (event: js.html.MouseEvent) -> {
			if (event.button != 0)
				return;
			openState = !openState;
			saveSetting(SameKind, "openState", openState ? true : null);
			refresh();
		});

		openState = getSetting(SameKind, "openState") ?? false;
		refresh();
		regenerateItems();
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

			var headerString = '<kit-line><kit-label class="first">$i</kit-label><kit-div class="header-content"></kit-div><kit-button class="square">-</kit-button></kit-line>';

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
				// If we don't copy, we will modify the value in the prefab
				// directly and this breaks the undo system
				value = hrt.prefab.Diff.deepCopy(value);
				value.splice(i, 1);
				broadcastValueChange(false);
				root.editor.rebuildInspector();
				e.stopPropagation();
				e.preventDefault();
			}

			listElement.appendChild(itemElement);
		}
		#end
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