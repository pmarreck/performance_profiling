-- Pure feedback-latency core: interval unions, independent correctness and
-- latency verdicts, historical references, summaries and the debounce policy.
package.path='./src/?.lua;'..package.path
local latency=require('latency')
local S=1000000000
local MS=1000000
local policy={target_ns=1*S,budget_ns=5*S}
local function span(name,kind,a,b,extra)
	local p={name=name,kind=kind,status='measured',start_ns=a,end_ns=b,exit_code=0}
	for k,v in pairs(extra or {}) do p[k]=v end
	return p
end
local function job(phases,extra)
	local j={phases=phases,correctness='pass',tests={declared=10,executed=10,skipped=0,failed=0}}
	for k,v in pairs(extra or {}) do j[k]=v end
	return j
end
local function has(list,text)
	for _,v in ipairs(list) do if v:find(text,1,true) then return true end end
	return false
end

-- Interval union never counts overlap twice.
assert(latency.union({})==0)
assert(latency.union({{start_ns=0,end_ns=10}})==10)
assert(latency.union({{start_ns=0,end_ns=10},{start_ns=5,end_ns=15}})==15,'overlap double-counted')
assert(latency.union({{start_ns=20,end_ns=30},{start_ns=0,end_ns=10}})==20,'disjoint spans')
assert(latency.union({{start_ns=0,end_ns=100},{start_ns=10,end_ns=20},{start_ns=30,end_ns=40}})==100,'nested spans')
assert(latency.union({{start_ns=0,end_ns=10},{start_ns=10,end_ns=20}})==20,'touching spans')

-- Exact budget edges: <= target, <= budget, > budget.
for _,c in ipairs({{1*S,'WITHIN_TARGET'},{1*S+1,'WITHIN_BUDGET'},{5*S,'WITHIN_BUDGET'},{5*S+1,'OVER_BUDGET'},{0,'WITHIN_TARGET'}}) do
	local r=latency.evaluate(job({span('t','execute',0,c[1])}),policy)
	assert(r.latency==c[2],('edge %d gave %s, wanted %s'):format(c[1],r.latency,c[2]))
	assert(r.correctness=='PASS' and r.execution_exact and r.comparable)
end

-- Parallel execution spans are a union for elapsed, a sum for resource use.
do
	local r=latency.evaluate(job({span('a','execute',0,3*S),span('b','execute',1*S,4*S)}),policy)
	assert(r.execution_ns==4*S,'parallel execute spans double-counted')
	assert(r.kinds.execute.elapsed_ns==4*S and r.kinds.execute.summed_ns==6*S and r.kinds.execute.count==2)
	assert(r.latency=='WITHIN_BUDGET')
end

-- Compile-heavy job within budget: compilation is excluded from the verdict but reported.
do
	local r=latency.evaluate(job({span('build','compile',0,40*S),span('tests','execute',40*S,40*S+800*MS)}),policy)
	assert(r.latency=='WITHIN_TARGET','compilation counted against the execution budget')
	assert(r.kinds.compile.elapsed_ns==40*S and r.total_ns==40*S+800*MS)
end

-- Execution-heavy job over budget.
do
	local r=latency.evaluate(job({span('build','compile',0,1*S),span('tests','execute',1*S,8*S)}),policy)
	assert(r.latency=='OVER_BUDGET' and r.execution_ns==7*S and r.over_ns==2*S)
end

-- Gaps are unattributed, never relabeled; begin/end extend the total.
do
	local r=latency.evaluate(job({span('a','setup',1*S,2*S),span('b','execute',4*S,5*S)},{begin_ns=0,end_ns=6*S}),policy)
	assert(r.total_ns==6*S and r.attributed_ns==2*S and r.unattributed_ns==4*S,'gap accounting')
	assert(r.kinds.compile==nil,'unattributed time became compilation')
end

