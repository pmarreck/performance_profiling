-- A case with processes = 3 spawns three fresh processes, gates on the
-- median one (by total metric across sizes) and keeps every process's
-- measurement in the record. The fixture adapter reports a different speed
-- per spawn (fast, slow, middle), so the selected process is known.
package.path='./src/?.lua;'..package.path
local uv=require('luv')
local process=require('process')
local json=require('json')
local root=uv.cwd()
local tmp=os.getenv('TMPDIR') or '/tmp'
local history=assert(uv.fs_mkdtemp(tmp..'/processes history.XXXXXX'))
local fixture=assert(uv.fs_mkdtemp(tmp..'/processes fixture.XXXXXX'))
process.checked({'git','-C',fixture,'init','-q','-b','yolo'})
process.checked({'git','-C',fixture,'-c','user.name=fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','fixture'})
local counter=history..'/../processes-spawns-'..uv.getpid()  -- outside the measured tree
local adapter=fixture..'/adapter.lua'
local f=assert(io.open(adapter,'wb'))
assert(f:write(([[
local f=io.open(%q,'a+') f:write('x') f:seek('set') local spawns=#f:read('*a') f:close()
local scale=({1,3,2})[spawns] or 1
local rows={}
for text in arg[2]:gmatch('[^,]+') do
	local n=tonumber(text) local v=n*1000*scale
	rows[#rows+1]={size=n,samples={cpu_ns={v,v,v}}}
end
io.write(require('cjson').encode({schema='performance-measurement/v1',correct=true,build_mode='optimized',rows=rows,spawn=spawns}),'\n')
]]):format(counter)))
assert(f:close())
local configuration={schema='performance-project/v1',project='processes_fixture',history_url='file://'..history,identity={runtime='LuaJIT',build_mode='optimized',concurrency=1},
	cases={{cores=1,processes=3,name='linear',mode='cg',metric='cpu_ns',sizes={10,20},bounds={1.5,2.5},command={'luajit',adapter,'{sizes}','{sizes}','{seed}'}}}}
f=assert(io.open(fixture..'/profiling.json','wb')); assert(f:write(json.encode(configuration))); assert(f:close())
local r=process.run({'luajit',root..'/bin/performance-profile','run','--config',fixture..'/profiling.json','--seed','1'},{cwd=root})
assert(r.rc==3,'expected UNBASELINED: '..r.stderr)
local record=json.decode(r.stdout)[1]
local raw=record.candidate.raw
local cf=assert(io.open(counter,'rb')); local spawns=#cf:read('*a'); cf:close()
assert(spawns==3,'expected 3 spawns, got '..spawns)
assert(type(raw.processes)=='table' and #raw.processes==3,'every process measurement must be kept')
assert(raw.selected_process==3 and raw.spawn==3,'median process (middle speed, third spawn) not selected: '..tostring(raw.selected_process))
os.remove(counter)
print('PASS: per-case processes select the median process and keep all of them')
