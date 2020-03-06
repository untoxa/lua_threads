unit lua_threads_main;

interface

uses  windows, messages, classes, sysutils, math,
      LuaLib, LuaHelpers;

const lua_supported_libs : array[0..1] of pAnsiChar = ('Lua5.1.dll', 'qlua.dll');

const package_name       = 'threads';
      msgbox_err_title   = 'LUA_THREADS ERROR';

const WM_KILLTHREAD      = WM_USER + 250;

type  tlogfunc           = procedure(const alog: pansichar); cdecl;

type  tRunnerThread      = class;

      tRunnerList        = class(tThreadList)
        function    addrunner(arunner: tRunnerThread): tRunnerThread;
        function    removerunner(arunner: tRunnerThread): tRunnerThread;
        function    checkrunner(arunner: tRunnerThread): boolean;
        function    getfirstrunner: tRunnerThread;
      end;

      tRunnerApi         = class(TLuaClass)
      private
        function    __gc(AContext: TLuaContext): integer;
      protected
        function    GetThreadObject(AContext: TLuaContext; AIndex: longint; extract: boolean): tRunnerThread;
        function    Terminated(AContext: TLuaContext): integer;
        function    TerminateThread(AContext: TLuaContext): integer;
        function    ForceTerminateThread(AContext: TLuaContext): integer;
        function    JoinThread(AContext: TLuaContext): integer;
        function    GetID(AContext: TLuaContext): integer;
      public
        function    GetCurrentID(AContext: TLuaContext): integer;
        function    IsTerminated(AContext: TLuaContext): integer;
        function    RunThread(AContext: TLuaContext): integer;
      end;

      pRunnerThreadData  = ^tRunnerThreadData;
      tRunnerThreadData  = record
        thread_instance  : tRunnerThread;
        ready            : boolean;
      end;

      tRunnerThread      = class(tThread)
      private
        fState           : TLuaState;
        fParams          : longint;
        fData            : pRunnerThreadData;
      public
        constructor create(AThreadState: TLuaState; nParams: longint; AData: pRunnerThreadData);
        procedure   execute; override;
      end;

const runner_list          : tRunnerList = nil;
      lua_threads_instance : tRunnerApi  = nil;

function initialize_lua_threads(ALuaInstance: Lua_State): longint;

implementation

const log_func             : tlogfunc    = nil;

procedure log(const alog: ansistring); overload;
begin if assigned(log_func) then log_func(pansichar(alog)); end;
procedure log(const afmt: ansistring; const aparams: array of const); overload;
begin log(format(afmt, aparams)) end;

{ tRunnerList }

function tRunnerList.addrunner(arunner: tRunnerThread): tRunnerThread;
begin
  result:= arunner;
  if assigned(result) then
    with locklist do try
      add(result);
    finally unlocklist; end;
end;

function tRunnerList.removerunner(arunner: tRunnerThread): tRunnerThread;
begin
  with locklist do try
    result:= extract(arunner);
  finally unlocklist; end;
end;

function tRunnerList.getfirstrunner: tRunnerThread;
begin
  with locklist do try
    if (count > 0) then result:= tRunnerThread(items[0])
                   else result:= nil;
  finally unlocklist; end;
end;

function tRunnerList.checkrunner(arunner: tRunnerThread): boolean;
begin
  with locklist do try
    result:= (IndexOf(arunner) >= 0);
  finally unlocklist; end;
end;

{ hook }

procedure lua_hook_proc(astate: lua_State; var ar: lua_Debug); cdecl;
var msg         : TMsg;
    threadstate : lua_State;
begin
  while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
    if Msg.Message = WM_KILLTHREAD then begin
      threadstate:= lua_State(Msg.wParam);
      lua_pushstring(threadstate, 'Abort requested!');
      lua_error(threadstate);
    end;
end;

{ tRunnerApi }

function tRunnerApi.__gc(AContext: TLuaContext): integer;
var trd: tRunnerThread;
begin
  try
    trd:= GetThreadObject(AContext, 1, true);
    if assigned(trd) then try
      try
        PostThreadMessage(trd.ThreadID, WM_KILLTHREAD, WPARAM(trd.fState), 0);
        trd.Terminate;
      finally if assigned(runner_list) then runner_list.removerunner(trd); end;
    finally trd.free; end;
  except on e: exception do messagebox(0, pAnsiChar(format('__gc() exception (TID: %d): %s', [GetCurrentThreadID, e.message])), msgbox_err_title, MB_ICONERROR); end;
  result:= 0;
