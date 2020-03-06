library lua_threads;

uses  windows, sysutils,
      LuaLib,
      lua_threads_main;

{$R *.res}

function luaopen_lua_threads(ALuaInstance: Lua_State): longint; cdecl;
begin result:= initialize_lua_threads(ALuaInstance); end;

exports  luaopen_lua_threads name 'luaopen_lua_threads';

begin
  IsMultiThread:= true;
  {$ifdef FPC}
  DefaultFormatSettings.DecimalSeparator:= '.';
  {$else}
  DecimalSeparator:= '.';
  {$endif}
end.
