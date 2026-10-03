local core=require('core')
local config=require('config')
local M={}
-- Ports: records, write, measure, identity, snapshot, now, id.
function M.run(cfg,options,ports)
	local history=ports.records()
	local source,provenance=ports.snapshot()
	local output,pending={},{}
	for _,case in ipairs(cfg.cases) do
		if (not options.mode or case.mode==options.mode) and (not options.case or case.name==options.case) then
			local cohort,hardware=ports.identity(case)
			local existing
			if options.run_id then
				assert(config.name(options.run_id),'unsafe logical run ID')
				for _,r in ipairs(history) do if r.id==options.run_id..'-'..case.name then existing=r; break end end
			end
			if existing then
				assert(existing.source==source and existing.cohort==cohort and (not options.seed or existing.seed==options.seed),'logical run identity reused with changed inputs/source/hardware')
				output[#output+1]=existing
			else
			local epoch=core.epoch(history,case.name,cohort)
			local baseline=core.baseline(history,case.name,cohort,epoch,case.policy)
			local result=core.run(case,baseline,function() return ports.measure(case,options.seed or '1') end)
			result.schema='performance-history/v1'; result.kind='observation'
			result.project=cfg.project; result.id=(options.run_id or ports.id())..'-'..case.name
			result.datetime_utc=ports.now(); result.case=case.name; result.mode=case.mode
			result.metric=case.metric; result.cohort=cohort; result.hardware=hardware
			result.epoch=epoch; result.policy=case.policy; result.seed=options.seed or '1'
			result.source=source; result.provenance=provenance
			result.command=config.command(case,result.seed); result.definition=case
			pending[#pending+1]=result
			output[#output+1]=result
			end
		end
	end
	assert(#output>0,'no matching profiling cases')
	-- One snapshot after the last case covers the whole run: a change anywhere
	-- in it invalidates every case measured in it. Records are written only
	-- after that check.
	if #pending>0 then
		local after=ports.snapshot()
		for _,result in ipairs(pending) do
			result.source_after=after
			if after~=source then result.verdict='INVALID'; result.reason='source or executable changed during the run'; result.eligible=false; result.selected=nil end
			ports.write(result)
		end
	end
	return output
end
function M.accept(cfg,id,reason,ports)
	assert(type(reason)=='string' and reason:match('%S'),'approval reason required')
	local history=ports.records(); local target
	for _,r in ipairs(history) do if r.id==id then target=r; break end end
	assert(target and target.kind=='observation','unknown observation ID')
	assert(target.source==target.source_after,'cannot accept changing source')
	local selected=target.selected or target.candidate
	assert(selected and selected.approvable==true,'correctness, shape, leak or noisy measurements cannot be accepted')
	local epoch=core.epoch(history,target.case,target.cohort)
	if epoch~='root' then
		for _,r in ipairs(history) do if r.id==epoch and r.target==id then return r end end
	end
	assert(target.epoch==epoch,'observation was measured against an obsolete epoch; remeasure')
	local r={schema='performance-history/v1',kind='approval',project=cfg.project,id=ports.id()..'-approve',
		datetime_utc=ports.now(),case=target.case,cohort=target.cohort,parent_epoch=epoch,target=id,
		reason=reason,selected=selected,policy=target.policy,source=target.source}
	ports.write(r)
	return r
end
return M