end;

function tRunnerApi.GetThreadObject(AContext: TLuaContext; AIndex: longint; extract: boolean): tRunnerThread;
var datablock : pRunnerThreadData;
begin
  result:= nil;
  if assigned(runner_list) and assigned(AContext) then with AContext do
    if Stack[AIndex].IsUserData then begin
      datablock:= Stack[AIndex].AsUserData;
      if assigned(datablock) then begin
        result:= datablock^.thread_instance;
        if extract then datablock^.thread_instance:= nil;
      end;
      if assigned(result) and not runner_list.checkrunner(result) then result:= nil;
    end;
end;

function tRunnerApi.GetCurrentID(AContext: TLuaContext): integer;
begin result:= AContext.PushArgs([GetCurrentThreadID()]); end;

function tRunnerApi.IsTerminated(AContext: TLuaContext): integer;
var trd    : tRunnerThread;
    i      : longint;
    status : boolean;
    tid    : DWORD;
begin
  status:= true;
  if assigned(runner_list) then with runner_list.locklist do try
    i:= 0; tid:= GetCurrentThreadID;
    while i < count do begin
      trd:= items[i];
      if assigned(trd) and (trd.ThreadID = tid) then begin
        status:= trd.Terminated;
        i:= count;
      end else inc(i);
    end;
  finally runner_list.unlocklist; end;
  result:= AContext.PushArgs([status]);
end;

function tRunnerApi.Terminated(AContext: TLuaContext): integer;
var trd: tRunnerThread;
begin
  trd:= GetThreadObject(AContext, 1, false);
  if assigned(trd) then result:= AContext.PushArgs([trd.terminated])
                   else result:= AContext.PushArgs([false]);
end;

function tRunnerApi.RunThread(AContext: TLuaContext): integer;
var threadstate   : TLuaState;
    i, ssize      : longint;
    datablock     : pRunnerThreadData;
begin
  result:= 0;
  if assigned(runner_list) then with AContext do begin
    ssize:= StackSize;
    if ssize > 0 then begin
      datablock:= lua_newuserdata(CurrentState, sizeof(tRunnerThreadData));
      if assigned(datablock) then fillchar(datablock^, sizeof(tRunnerThreadData), 0);

      lua_newtable(CurrentState);
        lua_pushstring(CurrentState, '__gc');
        PushMethod(CurrentState, __gc);
        lua_settable(CurrentState, -3);

        lua_pushstring(CurrentState, '__index');
        lua_newtable(CurrentState);
          lua_pushstring(CurrentState, 'Terminated');
          PushMethod(CurrentState, Terminated);
          lua_settable(CurrentState,  -3);

          lua_pushstring(CurrentState, 'Terminate');
          PushMethod(CurrentState, TerminateThread);
          lua_settable(CurrentState,  -3);

          lua_pushstring(CurrentState, 'ForceTerminate');
          PushMethod(CurrentState, ForceTerminateThread);
          lua_settable(CurrentState,  -3);

          lua_pushstring(CurrentState, 'Join');
          PushMethod(CurrentState, JoinThread);
          lua_settable(CurrentState,  -3);

          lua_pushstring(CurrentState, 'GetID');
          PushMethod(CurrentState, GetID);
          lua_settable(CurrentState,  -3);

        lua_settable(CurrentState, -3);

        lua_pushstring(CurrentState, '__threadstate');
        threadstate:= lua_newthread(CurrentState);

        lua_settable(CurrentState, -3);

      lua_setmetatable(CurrentState, -2);                    // set garbage collector event for thread object

      lua_sethook(threadstate, lua_hook_proc, LUA_MASKCOUNT, 100);

      for i:= 1 to ssize do                                  // call(function, ...)
        lua_pushvalue(CurrentState, i);
      lua_xmove(CurrentState, threadstate, ssize);           // transfer all parameters to thread state

      datablock^.thread_instance:= runner_list.addrunner(tRunnerThread.create(threadstate, ssize - 1, datablock));
      repeat sleep(1); until datablock^.ready;

      result:= 1;
    end;
  end;
