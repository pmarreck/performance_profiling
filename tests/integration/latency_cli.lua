-- Real CLI lifecycle for test feedback latency: begin, span (stdio and exit
-- status pass through untouched), finish (verdicts, history record outside
-- the cg/mg namespace, no argv stored), failure propagation, source changes,
-- idempotent finish, enforcement and debounced notices.
package.path='./src/?.lua;'..package.path
local uv=require('luv')
local process=require('process')
local json=require('json')
local root=uv.cwd()
local tmp=os.getenv('TMPDIR') or '/tmp'
local history=assert(uv.fs_mkdtemp(tmp..'/latency history.XXXXXX'))
local fixture=assert(uv.fs_mkdtemp(tmp..'/latency fixture.XXXXXX'))
local scratch=assert(uv.fs_mkdtemp(tmp..'/latency scratch.XXXXXX'))
process.checked({'git','-C',fixture,'init','-q','-b','yolo'})
local function write(path,text) local f=assert(io.open(path,'wb')); assert(f:write(text)); assert(f:close()) end
local function slurp(path) local f=io.open(path,'rb'); if not f then return nil end; local s=f:read('*a'); f:close(); return s end
local function configure(latency)
	write(fixture..'/profiling.json',json.encode({schema='performance-project/v1',project='latency_fixture',history_url='file://'..history,latency=latency}))
	process.checked({'git','-C',fixture,'add','profiling.json'})
	process.checked({'git','-C',fixture,'-c','user.name=fixture','-c','user.email=fixture@example.invalid','commit','-qm','config','--allow-empty'})
