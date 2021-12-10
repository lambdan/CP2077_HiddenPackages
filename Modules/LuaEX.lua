-- good useful stuff for Lua... "Lua Extended"

local LEX = {}

function LEX.fileExists(filename) -- https://stackoverflow.com/a/4991602
    local f=io.open(filename,"r")
    if f~=nil then io.close(f) return true else return false end
end

function LEX.tableHasValue(tab,val)
    for i,v in ipairs(tab) do
        if val == v then
            return true
        end
    end
    return false
end

function LEX.tableLen(table)
    local i = 0
    for p in pairs(table) do
        i = i + 1
    end
    return i
end

function LEX.stringStarts(String,Start)
   return string.sub(String,1,string.len(Start))==Start
end

return LEX