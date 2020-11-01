***Usage:

**Basic example:
  -e "notepad" -p "a -b -c" -c 3 -w 60 -l 5
  --exename="C:\Windows\System32\notepad.exe" --params="-a -b -c" --chkint=3 --wdtint=60 --launchmode=5
  
**Launch hidden Notepad window without any check:
	-e "notepad" -l 0

**Launch visible Notepad window with existing check every 15 s (full path is given for example)
	-e "C:\Windows\System32\notepad.exe" -l 5 -c 15 
	
**Launch visible Notepad window with existing check every 15 s and suspension check every 30 s:
	-e "C:\Windows\System32\notepad.exe" -l 5 -c 15 -w 30 
	
**Parameters explanation:

--exename | -e:
	Executable name and path, which will be executed by this program.
	If *.exe location is in current folder or in system32, path can be not specified.
	File extension also can be not provided, for example: "notepad" instead of "notepad.exe"
	If launch parameters does not contain symbols '\' or '/', you can add it here.
	Any type of executable file is supported, but only tested on .exe and .bat.
	
--params | -p:
	Executable launch parameters. If short parameter name (-p) is given, options should not start with "-".
	For example, -p "a -b -c" is ok, but -p "-a -b -c" is not ok. This is a bug of GetOptionValue function from Lazarus.
	Temporary solution: you can use --params="-a -b -c"
	
--chkint | -c:
	Process existing check interval, in seconds. If there is no such process with given name and PID, new
	process will be created and it PID will be stored in CHPW.
	If this parameter is omited, process will be created once.

--wdtint | -w:
	Process suspension check interval, in seconds. Process will be considered as suspended if it ProcessCycleTime
	not increased during this interval. If process is suspended, it will be killed by CHPW and new process will be 
	created and it PID will be stored in CHPW.
	If this parameter is omited, there will be no suspension check.

--launchmode | -l:
	Process launch mode. 0 - hidden window (SW_HIDE), 5 - normal window (SW_SHOW).
	This parameter passes directly into StartupInfo.wShowWindow and can take any value described here:
	https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-showwindow
	If this parameter is omited, there will be no process created.

--dirmode | -d:
	Process working directory.
	0: without changes, 1: chpw.exe location; 2: Executable location.