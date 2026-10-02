local cjson=require('cjson.safe')
local M={decode=function(s) local v,e=cjson.decode(s); assert(v,e); return v end}
-- Canonical key order makes idempotency comparisons independent of table order.
function M.encode(v)
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
