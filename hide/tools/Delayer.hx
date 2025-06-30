package hide.tools;

class Delayer<Item> {
	var queuedItems : Map<{}, Bool> = [];
	var callback : (Item) -> Void;

	public function new(callback: (Item) -> Void) {
		this.callback = callback;
	}

	public function queue(item: Item) {
		var empty = !queuedItems.iterator().hasNext();
		queuedItems.set(cast item, true);
		if (empty) {
			js.Browser.window.requestAnimationFrame((_) -> processQueue());
		}
	}

	function processQueue() {
		for (item => _ in queuedItems) {
			callback((cast item: Item));
		}
		queuedItems.clear();
	}
}