-- Mixed build+test spans make execution a lower bound: over budget stands,
-- within budget cannot be claimed.
do
	local r=latency.evaluate(job({span('zig','mixed',0,3*S),span('cli','execute',3*S,3*S+500*MS)}),policy)
	assert(r.latency=='UNMEASURED' and not r.execution_exact and not r.comparable,'mixed execution claimed within budget')
	assert(has(r.latency_reasons,'mixed'))
	r=latency.evaluate(job({span('zig','mixed',0,3*S),span('cli','execute',3*S,9*S)}),policy)
	assert(r.latency=='OVER_BUDGET' and not r.comparable,'lower bound over budget must still be reported')
	r=latency.evaluate(job({span('zig','mixed',0,3*S)}),policy)
	assert(r.latency=='UNMEASURED' and r.execution_ns==0)
end

-- Cached (not freshly executed) checks never count as fresh execution.
do
	local r=latency.evaluate(job({span('zig','execute',0,100*MS,{fresh=false,cache='hit'})}),policy)
	assert(r.latency=='UNMEASURED' and r.execution_ns==0 and has(r.latency_reasons,'cached'))
end

-- Unknown phases stay unknown, never zero.
do
	local r=latency.evaluate(job({span('cli','execute',0,500*MS),{name='zig-compile',kind='compile',status='unknown'}}),policy)
	assert(r.latency=='WITHIN_TARGET','an unknown compile phase must not block an exact execution verdict')
	assert(r.kinds.compile.elapsed_ns==nil and r.kinds.compile.unknown==1,'unknown compile phase became a number')
	r=latency.evaluate(job({span('cli','execute',0,500*MS),{name='zig-tests',kind='execute',status='unknown'}}),policy)
	assert(r.latency=='UNMEASURED' and has(r.latency_reasons,'unknown'))
	r=latency.evaluate(job({}),policy)
	assert(r.latency=='UNMEASURED' and r.total_ns==nil,'empty job produced a duration')
end

-- Correctness is independent and propagates from every source.
do
	local r=latency.evaluate(job({span('t','execute',0,1)},{correctness='fail'}),policy)
	assert(r.correctness=='FAIL' and r.latency=='WITHIN_TARGET' and not r.comparable,'failed run comparable or latency hidden')
	r=latency.evaluate(job({span('t','execute',0,1,{exit_code=1})}),policy)
	assert(r.correctness=='FAIL','nonzero span exit status ignored')
	r=latency.evaluate(job({span('t','execute',0,1,{signal=9})}),policy)
	assert(r.correctness=='FAIL','signaled span ignored')
	r=latency.evaluate(job({span('t','execute',0,1,{spawn_error='ENOENT'})}),policy)
	assert(r.correctness=='ERROR','spawn failure ignored')
	r=latency.evaluate(job({span('t','execute',0,1,{timed_out=true})}),policy)
	assert(r.correctness=='ERROR','timeout ignored')
	r=latency.evaluate(job({span('t','execute',0,1)},{tests={declared=10,executed=9,skipped=1,failed=0}}),policy)
	assert(r.correctness=='INCOMPLETE' and r.latency=='UNMEASURED' and not r.comparable,'skipped work counted as complete')
	r=latency.evaluate(job({span('t','execute',0,9*S)},{tests={declared=10,executed=9,skipped=1,failed=0}}),policy)
	assert(r.latency=='OVER_BUDGET','incomplete work that is already over budget must say so')
	r=latency.evaluate(job({span('t','execute',0,1)},{tests={declared=10,executed=10,skipped=0,failed=2}}),policy)
	assert(r.correctness=='FAIL','failed test count ignored')
	local unreported=job({span('t','execute',0,1)}); unreported.correctness=nil
	r=latency.evaluate(unreported,policy)
	assert(r.correctness=='ERROR','missing correctness treated as success')
	local untallied=job({span('t','execute',0,1)},{correctness='incomplete'}); untallied.tests=nil
	r=latency.evaluate(untallied,policy)
	assert(r.correctness=='INCOMPLETE')
	r=latency.evaluate(job({span('t','execute',0,1,{exit_code=1}),span('u','execute',1,2,{spawn_error='x'})},{correctness='incomplete'}),policy)
	assert(r.correctness=='ERROR','worst correctness outcome must win')
