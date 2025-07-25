#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <regex>
#include <Stripper>

public Plugin myinfo =
{
    name		= "Stripper:Source (SP edition)",
    version		= "1.3.5",
    description	= "Stripper:Source functionality in a Sourcemod plugin",
    author		= "Original Author: BAILOPAN. Ported to SM by: tilgep. Edited by: Lerrdy, .Rushaway, Heapons",
    url			= "https://github.com/Heapons/sm-plugin-stripper"
}

enum Mode
{
    Mode_None,
    Mode_Filter,
    Mode_Add,
    Mode_Modify,
}

enum SubMode
{
    SubMode_None,
    SubMode_Match,
    SubMode_Replace,
    SubMode_Delete,
    SubMode_Insert,
}

enum struct Property
{
    char key[PLATFORM_MAX_PATH];
    char val[PLATFORM_MAX_PATH];
    bool regex;
}

/* Stripper block struct */
enum struct Block
{
    Mode mode;
    SubMode submode;
    ArrayList match;	// Filter/Modify
    ArrayList replace;	// Modify
    ArrayList del;		// Modify
    ArrayList insert;	// Add/Modify
    bool hasClassname;	// Ensures that an add block has a classname set

    void Init()
    {
        this.mode = Mode_None;
        this.submode = SubMode_None;
        this.match = CreateArray(sizeof(Property));
        this.replace = CreateArray(sizeof(Property));
        this.del = CreateArray(sizeof(Property));
        this.insert = CreateArray(sizeof(Property));
    }

    void Clear()
    {
        this.hasClassname = false;
        this.mode = Mode_None;
        this.submode = SubMode_None;
        this.match.Clear();
        this.replace.Clear();
        this.del.Clear();
        this.insert.Clear();
    }
}

char file[PLATFORM_MAX_PATH];
char g_sLogPath[PLATFORM_MAX_PATH];
bool g_bConfigLoaded = false;
bool g_bConfigError = false;
Handle g_hFwd_OnErrorLogged = INVALID_HANDLE;
ConVar fileLowercase;
Block prop; // Global current stripper block
int section;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("Stripper_LogError", Native_Log);
    g_hFwd_OnErrorLogged = CreateGlobalForward("Stripper_OnErrorLogged", ET_Ignore, Param_String);

    RegPluginLibrary("Stripper");
    return APLRes_Success;
}

public void OnPluginStart()
{
    prop.Init();

    RegAdminCmd("stripper_dump", Command_Dump, ADMFLAG_ROOT, "Writes all of the map entity properties to a file in configs/stripper/dumps/");
    RegAdminCmd("sm_stripper", Command_Stripper, ADMFLAG_GENERIC, "Prints out if the current map has a loaded stripper file");

    fileLowercase = CreateConVar("stripper_file_lowercase", "0", "Whether to load map config filenames as lower case", _, true, 0.0, true, 1.0);
    AutoExecConfig(true, "stripper");
}

public Action Command_Stripper(int client, int args)
{
    bool bAccess = CheckCommandAccess(client, "sm_stripper", ADMFLAG_ROOT);
    if (g_bConfigLoaded)
    {
        ReplyToCommand(client, "[Strippper] The current map has a loaded stripper config.");
        if(bAccess) ReplyToCommand(client, "[Strippper] Actual cfg: %s", file);
    }
    else if (g_bConfigError)
    {
        ReplyToCommand(client, "[Strippper] The current map has a loaded stripper config but it contains error(s)");
        if(bAccess) ReplyToCommand(client, "[Strippper] Check (%s)", file);
    }
    else
    {
        ReplyToCommand(client, "[Strippper] The current map did not load a stripper config.");
        if(bAccess) ReplyToCommand(client, "[Strippper] No file found: (%s)", file);
    }
        
    return Plugin_Handled;
}

