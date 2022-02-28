
# Schema

	id = string
	name = string
	position = {x=float,y=float,z=float,w=float}
	vehicle_allowed = bool
	shard_message = {title=string, body=string}
	package_prop = string
	package_prop_z_boost = float
	respawn = float
	money = int
	xp = int
	streetcred = int
	items = [
		{item=string, amount=int}
	]
