-- Pure feedback-latency core. No I/O and no clock reads: callers pass spans
-- measured on one monotonic clock, policies and previous notification state.
local M={}
M.kinds={queue=true,setup=true,dependency=true,nix_eval=true,compile=true,execute=true,mixed=true,deliver=true,instrumentation=true,other=true}
M.reference_window=5
M.slowest_count=5
local severity={PASS=0,INCOMPLETE=1,FAIL=2,ERROR=3}
local function integer(n) return type(n)=='number' and n==n and n>=0 and n<math.huge and n%1==0 end

-- Elapsed time covered by possibly overlapping spans: sort by start and merge,
-- so parallel or nested spans are never counted twice (interval union).
function M.union(spans)
	local sorted={}
	for i,s in ipairs(spans) do sorted[i]=s end
	table.sort(sorted,function(a,b) return a.start_ns<b.start_ns end)
	local total,from,to=0,nil,nil
	for _,s in ipairs(sorted) do
		if to and s.start_ns<=to then
			if s.end_ns>to then to=s.end_ns end
		else
			if to then total=total+(to-from) end
			from,to=s.start_ns,s.end_ns
		end
	end
	if to then total=total+(to-from) end
	return total
end

local function worst(a,b) return severity[b]>severity[a] and b or a end

-- Classify one logical test job. Correctness and latency are independent
-- verdicts. Execution time is the union of fresh execute spans; it is exact
-- only when no execution hides in mixed, cached or unknown spans, so a lower
-- bound can still prove OVER_BUDGET but never WITHIN_BUDGET.
function M.evaluate(job,policy)
	assert(integer(policy.target_ns) and integer(policy.budget_ns) and policy.target_ns<=policy.budget_ns,'target must not exceed budget')
	local correctness,why={pass='PASS',fail='FAIL',incomplete='INCOMPLETE',error='ERROR'},{}
	local verdict=correctness[job.correctness]
	if not verdict then verdict='ERROR'; why[#why+1]='correctness not reported' end
	local t=job.tests
	if t then
		if (t.failed or 0)>0 then verdict=worst(verdict,'FAIL'); why[#why+1]=t.failed..' test(s) failed' end
		if (t.skipped or 0)>0 or (t.declared and t.executed and t.executed<t.declared) then verdict=worst(verdict,'INCOMPLETE'); why[#why+1]='inventory incomplete' end
	end
	local reasons,kinds,measured,fresh_execute={},{},{},{}
	local exact,clock_ok=true,true
	for _,p in ipairs(job.phases) do
		assert(M.kinds[p.kind],'unknown phase kind '..tostring(p.kind))
		local k=kinds[p.kind] or {count=0,unknown=0}
		kinds[p.kind]=k
		if p.spawn_error then verdict=worst(verdict,'ERROR'); why[#why+1]=p.name..' could not start' end
		if p.timed_out then verdict=worst(verdict,'ERROR'); why[#why+1]=p.name..' timed out' end
		if (p.exit_code and p.exit_code~=0) or (p.signal and p.signal~=0) then verdict=worst(verdict,'FAIL'); why[#why+1]=p.name..' exited unsuccessfully' end
		if p.status=='unknown' then
			k.unknown=k.unknown+1
			if p.kind=='execute' or p.kind=='mixed' then exact=false; reasons[#reasons+1]=p.name..' execution time unknown' end
		elseif not (integer(p.start_ns) and integer(p.end_ns) and p.end_ns>=p.start_ns) then
			clock_ok=false; reasons[#reasons+1]='clock error in '..tostring(p.name)
		else
			local d=p.end_ns-p.start_ns
			k.count=k.count+1; k.summed_ns=(k.summed_ns or 0)+d
			k.spans=k.spans or {}; k.spans[#k.spans+1]=p
			measured[#measured+1]=p
			if p.kind=='mixed' then exact=false; reasons[#reasons+1]=p.name..' is mixed compilation and execution'
			elseif p.kind=='execute' then
				if p.fresh==false then exact=false; reasons[#reasons+1]=p.name..' was cached, not executed'
				else fresh_execute[#fresh_execute+1]=p end
			end
		end
	end
	local r={correctness=verdict,correctness_reasons=why,kinds={},latency_reasons=reasons}
	for name,k in pairs(kinds) do
		r.kinds[name]={count=k.count,unknown=k.unknown,summed_ns=k.summed_ns,elapsed_ns=k.spans and M.union(k.spans) or nil}
	end
	if #measured>0 and clock_ok then
		local first,last=math.huge,-1
		for _,p in ipairs(measured) do first=math.min(first,p.start_ns); last=math.max(last,p.end_ns) end
		if integer(job.begin_ns) and job.begin_ns<=first then first=job.begin_ns end
		if integer(job.end_ns) and job.end_ns>=last then last=job.end_ns end
		r.total_ns=last-first
		r.attributed_ns=M.union(measured)
		r.unattributed_ns=r.total_ns-r.attributed_ns
	end
	r.execution_ns=M.union(fresh_execute)
	if #fresh_execute==0 then exact=false; if #reasons==0 then reasons[#reasons+1]='no execution measured' end end
	if job.source_changed then exact=false; reasons[#reasons+1]='source changed during the job' end
	if verdict=='INCOMPLETE' then exact=false; reasons[#reasons+1]='incomplete work cannot meet the budget' end
	if not clock_ok then r.latency='UNMEASURED'; exact=false
	elseif r.execution_ns>policy.budget_ns then r.latency='OVER_BUDGET'
	elseif not exact then r.latency='UNMEASURED'
	elseif r.execution_ns<=policy.target_ns then r.latency='WITHIN_TARGET'
	else r.latency='WITHIN_BUDGET' end
	if r.latency=='OVER_BUDGET' then r.over_ns=r.execution_ns-policy.budget_ns end
	r.execution_exact=exact
	r.comparable=exact and verdict=='PASS'
	r.target_ns,r.budget_ns=policy.target_ns,policy.budget_ns
	table.sort(measured,function(a,b)
		local da,db=a.end_ns-a.start_ns,b.end_ns-b.start_ns
		if da==db then return a.name<b.name end
		return da>db
	end)
	r.slowest={}
	for i=1,math.min(M.slowest_count,#measured) do
		local p=measured[i]; r.slowest[i]={name=p.name,kind=p.kind,duration_ns=p.end_ns-p.start_ns}
	end
	return r
end

-- Comparable historical execution time: median of the most recent comparable
-- records for one cohort and suite. Records arrive in chronological order.
function M.reference(history,cohort,suite)
	local values={}
	for _,r in ipairs(history) do
		if r.cohort==cohort and r.suite==suite and r.comparable==true and integer(r.execution_ns) then values[#values+1]=r.execution_ns end
	end
	if #values==0 then return nil end
	local recent={}
	for i=math.max(1,#values-M.reference_window+1),#values do recent[#recent+1]=values[i] end
	table.sort(recent)
	local n=#recent
	local median=n%2==1 and recent[(n+1)/2] or math.floor((recent[n/2]+recent[n/2+1])/2)
	return {execution_ns=median,count=n}
end

local function seconds(ns) return ('%.2fs'):format(ns/1e9) end
local function signed(ns) return (ns>=0 and '+' or '-')..seconds(math.abs(ns)) end

-- One-line status for humans and agent hooks: correctness, latency verdict,
-- execution against budget, separate compile/total time, reference delta
-- and the slowest measured phase.
function M.summary(r,o)
	local parts={o.project..' '..o.suite..' '..r.correctness..' '..r.latency}
	local exec='exec '..seconds(r.execution_ns)..(r.execution_exact and '' or ' (lower bound)')..' (budget '..seconds(r.budget_ns)
	if r.over_ns then exec=exec..', '..signed(r.over_ns)..' over' end
	parts[#parts+1]=exec..'; target '..seconds(r.target_ns)..')'
	for _,kind in ipairs({'compile','mixed'}) do
		local k=r.kinds[kind]
		if k then parts[#parts+1]=kind..' '..(k.elapsed_ns and seconds(k.elapsed_ns) or 'unknown')..(k.elapsed_ns and k.unknown>0 and ' + unknown' or '') end
	end
	if r.total_ns then parts[#parts+1]='total '..seconds(r.total_ns) end
	if o.reference and r.comparable then parts[#parts+1]='ref '..seconds(o.reference.execution_ns)..' ('..signed(r.execution_ns-o.reference.execution_ns)..')' end
	-- The budget concerns execution, so name the slowest span that holds it.
	local slow
	for _,q in ipairs(r.slowest) do if q.kind=='execute' or q.kind=='mixed' then slow=q; break end end
	slow=slow or r.slowest[1]
	if slow then parts[#parts+1]='slowest '..slow.name..' '..seconds(slow.duration_ns) end
	if #r.latency_reasons>0 and r.latency=='UNMEASURED' then parts[#parts+1]=r.latency_reasons[1] end
	return table.concat(parts,' · ')
end

-- Supporting lines for a detailed notice: reasons, per-kind time and the slowest phases.
function M.detail(r)
	local lines={}
	for _,w in ipairs(r.correctness_reasons) do lines[#lines+1]='correctness: '..w end
	for _,w in ipairs(r.latency_reasons) do lines[#lines+1]='latency: '..w end
	local names={}
	for name in pairs(r.kinds) do names[#names+1]=name end
	table.sort(names)
	for _,name in ipairs(names) do
		local k=r.kinds[name]
		lines[#lines+1]=('%s: %s elapsed, %s summed, %d span(s)%s'):format(name,k.elapsed_ns and seconds(k.elapsed_ns) or 'unknown',k.summed_ns and seconds(k.summed_ns) or 'unknown',k.count,k.unknown>0 and (', '..k.unknown..' unknown') or '')
	end
	if r.unattributed_ns then lines[#lines+1]='unattributed: '..seconds(r.unattributed_ns) end
	for i,p in ipairs(r.slowest) do lines[#lines+1]=('slowest %d: %s (%s) %s'):format(i,p.name,p.kind,seconds(p.duration_ns)) end
	return lines
end

-- Debounce decision for agent-visible notices: 'detail' for failures and for
-- first, renewed or worsening over-budget results; 'reminder' at most
-- max_reminders times, reminder_s apart, while over budget; otherwise 'brief'.
-- Returns a new state; display policy never changes records or exit status.
function M.notify(state,r,now_s,p)
	state=state or {}
	local s={over_since=state.over_since,last_notice_s=state.last_notice_s,reminders=state.reminders or 0,over_execution_ns=state.over_execution_ns}
	if r.correctness~='PASS' then s.last_notice_s=now_s; return 'detail',s end
	if r.latency~='OVER_BUDGET' then return 'brief',{reminders=0} end
	if not s.over_since or r.execution_ns>s.over_execution_ns*(1+p.worsen_fraction) then
		s.over_since=s.over_since or now_s; s.over_execution_ns=r.execution_ns
		s.last_notice_s=now_s; s.reminders=0
		return 'detail',s
	end
	if s.reminders<p.max_reminders and now_s-(s.last_notice_s or -math.huge)>=p.reminder_s then
		s.reminders=s.reminders+1; s.last_notice_s=now_s
		return 'reminder',s
	end
	return 'brief',s
end
return M
