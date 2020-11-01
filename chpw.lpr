program chpw;

{$mode objfpc}{$H+}
{
CHPW - Create Hidden Process and Watch
Process launching (hidden or not), activity monitoring, presence monitoring, re-start by timeout.
Windows Vista (Windows Server 2008) and later.
Запуск процесса (скрытого или нет), мониторинг его наличия, мониторинг зависания, перезапуск.

USAGE: in usage.txt

NOTES:
1. DO NOT use writeln with Project options > Config and targed > -WG ! App will crash silently.
2. Disable Main Unit has Application.Title statement in Project options > Miscellaneous

TODO:
1. Исправить баг парсинга exename - должно быть первое вхождение! Или же ???
2. Рефракторинг
3. Перевод
}
uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Classes, SysUtils, CustApp, Windows;

{https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-showwindow
const SW_HIDE = 0; // StartupInfo
const SW_SHOW = 5; // StartupInfo   }
const PROCESS_QUERY_LIMITED_INFORMATION = $1000; // OpenProcess

{ CreateProcessA Process Creation Flags
Флаг (бит) необходим для запуска процессов, которые переживут заверщение родительского процесса }
const CREATE_BREAKAWAY_FROM_JOB = $01000000;

// External functions
{   QueryFullProcessImageNameA - запрос имени и пути процесса
A - non-unicode function (ansichar), W - unicode (widechar)
Windows Vista +
https://docs.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-queryfullprocessimagenamea }
function QueryFullProcessImageNameA(hProcess: HANDLE; dwFlags: DWORD; lpExeName: LPTSTR;
         lpdwSize: LPDWORD): BOOL; stdcall; external 'KERNEL32';
{   QueryProcessCycleTime - запрос кол-ва тактов CPU, потребленых процессом.
Windows Vista +
https://docs.microsoft.com/en-us/windows/win32/api/realtimeapiset/nf-realtimeapiset-queryprocesscycletime  }
function QueryProcessCycleTime(ProcessHandle: HANDLE; CycleTime: PULONG64): BOOL;
         stdcall; external 'KERNEL32';
type

  { TMyApp }

  TMyApp = class(TCustomApplication)
  protected
    procedure DoRun; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;

    function PathToFname(const path: string): string;
    function PathToDir(const path: string): string;
    procedure ParseParamsFPC;
    function ProcessCreate(const cmd: string; const showmode: int32): int32;
    function ProcessKill(const ProcessId: uint32): bool;
    function FnameByPid(const ProcessId: uint32): string;
    function CyclesByPid(const ProcessId: uint32): uint64;
  private
    CHK_Counter: uint32;  // Если дергать раз в секунду, переполнится через 68/156 лет (int/uint) :)
    WDT_Counter: uint32;
    CHK_Interval: int32; // Seconds, время проверки наличия процесса
    WDT_interval: int32; // Seconds, если за это время не было активности процесса, он завершается
    LaunchMode: int32;
    DirMode: int32;
    AppCurrentDir: string; // Текущая рабочая директория
    ParamExename: string;  // Содержит только имя исполняемого файла
    ParamLaunchCmd: string;
    ProcessID: uint32;
    ProcessExeName: string;
    ProcessCycles: uint64;
    ProcessCyclesLast: uint64;
  end;

{ TMyApplication }
constructor TMyApp.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  StopOnException:=True;

  // Инициализация переменных
  CHK_Counter:= 0;
  WDT_Counter:= 0;
  CHK_Interval:= -1;
  WDT_interval:= -1;
  LaunchMode:= -1;
  DirMode:= 0;
  ParamExename:='';
  ParamLaunchCmd:='';
  ProcessID:= 0;
  ProcessExeName:= '';
  ProcessCycles:= 0;
  ProcessCyclesLast:= 0;

  AppCurrentDir:= GetCurrentDir();

end;

function TMyApp.PathToFname(const path: string): string;
// Получение Exename из строки c путем.
{  Примеры строк:
notepad
notepad.exe
notepad.exe -a -b - не поддерживается
C:\Windows\System32\notepad.exe
C:\Windows\System32\notepad.exe -a -b - не поддерживается
C:\Windows\System32\notepad.exe -a -b -c C:\anyfile.txt - не поддерживается
"C:\location with spaces\notepad.exe" -a -b -c "C:\anyfile.txt"  - не поддерживается
}
var x: int32;
begin
   x:= path.LastDelimiter('/\'); // Returns -1 if not found
   if x >= 0 then
      Result:= Copy(path, x+2, Length(path)-x-1)
   else
      Result:= path; // Seems like no path was here..
end;

function TMyApp.PathToDir(const path: string): string;
// Получение DIRNAME из строки c путем
// Например, C:\Windows\System32\notepad.exe  > C:\Windows\System32
var
  x: int32;
begin
  x:= path.LastDelimiter('/\'); // Returns -1 if not found
     if x >= 0 then
        Result:= Copy(path, 1, x)
     else
        Result:= '';
end;

function TMyApp.ProcessCreate(const cmd: string; const showmode: int32): int32;
// <Windows>
// https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessa
// Возвращает PID созданного процесса
var
   ProcessInfo:tProcessInformation;
   StartupInfo:tStartupInfo;
begin
  FillChar(ProcessInfo, SizeOf(ProcessInfo), #0); // ZeroMemory
  FillChar(StartupInfo, SizeOf(StartupInfo), #0); // ZeroMemory
  StartupInfo.dwFlags:= STARTF_USESHOWWINDOW;
  StartupInfo.wShowWindow:= showmode;
  // Если заменить CREATE_NEW_CONSOLE > DETACHED_PROCESS - не стартует процесс
  if (CreateProcess(nil, PChar(cmd), Nil, Nil,False, CREATE_NEW_CONSOLE or CREATE_BREAKAWAY_FROM_JOB, Nil, PChar(AppCurrentDir),
            StartupInfo, ProcessInfo)) then begin
    Result:= ProcessInfo.dwProcessId;
    //Writeln('New PID is: '+Inttostr(Result))
  end else begin
    Result:= 0;
    //writeln('Failed to start "'+ParamExeName+'"');
  end;

end;

function TMyApp.ProcessKill(const ProcessId: uint32): bool;
// Убиение процесса по его PID
// https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-terminateprocess
var
  hnd: THandle;
begin
  Result:= false;
  hnd:= OpenProcess(PROCESS_TERMINATE, FALSE, processId);
    if TerminateProcess(hnd, 0) then
      Result:= true;
  CloseHandle(hnd);
end;

function TMyApp.FnameByPid(const ProcessId: uint32): string;
// <Windows>
// Получение имени исполняемого файла процесса по его PID
var
   hnd: THandle;
   bufsize: uint32 = 1024;
   buf: Array[0..1024] of Char;
   str: string = '';
begin
   Result:= '';
   // https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-openprocess
   hnd:= OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
      if QueryFullProcessImageNameA(hnd, 0, @buf, @bufsize) then
         SetString(str, @buf, bufsize); // Раньше почему-то не обрезалось по #0
   CloseHandle(hnd);
   Result:= PathToFname(str);
end;

function TMyApp.CyclesByPid(const ProcessId: uint32): uint64;
// Получение количества тактов проца, потребленных процессом
var
  hnd: THandle;
  Cycles: uint64 = 0;
begin
  Result:= 0;
  hnd:= OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
    if QueryProcessCycleTime(hnd, @Cycles) then
      Result:= Cycles;
  CloseHandle(hnd);
end;

procedure TMyApp.ParseParamsFPC;
  // Парсинг параметров командной строки
  // Порядок параметров не важен, но необходимо явное обозначение каждого
  // Пример: -e "path/exefile" -p "-a -b -c" -c 3 -w 60 -l 5
begin
  if HasOption('h', 'help') then begin
    Writeln('Help is not here, see https://github.com/madcatdev/chpw');
    Halt;
  end;

  // Выделяем exename, т.к. тут может быть C:\Windows\System32\notepad.exe
  if HasOption('e', 'exename') then  begin
    ParamExeName:= PathToFname(GetOptionValue('e', 'exename'));
    ParamLaunchCmd:= GetOptionValue('e', 'exename');
  end;

  if HasOption('p', 'params') then
    begin
    ParamLaunchCmd:= ParamLaunchCmd+' '+GetOptionValue('p', 'params');
    end;


  if HasOption('l', 'launchmode') then begin
    try
      LaunchMode:= Strtoint(GetOptionValue('l', 'launchmode'));
    finally end;
  end;

  if HasOption('d', 'dirmode') then begin
    try
      DirMode:= Strtoint(GetOptionValue('d', 'dirmode'));
    finally end;
  end;

  if HasOption('c', 'chkint') then begin
    try
      CHK_interval:= Strtoint(GetOptionValue('c', 'chkint'));
    finally end;
  end;

  if HasOption('w', 'wdtint') then begin
    try
      WDT_interval:= Strtoint(GetOptionValue('w', 'wdtint'));
    finally end;
  end;
end;

procedure TMyApp.DoRun;
begin
  ParseParamsFPC(); // Обработка параметров командной строки

  if (DirMode > 0) then begin  // Изменение рабочей директории
    if (DirMode = 1) then
      AppCurrentDir:= PathToDir(ParamStr(0));
    if (DirMode = 2) then
      AppCurrentDir:= PathToDir(GetOptionValue('e', 'exename'));
    SetCurrentDir(AppCurrentDir);
  end;

  if LaunchMode >= 0 then // Принудительный первый запуск без таймаута
    ProcessID:= ProcessCreate(ParamLaunchCmd, LaunchMode);
  if LaunchMode < 0 then begin
    //Writeln('Incorrect usage!');
    Halt;
  end;

  // Не входим в цикл, если оба интервала <0
  if (CHK_INTERVAL < 0) and (WDT_INTERVAL < 0) then
    Halt;

  while Launchmode >= 0 do begin
    Sleep(1000);
    Inc(CHK_Counter);
    Inc(WDT_Counter);

    // Проверка наличия процесса
    if CHK_Counter = CHK_INTERVAL then begin
      CHK_Counter:= 0;

      ProcessExeName:= FnameByPid(ProcessID);
      if Pos(ParamExename, ProcessExeName) <> 1 then begin
        //Writeln('PID #'+Inttostr(ProcessID)+' image name is not "'+ParamExeName+'"');
        ProcessID:= ProcessCreate(ParamLaunchCmd, LaunchMode);
      end;
    end;

    // Проверка зависания процесса
    // Зависшим считается процесс, не проявивший активности за время WDT_INTERVAL
    if WDT_Counter = WDT_INTERVAL then begin
      WDT_Counter:= 0;
      ProcessCycles:= CyclesByPid(ProcessID);
      if ProcessCycles = ProcessCyclesLast then begin
        ProcessKill(ProcessID);
        //Writeln('Killing process by WDT..');
        if ProcessKill(ProcessID) then begin
          //Writeln('OK');
        end;
      end;
      ProcessCyclesLast:= ProcessCycles;
    end;

  end;
  Terminate;
end;

destructor TMyApp.Destroy;
begin
  inherited Destroy;
end;

var
  Application: TMyApp;
begin
  Application:=TMyApp.Create(nil);
  Application.Run;
  Application.Free;
end.

