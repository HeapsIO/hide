package hrt.tools;

/**
	A class that allow queueing operations on a given Item type and ensuring that only one `callback`
	will be called on the given item per frame.
**/
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
			haxe.Timer.delay(processQueue, 0);
		}
	}

	function processQueue() {
		for (item => _ in queuedItems) {
			callback((cast item: Item));
		}
		queuedItems.clear();
	}
}