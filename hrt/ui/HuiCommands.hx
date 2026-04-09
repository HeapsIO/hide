package hrt.ui;

import hxd.Key as K;

#if hui
class HuiCommands {
	static public var copy = new HuiCommand("Copy", {ctrl: true, key: K.C});
	static public var paste = new HuiCommand("Paste", {ctrl: true, key: K.V});
	static public var cut = new HuiCommand("Cut", {ctrl: true, key: K.X});
	static public var save = new HuiCommand("Save", {ctrl: true, key: K.S});

	static public var delete = new HuiCommand("Delete", {key: K.DELETE});
	static public var escape = new HuiCommand("Escape", {key: K.ESCAPE});

	static public var undo = new HuiCommand("Undo", {ctrl: true, key: K.Z});
	static public var redo = new HuiCommand("Redo", {ctrl: true, key: K.Y});

	static public var search = new HuiCommand("Search", {ctrl: true, key: K.F});

	static public var rename = new HuiCommand("Rename", {key: K.F2});
}

class HuiDebugCommands {
	static public var debugReload = new HuiCommand("Debug Reload", {ctrl: true, shift: true, key: K.R});
}

/**
	How a registered command shortcut is handled, by decreasing level of priority
**/
enum ShortcutContext {
	/**
		The element is focused
	**/
	Element;
	/**
		The element or one of it's children is focused
	**/
	ElementAndChildren;

	/**
		The element parent view is focused
	**/
	View;

	/**
		Global shortcut
	**/
	Global;
}

typedef Shortcut = {
	?ctrl: Bool,
	?alt: Bool,
	?shift: Bool,
	key: Int,
};

@:allow(hrt.ui.HuiCommands)
class HuiCommand {
	public var display : String;
	public var defaultShortcut: Shortcut;
	public var registeredShortcut : Shortcut;

	public function new(display: String, defaultShortcut: Shortcut) {
		this.display = display;
		this.defaultShortcut = defaultShortcut;
		this.registeredShortcut = defaultShortcut;
	}

	public function check(event: hxd.Event) : Bool {
		if (event.keyCode == registeredShortcut.key) {
			if ((registeredShortcut.ctrl ?? false) != hxd.Key.isDown(K.CTRL))
				return false;
			if ((registeredShortcut.shift ?? false) != hxd.Key.isDown(K.SHIFT))
				return false;
			if ((registeredShortcut.alt ?? false) != hxd.Key.isDown(K.ALT))
				return false;
			return true;
		}
		return false;
	}
}
#end