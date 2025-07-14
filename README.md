A rewrite of Stripper:Source into Sourcepawn.<br></br>It can read stripper configs with no changes necessary.*  

> [!WARNING]
> *See [this issue report](https://github.com/tilgep/stripper/issues/2) for an edge case.

Info on stripper: https://www.bailopan.net/stripper/.<br></br>Forum thread for this plugin: https://forums.alliedmods.net/showthread.php?t=339448.

### [Configuration](https://github.com/Heapons/sm-plugin-stripper/tree/master/configs/stripper)
[`global_filters.cfg`](https://github.com/Heapons/sm-plugin-stripper/blob/master/configs/stripper/global_filters.cfg) for the global config  
[`maps/mapname.cfg`](https://github.com/Heapons/sm-plugin-stripper/blob/master/configs/stripper/maps/example_map.cfg) for map specific config  
[`gamemodes/mapprefix.cfg`](https://github.com/Heapons/sm-plugin-stripper/blob/master/configs/stripper/gamemodes/ctf.cfg) for gamemode specific config

### Cvars
`stripper_file_lowercase` - Whether to load map config filenames as lower case.

### Commands
`stripper_dump` - Dumps all current entity properties to a file in `configs/stripper/dumps/`.