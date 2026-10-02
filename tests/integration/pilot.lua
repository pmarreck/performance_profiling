package.path='./src/?.lua;'..package.path
local uv=require('luv')
local process=require('process')
local json=require('json')
local root=uv.cwd()
local dir=assert(uv.fs_mkdtemp((os.getenv('TMPDIR') or '/tmp')..'/profiling CLI.XXXXXX'))
local url='file://'..dir
local function command(args)
	local argv={'luajit',root..'/bin/performance-profile'}
	for _,v in ipairs(args) do argv[#argv+1]=v end
	return process.run(argv,{cwd=root})
end
for _,mode in ipairs({'cg','mg'}) do
	local r=command({'run','--mode',mode,'--history-url',url,'--seed','15'})
	assert(r.rc==3,r.stderr)
	local event=json.decode(r.stdout)[1]
	assert(event.verdict=='UNBASELINED' and not event.eligible)
	local approved=command({'accept','--history-url',url,'--run',event.id,'--reason','independent arithmetic/allocation oracle verified'})
	assert(approved.rc==0,approved.stderr)
	local again=command({'run','--mode',mode,'--history-url',url,'--seed','15'})
	assert(again.rc==0,again.stderr)
	local pass=json.decode(again.stdout)[1]
	assert(pass.eligible and pass.verdict=='PASS')
	for _,ratio in ipairs(pass.selected.ratios) do assert(ratio==2) end
	assert(pass.provenance.git.head:match('^[a-f0-9]+$'))
	assert(pass.datetime_utc:match('%.%d%d%dZ$'))
	assert(pass.command_encoding and pass.provenance.uname_a)
end
local history=command({'history','--history-url',url})
assert(history.rc==0 and #json.decode(history.stdout)==6)
local denial=command({'run','--mode','cg','--history-url','file://'..dir..'/missing'})
assert(denial.rc~=0 and #denial.stdout==0)
-- Witness the real arithmetic oracle rejecting skipped work, not just a false flag.
local source=assert(io.open('tests/benchmark/pilot.lua','rb'))
local script=assert(source:read('*a')); assert(source:close())
local altered,count=script:gsub('sum=sum%+tonumber%(data%[i%]%)','sum=sum+0')
assert(count==1,'mutation did not change exactly one kernel statement')
local mutant=dir..'/skipped work.lua'
local file=assert(io.open(mutant,'wb')); assert(file:write(altered)); assert(file:close())
local skipped=process.run({'luajit',mutant,'vector_sum','4096,8192','15'})
assert(skipped.rc~=0 and skipped.stderr:find('independent result check failed',1,true),'work oracle accepted a skipped kernel')
print('PASS: real workload complexity/memory gates, approval, history and provenance')
