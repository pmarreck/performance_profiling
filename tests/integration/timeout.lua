-- A case's declared timeout_ms reaches the real child process: a child that
-- outlives a 100 ms deadline is killed and recorded as incorrect, while the
-- same fast adapter under a generous deadline passes. Every observation
-- records the effective deadline, including the 30000 ms default.
package.path='./src/?.lua;'..package.path
local uv=require('luv')
local process=require('process')
local json=require('json')
local root=uv.cwd()
local tmp=os.getenv('TMPDIR') or '/tmp'
local history=assert(uv.fs_mkdtemp(tmp..'/timeout history.XXXXXX'))
local fixture=assert(uv.fs_mkdtemp(tmp..'/timeout fixture.XXXXXX'))
process.checked({'git','-C',fixture,'init','-q','-b','yolo'})
process.checked({'git','-C',fixture,'-c','user.name=fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','fixture'})
local adapter=fixture..'/adapter.lua'
local f=assert(io.open(adapter,'wb'))
-- With HANG set the adapter blocks far longer than any deadline under test.
assert(f:write([[
if arg[1]=='hang' then require('luv').sleep(120000) end
local rows={}
for text in arg[2]:gmatch('[^,]+') do
	local n=tonumber(text) local v=n*1000
	rows[#rows+1]={size=n,samples={cpu_ns={v,v,v}}}
end
io.write(require('cjson').encode({schema='performance-measurement/v1',correct=true,build_mode='optimized',rows=rows}),'\n')
]]))
assert(f:close())
local function run(mode,timeout_ms)
	local case={cores=1,name='linear',mode='cg',metric='cpu_ns',sizes={10,20},bounds={1.5,2.5},timeout_ms=timeout_ms,command={'luajit',adapter,mode,'{sizes}'}}
	local configuration={schema='performance-project/v1',project='timeout_fixture',history_url='file://'..history,identity={runtime='LuaJIT',build_mode='optimized',concurrency=1},cases={case}}
	local cf=assert(io.open(fixture..'/profiling.json','wb')); assert(cf:write(json.encode(configuration))); assert(cf:close())
	-- The outer deadline only guards this test against a hung profiler.
	local r=process.run({'luajit',root..'/bin/performance-profile','run','--config',fixture..'/profiling.json','--seed','1'},{cwd=root,timeout_ms=60000})
	assert(not r.timed_out,'profiler itself hung')
	return r,json.decode(r.stdout)[1]
end
local started=uv.hrtime()
local r,record=run('hang',100)
local elapsed_ms=(uv.hrtime()-started)/1e6
assert(r.rc==1,'a child past its deadline must fail the run: rc '..tostring(r.rc)..' '..r.stderr)
assert(record.eligible==false and record.verdict~='PASS','timed-out child counted as a valid measurement: '..tostring(record.verdict))
-- One timing retry is allowed, so two deadlines may pass; neither may approach the 30 s default.
assert(elapsed_ms<20000,'declared 100 ms deadline was not applied ('..elapsed_ms..' ms)')
assert(record.definition.timeout_ms==100,'record does not carry the declared deadline')
r,record=run('fast',5000)
assert(r.rc==3,'fast child under a generous deadline should be UNBASELINED: '..r.stderr)
assert(record.definition.timeout_ms==5000,'record does not carry the declared deadline')
r,record=run('fast',nil)
assert(record.definition.timeout_ms==30000,'record does not carry the effective default deadline')
print('PASS: per-case deadlines reach the child and every record carries the effective deadline')
