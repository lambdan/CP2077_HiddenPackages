
# Schema

|Name|Type|Required|Default|Comment|Implemented|
|-----------|----|----|--------|-------|-------|
|id|string|**yes**|||✅|
|position|array of x,y,z,w|**yes**|||✅|
|name|string|no|fallsback to filepath||✅|
|vehicle_allowed|bool|no|false|||
|shard_message|array of title(string) and body(string)|no|no|||
|package_prop|string|no|holocubes||✅|
|package_prop_z_boost|number|no|0.25||✅|
|respawn|number|no|3||✅|
|permanent|bool|no|false||✅|
|collect_range|number|no|0.5||✅|
|money|number|no||||
|exp|number|no||||
|streetcred|number|no||||
|items|array of item(string), amount(number)|no||||
|teleport|array of x,y,z,w|no||||
