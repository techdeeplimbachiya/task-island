' Starts Task Island in the background with no window. Works from wherever the repo is cloned.
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "cmd /c cd /d """ & dir & """ && npm start", 0, False
