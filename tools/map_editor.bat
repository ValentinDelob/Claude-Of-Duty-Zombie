@echo off
rem Editeur de cartes de Claude of Duty Zombie (docs/MAP_AUTHORING.md).
rem Godot 4.7.2 doit etre dans le PATH, ou : set GODOT=C:\chemin\godot.exe
cd /d "%~dp0.."
if "%GODOT%"=="" set GODOT=godot
start "" "%GODOT%" --path . res://scenes/editor/map_editor.tscn
