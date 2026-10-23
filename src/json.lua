local cjson=require('cjson.safe')
local M={decode=function(s) local v,e=cjson.decode(s); assert(v,e); return v end}
-- Canonical key order makes idempotency comparisons independent of table order.
-- Integers are written exactly ('%.0f'): cjson's 14-significant-digit format
-- rounds 16-digit monotonic nanosecond timestamps to 100 ns.
local EXACT=2^53
function M.encode(v)
	if type(v)=='number' and v%1==0 and v>=-EXACT and v<=EXACT then return ('%.0f'):format(v) end
	if type(v)~='table' then local s,e=cjson.encode(v); return assert(s,e) end
	local count,max,keys=0,0,{}
	for k in pairs(v) do
		count=count+1
		if type(k)=='number' and k%1==0 and k>0 then max=math.max(max,k) else keys[#keys+1]=k end
	end
	if #keys==0 and count>0 and count==max then
		local out={}; for i=1,count do out[i]=M.encode(v[i]) end
		return '['..table.concat(out,',')..']'
	end
	assert(#keys==count,'JSON object keys must be strings')
	table.sort(keys)
	local out={}; for i,k in ipairs(keys) do out[i]=M.encode(k)..':'..M.encode(v[k]) end
	return '{'..table.concat(out,',')..'}'
end
return M
