@echo off
rem Launch the Mythforge desktop client (Godot 4.7 via winget, no CLI alias).
start "" "%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64.exe" --path "%~dp0godot"
