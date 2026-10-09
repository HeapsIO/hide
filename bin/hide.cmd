@cd %~dp0
set HIDE_DEBUG=1
set ELECTRON_RUN_AS_NODE=
@electron\electron.exe --remote-debugging-port=9222 . %*
