-- Pure measurement policy. No clocks, files, environment or process state.
local M = {}
local function finite(n) return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge end
local function stats(values)
	local mean, squared = 0, 0
	for _,v in ipairs(values) do assert(finite(v), 'non-finite measurement'); mean=mean+v end
	mean=mean/#values
	for _,v in ipairs(values) do squared=squared+(v-mean)^2 end
	return mean, #values>1 and math.sqrt(squared/(#values-1)) or 0
end
M.stats = stats
function M.code_path(path)
	if path:match('^%.') or path:match('/%.') then return false end
	local ext=path:match('%.([^./]+)$')
	return not (ext=='md' or ext=='ndjson' or ext=='toml' or ext=='txt')
end
function M.baseline(records, name, cohort, epoch, policy)
	local selected, approved = {}, false
	for _,r in ipairs(records) do
		assert(r.schema=='performance-history/v1','unsupported history schema')
		if r.kind=='approval' and r.id==epoch and r.case==name and r.cohort==cohort then
			assert(r.selected and (r.selected.values or r.selected.ratios),'approval missing anchor')
			selected[#selected+1]={id=r.id, selected=r.selected}; approved=true
		elseif r.kind=='observation' and r.case==name and r.cohort==cohort and r.epoch==epoch and r.eligible==true then
			assert((r.verdict=='PASS' or r.verdict=='PASS_ON_RETRY') and r.selected and r.selected.ratios,'invalid eligible row')
			selected[#selected+1]=r
		end
	end
	-- Caller supplies chronological history; ignore nested diagnostics entirely.
	local refs, cols, dimensions = {}, {}, nil
	for i=math.max(1,#selected-policy.window+1),#selected do
		refs[#refs+1]=selected[i].id
		local values=selected[i].selected.values or selected[i].selected.ratios
		assert(type(values)=='table' and #values>0,'empty historical measurement')
		dimensions=dimensions or #values
		assert(#values==dimensions,'historical sweep dimensions differ')
		for j,v in ipairs(values) do assert(finite(v) and v>0,'positive finite historical values required'); cols[j]=cols[j] or {}; cols[j][#cols[j]+1]=v end
	end
	local means, deviations = {}, {}
	for i,col in ipairs(cols) do means[i],deviations[i]=stats(col) end
	return {count=#refs, references=refs, means=means, deviations=deviations, approved=approved, epoch=epoch}
end
local function invalid(reason) return {verdict='INVALID', reason=reason, retryable=false} end
function M.evaluate(case, m, baseline)
	if type(m)~='table' or m.schema~='performance-measurement/v1' then return invalid('unsupported measurement schema') end
	if m.correct~=true then return invalid('work correctness not established') end
	if m.build_mode=='Debug' or m.build_mode=='debug' or type(m.build_mode)~='string' then return invalid('optimized build required') end
	if type(m.rows)~='table' or #m.rows~=#case.sizes then return invalid('incomplete size sweep') end
	local timing = case.metric=='cpu_ns' or case.metric=='wall_ns' or case.metric=='startup_ns'
	local means, ratios, noise = {}, {}, false
	for i,row in ipairs(m.rows) do
		if row.size~=case.sizes[i] then return invalid('input size mismatch') end
		local samples = row.samples and row.samples[case.metric]
		if type(samples)~='table' or #samples<3 then return invalid('at least three samples required') end
		for _,v in ipairs(samples) do if not finite(v) or v<=0 then return invalid('positive finite samples required') end end
		local mean,sd = stats(samples); means[i]=mean
		if timing and sd/mean>case.policy.max_cv then noise=true end
		if case.mode=='mg' then
			if type(row.residual_bytes)~='table' or #row.residual_bytes~=#samples or type(m.allocator_coverage)~='string' or #m.allocator_coverage==0 then return invalid('memory lifecycle/coverage missing') end
			for _,v in ipairs(row.residual_bytes) do
				if not finite(v) or v<0 then return invalid('invalid memory residual') end
				if v>(case.residual_allowance or 0) then return {verdict='LEAK',reason='residual live bytes exceed allowance',retryable=false} end
			end
		end
	end
	for i=2,#means do ratios[i-1]=means[i]/means[i-1] end
	local values=case.comparison=='absolute' and means or ratios
	local r={ratios=ratios,values=values,comparison=case.comparison or 'growth',raw=m,retryable=timing,comparisons={}}
	-- Noisy timing means support no conclusion about shape either: report the
	-- noise (retryable) before judging declared bounds from those means.
	if noise then r.verdict='INCONCLUSIVE'; r.reason='sample variation exceeds policy'; return r end
	for _,v in ipairs(values) do
		if v<case.bounds[1] or v>case.bounds[2] then r.verdict='SHAPE_FAIL'; r.reason='declared shape violated'; r.retryable=false; return r end
	end
	r.approvable=true
	if baseline.count==0 then r.verdict='UNBASELINED'; r.reason='no accepted cohort baseline'; r.retryable=false; return r end
	if baseline.count<case.policy.minimum and not baseline.approved then r.verdict='INCONCLUSIVE'; r.reason='insufficient accepted history'; r.retryable=false; return r end
	if #baseline.means~=#values then return invalid('baseline sweep mismatch') end
	local failed=false
	for i,value in ipairs(values) do
		local mean,sd=baseline.means[i],baseline.deviations[i]
		if baseline.count>=case.policy.minimum and mean>0 and sd/mean>case.policy.max_cv then
			r.verdict='INCONCLUSIVE'; r.reason='historical variation exceeds policy'; r.retryable=false; return r
		end
		local statistical=baseline.count>=case.policy.minimum and case.policy.sigma*sd or 0
		local band=math.max(mean*case.policy.percent/100, statistical, case.policy.absolute_floor)
		r.comparisons[i]={mean=mean,sd=sd,lower=mean-band,upper=mean+band,value=value,count=baseline.count,method=baseline.count<case.policy.minimum and 'approved-anchor-percent' or 'hybrid-percent-sd'}
		if value<mean-band or value>mean+band then failed=true end
	end
	r.verdict=failed and 'FAIL' or 'PASS'
	r.reason=failed and 'two-sided historical change' or 'within declared and historical bounds'
	return r
end
function M.run(case, baseline, measure)
	local attempts, chosen = {}, nil
	for i=1,2 do
		local measurement=measure()
		local result=M.evaluate(case,measurement,baseline)
		result.raw=measurement
		attempts[i]=result
		if result.verdict=='PASS' then chosen=result; break end
		if not result.retryable then break end
	end
	local last=attempts[#attempts]
	return {verdict=chosen and (#attempts==2 and 'PASS_ON_RETRY' or 'PASS') or last.verdict,
		eligible=chosen~=nil, selected=chosen, diagnostics=#attempts==2 and {attempts[1]} or {},
		candidate=not chosen and last or nil, reason=last.reason, attempts=#attempts, baseline=baseline}
end
function M.epoch(records,name,cohort)
	local epoch='root'
	while true do
		local next_id
		for _,r in ipairs(records) do
			if r.kind=='approval' and r.case==name and r.cohort==cohort and r.parent_epoch==epoch then
				assert(not next_id,'conflicting approvals; resolve explicitly')
				next_id=r.id
			end
		end
		if not next_id then return epoch end
		epoch=next_id
	end
end
-- Index of the median of an odd number of process measurements, ordered by
-- the sum of each one's per-size mean of `metric` (ties by process order).
-- Several fresh processes per case keep one process's JIT mode from deciding
-- a verdict; every process stays in the record.
function M.median_process(measurements, metric)
	assert(#measurements%2==1,'an odd number of processes is required')
	local order={}
	for i,m in ipairs(measurements) do
		local total=0
		for _,row in ipairs(m.rows) do total=total+stats(row.samples[metric]) end
		order[i]={i=i,total=total}
	end
	table.sort(order,function(x,y) if x.total~=y.total then return x.total<y.total end return x.i<y.i end)
	return order[(#order+1)/2].i
end
return M