end
configure(nil)
local function cli(args)
	local argv={'luajit',root..'/bin/performance-profile','latency'}
	for _,v in ipairs(args) do argv[#argv+1]=v end
	return process.run(argv,{cwd=fixture,env={TMPDIR=scratch},timeout_ms=60000})
end
local function finish(job,extra)
	local args={'finish','--config',fixture..'/profiling.json','--job',job,'--suite','test','--profile','ReleaseSafe','--concurrency','4'}
	for _,v in ipairs(extra or {}) do args[#args+1]=v end
	local r=cli(args)
	local ok,record=pcall(json.decode,r.stdout)
	return r,ok and record or nil
end
local function begin(job) local r=cli({'begin','--config',fixture..'/profiling.json','--job',job}); assert(r.rc==0,'begin: '..r.stderr); return r end
local function span(job,name,kind,command,extra)
	local args={'span','--job',job,'--name',name,'--kind',kind}
	for _,v in ipairs(extra or {}) do args[#args+1]=v end
	if command then args[#args+1]='--'; for _,v in ipairs(command) do args[#args+1]=v end end
	return cli(args)
end

-- A good job: output and status pass through; the record holds no argv.
begin('good')
local r=span('good','setup','setup',{'luajit','-e','io.write("prepared")'})
assert(r.rc==0 and r.stdout=='prepared' and r.stderr=='','span must pass stdout through untouched: '..r.stderr)
r=span('good','unit tests','execute',{'sh','-c','printf ok; printf diag >&2','sh','secret-argument'})
assert(r.rc==0 and r.stdout=='ok' and r.stderr=='diag','span must pass stderr through untouched: rc='..tostring(r.rc)..' out='..r.stdout..' err='..r.stderr)
r=span('good','zig-compile','compile',nil,{'--status','unknown'})
assert(r.rc==0,'unknown span: '..r.stderr)
local record
r,record=finish('good',{'--correctness','pass','--tests-declared','2','--tests-executed','2','--tests-skipped','0','--tests-failed','0'})
assert(r.rc==0,'good job: '..r.stderr)
assert(record and record.correctness=='PASS' and record.latency=='WITHIN_TARGET' and record.comparable==true,'good job verdicts')
assert(record.schema=='performance-latency/v1' and record.kind=='latency' and record.id=='good' and record.suite=='test')
assert(record.kinds.compile.unknown==1 and record.kinds.compile.elapsed_ns==nil,'unknown compile phase became a number')
assert(record.kinds.instrumentation and record.kinds.instrumentation.elapsed_ns>0,'instrumentation overhead not recorded')
assert(record.total_ns>=record.attributed_ns,'total smaller than attributed time')
assert(r.stderr:find('latency_fixture test PASS WITHIN_TARGET',1,true),'summary missing: '..r.stderr)
local stored=slurp(history..'/latency_fixture.latency--good.ndjson')
assert(stored,'latency record not written to its namespace')
assert(not stored:find('secret-argument',1,true) and not stored:find('printf',1,true),'argv leaked into the record')
assert(not stored:find(scratch,1,true),'environment-derived path leaked into the record')
-- The cg/mg history view never sees latency records.
local shared=require('store').open('file://'..history,'latency_fixture')
assert(#shared:read()==0 and #shared:read_latency()==1,'cg/mg reader saw latency records')
-- Finishing again is a no-op that reports the stored record.
local again
r,again=finish('good',{'--correctness','pass'})
assert(r.rc==0 and again and again.id=='good' and json.encode(again.kinds)==json.encode(record.kinds),'completed finish rerun was not a no-op')
-- A comparable predecessor yields a reference.
begin('second')
span('second','unit tests','execute',{'luajit','-e',''})
r,record=finish('second',{'--correctness','pass'})
assert(r.rc==0 and record.reference and record.reference.count==1,'no reference from comparable history')
assert(r.stderr:find('ref ',1,true),'summary lacks reference')

-- Exit status, signals and spawn failures propagate and fail correctness.
begin('failing')
r=span('failing','cli tests','execute',{'luajit','-e','os.exit(3)'})
assert(r.rc==3,'exit status not passed through: '..r.rc)
r=span('failing','killed','execute',{'sh','-c','kill -TERM $$'})
assert(r.rc==143,'signal not mapped to 128+n: '..tostring(r.rc))
r=span('failing','missing','execute',{'/nonexistent/performance-command'})
assert(r.rc==127,'spawn failure not 127')
r,record=finish('failing',{'--correctness','pass'})
assert(r.rc==1 and record.correctness=='ERROR' and record.comparable==false,'failing spans counted as a pass')

-- A declared skip exit passes through unchanged and makes the job INCOMPLETE.
begin('skipping')
r=span('skipping','cli-rar','execute',{'sh','-c','exit 77'},{'--skip-exit','77'})
assert(r.rc==77,'skip exit not passed through: '..tostring(r.rc))
r,record=finish('skipping',{'--correctness','pass'})
assert(r.rc==1 and record.correctness=='INCOMPLETE' and record.latency=='UNMEASURED','declared skip did not read INCOMPLETE')
local stored_skip=slurp(history..'/latency_fixture.latency--skipping.ndjson')
assert(stored_skip and stored_skip:find('"skip_exit":77',1,true) and stored_skip:find('"exit_code":77',1,true),'stored record lacks real exit and declared skip code')
for _,bad in ipairs({'0','256','-1','x','7.5'}) do
	r=span('skipping','bad','execute',{'true'},{'--skip-exit',bad})
	assert(r.rc==2,'invalid --skip-exit accepted: '..bad)
end

-- A stamped span covers time the recorder did not wrap, such as entering a
-- shell that then runs the suite: stamp outside, record it from inside.
local function stamp() local r=cli({'stamp'}); return r,r.stdout:match('^(%d+)\n$') end
local early_r,early=stamp()
assert(early_r.rc==0 and early,'stamp did not print a monotonic integer: '..early_r.stdout..early_r.stderr)
begin('stamped')
local _,since=stamp()
assert(tonumber(since)>=tonumber(early),'stamps went backwards')
span('stamped','unit tests','execute',{'luajit','-e',''})
r=span('stamped','shell entry','setup',nil,{'--since',since})
assert(r.rc==0 and r.stdout=='' and r.stderr=='','stamped span failed: '..r.stderr)
for _,bad in ipairs({{'--since','x'},{'--since','-1'},{'--since','1.5'},{'--since',''},{'--since',early},{'--since',tostring(tonumber(since)+1e15)},{'--since',since,'--skip-exit','77'},{'--since',since,'--status','unknown'}}) do
	r=span('stamped','bad','setup',nil,bad)
	assert(r.rc==2,'invalid stamped span accepted: '..table.concat(bad,' '))
end
r=span('stamped','bad','setup',{'true'},{'--since',since})
assert(r.rc==2,'stamped span with a command accepted')
r,record=finish('stamped',{'--correctness','pass'})
assert(r.rc==0 and record.correctness=='PASS' and record.latency=='WITHIN_TARGET','stamped job verdicts: '..r.stderr)
local entry
for _,p in ipairs(record.phases) do if p.name=='shell entry' and p.kind=='setup' then entry=p end end
assert(entry and entry.start_ns==tonumber(since) and entry.end_ns>entry.start_ns,'stamped span not recorded from its stamp')
assert(record.kinds.setup.elapsed_ns==entry.end_ns-entry.start_ns,'setup time not taken from the stamped span')
for _,p in ipairs(record.phases) do assert(p.end_ns>=p.start_ns,'negative phase '..p.name) end

-- An incomplete inventory is not a pass.
begin('partial')
span('partial','unit tests','execute',{'luajit','-e',''})
r,record=finish('partial',{'--correctness','pass','--tests-declared','5','--tests-executed','4','--tests-skipped','1'})
assert(r.rc==1 and record.correctness=='INCOMPLETE' and record.latency=='UNMEASURED','skipped tests counted as complete')

-- Source changes between begin and finish invalidate the latency claim.
begin('drift')
span('drift','unit tests','execute',{'luajit','-e',''})
write(fixture..'/new_source.lua','return 1\n')
r,record=finish('drift',{'--correctness','pass'})
assert(record.latency=='UNMEASURED' and record.comparable==false and record.source_changed==true,'changed source still comparable')
uv.fs_unlink(fixture..'/new_source.lua')

-- Unknown jobs and spans without begin are errors, not empty successes.
r=finish('never-begun',{'--correctness','pass'})
assert(r.rc~=0,'finishing an unknown job succeeded')
r=span('never-begun','x','execute',{'luajit','-e',''})
assert(r.rc~=0 and r.stderr:find('begin',1,true),'span without begin accepted')
r=span('good2','x','bogus',{'luajit','-e',''})
assert(r.rc==2,'invalid kind is a usage error')

-- Enforcement turns an overrun into a failing exit; without it, a warning.
configure({target_ms=1,budget_ms=1,enforce=false})
begin('slow-warn')
span('slow-warn','unit tests','execute',{'luajit','-e','require("luv").sleep(50)'})
r,record=finish('slow-warn',{'--correctness','pass'})
assert(r.rc==0 and record.latency=='OVER_BUDGET','pilot overrun must warn, not fail')
configure({target_ms=1,budget_ms=1,enforce=true})
begin('slow-enforced')
span('slow-enforced','unit tests','execute',{'luajit','-e','require("luv").sleep(50)'})
r,record=finish('slow-enforced',{'--correctness','pass'})
assert(r.rc==1 and record.latency=='OVER_BUDGET','enforced overrun did not fail')

-- Debounced notices: detail on the first overrun, brief on an unchanged repeat.
configure({target_ms=1,budget_ms=1,enforce=false})
local state=scratch..'/notify state.json'
begin('n1'); span('n1','unit tests','execute',{'luajit','-e','require("luv").sleep(50)'})
r=finish('n1',{'--correctness','pass','--notify-state',state})
local first_lines=select(2,r.stderr:gsub('\n',''))
assert(first_lines>1,'first overrun was not detailed: '..r.stderr)
begin('n2'); span('n2','unit tests','execute',{'luajit','-e','require("luv").sleep(50)'})
r=finish('n2',{'--correctness','pass','--notify-state',state})
assert(select(2,r.stderr:gsub('\n',''))==1,'unchanged repeat overrun was not brief: '..r.stderr)
assert(slurp(history..'/latency_fixture.latency--n2.ndjson'),'debounce suppressed the durable record')
print('PASS: latency CLI spans, verdicts, namespace, privacy, failures, drift, idempotency, enforcement and debounce')
