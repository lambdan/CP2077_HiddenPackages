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

function LEX.stringStarts(String,Start) -- https://stackoverflow.com/a/22831842
   return string.sub(String,1,string.len(Start))==Start
end

function LEX.copyTable(t) -- https://stackoverflow.com/a/39185792
    local new = {}
    for k,v in ipairs(t) do
        new[k] = v
    end
    return new
end

function LEX.trim(s) -- https://gist.github.com/ram-nadella/dd067dfeb3c798299e8d
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

return LEX