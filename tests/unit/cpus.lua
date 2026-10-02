-- CPU-list parsing, formatting and selection for pinned (single-core and
-- multicore) measurements, checked over a set of inputs.
package.path='./src/?.lua;'..package.path
local cpus=require('cpus')
local tests=0
local function check(name,actual,expected)
	assert(actual==expected,name..': expected '..tostring(expected)..', got '..tostring(actual))
	tests=tests+1
end
-- Linux cpulist syntax (Cpus_allowed_list, taskset -c): ranges and singles.
local parse_cases={
	{'0','0'}, {'0-3','0,1,2,3'}, {'0-1,4,6-7','0,1,4,6,7'}, {'7,3,3,1','1,3,7'},
	{' 2-3 ','2,3'}, {'10-11,8','8,10,11'},
}
for _,c in ipairs(parse_cases) do check('parse '..c[1],table.concat(cpus.parse(c[1]),','),c[2]) end
for _,bad in ipairs({'','a','3-1','1-','-2','1,,2','1.5'}) do check('reject '..bad,pcall(cpus.parse,bad),false) end
-- Formatting compresses runs; parse(format(x)) is the identity on sorted sets.
local format_cases={{{0},'0'},{{0,1,2,3},'0-3'},{{0,1,4,6,7},'0-1,4,6-7'},{{5,9},'5,9'}}
for _,c in ipairs(format_cases) do
	check('format '..c[2],cpus.format(c[1]),c[2])
	check('round trip '..c[2],cpus.format(cpus.parse(c[2])),c[2])
end
-- Selection takes the first n allowed CPUs and refuses to silently use fewer.
check('select 1',cpus.format(cpus.select({4,5,6,7},1)),'4')
check('select 3',cpus.format(cpus.select({0,2,4,6},3)),'0,2,4')
check('select all',cpus.format(cpus.select({0,1,2},3)),'0-2')
check('too few allowed',pcall(cpus.select,{0,1},3),false)
check('zero cores',pcall(cpus.select,{0,1},0),false)
-- The pinned command wraps argv in taskset with an exact list.
local argv=cpus.pin({'bench','a b'},{0,1,2})
check('pin wrapper',table.concat(argv,'|'),'taskset|-c|0-2|bench|a b')
print('PASS: '..tests..' CPU-list assertions')
