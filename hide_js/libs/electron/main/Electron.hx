package electron.main;

/**
	Minimal externs for the Electron main process APIs used by hide.ElectronMain
**/

typedef Rectangle = { x : Int, y : Int, width : Int, height : Int };

@:jsRequire("electron", "app")
extern class App {
	static var commandLine : { function appendSwitch( name : String, ?value : String ) : Void; };
	static var isPackaged : Bool;
	static function setName( name : String ) : Void;
	static function getPath( name : String ) : String;
	static function setPath( name : String, path : String ) : Void;
	static function getAppPath() : String;
	static function requestSingleInstanceLock() : Bool;
	static function whenReady() : js.lib.Promise<Dynamic>;
	static function quit() : Void;
	static function on( event : String, callb : haxe.Constraints.Function ) : Void;
}

@:jsRequire("electron", "BrowserWindow")
extern class BrowserWindow {
	var id(default, null) : Int;
	var webContents(default, null) : WebContents;
	function new( options : Dynamic ) : Void;
	function on( event : String, callb : haxe.Constraints.Function ) : Void;
	function once( event : String, callb : haxe.Constraints.Function ) : Void;
	function loadURL( url : String ) : js.lib.Promise<Dynamic>;
	function loadFile( file : String, ?options : Dynamic ) : js.lib.Promise<Dynamic>;
	function isDestroyed() : Bool;
	function getBounds() : Rectangle;
	function getSize() : Array<Int>;
	function setSize( w : Int, h : Int ) : Void;
	function setPosition( x : Int, y : Int ) : Void;
	function getTitle() : String;
	function setTitle( t : String ) : Void;
	function isMaximized() : Bool;
	function isMinimized() : Bool;
	function maximize() : Void;
	function unmaximize() : Void;
	function minimize() : Void;
	function restore() : Void;
	function setFullScreen( b : Bool ) : Void;
	function show() : Void;
	function showInactive() : Void;
	function hide() : Void;
	function focus() : Void;
	function blur() : Void;
	function close() : Void;
	function setMenu( menu : Menu ) : Void;
	static function fromWebContents( wc : WebContents ) : Null<BrowserWindow>;
	static function fromId( id : Int ) : Null<BrowserWindow>;
	static function getAllWindows() : Array<BrowserWindow>;
}

@:jsRequire("electron", "webContents")
extern class WebContents {
	var id(default, null) : Int;
	var session(default, null) : Session;
	function on( event : String, callb : haxe.Constraints.Function ) : Void;
	function send( channel : String, args : haxe.extern.Rest<Dynamic> ) : Void;
	function isDestroyed() : Bool;
	function isCrashed() : Bool;
	function openDevTools( ?options : Dynamic ) : Void;
	function setDevToolsWebContents( wc : WebContents ) : Void;
	static function fromId( id : Int ) : Null<WebContents>;
}

@:jsRequire("electron", "Menu")
extern class Menu {
	function getMenuItemById( id : String ) : Null<Dynamic>;
	static function buildFromTemplate( template : Array<Dynamic> ) : Menu;
	static function setApplicationMenu( menu : Null<Menu> ) : Void;
}

@:jsRequire("electron", "ipcMain")
extern class IpcMain {
	static function on( channel : String, callb : haxe.Constraints.Function ) : Void;
	static function off( channel : String, callb : haxe.Constraints.Function ) : Void;
	static function handle( channel : String, callb : haxe.Constraints.Function ) : Void;
}

@:jsRequire("electron", "dialog")
extern class Dialog {
	static function showOpenDialog( win : BrowserWindow, options : Dynamic ) : js.lib.Promise<{ canceled : Bool, filePaths : Array<String> }>;
	static function showSaveDialog( win : BrowserWindow, options : Dynamic ) : js.lib.Promise<{ canceled : Bool, ?filePath : String }>;
}

@:jsRequire("electron", "screen")
extern class Screen {
	static function getAllDisplays() : Array<Dynamic>;
}

@:jsRequire("electron", "clipboard")
extern class Clipboard {
	static function readText() : js.lib.Promise<String>;
	static function read() : js.lib.Promise<Array<ClipboardItem>>;
	static function write( items : Array<ClipboardItem> ) : js.lib.Promise<Dynamic>;
	static function clear() : Void;
}

@:jsRequire("electron", "ClipboardItem")
extern class ClipboardItem {
	var types(default, null) : Array<String>;
	function new( items : Dynamic<String> ) : Void;
	function getType( type : String ) : js.lib.Promise<js.html.Blob>;
}

@:jsRequire("electron", "globalShortcut")
extern class GlobalShortcut {
	static function register( accelerator : String, callb : Void -> Void ) : Bool;
	static function unregister( accelerator : String ) : Void;
	static function unregisterAll() : Void;
}

@:jsRequire("electron", "session")
extern class Session {
	static var defaultSession(default, null) : Session;
	function clearCache() : js.lib.Promise<Dynamic>;
	function setSpellCheckerLanguages( langs : Array<String> ) : Void;
}