end;

function tRunnerApi.TerminateThread(AContext: TLuaContext): integer;
var trd: tRunnerThread;
begin
  trd:= GetThreadObject(AContext, 1, false);
  if assigned(trd) then trd.terminate;
  result:= 0;
end;

function tRunnerApi.ForceTerminateThread(AContext: TLuaContext): integer;
var trd: tRunnerThread;
begin
  trd:= GetThreadObject(AContext, 1, false);
  if assigned(trd) then PostThreadMessage(trd.ThreadID, WM_KILLTHREAD, WPARAM(trd.fState), 0);
  result:= 0;
end;

function tRunnerApi.JoinThread(AContext: TLuaContext): integer;
var trd: tRunnerThread;
begin
  trd:= GetThreadObject(AContext, 1, false);
  if assigned(trd) then trd.WaitFor;
  result:= 0;
end;

function tRunnerApi.GetID(AContext: TLuaContext): integer;
var trd: tRunnerThread;
begin
  result:= 0;
  trd:= GetThreadObject(AContext, 1, false);
  if assigned(trd) then result:= AContext.PushArgs([trd.ThreadID]);
end;

{ tRunnerThread }

constructor tRunnerThread.create(AThreadState: TLuaState; nParams: longint; AData: pRunnerThreadData);
begin
  fData:= AData;
  fState:= AThreadState;
  fParams:= nParams;
  inherited create(false);
end;

procedure tRunnerThread.execute;
var len : cardinal;
    err : ansistring;
begin
  freeonterminate:= false;
  try

    if assigned(fData) then fData^.ready:= true;
    if (lua_pcall(fState, fParams, 0, 0) <> 0) then begin
      len:= 0;
      SetString(err, lua_tolstring(fState, -1, len), len);
      lua_pop(fState, 1);
    end;
  except on e: exception do messagebox(0, pAnsiChar(format('Exception (TID: %d): %s', [GetCurrentThreadID, e.message])), msgbox_err_title, MB_ICONERROR); end;
end;

{ misc functions }

function get_lua_library: HMODULE;
var i : integer;
begin
  result:= 0;
  i:= low(lua_supported_libs);
  while (i <= high(lua_supported_libs)) do begin
    result:= GetModuleHandle(lua_supported_libs[i]);
    if (result <> 0) then i:= high(lua_supported_libs) + 1
                     else inc(i);
  end;
end;

function get_module_name(Module: HMODULE): ansistring;
var ModName: array[0..MAX_PATH] of char;
begin SetString(Result, ModName, GetModuleFileName(Module, ModName, SizeOf(ModName))); end;

function initialize_lua_threads(ALuaInstance: Lua_State): longint; 
var hLib       : HMODULE;
begin
  result:= 0;
  if not assigned(lua_threads_instance) then begin
    log_func:= GetProcAddress(GetModuleHandle(nil), '__debuglog');
    hLib:= get_lua_library;
    if (hLib <> 0) then begin
      // force lua unit initialization:
      InitializeLuaLib(hLib);
      lua_threads_instance:= tRunnerApi.create(hLib);
    end else messagebox(0, pAnsiChar(format('Failed to find LUA library: %s', [lua_supported_libs[low(lua_supported_libs)]])), msgbox_err_title, MB_ICONERROR);
  end;
  if assigned(lua_threads_instance) then with lua_threads_instance do begin
    StartRegister;
    // register adapter functions
    RegisterMethod('GetCurrentThreadID', GetCurrentID);
    RegisterMethod('IsCurrentThreadTerminated', IsTerminated);
    RegisterMethod('CreateThread', RunThread);
    result:= StopRegister(ALuaInstance, package_name, true);
    // register result table as a global variable:
    lua_pushvalue(ALuaInstance, -1);
    lua_setglobal(ALuaInstance, package_name);
  end;
  result:= min(result, 1);
end;

initialization
  runner_list:= tRunnerList.create;

finalization
  if assigned(lua_threads_instance) then freeandnil(lua_threads_instance);
  if assigned(runner_list) then freeandnil(runner_list);
end.
