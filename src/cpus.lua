-- CPU sets for pinned measurements: a case declares how many cores it runs
-- on (1 for single-core, more for multicore), and on Linux the command runs
-- under `taskset -c` with that many CPUs from the allowed set. Lists use the
-- kernel's cpulist syntax ("0-3,8,10-11").
local M={}

-- Parse a cpulist into a sorted array of distinct CPU numbers.
function M.parse(text)
	assert(type(text)=='string','cpulist must be a string')
	text=text:match('^%s*(.-)%s*$')
	assert(#text>0,'empty cpulist')
	local seen,out={},{}
	for item in (text..','):gmatch('([^,]*),') do
		local a,b=item:match('^(%d+)%-(%d+)$')
		if not a then a=item:match('^(%d+)$'); b=a end
		assert(a,'invalid cpulist item: '..item)
		a,b=tonumber(a),tonumber(b)
		assert(a<=b,'descending cpulist range: '..item)
		for c=a,b do if not seen[c] then seen[c]=true; out[#out+1]=c end end
	end
	table.sort(out)
	return out
end

-- Format a sorted array of CPU numbers, compressing consecutive runs.
function M.format(list)
	local parts,i={},1
	while i<=#list do
		local j=i
		while j<#list and list[j+1]==list[j]+1 do j=j+1 end
		parts[#parts+1]=j>i and (list[i]..'-'..list[j]) or tostring(list[i])
		i=j+1
	end
	return table.concat(parts,',')
end

-- The first n CPUs of the allowed set; fewer than n is an error, never a
-- silent smaller measurement.
function M.select(allowed,n)
	assert(type(n)=='number' and n>=1 and n%1==0,'core count must be a positive integer')
	assert(#allowed>=n,('%d cores requested, %d allowed (%s)'):format(n,#allowed,M.format(allowed)))
	local out={}
	for i=1,n do out[i]=allowed[i] end
	return out
end

-- Wrap argv so it runs on exactly `list`.
function M.pin(argv,list)
	local out={'taskset','-c',M.format(list)}
	for _,a in ipairs(argv) do out[#out+1]=a end
	return out
end

-- The CPUs this process may run on (Linux), or nil where affinity is not
-- available to enforce.
function M.allowed()
	local f=io.open('/proc/self/status','rb')
	if not f then return nil end
	local status=f:read('*a'); f:close()
	local list=status:match('\nCpus_allowed_list:%s*([^\n]+)')
	return list and M.parse(list) or nil
end

return M