public Action Command_Dump(int client, int args)
{
    char buf1[PLATFORM_MAX_PATH], buf2[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
    int num = -1;

    GetCurrentMap(buf1, PLATFORM_MAX_PATH);

    // Workshop Fix
    if (strncmp(buf1, "workshop/", 9, false) == 0)
    {
        strcopy(buf1, sizeof(buf1), buf1[9]);
        int workshopID = StrContains(buf1, ".ugc", false);
        if (workshopID != -1)
            buf1[workshopID] = '\0';
    }

    BuildPath(Path_SM, buf2, PLATFORM_MAX_PATH, "configs/stripper/dumps");
    
    if(!DirExists(buf2)) CreateDirectory(buf2, FPERM_O_READ|FPERM_O_EXEC|FPERM_G_READ|FPERM_G_EXEC|FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC);

    do
    {
        num++;
        // Use same format as original stripper
        Format(path, PLATFORM_MAX_PATH, "%s/%s.%04d.cfg", buf2, buf1, num);
    }
    while(FileExists(path));

    File fi = OpenFile(path, "w");
    if(fi == null)
    {
        LogError("Failed to create dump file \"%s\"", path);
        return Plugin_Handled;
    }

    EntityLumpEntry ent;

    for(int i = 0; i < EntityLump.Length(); i++)
    {
        ent = EntityLump.Get(i);

        fi.WriteLine("{");

        for(int j = 0; j < ent.Length; j++)
        {
            ent.Get(j, buf1, PLATFORM_MAX_PATH, buf2, PLATFORM_MAX_PATH);
            fi.WriteLine("\"%s\" \"%s\"", buf1, buf2);
        }

        fi.WriteLine("}");

        delete ent;
    }

    delete fi;
    
    ReplyToCommand(client, "[SM] Dumped entities to '%s'", path);
    return Plugin_Handled;
}

public void OnMapInit(const char[] mapName)
{
    // Workshop Fix
    if (strncmp(mapName, "workshop/", 9, false) == 0)
    {
        int workshopID = StrContains(mapName, ".ugc", false);
        if (workshopID != -1)
            mapName[workshopID] = '\0';
    }

    //// Map Names ////
    // Path used for logging.
    BuildPath(Path_SM, g_sLogPath, sizeof(g_sLogPath), "logs/stripper/maps/%s.log", mapName);

    g_bConfigLoaded = false;
    g_bConfigError = false;

    // Parse global filters
    BuildPath(Path_SM, file, sizeof(file), "configs/stripper/global_filters.cfg");
    ParseFile(false);

    // Parse map config
    BuildPath(Path_SM, file, sizeof(file), "configs/stripper/maps/%s.cfg", mapName);

    if(!ParseFile(true) && fileLowercase.BoolValue)
    {
        strcopy(file, sizeof(file), mapName);
        for(int i = 0; file[i]; i++)
            file[i] = CharToLower(file[i]);

        BuildPath(Path_SM, file, sizeof(file), "configs/stripper/maps/%s.cfg", file);
        ParseFile(true);
    }
    // Parse gamemode config
    char mapPrefix[16];
    if (SplitString(mapName, "_", mapPrefix, sizeof(mapPrefix)) != -1) {
        BuildPath(Path_SM, file, sizeof(file), "configs/stripper/gamemodes/%s.cfg", mapPrefix);
        
        if (!ParseFile(true) && fileLowercase.BoolValue)
        {
            strcopy(file, sizeof(file), mapPrefix);
            for(int i = 0; file[i]; i++)
                file[i] = CharToLower(file[i]);

            BuildPath(Path_SM, file, sizeof(file), "configs/stripper/gamemodes/%s.cfg", file);
            ParseFile(true);
        }
    }
}

/**
 * Parses a stripper config file
 *
 * @param path		Path to parse from
 * @return          True if successful, false otherwise
 */
public bool ParseFile(bool mapconfig)
{
    int line, col;
    section = 0;

    prop.Clear();

    SMCParser parser = SMC_CreateParser();
    SMC_SetReaders(parser, Config_NewSection, Config_KeyValue, Config_EndSection);

    SMCError result = SMC_ParseFile(parser, file, line, col);
    delete parser;

    if (result == SMCError_Okay)
    {
        if (mapconfig)
            g_bConfigLoaded = true;

        return true;
    }

    if(result != SMCError_Okay && result != SMCError_StreamOpen)
    {
        if(result == SMCError_StreamOpen)
        {
            g_bConfigLoaded = false;
            LogMessage("Failed to open stripper config \"%s\"", file);
        }
        else
        {
            char error[128];
            g_bConfigError = true;
            SMC_GetErrorString(result, error, sizeof(error));
            Stripper_LogError("%s on line %d, col %d of %s", error, line, col, file);
        }
    }

    return false;
}

public SMCResult Config_NewSection(SMCParser smc, const char[] name, bool opt_quotes)
{
    section++;
    if(!strcmp(name, "filter:", false) || !strcmp(name, "remove:", false))
    {
        if(prop.mode != Mode_None)
        {
            g_bConfigError = true;
            Stripper_LogError("Found 'filter' block while inside another block at section %d in file '%s'", section, file);
        }

        prop.Clear();
        prop.mode = Mode_Filter;
    }
    else if(!strcmp(name, "add:", false))
    {
        if(prop.mode != Mode_None)
        {
            g_bConfigError = true;
            Stripper_LogError("Found 'add' block while inside another block at section %d in file '%s'", section, file);
        }

        prop.Clear();
        prop.mode = Mode_Add;
    }
    else if(!strcmp(name, "modify:", false))
    {
        if(prop.mode != Mode_None)
        {
            g_bConfigError = true;
            Stripper_LogError("Found 'modify' block while inside another block at section %d in file '%s'", section, file);
        }

        prop.Clear();
        prop.mode = Mode_Modify;
    }
    else if(prop.mode == Mode_Modify)
    {
        if(!strcmp(name, "match:", false))			prop.submode = SubMode_Match;
        else if(!strcmp(name, "replace:", false))	prop.submode = SubMode_Replace;
        else if(!strcmp(name, "delete:", false))	prop.submode = SubMode_Delete;
        else if(!strcmp(name, "insert:", false))	prop.submode = SubMode_Insert;
        else
        {
            g_bConfigError = true;
            Stripper_LogError("Found invalid section '%s' in modify block at section %d in file '%s'", name, section, file);
        }
    }
    else
    {
        g_bConfigError = true;
        Stripper_LogError("Found invalid section name '%s' at section %d in file '%s'", name, section, file);
    }

    return SMCParse_Continue;
}

public SMCResult Config_KeyValue(SMCParser smc, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
    Property kv;
    strcopy(kv.key, PLATFORM_MAX_PATH, key);
    strcopy(kv.val, PLATFORM_MAX_PATH, value);
    kv.regex = FormatRegex(kv.val, strlen(value));

    switch(prop.mode)
    {
        case Mode_None:		return SMCParse_Continue;
        case Mode_Filter:	prop.match.PushArray(kv);
        case Mode_Add:
        {
            // Adding an entity without a classname will crash the server (shortest classname is "gib")
            if(strcmp(key, "classname", false) == 0 && strlen(value) > 2) prop.hasClassname = true;

            prop.insert.PushArray(kv);
        }
        case Mode_Modify:
        {
            switch(prop.submode)
            {
                case SubMode_Match:		prop.match.PushArray(kv);
                case SubMode_Replace:	prop.replace.PushArray(kv);
                case SubMode_Delete:	prop.del.PushArray(kv);
                case SubMode_Insert:	prop.insert.PushArray(kv);
            }
        }
    }

    return SMCParse_Continue;
}

public SMCResult Config_EndSection(SMCParser smc)
{
    switch(prop.mode)
    {
        case Mode_Filter:
        {
            if(prop.match.Length > 0) RunRemoveFilter();

            prop.mode = Mode_None;
        }
        case Mode_Add:
        {
            if(prop.insert.Length > 0)
            {
                if(prop.hasClassname)
                    RunAddFilter();
                else
                {
                    g_bConfigError = true;
                    Stripper_LogError("Add block with no classname found at section %d in file '%s'", section, file);
                }
            }

            prop.mode = Mode_None;
        }
        case Mode_Modify:
        {
            // Exiting a modify sub-block
            if(prop.submode != SubMode_None)
            {
                prop.submode = SubMode_None;
                return SMCParse_Continue;
            }

            // Must have something to match for modify blocks
            if(prop.match.Length > 0) RunModifyFilter();

            prop.mode = Mode_None;
        }
    }
    return SMCParse_Continue;
}

public void RunRemoveFilter()
{
    /* prop.match holds what we want
     * we know it has at least 1 entry here
     */

    char val2[PLATFORM_MAX_PATH];
    Property kv;
    EntityLumpEntry entry;
    for(int i, matches, j, index; i < EntityLump.Length(); i++)
    {
        matches = 0;
        entry = EntityLump.Get(i);

        for(j = 0; j < prop.match.Length; j++)
        {
            prop.match.GetArray(j, kv, sizeof(kv));

            index = entry.GetNextKey(kv.key, val2, sizeof(val2));
            while(index != -1)
            {
                if(EntPropsMatch(kv.val, val2, kv.regex))
                {
                    matches++;
                    break;
                }

                index = entry.GetNextKey(kv.key, val2, sizeof(val2), index);
            }
        }

        if(matches == prop.match.Length)
        {
            EntityLump.Erase(i);
            i--;
        }
        delete entry;
    }
}

public void RunAddFilter()
{
    /* prop.insert holds what we want
     * we know it has at least 1 entry here
     */

    int index = EntityLump.Append();
    EntityLumpEntry entry = EntityLump.Get(index);

    Property kv;
    for(int i; i < prop.insert.Length; i++)
    {
        prop.insert.GetArray(i, kv, sizeof(kv));
        entry.Append(kv.key, kv.val);
    }

    delete entry;
}

public void RunModifyFilter()
{
    /* prop.match holds at least 1 entry here
     * others may not have anything
     */

    // Nothing to do if these are all empty
    if(prop.replace.Length == 0 && prop.del.Length == 0 && prop.insert.Length == 0)
    {
        return;
    }

    char val2[PLATFORM_MAX_PATH];

    Property kv;
    EntityLumpEntry entry;
    for(int i, matches, j, index; i < EntityLump.Length(); i++)
    {
        matches = 0;
        entry = EntityLump.Get(i);

        /* Check matches */
        for(j = 0; j < prop.match.Length; j++)
        {
            prop.match.GetArray(j, kv, sizeof(kv));

            index = entry.GetNextKey(kv.key, val2, sizeof(val2));
            while(index != -1)
            {
                if(EntPropsMatch(kv.val, val2, kv.regex))
                {
                    matches++;
                    break;
                }

                index = entry.GetNextKey(kv.key, val2, sizeof(val2), index);
            }
        }

        if(matches < prop.match.Length)
        {
            delete entry;
            continue;
        }

        /* This entry matches, perform any changes */

        /* First do deletions */
        if(prop.del.Length > 0)
        {
            for(j = 0; j < prop.del.Length; j++)
            {
                prop.del.GetArray(j, kv, sizeof(kv));

                index = entry.GetNextKey(kv.key, val2, sizeof(val2));
                while(index != -1)
                {
                    if(EntPropsMatch(kv.val, val2, kv.regex))
                    {
                        entry.Erase(index);
                        index--;
                    }
                    index = entry.GetNextKey(kv.key, val2, sizeof(val2), index);
                }
            }
        }

        /* do replacements */
        if(prop.replace.Length > 0)
        {
            for(j = 0; j < prop.replace.Length; j++)
            {
                prop.replace.GetArray(j, kv, sizeof(kv));

                index = entry.GetNextKey(kv.key, val2, sizeof(val2));
                while(index != -1)
                {
                    entry.Update(index, NULL_STRING, kv.val);
                    index = entry.GetNextKey(kv.key, val2, sizeof(val2), index);
                }
            }
        }

        /* do insertions */
        if(prop.insert.Length > 0)
        {
            for(j = 0; j < prop.insert.Length; j++)
            {
                prop.insert.GetArray(j, kv, sizeof(kv));
                entry.Append(kv.key, kv.val);
            }
        }

        delete entry;
    }
}

/**
 * Checks if 2 values match
 *
 * @param val1		First value
 * @param val2		Second value
 * @param isRegex	True if val1 should be treated as a regex pattern, false if not
 * @return			True if match, false otherwise
 *
 */
stock bool EntPropsMatch(const char[] val1, const char[] val2, bool isRegex)
{
    return isRegex ? SimpleRegexMatch(val2, val1) > 0 : !strcmp(val1, val2);
}

stock bool FormatRegex(char[] pattern, int len)
{
    if(pattern[0] == '/' && pattern[len-1] == '/')
    {
        strcopy(pattern, len-1, pattern[1]);
        return true;
    }

    return false;
}

// native Stripper_LogError(const char[] format, any...);
public int Native_Log(Handle plugin, int numParams)
{
    char sBuffer[2048];
    FormatNativeString(0, 1, 2, sizeof(sBuffer), _, sBuffer);
    LogToFileEx(g_sLogPath, "%s", sBuffer);

    // Start forward call
    Call_StartForward(g_hFwd_OnErrorLogged);
    Call_PushString(sBuffer);
    Call_Finish();

    return 1;
}