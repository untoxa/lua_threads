{$apptype console}

program lua_threads;

uses  windows, messages, classes, sysutils,
      LuaLib, LuaHelpers;

{$R *.res}

const global_exit_flag  : boolean = false;

{ lua api object }

type  tMainScriptApi  = class(TLuaClass)
        function    GlobalExit(AContext: TLuaContext): integer;
        function    Sleep(AContext: TLuaContext): integer;
      end;
      
function tMainScriptApi.GlobalExit(AContext: TLuaContext): integer;
begin result:= AContext.PushArgs([global_exit_flag]); end;
function tMainScriptApi.Sleep(AContext: TLuaContext): integer;
begin windows.Sleep(AContext.Stack[1].AsInteger); result:= 0; end;

{ log functions }

var log_cs : TRTLCriticalSection;
procedure log(const alog: ansistring); overload;
begin
  EnterCriticalSection(log_cs);
  try writeln(alog);
  finally LeaveCriticalSection(log_cs); end;
end;
procedure log(const afmt: ansistring; const aparams: array of const); overload;
begin log(format(afmt, aparams)); end;
procedure debuglog(const alog: pansichar); cdecl;
begin log(alog); end;

exports debuglog name '__debuglog';

{ main }

function LuaAtPanic(astate: Lua_State): Integer; cdecl;
var err: ansistring;
begin
  result:= 0;
  SetString(err, lua_tolstring(astate, -1, cardinal(result)), result);
  log('LUA PANIC: %s', [err]);
  raise Exception.CreateFmt('LUA ERROR: %s', [err]);
end;

function get_module_name(Module: HMODULE): ansistring;
var ModName: array[0..MAX_PATH] of char;
begin SetString(Result, ModName, GetModuleFileName(Module, ModName, SizeOf(ModName))); end;

function CtrlHandler(CtrlType: Longint): bool; stdcall;
const reasons        : array[0..6] of pAnsiChar = ('ctrl-C', 'ctrl-break', 'close', nil, nil, 'logoff', 'shutdown');
begin
  if ((CtrlType >= low(reasons)) and (CtrlType <= high(reasons))) then
    log('shutting down... reason: %s code: %d', [reasons[CtrlType], CtrlType]);
  global_exit_flag:= true;
  if (CtrlType = 1) then halt;
  result:= true;
end;

const hLib       : HMODULE         = 0;
var   fname, err : ansistring;
      luastate   : TLuaState;
      main_api   : tMainScriptApi;
begin
  IsMultiThread:= true;
  InitializeCriticalSection(log_cs);
  main_api:= nil;
  SetConsoleCtrlHandler(@CtrlHandler, true);
  fname:= expandfilename(changefileext(get_module_name(HInstance), '.lua'));
  if fileexists(fname) then begin
    hLib:= LoadLuaLib('lua5.1.dll');
    if (hLib <> 0) then begin
      luastate:= luaL_newstate;
      try
        lua_atpanic(luastate, LuaAtPanic);

        luaL_openlibs(luastate);
        main_api:= tMainScriptApi.create(hLib, '');
        main_api.RegisterGlobalMethod(luastate, 'GlobalExit', main_api.GlobalExit);
        main_api.RegisterGlobalMethod(luastate, 'Sleep', main_api.Sleep);

        with TLuaContext.create(luastate) do try
          if not ExecuteFileSafe(fname, 0, err) then log('error executing script: %s', [err]);
        finally free; end;

      finally lua_close(luastate) end;
      if assigned(main_api) then freeandnil(main_api);
      log('done!');
    end else log('error: unable to load lua5.1.dll');
  end else log('error: filename "%s" not found!', [fname]);
  log('press ENTER to quit'); readln;
  DeleteCriticalSection(log_cs);
end.
