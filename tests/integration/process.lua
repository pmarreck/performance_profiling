package.path='./src/?.lua;'..package.path
local process=require('process')
local p=process.run({'luajit','-e','io.write(arg[0]); io.stderr:write("expected"); os.exit(7)','--','a "quote" \\ path\n'})
assert(p.rc==7 and p.stdout=='a "quote" \\ path\n' and p.stderr=='expected')
p=process.run({'luajit','-e','io.write(io.read("*a"))'},{stdin='binary\0data'})
assert(p.rc==0 and p.stdout=='binary\0data')
p=process.run({'/missing/performance-command'})
assert(p.rc==127 and p.stderr~='')
local uv=require('luv')
local dir=assert(uv.fs_mkdtemp((os.getenv('TMPDIR') or '/tmp')..'/process.XXXXXX'))
p=process.run({'luajit','-e','io.write(require("luv").cwd())'},{cwd=dir})
assert(p.stdout==dir)
local tick=0
p=process.run({'luajit','-e','io.write("READY\\nresult"); io.stdout:flush()'}, {ready_marker='READY',clock=function() tick=tick+100; return tick end})
assert(p.ready_ns==100 and p.stdout=='READY\nresult','readiness timing contract')
-- Extra environment reaches the child alongside the inherited environment.
p=process.run({'luajit','-e','io.write(os.getenv("PERFORMANCE_CORES") or "", "|", os.getenv("PATH") and "path" or "")'},{env={PERFORMANCE_CORES='3'}})
assert(p.stdout=='3|path','extra environment not passed with the inherited one: '..p.stdout)
-- A pinned command really runs on the requested CPUs (Linux).
local cpus=require('cpus')
local allowed=cpus.allowed()
if allowed and #allowed>=2 then
	local want=cpus.select(allowed,2)
	p=process.run(cpus.pin({'luajit','-e','io.write(io.open("/proc/self/status"):read("*a"):match("Cpus_allowed_list:%s*([^\\n]+)"))'},want))
	assert(p.rc==0 and p.stdout==cpus.format(want),'pinned child ran on '..p.stdout..', wanted '..cpus.format(want)..' '..p.stderr)
end
print('PASS: process argv, binary stdin, cwd, exit status, environment and CPU pinning')