end

-- A span may declare one skip exit code (automake's 77). Classified over a set
-- of outcomes: only that exact code, unsignaled, is a skip (INCOMPLETE); any
-- other failure stays FAIL, and the real exit status is kept, not rewritten.
do
	local cases={
		{{exit_code=77,skip_exit=77},'INCOMPLETE',true},
		{{exit_code=0,skip_exit=77},'PASS',false},
		{{exit_code=1,skip_exit=77},'FAIL',false},
		{{exit_code=78,skip_exit=77},'FAIL',false},
		{{exit_code=77},'FAIL',false},
		{{exit_code=77,skip_exit=77,signal=9},'FAIL',false},
		{{exit_code=127,skip_exit=77,spawn_error='ENOENT'},'ERROR',false},
	}
	for i,c in ipairs(cases) do
		local r=latency.evaluate(job({span('cli-rar','execute',0,1,c[1])}),policy)
		assert(r.correctness==c[2],('skip case %d gave %s, wanted %s'):format(i,r.correctness,c[2]))
		assert(has(r.correctness_reasons,'cli-rar skipped')==c[3],('skip case %d reason mismatch'):format(i))
		if c[2]~='PASS' then assert(not r.comparable,'skipped or failed span comparable') end
	end
	local r=latency.evaluate(job({span('cli-rar','execute',0,1,{exit_code=77,skip_exit=77}),span('cli-x','execute',1,2,{exit_code=1})}),policy)
	assert(r.correctness=='FAIL','a skip must not mask a real failure')
end

-- Bad clocks and changed sources invalidate latency, not silently.
do
	local r=latency.evaluate(job({span('t','execute',5,4)}),policy)
	assert(r.latency=='UNMEASURED' and has(r.latency_reasons,'clock') and not r.comparable)
	r=latency.evaluate(job({span('t','execute',-1,4)}),policy)
	assert(r.latency=='UNMEASURED' and has(r.latency_reasons,'clock'))
	r=latency.evaluate(job({span('t','execute',0,1.5)}),policy)
	assert(r.latency=='UNMEASURED' and has(r.latency_reasons,'clock'))
	r=latency.evaluate(job({span('t','execute',0,1)},{source_changed=true}),policy)
	assert(r.latency=='UNMEASURED' and has(r.latency_reasons,'source') and not r.comparable)
	assert(not pcall(latency.evaluate,job({span('t','bogus',0,1)}),policy),'unknown phase kind accepted')
	assert(not pcall(latency.evaluate,job({span('t','execute',0,1)}),{target_ns=6*S,budget_ns=5*S}),'target above budget accepted')
end

-- The slowest list is deterministic and bounded.
do
	local phases={}
	for i=1,8 do phases[i]=span('p'..i,'execute',0,i*MS) end
	phases[9]=span('q','execute',0,8*MS)
	local r=latency.evaluate(job(phases),policy)
	assert(#r.slowest==5 and r.slowest[1].name=='p8' and r.slowest[2].name=='q' and r.slowest[5].name=='p5','slowest ordering')
end

-- Reference: median of recent comparable records in the same cohort/suite only.
do
	local function rec(ns,extra)
		local r={kind='latency',cohort='c',suite='test',comparable=true,execution_ns=ns,datetime_utc='2026-10-20T00:00:00.000Z'}
		for k,v in pairs(extra or {}) do r[k]=v end
		return r
	end
	assert(latency.reference({},'c','test')==nil)
	assert(latency.reference({rec(3),rec(1),rec(2)},'c','test').execution_ns==2)
	local ref=latency.reference({rec(5),rec(100,{comparable=false}),rec(7,{cohort='other'}),rec(9,{suite='quick'})},'c','test')
	assert(ref.execution_ns==5 and ref.count==1,'non-comparable or foreign records used as reference')
	local many={}
	for i=1,30 do many[i]=rec(i) end
	ref=latency.reference(many,'c','test')
	assert(ref.count==latency.reference_window and ref.execution_ns==28,'reference must use only the most recent window')
end

-- Summaries carry the facts an agent needs; unknown is spelled out.
do
	local r=latency.evaluate(job({span('build','compile',0,40*S),span('cli-tests','execute',40*S,47*S+310*MS)},{begin_ns=0,end_ns=48*S}),policy)
	local line=latency.summary(r,{project='validate',suite='test',reference={execution_ns=6*S+800*MS,count=3}})
	assert(not line:find('\n'),'summary must be one line')
	for _,want in ipairs({'validate','test','PASS','OVER_BUDGET','7.31s','5.00s','+2.31s','compile 40.00s','total 48.00s','ref 6.80s','+0.51s','cli-tests'}) do
		assert(line:find(want,1,true),'summary lacks '..want..': '..line)
	end
	r=latency.evaluate(job({span('zig','mixed',0,3*S)}),policy)
	line=latency.summary(r,{project='validate',suite='test'})
	assert(line:find('UNMEASURED',1,true) and line:find('mixed',1,true) and not line:find('ref ',1,true),line)
	local detail=latency.detail(r)
	assert(type(detail)=='table' and #detail>0 and has(detail,'zig'),'detail lacks phases')
end

-- Debounce: brief when fine, detail on first/new/worsening over-budget or
-- failures, bounded reminders otherwise. Pure: state in, state out.
do
	local np={reminder_s=3600,max_reminders=2,worsen_fraction=0.10}
	local ok=latency.evaluate(job({span('t','execute',0,500*MS)}),policy)
	local over=latency.evaluate(job({span('t','execute',0,6*S)}),policy)
	local worse=latency.evaluate(job({span('t','execute',0,7*S)}),policy)
	local fail=latency.evaluate(job({span('t','execute',0,1)},{correctness='fail'}),policy)
	local d,s=latency.notify(nil,ok,1000,np)
	assert(d=='brief','normal result not brief')
	d,s=latency.notify(s,over,1010,np); assert(d=='detail','first over-budget not detailed')
	d,s=latency.notify(s,over,1020,np); assert(d=='brief','repeat over-budget within interval should be brief')
	d,s=latency.notify(s,worse,1030,np); assert(d=='detail','worsening over-budget not detailed')
	d,s=latency.notify(s,worse,1040,np); assert(d=='brief')
	d,s=latency.notify(s,worse,1030+3600,np); assert(d=='reminder','reminder not issued after interval')
	d,s=latency.notify(s,worse,1030+7200,np); assert(d=='reminder')
	d,s=latency.notify(s,worse,1030+10800,np); assert(d=='brief','reminders must be bounded')
	d,s=latency.notify(s,ok,20000,np); assert(d=='brief')
	d,s=latency.notify(s,over,20010,np); assert(d=='detail','returning to over budget is new')
	d,s=latency.notify(s,fail,20020,np); assert(d=='detail','failure not detailed')
	d,s=latency.notify(s,fail,20030,np); assert(d=='detail','failures are never debounced')
	local before=latency.notify
	local frozen={over_since=1,last_notice_s=1,reminders=0,over_execution_ns=6*S}
	assert(latency.notify(frozen,over,5000,np)=="reminder")
	assert(frozen.reminders==0 and frozen.last_notice_s==1,'notify mutated the caller state')
	assert(before==latency.notify)
end
print('PASS: latency unions, budget edges, attribution, correctness, references, summaries and debounce')
