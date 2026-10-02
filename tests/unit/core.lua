package.path = './src/?.lua;' .. package.path
local core = require('core')
local tests = 0
local function check(name, actual, expected)
	assert(actual == expected, name .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
	tests = tests + 1
end
local policy = {percent=10, sigma=3, minimum=3, window=20, max_cv=0.3, absolute_floor=0}
local case = {name='linear', mode='cg', metric='operations', sizes={10,20,40,80}, bounds={1.8,2.2}, policy=policy}
local function measurement(values)
	local rows = {}
	for i, size in ipairs(case.sizes) do rows[i] = {size=size, samples={operations={values[i], values[i], values[i]}, cpu_ns={values[i], values[i], values[i]}, wall_ns={values[i], values[i], values[i]}}} end
	return {schema='performance-measurement/v1', correct=true, build_mode='optimized', rows=rows}
end
local function row(id, values)
	return {schema='performance-history/v1', kind='observation', id=id, project='pilot', case='linear', cohort='cpu1', epoch='e1', eligible=true, verdict='PASS', selected={ratios=values}}
end
local records = {row('a',{2,2,2}),row('b',{2,2,2}),row('c',{2,2,2})}
local baseline = core.baseline(records, 'linear', 'cpu1', 'e1', policy)
check('frozen baseline count', baseline.count, 3)
check('unequal historical sweep lengths rejected',pcall(core.baseline,{row('a',{2,2,2}),row('b',{2,2})},'linear','cpu1','e1',policy),false)
check('nonpositive historical ratio rejected',pcall(core.baseline,{row('a',{2,0,2})},'linear','cpu1','e1',policy),false)
check('linear pass', core.evaluate(case, measurement({10,20,40,80}), baseline).verdict, 'PASS')
case.bounds = {1,5}
check('12.5 percent increase fails before append', core.evaluate(case, measurement({10,22.5,50.625,113.90625}), baseline).verdict, 'FAIL')
check('unexpected reduction fails', core.evaluate(case, measurement({10,17.5,30.625,53.59375}), baseline).verdict, 'FAIL')
records[1].diagnostics = {row('evil',{200,200,200})}
records[#records+1] = {schema='performance-history/v1', kind='observation', id='failed', case='linear', cohort='cpu1', epoch='e1', eligible=false, selected={ratios={900,900,900}}}
check('nested and failed rows never count', core.baseline(records,'linear','cpu1','e1',policy).count, 3)
check('diagnostics never shift baseline', core.baseline(records,'linear','cpu1','e1',policy).means[1], 2)
local attempts = 0
case.metric = 'cpu_ns'
local result = core.run(case, baseline, function()
	attempts=attempts+1
	return measurement(attempts == 1 and {10,25,62.5,156.25} or {10,20,40,80})
end)
check('retry selected pass', result.verdict, 'PASS_ON_RETRY')
check('exactly one retry', attempts, 2)
check('selected passing ratio', result.selected.ratios[1], 2)
check('failed attempt remains diagnostic', result.diagnostics[1].ratios[1], 2.5)
check('normal retry does not approve epoch', result.epoch, nil)
attempts=0
result = core.run(case, baseline, function() attempts=attempts+1; return measurement({10,25,62.5,156.25}) end)
check('two failures fail',result.verdict,'FAIL')
check('two failures not eligible',result.eligible,false)
check('two failures have no selected baseline',result.selected,nil)
attempts=0
result = core.run(case, baseline, function() attempts=attempts+1; local m=measurement({10,20,40,80}); m.correct=false; return m end)
check('correctness fail',result.verdict,'INVALID')
check('no correctness retry',attempts,1)
check('new hardware unbaselined',core.evaluate(case,measurement({10,20,40,80}),core.baseline({},'linear','cpu2','root',policy)).verdict,'UNBASELINED')
local paths={'src/a.c','src/a.zig','src/a.lua','a.md','a.toml','a.ndjson','a.txt','.env','src/.hidden/b.c','a dir/a.c'}
local eligible={true,true,true,false,false,false,false,false,false,true}
for i,path in ipairs(paths) do check('code classifier '..path,core.code_path(path),eligible[i]) end
local absolute={name='fixed',mode='bm',metric='cpu_ns',comparison='absolute',sizes={10},bounds={1,100},policy=policy}
local absolute_history={row('a',{20}),row('b',{20}),row('c',{20})}
local ab=core.baseline(absolute_history,'linear','cpu1','e1',policy)
local am={schema='performance-measurement/v1',correct=true,build_mode='optimized',rows={{size=10,samples={cpu_ns={25,25,25}}}}}
check('fixed-workload absolute drift',core.evaluate(absolute,am,ab).verdict,'FAIL')
case.metric='operations'; case.bounds={1.8,2.2}
check('crossover must not hide behind median',core.evaluate(case,measurement({10,20,80,160}),baseline).verdict,'SHAPE_FAIL')
local memory_case={mode='mg',metric='peak_bytes',sizes={10,20,40,80},bounds={1.8,2.2},policy=policy}
local mm=measurement({10,20,40,80}); mm.allocator_coverage='fixture malloc'
for _,r in ipairs(mm.rows) do r.samples.peak_bytes=r.samples.operations; r.residual_bytes={0,0,1} end
check('leak fails independent of history',core.evaluate(memory_case,mm,baseline).verdict,'LEAK')
mm.rows[1].residual_bytes={0,0,0,0}
check('cleanup sample mismatch invalid',core.evaluate(memory_case,mm,baseline).verdict,'INVALID')
local varying={row('a',{1.9,1.9,1.9}),row('b',{2,2,2}),row('c',{2.1,2.1,2.1})}
case.bounds={1,5}
local vb=core.baseline(varying,'linear','cpu1','e1',policy)
check('known mean',vb.means[1],2)
assert(math.abs(vb.deviations[1]-0.1)<1e-10)
check('SD band permits practically surprising value',core.evaluate(case,measurement({10,22.5,50.625,113.90625}),vb).verdict,'PASS')
case.metric='cpu_ns'
local noisy=measurement({10,20,40,80}); noisy.rows[1].samples.cpu_ns={1,10,19}
check('unresolved noise not green',core.run(case,baseline,function() return noisy end).verdict,'INCONCLUSIVE')
print('PASS: '..tests..' functional assertions')
