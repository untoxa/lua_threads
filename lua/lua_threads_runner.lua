package.path = "./?.lua;./scripts/?.lua"
package.cpath = "./?.dll;./scripts/?.dll"


-- tableutils ----------------------------------------
function table.val_to_str ( v )
    if "string" == type( v ) then
        v = string.gsub( v, "\n", "\\n" )
        if string.match( string.gsub(v,"[^'\"]",""), '^"+$' ) then
            return "'" .. v .. "'"
        end
        return '"' .. string.gsub(v,'"', '\\"' ) .. '"'
    end
    return "table" == type( v ) and table.tostring( v ) or tostring( v )
end
function table.key_to_str ( k )
    if "string" == type( k ) and string.match( k, "^[_%a][_%a%d]*$" ) then
        return k
    end
    return "[" .. table.val_to_str( k ) .. "]"
end
function table.tostring( tbl )
    if type(tbl)~='table' then return table.val_to_str(tbl) end
    local result, done = {}, {}
    for k, v in ipairs( tbl ) do
        table.insert( result, table.val_to_str( v ) )
        done[ k ] = true
    end
    for k, v in pairs( tbl ) do
        if not done[ k ] then
            table.insert( result, table.key_to_str( k ) .. "=" .. table.val_to_str( v ) )
        end
    end
    return "{" .. table.concat( result, "," ) .. "}"
end
table.unpack = table.unpack or unpack
------------------------------------------------------

tlib = require "lua_threads"
                         
function threadfunc2(astr)
    message(astr, 1);
    while not tlib.IsCurrentThreadTerminated() do
        --
    end
    message('thread2 exit')
end
 
function threadfunc(astr)
    thread2 = tlib.CreateThread(threadfunc2, "hello, world from thread2")
    message(astr, 1);
    while true do
        -- 
    end
end

function main()
    message("hello from main() from thread0", 1)
    thread1 = tlib.CreateThread(threadfunc, "hello, world from thread1")
    message('thread1: '..table.tostring(getmetatable(thread1)), 1)
    message('thread1.ThreadID: '..tostring(thread1:GetID()), 1)

    local i = 0
    while not GlobalExit() do
        i = i + 1
        if i == 10000000 then
            message("force free thread1", 1)
            thread1 = nil
            collectgarbage()           
            message("free thread1 done", 1)
        end 
    end
    thread1 = nil
    thread2 = nil
    collectgarbage()
    message('main() exit', 1)
end

function OnStop()
    message('OnStop called!', 1)
    exitflag = true
end

-- quik compability functions ------------------------

if type(isConnected) ~= 'function' then
    message = function(msg, code)
        io.write("TID:"..tostring(tlib.GetCurrentThreadID()).."  "..tostring(msg) .. '\r\n')
    end
    main()
else 
    GlobalExit = function()
        return exitflag == true
    end
end
