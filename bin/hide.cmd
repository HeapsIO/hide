@cd %~dp0
set ELECTRON_RUN_AS_NODE=
@start "" electron\electron.exe --remote-debugging-port=9222 . %*
