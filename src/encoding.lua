local uv=require('luv')
local process=require('process')
local source=assert(os.getenv('PERFORMANCE_PRINTABLE_BINARY'),'use the pinned Nix runtime (PERFORMANCE_PRINTABLE_BINARY missing)')
local old_arg,old_map=arg,os.getenv('PRINTABLE_BINARY_MAP')
arg=nil; uv.os_unsetenv('PRINTABLE_BINARY_MAP')
local ok,pb=pcall(dofile,source..'/bin/printable-binary-luajit')
arg=old_arg
if old_map then uv.os_setenv('PRINTABLE_BINARY_MAP',old_map) end
assert(ok,pb)
local f=assert(io.open(source..'/character_map.txt','rb')); local data=f:read('*a'); f:close()
local M={name='printable-binary-spaces/v1',map_sha256=process.sha256(data)}
function M.encode(bytes) return pb.encode(bytes,{spaces=true}) end
function M.decode(bytes) return pb.decode(bytes,{spaces=true}) end
return M
