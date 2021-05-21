@cd %~dp0
set HIDE_DEBUG=1
@nwjs\nw.exe --remote-debugging-port=9222 --nwapp package.json %*