// Loaded by main.js when HIDE_TEST=1 : replace blocking popups by console logs
// so that automated test runs never get stuck on a modal dialog
window.alert = function( msg ) {
	console.warn('[alert] ' + msg);
};
window.confirm = function( msg ) {
	console.warn('[confirm] ' + msg);
	return true;
};
